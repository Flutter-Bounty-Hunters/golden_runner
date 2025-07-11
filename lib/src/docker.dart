import 'dart:io';

import 'package:golden_runner/golden_runner.dart';

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
    required String dockerFilePath,
    required String imageName,
    String? workingDirectory,
    bool throwOnError = false,
  }) async {
    GrLog.docker.info(
      "Building Docker image - docker file: $dockerFilePath, image name: $imageName, working directory: $workingDirectory",
    );

    final process = await Process.start(
      'docker',
      [
        'build',
        '-f',
        dockerFilePath, // e.g., "golden-tester.Dockerfile"
        '-t',
        imageName, // e.g., "golden-tester"
        '.',
      ],
      workingDirectory: workingDirectory,
    );

    await stdout.addStream(process.stdout);
    await stderr.addStream(process.stderr);

    final exitCode = await process.exitCode;

    if (exitCode != 0 && throwOnError) {
      throw Exception(
        'Failed to create Docker image. Exit code: $exitCode. Provided configuration - working directory: $workingDirectory, Dockerfile path: $dockerFilePath, image name: $imageName',
      );
    }

    return exitCode;
  }

  /// Deletes the Docker image with the given [imageName].
  ///
  /// This method calls out to Docker, which must be installed and running on the host
  /// operating system.
  Future<ExitCode> deleteImage({
    required String imageName,
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

    await stdout.addStream(process.stdout);
    await stderr.addStream(process.stderr);

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
    );

    await stdout.addStream(process.stdout);
    await stderr.addStream(process.stderr);

    final exitCode = await process.exitCode;

    if (exitCode != 0 && throwOnError) {
      throw Exception(
        'Failed to run Docker container. Exit code: $exitCode. Provided configuration - working directory: $workingDirectory, image name: $imageName, mount paths: $mountPaths, command to run: $commandToRun',
      );
    }

    return exitCode;
  }
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
    required String dockerFilePath,
    required String imageName,
    String? workingDirectory,
    bool throwOnError = false,
  }) async {
    print("Running buildImage() on fake");
    _incrementCallCount("buildImage");
    _images.add(imageName);
    return 0;
  }

  @override
  Future<ExitCode> deleteImage({required String imageName, bool throwOnError = false}) async {
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
    bool throwOnError = false,
  }) async {
    _incrementCallCount("runContainer");
    return 0;
  }

  void _incrementCallCount(String methodName) {
    _callCounts[methodName] = (_callCounts[methodName] ?? 0) + 1;
  }
}
