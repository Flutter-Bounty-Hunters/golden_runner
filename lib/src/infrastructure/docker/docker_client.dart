import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:golden_runner/src/infrastructure/build_context.dart';
import 'package:golden_runner/src/infrastructure/checkpoints.dart';
import 'package:golden_runner/src/infrastructure/container_diagnostics.dart';
import 'package:golden_runner/src/infrastructure/logging.dart';
import 'package:golden_runner/src/infrastructure/native_assets.dart';
import 'package:meta/meta.dart';

/// Client to build a Docker Image and then run it in a Docker Container.
class DockerGoldenContainer {
  const DockerGoldenContainer();

  /// Builds the image, runs the tests in a container, and cleans up, returning the
  /// process exit code (0 on success; non-zero if the image build or the tests fail).
  Future<int> buildAndRun(RunDockerContainerRequest request) async {
    // Print high-level progress with per-step timing, because a golden run can spend several
    // minutes in each phase (especially building the image). Stay silent when the caller asked
    // for silent mode, or for no Docker output at all.
    final checkpoints = GrCheckpoints(
      enabled: !request.silent && request.dockerVerbosity != DockerVerbosity.none,
      totalSteps: 3,
    );

    // Before the (potentially slow) build, keep the build context small: if it's
    // large and has no `.dockerignore`, the whole directory - including generated
    // output - is copied into the image on every run. When we're using golden_runner's
    // built-in Dockerfile, apply a sensible default `.dockerignore` for this build via
    // a Dockerfile-adjacent ignore file, so nothing is written into the user's project.
    // A user's own `.dockerignore` is always respected.
    // Applies even in silent mode (it speeds up the build); only the message below
    // is suppressed, since `checkpoints.info` is a no-op when checkpoints are off.
    String? dockerignoreContent;
    if (request.dockerFilePath == null) {
      final assessment = await const BuildContextGuard().assess(request.pathToProjectRoot);
      if (assessment.decision == BuildContextIgnoreDecision.applyDefault) {
        dockerignoreContent = BuildContextGuard.defaultDockerignore;
        final full = "${BuildContextGuard.formatBytes(assessment.measuredBytes)}${assessment.isApproximate ? "+" : ""}";
        final kept = BuildContextGuard.formatBytes(assessment.keptBytes);
        final saved = BuildContextGuard.formatBytes(assessment.savedBytes);
        final percent =
            assessment.measuredBytes > 0 ? (assessment.savedBytes * 100 / assessment.measuredBytes).round() : 0;
        checkpoints.info(
          "Build context at '${assessment.contextPath}' is $full with no .dockerignore - the whole tree would be copied into the image on every run.\n"
          "Applying golden_runner's default .dockerignore shrinks it to ~$kept for this build (saving ~$saved, $percent%) - nothing is written to your project.\n"
          "Add your own .dockerignore to the project to customize what's sent to Docker.",
        );
      }
    }

    // Only install a C toolchain (clang) in the built-in image when the project
    // actually has a Dart native-asset build hook that needs it. Most projects
    // don't, so they get a lighter, faster image. Errs toward including it.
    final includeCToolchain =
        request.dockerFilePath != null || const NativeAssetDetector().needsCToolchain(request.pathToProjectRoot);
    GrLog.docker.info("Including C toolchain in image: $includeCToolchain");

    // Builds the image used to run the container. We can build the image
    // even if it already exists. Docker will cache each step used in the
    // Dockerfile, so subsequent builds will be faster.
    final buildingImageLabel = request.flutterVersion != null
        ? "Building Docker image (Flutter ${request.flutterVersion})"
        : "Building Docker image";
    final buildExitCode = await checkpoints.step(
      buildingImageLabel,
      () => Docker.instance.buildImage(
        dockerFilePath: request.dockerFilePath,
        imageName: request.dockerImageName,
        pathToProjectRoot: request.pathToProjectRoot,
        flutterVersion: request.flutterVersion,
        dockerignoreContent: dockerignoreContent,
        includeCToolchain: includeCToolchain,
        verbosity: request.dockerVerbosity,
      ),
    );

    // Runs the Docker container (which runs `flutter test` internally), unless the
    // image build already failed. In silent mode the container's stdout is dropped
    // but its stderr (errors) still surfaces.
    var testExitCode = buildExitCode;
    if (buildExitCode == 0) {
      testExitCode = await checkpoints.step(
        "Running golden tests in container",
        () => Docker.instance.runContainer(
          imageName: request.dockerImageName,

          // (Maybe) mounted part of the host machine with the Container so the Container can alter
          // the host machine.
          mountPaths: request.mountPaths,

          // Within the container, set the working directory to the place where the image
          // copied the project into the container.
          workingDirectory: request.containerWorkingDirectory,

          // The CLI command that runs in the Container. This where all the interesting stuff happens.
          commandToRun: request.command,

          silent: request.silent,
          verbosity: request.dockerVerbosity,
        ),
      );
    }

    // After running, we don't need the image anymore. Remove it (even on failure).
    await checkpoints.step(
      "Removing Docker image",
      () => Docker.instance.deleteImage(
        imageName: request.dockerImageName,
        verbosity: request.dockerVerbosity,
      ),
    );

    checkpoints.done();

    return testExitCode;
  }
}

class RunDockerContainerRequest {
  const RunDockerContainerRequest({
    this.dockerFilePath,
    required this.dockerImageName,
    required this.dockerVerbosity,
    this.silent = false,
    this.flutterVersion,
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
  final String? dockerFilePath;

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

  /// Whether to run silently: suppress all progress output while still surfacing
  /// errors (stderr, including from the container) and a failing exit code.
  final bool silent;

  /// The Flutter version (a git ref of the flutter/flutter repo, e.g., `"3.44.6"` or `"stable"`)
  /// to install in golden_runner's built-in Dockerfile.
  ///
  /// When `null`, the built-in Dockerfile clones Flutter's default branch. Ignored when a custom
  /// Dockerfile is provided via [dockerFilePath].
  final String? flutterVersion;

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
          silent == other.silent &&
          flutterVersion == other.flutterVersion &&
          pathToProjectRoot == other.pathToProjectRoot &&
          containerWorkingDirectory == other.containerWorkingDirectory &&
          const DeepCollectionEquality().equals(mountPaths, other.mountPaths) &&
          const DeepCollectionEquality().equals(command, other.command);

  @override
  int get hashCode => Object.hash(
        dockerFilePath,
        dockerImageName,
        dockerVerbosity,
        silent,
        flutterVersion,
        const DeepCollectionEquality().hash(mountPaths),
        pathToProjectRoot,
        containerWorkingDirectory,
        const DeepCollectionEquality().hash(command),
      );
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
  static resetDocker() => _overrideInstance = null;

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
    String? flutterVersion,
    String? dockerignoreContent,
    bool includeCToolchain = true,
    DockerVerbosity verbosity = DockerVerbosity.errorOnly,
    bool throwOnError = false,
  }) async {
    GrLog.docker.info(
      "Building Docker image - docker file: $dockerFilePath, image name: $imageName, working directory: $pathToProjectRoot, flutter version: ${flutterVersion ?? "default"}, C toolchain: $includeCToolchain",
    );

    // For golden_runner's built-in Dockerfile, write it to a temp directory OUTSIDE
    // the project and point `-f` at it. When a default `.dockerignore` is supplied,
    // write it next to the Dockerfile as a Dockerfile-adjacent ignore file
    // (`<dockerfile>.dockerignore`), which BuildKit honors for the build context.
    // This lets us shrink the context without writing any file into the user's project.
    Directory? tempBuildDir;
    var effectiveDockerFilePath = dockerFilePath;
    if (dockerFilePath == null) {
      tempBuildDir = Directory.systemTemp.createTempSync("golden_runner_build");
      final dockerfile = File(_join(tempBuildDir.path, "golden_tester.Dockerfile"))
        ..writeAsStringSync(createGoldenTesterDockerfile(
          flutterVersion: flutterVersion,
          includeCToolchain: includeCToolchain,
        ));
      if (dockerignoreContent != null) {
        File("${dockerfile.path}.dockerignore").writeAsStringSync(dockerignoreContent);
      }
      effectiveDockerFilePath = dockerfile.path;
      GrLog.docker.finer("Wrote virtual Dockerfile to ${dockerfile.path}");
    }

    try {
      final process = await Process.start(
        'docker',
        [
          'build',
          '-t',
          imageName, // e.g., "golden-tester"
          '-f',
          effectiveDockerFilePath!, // golden_runner's temp Dockerfile, or the caller's own
          if (verbosity != DockerVerbosity.standard) //
            '-q',
          '.',
        ],
        workingDirectory: pathToProjectRoot,
      );
      GrLog.docker.finer("Docker process started");

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
          'Failed to create Docker image. Exit code: $exitCode. Provided configuration - working directory: $pathToProjectRoot, Dockerfile path: $effectiveDockerFilePath, image name: $imageName',
        );
      }

      return exitCode;
    } finally {
      tempBuildDir?.deleteSync(recursive: true);
    }
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
    bool silent = false,
    DockerVerbosity verbosity = DockerVerbosity.errorOnly,
    bool throwOnError = false,
  }) async {
    GrLog.docker.info("Running Docker container: $imageName");
    GrLog.docker.fine(" - mount paths: $mountPaths");
    GrLog.docker.fine(" - working directory: $workingDirectory");
    GrLog.docker.fine(" - command to run: $commandToRun");

    // In non-silent mode we inherit the real terminal for the live display (color, and in-place
    // line replacement so a single test doesn't spam dozens of lines). That means we can't watch
    // the stream directly, so we give the container a name and replay its captured logs through
    // the scanner after it exits. In silent mode we already pipe the streams, so we scan inline
    // and let Docker auto-remove the container with `--rm`.
    final containerName = silent ? null : "${imageName}_run_$pid";

    // Watch the container's output for known failure signatures (e.g. the Dart compiler being
    // killed when Docker runs out of memory) so we can explain an otherwise-cryptic failure.
    final failureScanner = StreamingMatcher(ContainerFailureDiagnostics.compilerCrashMarker);

    final args = [
      'run',
      // In silent mode, auto-remove the container on exit. In non-silent mode we need its logs
      // after it exits (to scan them), so we name it and remove it ourselves in the `finally`.
      if (silent) '--rm' else ...['--name', containerName!],
      // Allocate a pseudo-terminal (t) for a nicer live display: color formatting, and line
      // replacement. This needs the inherited real terminal (below) to size correctly, so it's
      // used only in non-silent mode; silent mode pipes clean, TTY-free logs.
      if (!silent) '-it',
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

    final ExitCode exitCode;
    if (silent) {
      // Silent mode: buffer the container's stdout and only print it if the run fails, so a
      // failing golden test still shows its failure summary (and CI logs aren't a silent
      // success). stderr is always forwarded so errors surface live. We scan the streams inline.
      final process = await Process.start('docker', args);
      exitCode = await consumeSilently(process, onScan: failureScanner.add);
    } else {
      // Non-silent: inherit the real terminal so the run behaves as an interactive terminal
      // (needed for `-it`'s color and in-place updates). Clear any stale container with our name,
      // run, then replay the captured logs through the scanner and remove the container.
      await _removeContainer(containerName!);
      try {
        final process = await Process.start('docker', args, mode: ProcessStartMode.inheritStdio);
        exitCode = await process.exitCode;
        await _scanContainerLogs(containerName, failureScanner);
      } finally {
        await _removeContainer(containerName);
      }
    }

    // If the container died in a recognizable way, print a plain-language explanation. This is an
    // error diagnosis, so it surfaces even in silent mode - but not when the caller asked for no
    // Docker output at all.
    if (failureScanner.found && verbosity != DockerVerbosity.none) {
      _sendToStdErr("\n[golden_runner] ✗ ${ContainerFailureDiagnostics.compilerCrashDiagnostic}\n");
    }

    if (exitCode != 0 && throwOnError) {
      throw Exception(
        'Failed to run Docker container. Exit code: $exitCode. Provided configuration - working directory: $workingDirectory, image name: $imageName, mount paths: $mountPaths, command to run: $commandToRun',
      );
    }

    return exitCode;
  }
}

String _join(String directory, String file) => "$directory${Platform.pathSeparator}$file";

/// Builds golden_runner's built-in ("virtual") Dockerfile.
///
/// When [flutterVersion] is provided, the container clones that exact git ref
/// (tag/branch/commit) of flutter/flutter, so the SDK matches the project (and CI)
/// - a pinned version never moves, so Docker caches the clone layer.
///
/// When [flutterVersion] is `null`, the container tracks Flutter's **stable**
/// channel: it clones `--branch stable`, and an `ADD` of stable's git ref busts the
/// Docker cache whenever stable advances, so the clone picks up new stable releases.
/// (For strict reproducibility, pass a specific version instead.)
///
/// [includeCToolchain] adds a C toolchain (clang, build-essential), needed only for
/// projects with a Dart native-asset build hook (package:native_toolchain_c).
@visibleForTesting
String createGoldenTesterDockerfile({String? flutterVersion, bool includeCToolchain = true}) {
  final installFlutter = flutterVersion != null
      ? "# Clone the pinned Flutter version so the container matches the project (and CI).\n"
          "RUN git clone https://github.com/flutter/flutter.git --branch $flutterVersion \${FLUTTER_HOME}"
      : "# Default to Flutter's stable channel. The ADD busts the Docker cache whenever stable\n"
          "# advances, so the clone below picks up new stable releases.\n"
          "ADD https://api.github.com/repos/flutter/flutter/git/refs/heads/stable ./flutter-latest-stable\n"
          "\n"
          "RUN git clone https://github.com/flutter/flutter.git --branch stable \${FLUTTER_HOME}";

  // git/curl/unzip are always needed to fetch Flutter. clang and build-essential provide a
  // C toolchain, added only when the project has a Dart native-asset build hook
  // (package:native_toolchain_c) that compiles native code during `flutter test`; without a
  // compiler on PATH such builds fail with "No compiler configured on host". Projects with no
  // native hooks get a lighter image without the toolchain.
  final aptPackages = includeCToolchain ? "git curl unzip clang build-essential" : "git curl unzip";

  return """
FROM ubuntu:latest

ENV FLUTTER_HOME=\${HOME}/sdks/flutter
ENV PATH \${PATH}:\${FLUTTER_HOME}/bin:\${FLUTTER_HOME}/bin/cache/dart-sdk/bin

USER root

RUN apt update

RUN apt install -y $aptPackages

# Print the Ubuntu version. Useful when there are failing tests.
RUN cat /etc/lsb-release

$installFlutter

RUN flutter doctor

# Copy the whole repo, which makes it possible for one package to reference
# other packages within a mono-repo.
COPY ./ /golden_tester
""";
}

/// Consumes a [process]'s output for silent mode.
///
/// stderr is forwarded live via [onStderr] (default: this process's stderr), so errors
/// always surface. stdout is buffered and, **only if the process exits non-zero**, written
/// via [onStdout] (default: this process's stdout) - so a failing run (e.g. a golden test
/// failure) still shows its output, while a successful run stays silent. Returns the exit code.
///
/// [onScan] (if provided) receives every stdout and stderr chunk as it arrives, so callers can
/// watch the output for failure signatures without buffering all of it.
@visibleForTesting
Future<int> consumeSilently(
  Process process, {
  void Function(String)? onStdout,
  void Function(String)? onStderr,
  void Function(String)? onScan,
}) async {
  final writeStdout = onStdout ?? stdout.write;
  final writeStderr = onStderr ?? stderr.write;

  final bufferedStdout = StringBuffer();
  await Future.wait([
    process.stdout.transform(utf8.decoder).forEach((chunk) {
      onScan?.call(chunk);
      bufferedStdout.write(chunk);
    }),
    process.stderr.transform(utf8.decoder).forEach((chunk) {
      onScan?.call(chunk);
      writeStderr(chunk);
    }),
  ]);

  final exitCode = await process.exitCode;
  if (exitCode != 0 && bufferedStdout.isNotEmpty) {
    writeStdout(bufferedStdout.toString());
  }
  return exitCode;
}

/// Feeds the captured logs of the container named [containerName] through [matcher], so a
/// non-silent run (whose live output was inherited by the terminal, not piped to us) can still be
/// scanned for failure signatures after it exits.
///
/// Best-effort: if `docker logs` isn't available (e.g. a `none` log driver, or Docker errors),
/// the scan simply finds nothing, since the diagnosis is a nice-to-have on top of the real output.
Future<void> _scanContainerLogs(String containerName, StreamingMatcher matcher) async {
  try {
    final process = await Process.start('docker', ['logs', containerName]);
    await Future.wait([
      process.stdout.transform(utf8.decoder).forEach(matcher.add),
      process.stderr.transform(utf8.decoder).forEach(matcher.add),
    ]);
    await process.exitCode;
  } catch (_) {
    // Ignore - detection is best-effort.
  }
}

/// Force-removes the container named [containerName], ignoring the common case where no such
/// container exists. Used to clear a stale container before a named run, and to clean up after.
Future<void> _removeContainer(String containerName) async {
  try {
    final process = await Process.start('docker', ['rm', '-f', containerName]);
    await Future.wait([process.stdout.drain<void>(), process.stderr.drain<void>()]);
    await process.exitCode;
  } catch (_) {
    // Ignore - best-effort cleanup.
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
    int buildImageExitCode = 0,
    int runContainerExitCode = 0,
  })  : _isInstalled = isInstalled,
        _isRunning = isRunning,
        _buildImageExitCode = buildImageExitCode,
        _runContainerExitCode = runContainerExitCode;

  final bool _isInstalled;
  final bool _isRunning;
  final int _buildImageExitCode;
  final int _runContainerExitCode;

  /// Records whether the most recent `runContainer` call requested silent mode.
  bool? lastRunWasSilent;

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
    String? flutterVersion,
    String? dockerignoreContent,
    bool includeCToolchain = true,
    DockerVerbosity verbosity = DockerVerbosity.errorOnly,
    bool throwOnError = false,
  }) async {
    _incrementCallCount("buildImage");
    _images.add(imageName);
    return _buildImageExitCode;
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
    bool silent = false,
    DockerVerbosity verbosity = DockerVerbosity.errorOnly,
    bool throwOnError = false,
  }) async {
    _incrementCallCount("runContainer");
    lastRunWasSilent = silent;
    return _runContainerExitCode;
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
