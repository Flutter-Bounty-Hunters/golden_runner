import 'dart:io';

import 'package:golden_runner/src/commands/command_docker_container.dart';
import 'package:golden_runner/src/infrastructure/arguments.dart';
import 'package:golden_runner/src/infrastructure/docker/docker_client.dart';
import 'package:golden_runner/src/infrastructure/fvm.dart';
import 'package:golden_runner/src/infrastructure/logging.dart';
import 'package:golden_runner/src/infrastructure/path_dependencies.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

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
        // Mount any local `path:` dependencies that live outside the copied project
        // (read-only), at their absolute path, so the container's `pub get` resolves them.
        ..._externalPathDependencyMounts,
      };

  /// Bind-mount specs (`<hostDir>:<hostDir>:ro`) for local path dependencies that
  /// resolve outside the copied project tree.
  Set<String> _externalPathDependencyMounts = const {};

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

    // If no explicit --flutter-version was passed, pin the container's Flutter to
    // the project's FVM configuration (.fvmrc), walking up from the package to the
    // project root, so goldens match the developer's local (and CI) SDK. An explicit
    // --flutter-version always wins.
    if (flutterVersion == null) {
      final fvmVersion = const FvmVersionResolver().resolve(
        currentDirectoryPath,
        projectRootPath,
        readFile: _environment.readFileAsString,
      );
      if (fvmVersion != null) {
        useFlutterVersionIfUnset(fvmVersion);
        GrLog.commands.fine("Inferred Flutter version '$fvmVersion' from FVM config");
        if (!silent && dockerVerbosity != DockerVerbosity.none) {
          // ignore: avoid_print
          print("[golden_runner] ℹ Using Flutter '$fvmVersion', inferred from your project's FVM config.");
        }
      }
    }

    // Fail early (before building any Docker image) if this package belongs to a
    // Dart pub workspace whose root won't be copied into the container. Without
    // this check, the container copy contains a workspace member but no workspace
    // root, and Flutter fails deep inside the container with a cryptic pub error.
    _verifyWorkspaceRootWillBeCopied(
      packageDirectoryPath: currentDirectoryPath,
      projectRootPath: projectRootPath,
    );

    // Find local `path:` dependencies that live outside the copied project tree and
    // mount them into the container (read-only, at their absolute path) so `pub get`
    // can resolve them. Handles absolute-path overrides like a local `super_editor`.
    _resolveExternalPathDependencies(currentDirectoryPath, projectRootPath);

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

  /// Verifies that, when the package under test is a member of a Dart pub workspace,
  /// that workspace's root is included in the files copied into the Docker container.
  ///
  /// golden_runner copies the "project root" ([pathToProjectRoot]) into the container.
  /// A pub workspace member (a pubspec with `resolution: workspace`) can't resolve its
  /// dependencies unless the workspace root (a pubspec with a top-level `workspace:` key)
  /// is copied alongside it. If the workspace root sits above the project root, it won't
  /// be copied, and Flutter fails inside the container. In that case, throw a clear error
  /// that tells the caller to point [argPathToProjectRoot] at the workspace root.
  void _verifyWorkspaceRootWillBeCopied({
    required String packageDirectoryPath,
    required String projectRootPath,
  }) {
    final packagePubspec = _environment.readFileAsString(
      path.join(packageDirectoryPath, "pubspec.yaml"),
    );
    if (packagePubspec == null || !_pubspecIsWorkspaceMember(packagePubspec)) {
      // Either there's no pubspec to inspect, or this package isn't a workspace
      // member. There's no workspace root that needs to be copied.
      return;
    }

    // This package is a workspace member. Find the workspace root by walking up
    // the host directory tree, the same way pub does inside the container.
    final workspaceRootPath = _findWorkspaceRoot(packageDirectoryPath);
    final normalizedProjectRoot = path.normalize(projectRootPath);
    if (workspaceRootPath != null &&
        (path.equals(normalizedProjectRoot, workspaceRootPath) ||
            path.isWithin(normalizedProjectRoot, workspaceRootPath))) {
      // The workspace root is at, or within, the project root that we copy into
      // the container, so it'll be available to pub. Nothing to do.
      return;
    }

    // The workspace root won't be copied into the container. Suggest the path the
    // caller most likely needs to pass. If we found the actual root, suggest the
    // exact relative path to it; otherwise fall back to a generic example.
    final suggestedProjectRoot = workspaceRootPath != null
        ? _toPosixPath(path.relative(workspaceRootPath, from: packageDirectoryPath))
        : "../..";

    throw Exception(
      "This package is a member of a Dart pub workspace (its pubspec.yaml has "
      "`resolution: workspace`), but the workspace root isn't included in the files "
      "copied into the Docker container.\n"
      "\n"
      "golden_runner copies the project root into the container, which defaults to the "
      "current directory. Point it at the workspace root so the root pubspec.yaml is "
      "copied too, using ${GoldensCommand.argPathToProjectRoot}. For example:\n"
      "\n"
      "    goldens ${GoldensCommand.argPathToProjectRoot} $suggestedProjectRoot <test target>",
    );
  }

  /// Returns `true` if the given [pubspecContent] declares `resolution: workspace`,
  /// which marks it as a member of a Dart pub workspace.
  bool _pubspecIsWorkspaceMember(String pubspecContent) {
    final pubspec = _tryParseYamlMap(pubspecContent);
    return pubspec != null && pubspec["resolution"] == "workspace";
  }

  /// Returns `true` if the given [pubspecContent] has a top-level `workspace:` key,
  /// which marks it as the root of a Dart pub workspace.
  bool _pubspecIsWorkspaceRoot(String pubspecContent) {
    final pubspec = _tryParseYamlMap(pubspecContent);
    return pubspec != null && pubspec.containsKey("workspace");
  }

  /// Walks up from [packageDirectoryPath] looking for the pubspec.yaml that roots the
  /// Dart pub workspace (the one with a top-level `workspace:` key), and returns its
  /// directory, or `null` if no workspace root is found.
  String? _findWorkspaceRoot(String packageDirectoryPath) {
    var directory = path.normalize(packageDirectoryPath);
    while (true) {
      final pubspecContent = _environment.readFileAsString(
        path.join(directory, "pubspec.yaml"),
      );
      if (pubspecContent != null && _pubspecIsWorkspaceRoot(pubspecContent)) {
        return directory;
      }

      final parent = path.dirname(directory);
      if (parent == directory) {
        // Reached the filesystem root without finding a workspace root.
        return null;
      }
      directory = parent;
    }
  }

  Map? _tryParseYamlMap(String yamlContent) {
    try {
      final document = loadYaml(yamlContent);
      return document is Map ? document : null;
    } catch (_) {
      // If the pubspec can't be parsed, don't block the run over it. Let Flutter
      // surface any resulting error from inside the container.
      return null;
    }
  }

  void _resolveExternalPathDependencies(String currentDirectoryPath, String projectRootPath) {
    final externalPaths = const PathDependencyResolver().resolveExternalPathDependencies(
      copiedRoot: projectRootPath,
      seedPubspecs: [
        path.join(projectRootPath, "pubspec.yaml"),
        path.join(currentDirectoryPath, "pubspec.yaml"),
      ],
      readFile: _environment.readFileAsString,
      directoryExists: _environment.directoryExists,
    );

    _externalPathDependencyMounts = {
      for (final directory in externalPaths) "$directory:$directory:ro",
    };

    if (externalPaths.isNotEmpty && !silent && dockerVerbosity != DockerVerbosity.none) {
      final plural = externalPaths.length == 1 ? "y" : "ies";
      // ignore: avoid_print
      print("[golden_runner] ℹ Mounting ${externalPaths.length} local path dependenc$plural into the container (read-only):");
      for (final directory in externalPaths) {
        // ignore: avoid_print
        print("[golden_runner]   $directory");
      }
    }
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

  /// Reads the file at [filePath] as a string, or returns `null` if no such file exists.
  String? readFileAsString(String filePath) {
    final file = File(filePath);
    return file.existsSync() ? file.readAsStringSync() : null;
  }
}
