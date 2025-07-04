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

  static const defaultDockerfilePath = "./golden_tester.Dockerfile";
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
    } else {
      throw Exception("Unknown command: ${arguments.first}");
    }
  }
}

Future<void> _runGoldenCommand(List<String> arguments, {bool updateGoldens = false}) async {
  final goldenRequest = parseTestCommandArguments(arguments);

  // Builds the image used to run the container. We can build the image
  // even if it already exists. Docker will cache each step used in the
  // Dockerfile, so subsequent builds will be faster.
  await Docker.instance.buildImage(
    dockerFilePath: goldenRequest.dockerFilePath,
    imageName: goldenRequest.dockerImageName,
    workingDirectory: goldenRequest.pathToProjectRoot,
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
  );

  // After running the tests, we don't need the image anymore. Remove it.
  await Docker.instance.deleteImage(imageName: goldenRequest.dockerImageName);
}

@visibleForTesting
GoldenRequest parseTestCommandArguments(List<String> arguments) {
  GrLog.commands.fine("Parsing command arguments: $arguments");
  final optionNames = [
    GoldensRunner.argDockerFilePath,
    GoldensRunner.argDockerImageName,
    GoldensRunner.argPathToProjectRoot,
  ];

  final options = <String, String?>{};
  for (final name in optionNames) {
    options[name] = _parseOption(arguments, name);
  }
  GrLog.commands.fine("Parsed options: $options");

  var testDirectoryPath = GoldensRunner.defaultTestDirectoryPath;
  final testDirectoryOrFile = arguments.isEmpty || arguments.last.startsWith("--") || arguments.last.startsWith("-") //
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
    dockerFilePath: options[GoldensRunner.argDockerFilePath] ?? GoldensRunner.defaultDockerfilePath,
    dockerImageName: options[GoldensRunner.argDockerImageName] ?? GoldensRunner.defaultDockerImageName,
    packageDirectory: packageDirectory,
    pathToProjectRoot: options[GoldensRunner.argPathToProjectRoot] ?? GoldensRunner.defaultPathToProjectRoot,
    testBaseDirectory: testDirectoryPath,
    testCommandArguments: testCommandArguments,
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

class GoldenRequest {
  const GoldenRequest({
    required this.dockerFilePath,
    required this.dockerImageName,
    required this.packageDirectory,
    required this.pathToProjectRoot,
    required this.testBaseDirectory,
    required this.testCommandArguments,
  });

  /// The path from the CLI command is running, to the Dockerfile that says
  /// how to build the image.
  ///
  /// The file path must include the name of the file, e.g., `golden_tester.Dockerfile`.
  final String dockerFilePath;

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
}
