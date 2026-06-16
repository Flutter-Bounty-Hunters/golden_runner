import 'package:golden_runner/golden_runner.dart';
import 'package:golden_runner/src/commands/command_base.dart';
import 'package:golden_runner/src/infrastructure/arguments.dart';
import 'package:meta/meta.dart';

/// A CLI command that will be run inside of a Docker Container.
abstract class DockerContainerCommand implements Command {
  static const argDockerFilePath = "--docker-file-path";
  static const argDockerImageName = "--docker-image-name";
  static const argDockerVerbosity = "--docker-verbosity";

  static const defaultDockerImageName = "golden_tester";
  static const defaultDockerVerbosity = DockerVerbosity.errorOnly;

  @visibleForTesting
  String get dockerFilePath => _dockerFilePath!;
  String? _dockerFilePath;

  @visibleForTesting
  String get dockerImageName => _dockerImageName!;
  String? _dockerImageName;

  @visibleForTesting
  DockerVerbosity get dockerVerbosity => _dockerVerbosity!;
  DockerVerbosity? _dockerVerbosity;

  /// Docker mount paths from the host machine into the Docker Container, which allows the Docker Container
  /// to alter the host file system.
  ///
  /// Defaults to nothing.
  Set<String> get mountPaths => {};

  /// The path from where this command is running, to the directory that should be copied over into the
  /// Docker Image.
  ///
  /// Defaults to ".", which copies content from where this command is run.
  String get pathToProjectRoot => ".";

  /// The path within the Docker Container where the [command] should be run.
  ///
  /// Defaults to ".", which runs the command within the root directory of what's copied to the Docker Image.
  String get containerWorkingDirectory => ".";

  /// Returns the CLI command that should run in the Docker Container that's setup by this command.
  ///
  /// It's expected that this command will require information from [parseArguments], so it's OK for
  /// implementers to throw an error if this is ever accessed before [parseArguments] is called.
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

class DockerGoldenContainer {
  const DockerGoldenContainer();

  Future<void> buildAndRun(RunDockerContainerRequest request) async {
    // Builds the image used to run the container. We can build the image
    // even if it already exists. Docker will cache each step used in the
    // Dockerfile, so subsequent builds will be faster.
    await Docker.instance.buildImage(
      dockerFilePath: request.dockerFilePath,
      imageName: request.dockerImageName,
      pathToProjectRoot: request.pathToProjectRoot,
      verbosity: request.dockerVerbosity,
    );

    // Runs the Docker container, which then runs the Flutter test command internally.
    await Docker.instance.runContainer(
      imageName: request.dockerImageName,

      // mountPaths: {
      //   // Mount the entire host machine test directory so that the container can either
      //   // create failure files, or create updated golden files.
      //   '${Directory.current.path}/${request.testBaseDirectory}:/golden_tester/${request.packageDirectory}/${request.testBaseDirectory}',
      // },
      mountPaths: request.mountPaths,

      // Within the container, set the working directory to the place where the image
      // copied the project into the container.
      // workingDirectory: '/golden_tester/${request.packageDirectory}',
      workingDirectory: request.containerWorkingDirectory,

      // Run a "flutter test" command inside the container.
      // commandToRun: [
      //   'flutter',
      //   'test',
      //   if (request.updateGoldens) //
      //     '--update-goldens',
      //   ...request.testCommandArguments,
      // ],
      commandToRun: request.command,

      verbosity: request.dockerVerbosity,
    );

    // After running the tests, we don't need the image anymore. Remove it.
    await Docker.instance.deleteImage(
      imageName: request.dockerImageName,
      verbosity: request.dockerVerbosity,
    );
  }
}

class RunDockerContainerRequest {
  const RunDockerContainerRequest({
    required this.dockerFilePath,
    required this.dockerImageName,
    required this.dockerVerbosity,
    this.mountPaths = const {},
    this.pathToProjectRoot = ".",
    this.containerWorkingDirectory = ".",
    required this.command,
  });

  /// The path from where the CLI command is running, to the Dockerfile that says
  /// how to build the image.
  ///
  /// When `null`, golden_runner uses its own version of a Dockerfile, which includes
  /// a configuration that should suit typical users.
  ///
  /// The file path must include the name of the file, e.g., `golden_tester.Dockerfile`.
  final String dockerFilePath;

  /// The name to give the Docker image when its created.
  ///
  /// This is the name that will identify the Docker image when using an app like
  /// Docker Desktop. The value can be anything.
  final String dockerImageName;

  /// The relative type/volume of logs that should be forwarded from Docker
  /// to the CLI.
  ///
  /// Note: Docker has poor consistency with logging/verbosity configurations.
  /// There may be Docker commands where this verbosity cannot be strictly honored.
  /// However, this package does its best to get as close to the requested verbosity
  /// as possible.
  final DockerVerbosity dockerVerbosity;

  final Set<String> mountPaths;

  /// The path from where this command is executed, to the root of the project that copied into
  /// the image.
  ///
  /// Typically this path is just ".", but there may be instances where this command is run from a directory
  /// other than the directory that should be copied into the image. For example, you run this command from
  /// within a single package in a mono-repo, but the Docker image needs to copy the entire mono-repo so that
  /// it can resolve dependencies. In that case you would pass "..".
  final String pathToProjectRoot;

  /// The working directory within the running container where the [command] will be run.
  ///
  /// Example: `"test_goldens/super_editor/"
  final String containerWorkingDirectory;

  /// Arguments for a CLI command to run within the container, e.g., `["flutter", "test"]`.
  final List<String> command;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunDockerContainerRequest &&
          runtimeType == other.runtimeType &&
          dockerFilePath == other.dockerFilePath &&
          dockerImageName == other.dockerImageName &&
          dockerVerbosity == other.dockerVerbosity &&
          mountPaths == other.mountPaths &&
          pathToProjectRoot == other.pathToProjectRoot &&
          containerWorkingDirectory == other.containerWorkingDirectory &&
          command == other.command;

  @override
  int get hashCode => Object.hash(dockerFilePath, dockerImageName, dockerVerbosity, mountPaths, pathToProjectRoot,
      containerWorkingDirectory, command);
}
