import 'dart:convert';
import 'dart:io';

import 'package:golden_runner/golden_runner.dart';

/// Client to build a Docker Image and then run it in a Docker Container.
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

      // (Maybe) mounted part of the host machine with the Container so the Container can alter
      // the host machine.
      mountPaths: request.mountPaths,

      // Within the container, set the working directory to the place where the image
      // copied the project into the container.
      workingDirectory: request.containerWorkingDirectory,

      // The CLI command that runs in the Container. This where all the interesting stuff happens.
      commandToRun: request.command,

      verbosity: request.dockerVerbosity,
    );

    // After running, we don't need the image anymore. Remove it.
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

  /// Locations on the host machine where the Container should be able to read/write.
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

/// A Dart client that talks to Docker on the host machine.
class Docker {
  static Docker? _instance;
  static Docker get instance {
    _instance ??= Docker._();
    return _overrideInstance ?? _instance!;
  }

  static Docker? _overrideInstance;

  /// Uses the given [docker] instead of the default instance, which is primarily intended
  /// for tests to fake/mock the [Docker] implementation.
  static useDocker(Docker docker) => _overrideInstance = docker;

  /// Remove any previous [Docker] given to [useDocker] and return to the default instance,
  /// which means real interactions with the operating system's Docker.
  static resetRocker() => _overrideInstance = null;

  const Docker._();

  /// Returns `true` if Docker is installed on the current operating system, or `false` if its not.
  Future<bool> isInstalled() async {
    final result = await Process.run("which", ["docker"]);
    // We get an exit code of 1 if we run `which` on a non-existent command.
    return result.exitCode == 0;
  }

  /// Returns `true` if Docker is currently running on the operating system, or `false` if its not
  /// running, or not installed.
  Future<bool> isRunning() async {
    final isInstalled = await this.isInstalled();
    if (!isInstalled) {
      return false;
    }

    final result = await Process.run("docker", ["container", "ls"]);
    // The "docker container ls" command is one that requires Docker to actually be
    // running to respond to (unlike "docker --version"). We get an exit code of
    // 1 if Docker isn't running.
    return result.exitCode == 0;
  }

  /// Builds a Docker image based on the given [dockerFilePath], giving it [imageName].
  ///
  /// This method calls out to Docker, which must be installed and running on the host
  /// operating system.
  Future<ExitCode> buildImage({
    String? dockerFilePath,
    required String imageName,
    String? pathToProjectRoot,
    DockerVerbosity verbosity = DockerVerbosity.errorOnly,
    bool throwOnError = false,
  }) async {
    GrLog.docker.info(
      "Building Docker image - docker file: $dockerFilePath, image name: $imageName, working directory: $pathToProjectRoot",
    );

    final process = await Process.start(
      'docker',
      [
        'build',
        // Note: We can't use "interactive" mode because we (may) need to send the Dockerfile
        // through stdin at the end of the Docker command.
        '-t',
        imageName, // e.g., "golden-tester"
        if (dockerFilePath != null) ...[
          '-f',
          dockerFilePath, // e.g., "golden-tester.Dockerfile"
        ] else ...[
          // Send the Dockerfile through STDIN instead of from a file.
          '-f',
          '-',
        ],
        if (verbosity != DockerVerbosity.standard) //
          '-q',
        '.',
      ],
      workingDirectory: pathToProjectRoot,
    );
    GrLog.docker.finer("Docker process started");

    if (dockerFilePath == null) {
      // Send the Dockerfile through STDIN instead of from a file.
      process.stdin.write(_createVirtualDockerfile());
      await process.stdin.close();
      GrLog.docker.finer("Virtual Dockerfile sent to Docker process");
    }

    // Handle the Process's stdout and stderr concurrently to prevent a possible deadlock.
    await Future.wait([
      process.stdout.transform(utf8.decoder).forEach(
          verbosity != DockerVerbosity.errorOnly && verbosity != DockerVerbosity.none ? _sendToStdOut : _noOpOutput),
      process.stderr.transform(utf8.decoder).forEach(verbosity != DockerVerbosity.none ? _sendToStdErr : _noOpOutput),
    ]);

    GrLog.docker.finer("Waiting for Docker process to finish");
    final exitCode = await process.exitCode;
    GrLog.docker.finer("Docker process finished - exist code: $exitCode");

    if (exitCode != 0 && throwOnError) {
      throw Exception(
        'Failed to create Docker image. Exit code: $exitCode. Provided configuration - working directory: $pathToProjectRoot, Dockerfile path: $dockerFilePath, image name: $imageName',
      );
    }

    return exitCode;
  }

  String _createVirtualDockerfile() {
    return r'''
FROM ubuntu:latest

ENV FLUTTER_HOME=${HOME}/sdks/flutter 
ENV PATH ${PATH}:${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin

USER root

RUN apt update

RUN apt install -y git curl unzip

# Print the Ubuntu version. Useful when there are failing tests.
RUN cat /etc/lsb-release

# Invalidate the cache when flutter pushes a new commit.
ADD https://api.github.com/repos/flutter/flutter/git/refs/heads/stable ./flutter-latest-stable

RUN git clone https://github.com/flutter/flutter.git ${FLUTTER_HOME}

RUN flutter doctor

# Copy the whole repo, which makes it possible for one package to reference
# other packages within a mono-repo.
COPY ./ /golden_tester
''';
  }

  /// Deletes the Docker image with the given [imageName].
  ///
  /// This method calls out to Docker, which must be installed and running on the host
  /// operating system.
  Future<ExitCode> deleteImage({
    required String imageName,
    DockerVerbosity verbosity = DockerVerbosity.errorOnly,
    bool throwOnError = false,
  }) async {
    final process = await Process.start(
      'docker',
      [
        'image', 'rm', //
        '-f',
        imageName,
      ],
    );

    if (verbosity == DockerVerbosity.standard) {
      await stdout.addStream(process.stdout);
    } else {
      // Ignore stdout. We ignore stdout, even in "quiet" mode, because the
      // "docker image rm" command doesn't support any verbosity control, itself.
      await process.stdout.drain();
    }

    if (verbosity != DockerVerbosity.none) {
      await stderr.addStream(process.stderr);
    } else {
      // Ignore stderr.
      await process.stderr.drain();
    }

    final exitCode = await process.exitCode;

    if (exitCode != 0 && throwOnError) {
      throw Exception(
        'Failed to remove Docker image. Exit code: $exitCode. Provided configuration - image name: $imageName',
      );
    }

    return exitCode;
  }

  /// Starts a Docker container based on the Docker image with the given [imageName].
  ///
  /// After starting the container, the [commandToRun] is run within the container.
  ///
  /// Optionally, a set of host operating system paths can be mounted into the Docker container
  /// so that files are shared between the two.
  ///
  /// This method calls out to Docker, which must be installed and running on the host
  /// operating system.
  Future<ExitCode> runContainer({
    required String imageName,
    Set<String> mountPaths = const {},
    String? workingDirectory,
    required List<String> commandToRun,
    DockerVerbosity verbosity = DockerVerbosity.errorOnly,
    bool throwOnError = false,
  }) async {
    GrLog.docker.info("Running Docker container: $imageName");
    GrLog.docker.fine(" - mount paths: $mountPaths");
    GrLog.docker.fine(" - working directory: $workingDirectory");
    GrLog.docker.fine(" - command to run: $commandToRun");

    final args = [
      'run',
      // Remove the container when it exits.
      '--rm',
      // Run as an interactive (i) terminal (t). Running as a terminal retains color
      // formatting. Making it interactive allows lines to be replaced so that a single test
      // doesn't produce dozens of the same line of output over time.
      '-it',
      if (verbosity != DockerVerbosity.standard) //
        '--log-driver=none',
      // If desired, mount some paths from the host machine into the container to share
      // files.
      for (final path in mountPaths) ...[
        '-v', path, //
      ],
      // If desired, set the working directory within the container.
      if (workingDirectory != null) ...[
        '--workdir', workingDirectory, //
      ],
      // The name of the Docker image, from which a container is started.
      imageName,
      // The command to run within the container. For example, this could be a
      // "flutter test" to run tests within a container.
      ...commandToRun,
    ];
    GrLog.docker.fine("Run arguments: $args");

    final process = await Process.start(
      'docker',
      args,
      // Must inherit stdio to be able to configure the command as an interactive terminal.
      // If we pipe streams instead of inheriting, we can still operate as a terminal (-t),
      // but we get an error when trying interactive (-i).
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;

    if (exitCode != 0 && throwOnError) {
      throw Exception(
        'Failed to run Docker container. Exit code: $exitCode. Provided configuration - working directory: $workingDirectory, image name: $imageName, mount paths: $mountPaths, command to run: $commandToRun',
      );
    }

    return exitCode;
  }
}

void _sendToStdOut(String output) {
  stdout.write(output);
}

void _sendToStdErr(String output) {
  stderr.write(output);
}

void _noOpOutput(String output) {
  // No-op.
}

typedef ExitCode = int;

class FakeDocker implements Docker {
  FakeDocker({
    bool isInstalled = true,
    bool isRunning = true,
  })  : _isInstalled = isInstalled,
        _isRunning = isRunning;

  final bool _isInstalled;
  final bool _isRunning;

  final _images = <String>{};

  int getCallCountFor(String methodName) => _callCounts[methodName] ?? 0;
  final _callCounts = <String, int>{};

  @override
  Future<bool> isInstalled() async {
    _incrementCallCount("isInstalled");
    return _isInstalled;
  }

  @override
  Future<bool> isRunning() async {
    _incrementCallCount("isRunning");
    return _isRunning;
  }

  @override
  Future<ExitCode> buildImage({
    String? dockerFilePath,
    required String imageName,
    String? pathToProjectRoot,
    DockerVerbosity verbosity = DockerVerbosity.errorOnly,
    bool throwOnError = false,
  }) async {
    _incrementCallCount("buildImage");
    _images.add(imageName);
    return 0;
  }

  @override
  String _createVirtualDockerfile() {
    throw UnimplementedError();
  }

  @override
  Future<ExitCode> deleteImage({
    required String imageName,
    DockerVerbosity verbosity = DockerVerbosity.errorOnly,
    bool throwOnError = false,
  }) async {
    _incrementCallCount("deleteImage");
    _images.remove(imageName);
    return 0;
  }

  @override
  Future<ExitCode> runContainer({
    required String imageName,
    Set<String> mountPaths = const {},
    String? workingDirectory,
    required List<String> commandToRun,
    DockerVerbosity verbosity = DockerVerbosity.errorOnly,
    bool throwOnError = false,
  }) async {
    _incrementCallCount("runContainer");
    return 0;
  }

  void _incrementCallCount(String methodName) {
    _callCounts[methodName] = (_callCounts[methodName] ?? 0) + 1;
  }
}

enum DockerVerbosity {
  standard("standard"),
  quiet("quiet"),
  errorOnly("error"),
  none("none");

  static DockerVerbosity parse(String name) {
    final lowerCaseName = name.toLowerCase();
    for (final value in values) {
      if (value.name == lowerCaseName) {
        return value;
      }
    }

    throw Exception("Unknown DockerVerbosity: $name");
  }

  static DockerVerbosity? maybeParse(String? name) {
    if (name == null) {
      return null;
    }

    try {
      return parse(name);
    } catch (exception) {
      return null;
    }
  }

  const DockerVerbosity(this.name);

  final String name;
}
