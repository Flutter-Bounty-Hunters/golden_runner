import 'package:golden_runner/src/commands/command_base.dart';
import 'package:golden_runner/src/infrastructure/arguments.dart';
import 'package:golden_runner/src/infrastructure/docker/docker_client.dart';
import 'package:meta/meta.dart';

/// A CLI command that will be run inside of a Docker Container.
abstract class DockerContainerCommand implements Command {
  static const argDockerFilePath = "--docker-file-path";
  static const argDockerImageName = "--docker-image-name";
  static const argDockerVerbosity = "--docker-verbosity";

  static const defaultDockerImageName = "golden_tester";
  static const defaultDockerVerbosity = DockerVerbosity.errorOnly;

  @visibleForTesting
  @protected
  String get dockerFilePath => _dockerFilePath!;
  String? _dockerFilePath;

  @visibleForTesting
  @protected
  String get dockerImageName => _dockerImageName!;
  String? _dockerImageName;

  @visibleForTesting
  @protected
  DockerVerbosity get dockerVerbosity => _dockerVerbosity!;
  DockerVerbosity? _dockerVerbosity;

  /// Docker mount paths from the host machine into the Docker Container, which allows the Docker Container
  /// to alter the host file system.
  ///
  /// Defaults to nothing.
  @protected
  Set<String> get mountPaths => {};

  /// The path from where this command is running, to the directory that should be copied over into the
  /// Docker Image.
  ///
  /// Defaults to ".", which copies content from where this command is run.
  @protected
  String get pathToProjectRoot => ".";

  /// The path within the Docker Container where the [command] should be run.
  ///
  /// Defaults to ".", which runs the command within the root directory of what's copied to the Docker Image.
  @protected
  String get containerWorkingDirectory => ".";

  /// Returns the CLI command that should run in the Docker Container that's setup by this command.
  ///
  /// It's expected that this command will require information from [parseArguments], so it's OK for
  /// implementers to throw an error if this is ever accessed before [parseArguments] is called.
  @protected
  List<String> get command;

  @override
  void parseArguments(List<String> arguments) {
    _dockerFilePath = parseArgumentOption(arguments, argDockerFilePath);
    if (_dockerFilePath == null) {
      throw Exception("Missing $argDockerFilePath argument");
    }

    _dockerImageName = parseArgumentOption(arguments, argDockerImageName) ?? defaultDockerImageName;

    _dockerVerbosity =
        DockerVerbosity.maybeParse(parseArgumentOption(arguments, argDockerVerbosity)) ?? defaultDockerVerbosity;
  }

  @override
  Future<void> run() async {
    await DockerGoldenContainer().buildAndRun(
      RunDockerContainerRequest(
        dockerImageName: dockerImageName,
        dockerFilePath: dockerFilePath,
        dockerVerbosity: dockerVerbosity,
        mountPaths: mountPaths,
        pathToProjectRoot: pathToProjectRoot,
        containerWorkingDirectory: containerWorkingDirectory,
        command: command,
      ),
    );
  }
}
