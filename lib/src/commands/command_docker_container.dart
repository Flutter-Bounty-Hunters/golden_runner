import 'package:golden_runner/src/commands/command_base.dart';
import 'package:golden_runner/src/infrastructure/arguments.dart';
import 'package:golden_runner/src/infrastructure/docker/docker_client.dart';
import 'package:meta/meta.dart';

/// A CLI command that will be run inside of a Docker Container.
abstract class DockerContainerCommand implements Command {
  static const argDockerFilePath = "--docker-file-path";
  static const argDockerImageName = "--docker-image-name";
  static const argDockerVerbosity = "--docker-verbosity";
  static const argFlutterVersion = "--flutter-version";

  static const defaultDockerImageName = "golden_tester";
  static const defaultDockerVerbosity = DockerVerbosity.errorOnly;

  @protected
  @visibleForTesting
  String? get dockerFilePath => _dockerFilePath;
  String? _dockerFilePath;

  @protected
  @visibleForTesting
  String get dockerImageName => _dockerImageName!;
  String? _dockerImageName;

  @protected
  @visibleForTesting
  DockerVerbosity get dockerVerbosity => _dockerVerbosity!;
  DockerVerbosity? _dockerVerbosity;

  /// The Flutter version to install in the Docker Container, e.g., `"3.44.6"`, `"stable"`,
  /// or any git ref (tag/branch/commit) of the flutter/flutter repository.
  ///
  /// When `null`, the default Dockerfile clones Flutter's default branch. Pinning a version
  /// is important when the project (or its dependencies) only build against a specific Flutter
  /// SDK - a mismatched SDK can fail to compile, or paint goldens differently.
  ///
  /// This only applies to golden_runner's built-in Dockerfile. When a custom Dockerfile is
  /// provided via [argDockerFilePath], that Dockerfile controls the Flutter version.
  @protected
  @visibleForTesting
  String? get flutterVersion => _flutterVersion;
  String? _flutterVersion;

  /// Docker mount paths from the host machine into the Docker Container, which allows the Docker Container
  /// to alter the host file system.
  ///
  /// Defaults to nothing.
  @protected
  @visibleForTesting
  Set<String> get mountPaths => {};

  /// The path from where this command is running, to the directory that should be copied over into the
  /// Docker Image.
  ///
  /// Defaults to ".", which copies content from where this command is run.
  @protected
  @visibleForTesting
  String get pathToProjectRoot => ".";

  /// The path within the Docker Container where the [command] should be run.
  ///
  /// Defaults to ".", which runs the command within the root directory of what's copied to the Docker Image.
  @protected
  @visibleForTesting
  String get containerWorkingDirectory => ".";

  /// Returns the CLI command that should run in the Docker Container that's setup by this command.
  ///
  /// It's expected that this command will require information from [parseArguments], so it's OK for
  /// implementers to throw an error if this is ever accessed before [parseArguments] is called.
  @protected
  @visibleForTesting
  List<String> get command;

  @override
  @mustCallSuper
  void parseArguments(List<String> arguments) {
    _dockerFilePath = parseArgumentOption(arguments, argDockerFilePath);

    _dockerImageName = parseArgumentOption(arguments, argDockerImageName) ?? defaultDockerImageName;

    _dockerVerbosity =
        DockerVerbosity.maybeParse(parseArgumentOption(arguments, argDockerVerbosity)) ?? defaultDockerVerbosity;

    _flutterVersion = parseArgumentOption(arguments, argFlutterVersion);
  }

  @override
  Future<void> run() async {
    await DockerGoldenContainer().buildAndRun(
      assembleDockerContainerRequest(),
    );
  }

  /// Uses parsed arguments to assemble a [RunDockerContainerRequest], which is then used to tell Docker how to
  /// build an Image and then run in a Container.
  ///
  /// This exists as a method only because we want to verify this request in tests, and we can't create this
  /// request during [parseArguments] because it depends on sub-class argument parsing, which might happen
  /// after we parse our arguments.
  @protected
  @visibleForTesting
  RunDockerContainerRequest assembleDockerContainerRequest() => RunDockerContainerRequest(
        dockerImageName: dockerImageName,
        dockerFilePath: dockerFilePath,
        dockerVerbosity: dockerVerbosity,
        flutterVersion: flutterVersion,
        mountPaths: mountPaths,
        pathToProjectRoot: pathToProjectRoot,
        containerWorkingDirectory: containerWorkingDirectory,
        command: command,
      );
}
