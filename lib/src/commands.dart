import 'dart:io';

import 'package:golden_runner/golden_runner.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

/// Runs golden tests or golden updates, based on the given CLI [arguments].
class GoldensRunner {
  static const argDockerFilePath = "--docker-file-path";
  static const argDockerImageName = "--docker-image-name";
  static const argPathToProjectRoot = "--path-to-project-root";
  static const argVerbose = "--verbose";
  static const argVerboseShort = "-v";
  static const argDockerVerbosity = "--docker-verbosity";

  static const defaultDockerImageName = "golden_tester";
  static const defaultPathToProjectRoot = ".";
  static const defaultTestDirectoryPath = "test_goldens";

  Future<void> run(List<String> arguments) async {
    GrLog.commands.info("Goldens runner, running with arguments: $arguments");

    if (arguments.isEmpty) {
      throw Exception("Not enough arguments: '${arguments.join(" ")}'");
    }

    if (arguments.first == "test") {
      GrLog.commands.fine("Running golden test comparisons");
      await _runGoldenCommand(arguments.sublist(1));
    } else if (arguments.first == "update") {
      GrLog.commands.fine("Updating goldens");
      await _runGoldenCommand(arguments.sublist(1), updateGoldens: true);
    } else if (arguments.first == "clean") {
      GrLog.commands.fine("Cleaning golden failure artifacts");
      await cleanGoldenFailures(
        parseCleanCommandArguments(arguments.sublist(1)),
      );
    } else {
      throw Exception("Unknown command: ${arguments.first}");
    }
  }
}

Future<void> _runGoldenCommand(
  List<String> arguments, {
  bool updateGoldens = false,
}) async {
  final goldenRequest = parseTestCommandArguments(arguments);

  // Builds the image used to run the container. We can build the image
  // even if it already exists. Docker will cache each step used in the
  // Dockerfile, so subsequent builds will be faster.
  await Docker.instance.buildImage(
    dockerFilePath: goldenRequest.dockerFilePath,
    imageName: goldenRequest.dockerImageName,
    workingDirectory: goldenRequest.pathToProjectRoot,
    verbosity: goldenRequest.dockerVerbosity,
  );

  // Runs the Docker container, which then runs the Flutter test command internally.
  await Docker.instance.runContainer(
    imageName: goldenRequest.dockerImageName,

    mountPaths: {
      // Mount the entire host machine test directory so that the container can either
      // create failure files, or create updated golden files.
      '${Directory.current.path}/${goldenRequest.testBaseDirectory}:/golden_tester/${goldenRequest.packageDirectory}/${goldenRequest.testBaseDirectory}',
    },

    // Within the container, set the working directory to the place where the image
    // copied the project into the container.
    workingDirectory: '/golden_tester/${goldenRequest.packageDirectory}',

    // Run a "flutter test" command inside the container.
    commandToRun: [
      'flutter',
      'test',
      if (updateGoldens) //
        '--update-goldens',
      ...goldenRequest.testCommandArguments,
    ],

    verbosity: goldenRequest.dockerVerbosity,
  );

  // After running the tests, we don't need the image anymore. Remove it.
  await Docker.instance.deleteImage(
    imageName: goldenRequest.dockerImageName,
    verbosity: goldenRequest.dockerVerbosity,
  );
}

@visibleForTesting
GoldenRequest parseTestCommandArguments(List<String> arguments) {
  GrLog.commands.fine("Parsing command arguments: $arguments");
  final optionNames = [
    GoldensRunner.argDockerFilePath,
    GoldensRunner.argDockerImageName,
    GoldensRunner.argPathToProjectRoot,
    GoldensRunner.argDockerVerbosity,
  ];

  final options = <String, String?>{};
  for (final name in optionNames) {
    options[name] = _parseOption(arguments, name);
  }
  GrLog.commands.fine("Parsed options: $options");

  var testDirectoryPath = GoldensRunner.defaultTestDirectoryPath;
  final testDirectoryOrFile = arguments.isEmpty ||
          arguments.last.startsWith("--") ||
          arguments.last.startsWith("-") //
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
          testDirectoryOrFile.length -
              path.basename(testDirectoryOrFile).length,
        );
      }
    }
  }
  GrLog.commands.fine("Test directory: $testDirectoryPath");

  // The tool must run from the root of the package being tested.
  // In a single-project repository, this should be the case automatically.
  // However, in a mono-repo, this command must be run from a subdirectory
  // that corresponds to the project under test.
  //
  // For example, `super_editor` is a mono-repo. Therefore, golden tests
  // must be run from within subdirectories, such as:
  //  - `super_editor/super_editor/`
  //  - `super_editor/super_text_layout/`
  //  - `super_editor/super_editor_markdown/'
  final packageDirectory = path.split(Directory.current.path).last;

  // Other arguments passed at the end of the command.
  // For example, the test directory.
  final testCommandArguments = [...arguments];
  GrLog.commands.fine("Test command arguments: $testCommandArguments");

  return GoldenRequest(
    dockerFilePath: options[GoldensRunner.argDockerFilePath],
    dockerImageName: options[GoldensRunner.argDockerImageName] ??
        GoldensRunner.defaultDockerImageName,
    packageDirectory: packageDirectory,
    pathToProjectRoot: options[GoldensRunner.argPathToProjectRoot] ??
        GoldensRunner.defaultPathToProjectRoot,
    testBaseDirectory: testDirectoryPath,
    testCommandArguments: testCommandArguments,
    dockerVerbosity: options[GoldensRunner.argDockerVerbosity] != null
        ? DockerVerbosity.parse(options[GoldensRunner.argDockerVerbosity]!)
        : DockerVerbosity.errorOnly,
  );
}

String? _parseOption(List<String> arguments, String name) {
  String? value;
  for (int i = arguments.length - 1; i >= 0; i -= 1) {
    if (arguments[i] == name && i < arguments.length - 1) {
      if (value != null) {
        throw Exception("Multiple values found for parameter: $name");
      }

      value = arguments[i + 1];
      arguments.removeAt(i + 1);
      arguments.removeAt(i);
      continue;
    }

    if (arguments[i].contains("=")) {
      final pieces = arguments[i].split("=");
      if (pieces.length != 2) {
        continue;
      }

      final key = pieces.first;
      if (key.trim() != name) {
        continue;
      }

      value = pieces.last;
      arguments.removeAt(i);
      continue;
    }
  }

  return value;
}

@visibleForTesting
CleanRequest parseCleanCommandArguments(List<String> arguments) {
  GrLog.commands.fine("Parsing clean command arguments: $arguments");

  var includeLooseFiles = false;
  var dryRun = false;
  var silent = false;
  var verbose = false;
  final positionalArguments = <String>[];

  for (final argument in arguments) {
    switch (argument) {
      case "--loose-files":
        includeLooseFiles = true;
      case "--dry-run":
        dryRun = true;
      case "--silent":
        silent = true;
      case GoldensRunner.argVerbose:
      case GoldensRunner.argVerboseShort:
        verbose = true;
      default:
        if (argument.startsWith("-")) {
          throw Exception("Unknown clean option: $argument");
        }

        positionalArguments.add(argument);
    }
  }

  if (positionalArguments.length > 1) {
    throw Exception(
      "Expected at most one clean target path, but found: ${positionalArguments.join(", ")}",
    );
  }

  if (silent && verbose) {
    throw Exception("Cannot use --silent with --verbose.");
  }

  if (silent && dryRun) {
    throw Exception(
      "Cannot use --silent with --dry-run. Dry run is intended as a print-only behavior.",
    );
  }

  return CleanRequest(
    targetPath: positionalArguments.isEmpty
        ? GoldensRunner.defaultTestDirectoryPath
        : positionalArguments.single,
    includeLooseFiles: includeLooseFiles,
    dryRun: dryRun,
    silent: silent,
    verbose: verbose,
  );
}

@visibleForTesting
Future<CleanResult> cleanGoldenFailures(
  CleanRequest request, {
  void Function(String line)? printLine,
}) async {
  printLine ??= (line) => stdout.writeln(line);

  final targetType = FileSystemEntity.typeSync(
    request.targetPath,
    followLinks: false,
  );
  if (targetType == FileSystemEntityType.notFound) {
    throw Exception("Clean target does not exist: ${request.targetPath}");
  }

  if (targetType == FileSystemEntityType.link) {
    throw Exception("Clean target cannot be a symlink: ${request.targetPath}");
  }

  final targetDirectory = targetType == FileSystemEntityType.file //
      ? Directory(path.dirname(request.targetPath))
      : Directory(request.targetPath);

  final failureDirectories = <Directory>[
    if (path.basename(targetDirectory.path) == "failures") //
      targetDirectory,
  ];
  final looseFailureFiles = <File>[];

  await for (final entity in targetDirectory.list(
    recursive: true,
    followLinks: false,
  )) {
    final entityType = await FileSystemEntity.type(
      entity.path,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.directory &&
        path.basename(entity.path) == "failures") {
      failureDirectories.add(Directory(entity.path));
      continue;
    }

    if (request.includeLooseFiles &&
        entityType == FileSystemEntityType.file &&
        _isLooseFailureFile(entity.path)) {
      looseFailureFiles.add(File(entity.path));
    }
  }

  final topLevelFailureDirectories = _topLevelFailureDirectories(
    failureDirectories,
  );
  final looseFilesOutsideFailureDirectories = looseFailureFiles
      .where(
        (file) => !_isWithinAnyDirectory(
          file.path,
          topLevelFailureDirectories.map((directory) => directory.path),
        ),
      )
      .toList();

  if (request.verbose && request.dryRun) {
    for (final directory in topLevelFailureDirectories) {
      printLine(
        "Would delete directory: ${path.relative(directory.path)}",
      );
    }

    for (final file in looseFilesOutsideFailureDirectories) {
      printLine("Would delete file: ${path.relative(file.path)}");
    }
  }

  if (!request.dryRun) {
    for (final directory in topLevelFailureDirectories) {
      await directory.delete(recursive: true);
      if (request.verbose) {
        printLine("Deleted directory: ${path.relative(directory.path)}");
      }
    }

    for (final file in looseFilesOutsideFailureDirectories) {
      await file.delete();
      if (request.verbose) {
        printLine("Deleted file: ${path.relative(file.path)}");
      }
    }
  }

  final result = CleanResult(
    deletedFailureDirectoryCount: topLevelFailureDirectories.length,
    deletedLooseFailureFileCount: looseFilesOutsideFailureDirectories.length,
    dryRun: request.dryRun,
  );

  if (!request.silent) {
    printLine(result.summary);
  }

  return result;
}

bool _isLooseFailureFile(String filePath) {
  final filename = path.basename(filePath);
  return filename.endsWith(".masterImage.png") ||
      filename.endsWith(".testImage.png") ||
      filename.endsWith(".isolatedDiff.png") ||
      filename.endsWith(".maskedDiff.png") ||
      (filename.startsWith("failure_") && filename.endsWith(".png"));
}

List<Directory> _topLevelFailureDirectories(List<Directory> directories) {
  final sortedDirectories = [...directories]..sort(
      (a, b) => path.split(a.path).length.compareTo(path.split(b.path).length),
    );

  final topLevelDirectories = <Directory>[];
  for (final directory in sortedDirectories) {
    if (!_isWithinAnyDirectory(
      directory.path,
      topLevelDirectories.map((directory) => directory.path),
    )) {
      topLevelDirectories.add(directory);
    }
  }

  return topLevelDirectories;
}

bool _isWithinAnyDirectory(String childPath, Iterable<String> parentPaths) {
  final canonicalChildPath = path.canonicalize(childPath);
  for (final parentPath in parentPaths) {
    final canonicalParentPath = path.canonicalize(parentPath);
    if (path.equals(canonicalChildPath, canonicalParentPath)) {
      continue;
    }

    if (path.isWithin(canonicalParentPath, canonicalChildPath)) {
      return true;
    }
  }

  return false;
}

class CleanRequest {
  const CleanRequest({
    required this.targetPath,
    required this.includeLooseFiles,
    required this.dryRun,
    required this.silent,
    required this.verbose,
  });

  /// The file or directory that scopes the cleanup.
  ///
  /// Directory targets are searched directly. File targets scope cleanup to
  /// the file's parent directory.
  final String targetPath;

  /// Whether to delete loose PNG files that match Flutter golden failure names.
  final bool includeLooseFiles;

  /// Whether to print what would be deleted without deleting anything.
  final bool dryRun;

  /// Whether to suppress command output.
  final bool silent;

  /// Whether to print each deleted path.
  final bool verbose;
}

class CleanResult {
  const CleanResult({
    required this.deletedFailureDirectoryCount,
    required this.deletedLooseFailureFileCount,
    required this.dryRun,
  });

  final int deletedFailureDirectoryCount;
  final int deletedLooseFailureFileCount;
  final bool dryRun;

  String get summary {
    if (deletedFailureDirectoryCount == 0 &&
        deletedLooseFailureFileCount == 0) {
      return dryRun
          ? "No golden failure artifacts would be deleted."
          : "No golden failure artifacts found.";
    }

    final prefix = dryRun ? "Would delete" : "Deleted";
    return "$prefix ${_pluralize(deletedFailureDirectoryCount, "failure directory", "failure directories")} "
        "and ${_pluralize(deletedLooseFailureFileCount, "loose failure file", "loose failure files")}.";
  }

  String _pluralize(int count, String singular, String plural) {
    return "$count ${count == 1 ? singular : plural}";
  }
}

class GoldenRequest {
  const GoldenRequest({
    this.dockerFilePath,
    required this.dockerImageName,
    required this.packageDirectory,
    required this.pathToProjectRoot,
    required this.testBaseDirectory,
    required this.testCommandArguments,
    required this.dockerVerbosity,
  });

  /// The path from where the CLI command is running, to the Dockerfile that says
  /// how to build the image.
  ///
  /// When `null`, golden_runner uses its own version of a Dockerfile, which includes
  /// a configuration that should suit typical users.
  ///
  /// The file path must include the name of the file, e.g., `golden_tester.Dockerfile`.
  final String? dockerFilePath;

  /// The name to give the Docker image when its created.
  ///
  /// This is the name that will identify the Docker image when using an app like
  /// Docker Desktop. The value can be anything.
  final String dockerImageName;

  /// The name of the directory for the package under test.
  ///
  /// Given a package at path `/Users/admin/my_repo/my_app`, the value of
  /// this property would be `my_app`.
  final String packageDirectory;

  /// The relative path from the package under test to the root of the
  /// project.
  ///
  /// For single-package projects, this value should be ".", but for
  /// mono-repos it's probably an ancestor path, such as "../".
  final String pathToProjectRoot;

  /// The full system path to the root test directory, e.g., the path
  /// to the `test` or `test_goldens` directory.
  final String testBaseDirectory;

  /// Arguments that are passed to Flutter's `test` command.
  final List<String> testCommandArguments;

  /// The relative type/volume of logs that should be forwarded from Docker
  /// to the CLI.
  ///
  /// Note: Docker has poor consistency with logging/verbosity configurations.
  /// There may be Docker commands where this verbosity cannot be strictly honored.
  /// However, this package does its best to get as close to the requested verbosity
  /// as possible.
  final DockerVerbosity dockerVerbosity;
}
