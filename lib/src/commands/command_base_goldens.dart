import 'dart:io';

import 'package:golden_runner/src/commands/command_docker_container.dart';
import 'package:golden_runner/src/infrastructure/arguments.dart';
import 'package:golden_runner/src/infrastructure/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

/// Base class for a Golden command, such as `test` or `update` goldens.
///
/// This command configures a Docker Image and Docker Container for either testing or updating goldens. This includes
/// making sure to copy the whole repo when working within a project in a mono-repo, and configuring the working
/// directory when interested in running/updating from a test sub-directory. This command also mounts the test
/// directory from the host machine so that goldens can be updated, and failure scenes can be created.
///
/// The primary job of a subclass is to return the desired Flutter Golden [command] to run in the Docker Container.
abstract class GoldensCommand extends DockerContainerCommand {
  static const argPathToProjectRoot = "--path-to-project-root";
  static const argVerbose = "--verbose";
  static const argVerboseShort = "-v";

  static const defaultPathToProjectRoot = ".";
  static const defaultTestDirectoryPath = "test_goldens";

  GoldensCommand({
    GoldensCommandEnvironment environment = const GoldensCommandEnvironment(),
  }) : _environment = environment;

  final GoldensCommandEnvironment _environment;

  @override
  Set<String> get mountPaths => {
        // Mount the entire host machine test directory so that the container can either
        // create failure files, or create updated golden files.
        '$hostTestDirectoryPath:'
            '${path.posix.join(containerWorkingDirectory, containerTestDirectoryPath)}',
      };

  @override
  String get pathToProjectRoot => _pathToProjectRoot!;
  String? _pathToProjectRoot;

  @override
  String get containerWorkingDirectory {
    final packagePath = packagePathFromProjectRoot;
    return packagePath == "." //
        ? "/golden_tester"
        : path.posix.join("/golden_tester", _toPosixPath(packagePath));
  }

  @protected
  @visibleForTesting
  String get hostTestDirectoryPath {
    final testBaseDirectory = _testBaseDirectory!;
    return path.isAbsolute(testBaseDirectory) //
        ? testBaseDirectory
        : path.join(_environment.currentDirectoryPath, testBaseDirectory);
  }

  @protected
  @visibleForTesting
  String get containerTestDirectoryPath {
    final testBaseDirectory = _testBaseDirectory!;
    final packageRelativeTestDirectory = path.isAbsolute(testBaseDirectory) //
        ? path.relative(testBaseDirectory, from: _environment.currentDirectoryPath)
        : testBaseDirectory;

    return _toPosixPath(packageRelativeTestDirectory);
  }

  String _toPosixPath(String filePath) {
    return path.split(filePath).join("/");
  }

  /// The specific Flutter golden command that's run by this command.
  ///
  /// Choosing this command is the primary focus of subclasses.
  @override
  List<String> get command;

  @protected
  @visibleForTesting
  String get packageDirectory => _packageDirectory!;
  String? _packageDirectory;

  @protected
  @visibleForTesting
  String get packagePathFromProjectRoot => _packagePathFromProjectRoot!;
  String? _packagePathFromProjectRoot;

  @protected
  @visibleForTesting
  String get testBaseDirectory => _testBaseDirectory!;
  String? _testBaseDirectory;

  @protected
  @visibleForTesting
  List<String> get testCommandArguments => _testCommandArguments!;
  List<String>? _testCommandArguments;

  @override
  @mustCallSuper
  void parseArguments(List<String> arguments) {
    super.parseArguments(arguments);

    GrLog.commands.fine("Parsing golden command arguments: $arguments");
    _pathToProjectRoot = parseArgumentOption(arguments, argPathToProjectRoot) ?? defaultPathToProjectRoot;

    var testDirectoryPath = defaultTestDirectoryPath;
    var targetTestDirectoryOrFileInContainer = defaultTestDirectoryPath;

    final testDirectoryOrFileOnHostMachine = _findTargetTestDirectoryOrFileInArguments(arguments);

    if (testDirectoryOrFileOnHostMachine != null) {
      if (_environment.directoryExists(testDirectoryOrFileOnHostMachine)) {
        // The caller specified a directory to run tests.
        testDirectoryPath = testDirectoryOrFileOnHostMachine;
        targetTestDirectoryOrFileInContainer = _packageRelativePath(testDirectoryOrFileOnHostMachine);
      } else {
        // The caller specified a specific file to run tests.
        if (_environment.fileExists(testDirectoryOrFileOnHostMachine)) {
          testDirectoryPath = path.dirname(testDirectoryOrFileOnHostMachine);
          targetTestDirectoryOrFileInContainer = _packageRelativePath(testDirectoryOrFileOnHostMachine);
        } else {
          throw Exception(
            "No such golden test directory or file: $testDirectoryOrFileOnHostMachine",
          );
        }
      }

      // The caller provided an explicit test directory or test file. We need to massage its
      // file system path, so remove it from the argument list and then we'll explicitly insert
      // our massaged version at the end.
      _removeTargetTestDirectoryOrFileFromArguments(arguments, testDirectoryOrFileOnHostMachine);
    }
    _testBaseDirectory = testDirectoryPath;
    GrLog.commands.fine("Test directory: $testDirectoryPath");

    // The tool must run from the root of the package being tested.
    //
    // In a single-project repository, this directory is the same as the working
    // directory.
    //
    // However, in a mono-repo, this command must be run from a subdirectory
    // that corresponds to the project under test.
    //
    // For example, `super_editor` is a mono-repo. Therefore, golden tests
    // must be run from within subdirectories, such as:
    //  - `super_editor/super_editor/`
    //  - `super_editor/super_text_layout/`
    //  - `super_editor/super_editor_markdown/'
    final currentDirectoryPath = path.normalize(_environment.currentDirectoryPath);
    final projectRootPath = path.normalize(
      path.isAbsolute(pathToProjectRoot) //
          ? pathToProjectRoot
          : path.join(currentDirectoryPath, pathToProjectRoot),
    );
    _packagePathFromProjectRoot = path.relative(
      currentDirectoryPath,
      from: projectRootPath,
    );
    _packageDirectory = path.basename(currentDirectoryPath);

    // Other arguments passed at the end of the command.
    // For example, the test directory.
    _testCommandArguments = [
      ...arguments,
      targetTestDirectoryOrFileInContainer,
    ];
    GrLog.commands.fine("Test command arguments: $_testCommandArguments");
  }

  String? _findTargetTestDirectoryOrFileInArguments(List<String> arguments) {
    final positionalMarkerIndex = arguments.indexOf("--");
    if (positionalMarkerIndex != -1) {
      if (positionalMarkerIndex == arguments.length - 1) {
        throw Exception("Expected golden test directory or file after --.");
      }

      return arguments[positionalMarkerIndex + 1];
    }

    final targetIndex = arguments.lastIndexWhere((String argument) => !argument.startsWith("-"));
    if (targetIndex == -1) {
      return null;
    }

    final valueIndexes = <int>[];
    for (int i = 0; i < targetIndex; i += 1) {
      final argument = arguments[i];
      if (!argument.startsWith("-")) {
        valueIndexes.add(i);
        continue;
      }

      if (argument.contains("=")) {
        continue;
      }

      final nextIndex = i + 1;
      if (nextIndex < targetIndex && !arguments[nextIndex].startsWith("-")) {
        // Treat this as an option/value pair.
        i = nextIndex;
      }
    }
    valueIndexes.add(targetIndex);

    if (valueIndexes.length == 1 && _isOnlyValueProbablyAnOptionValue(arguments, targetIndex)) {
      return null;
    }

    return arguments[targetIndex];
  }

  void _removeTargetTestDirectoryOrFileFromArguments(List<String> arguments, String target) {
    final positionalMarkerIndex = arguments.indexOf("--");
    if (positionalMarkerIndex != -1) {
      arguments.removeRange(positionalMarkerIndex, positionalMarkerIndex + 2);
      return;
    }

    arguments.removeAt(arguments.lastIndexOf(target));
  }

  bool _isOnlyValueProbablyAnOptionValue(List<String> arguments, int valueIndex) {
    if (valueIndex == 0) {
      return false;
    }

    final previousArgument = arguments[valueIndex - 1];
    if (!previousArgument.startsWith("-") || previousArgument.contains("=")) {
      return false;
    }

    final value = arguments[valueIndex];
    return !_environment.directoryExists(value) && !_environment.fileExists(value);
  }

  String _packageRelativePath(String hostPath) {
    final packageRelativePath = path.isAbsolute(hostPath) //
        ? path.relative(hostPath, from: _environment.currentDirectoryPath)
        : hostPath;

    return _toPosixPath(packageRelativePath);
  }
}

class GoldensCommandEnvironment {
  const GoldensCommandEnvironment();

  String get currentDirectoryPath => Directory.current.path;

  bool directoryExists(String directoryPath) => Directory(directoryPath).existsSync();

  bool fileExists(String filePath) => File(filePath).existsSync();
}
