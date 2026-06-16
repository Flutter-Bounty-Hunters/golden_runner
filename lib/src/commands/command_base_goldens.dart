import 'dart:io';

import 'package:golden_runner/golden_runner.dart';
import 'package:golden_runner/src/goldens_runner.dart';
import 'package:golden_runner/src/infrastructure/arguments.dart';
import 'package:golden_runner/src/infrastructure/docker/docker_golden_container.dart';
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

  GoldensCommand();

  @override
  Set<String> get mountPaths => {
        // Mount the entire host machine test directory so that the container can either
        // create failure files, or create updated golden files.
        '${Directory.current.path}/$_testBaseDirectory:/golden_tester/$_packageDirectory/$_testBaseDirectory',
      };

  @override
  @visibleForTesting
  String get pathToProjectRoot => _pathToProjectRoot!;
  String? _pathToProjectRoot;

  @override
  String get containerWorkingDirectory => '/golden_tester/$_packageDirectory';

  /// The specific Flutter golden command that's run by this command.
  ///
  /// Choosing this command is the primary focus of subclasses.
  @override
  List<String> get command;

  @visibleForTesting
  String get packageDirectory => _packageDirectory!;
  String? _packageDirectory;

  @visibleForTesting
  String get testBaseDirectory => _testBaseDirectory!;
  String? _testBaseDirectory;

  @visibleForTesting
  List<String> get testCommandArguments => _testCommandArguments!;
  List<String>? _testCommandArguments;

  @override
  void parseArguments(List<String> arguments) {
    super.parseArguments(arguments);

    GrLog.commands.fine("Parsing golden command arguments: $arguments");
    _pathToProjectRoot = parseArgumentOption(arguments, argPathToProjectRoot) ?? defaultPathToProjectRoot;

    var testDirectoryPath = defaultTestDirectoryPath;
    final testDirectoryOrFile =
        arguments.isEmpty || arguments.last.startsWith("--") || arguments.last.startsWith("-") //
            ? null
            : arguments.last;

    if (testDirectoryOrFile != null) {
      final testDirectory = Directory(testDirectoryOrFile);
      if (testDirectory.existsSync()) {
        testDirectoryPath = testDirectoryOrFile;
      } else {
        final testFile = File(testDirectoryOrFile);
        if (testFile.existsSync()) {
          // Use the given path, minus the file name and extension.
          testDirectoryPath = testDirectoryOrFile.substring(
            0,
            testDirectoryOrFile.length - path.basename(testDirectoryOrFile).length,
          );
        }
      }
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
    _packageDirectory = path.split(Directory.current.path).last;

    // Other arguments passed at the end of the command.
    // For example, the test directory.
    _testCommandArguments = [...arguments];
    GrLog.commands.fine("Test command arguments: $_testCommandArguments");
  }
}
