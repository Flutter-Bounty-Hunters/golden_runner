import 'dart:io' as io;

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
  static const argUbuntuVersion = "--ubuntu-version";

  /// Verbosity flags. `--silent` suppresses all normal output (but still surfaces
  /// errors and a failing exit code); `--verbose`/`-v` turns on maximum output,
  /// including fine-grained debug logs.
  static const argSilent = "--silent";
  static const argVerbose = "--verbose";
  static const argVerboseShort = "-v";

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

  /// Whether the command is running in silent mode (`--silent`): no progress
  /// output, but errors (including from sub-processes) and a failing exit code
  /// still surface.
  @protected
  @visibleForTesting
  bool get silent => _silent;
  bool _silent = false;

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

  /// Sets the Flutter version to [version] only if one wasn't already provided via
  /// [argFlutterVersion], so an explicit `--flutter-version` always wins over an
  /// auto-detected default (e.g. from FVM config).
  @protected
  void useFlutterVersionIfUnset(String version) => _flutterVersion ??= version;

  /// The Ubuntu version (a Docker Hub `ubuntu` image tag, e.g., `"24.04"`, `"noble"`,
  /// or `"latest"`) to base the Docker Image on.
  ///
  /// When `null`, the default Dockerfile uses `ubuntu:latest`. Pinning a version matters when
  /// golden output depends on the OS's font rendering (a different Ubuntu can paint goldens
  /// slightly differently), or to match the Ubuntu version of your CI runner.
  ///
  /// This only applies to golden_runner's built-in Dockerfile. When a custom Dockerfile is
  /// provided via [argDockerFilePath], that Dockerfile controls the Ubuntu version.
  @protected
  @visibleForTesting
  String? get ubuntuVersion => _ubuntuVersion;
  String? _ubuntuVersion;

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

    _resolveVerbosity(arguments);

    _flutterVersion = parseArgumentOption(arguments, argFlutterVersion);

    _ubuntuVersion = parseArgumentOption(arguments, argUbuntuVersion);
  }

  /// Resolves [dockerVerbosity] and [silent] from the verbosity flags.
  ///
  /// `--silent` and `--verbose`/`-v` are the primary controls; an explicit
  /// `--docker-verbosity` is an advanced override of the Docker passthrough level.
  /// `--silent` is consumed (never forwarded to `flutter test`); `--verbose`/`-v`
  /// is left in place so it also reaches `flutter test`.
  void _resolveVerbosity(List<String> arguments) {
    final explicitDockerVerbosity = DockerVerbosity.maybeParse(parseArgumentOption(arguments, argDockerVerbosity));
    final wantsSilent = parseArgumentFlag(arguments, argSilent);
    final wantsVerbose = hasArgumentFlag(arguments, [argVerbose, argVerboseShort]);

    if (wantsSilent && wantsVerbose) {
      throw Exception("Cannot combine $argSilent with $argVerbose/$argVerboseShort - choose one verbosity level.");
    }

    _silent = wantsSilent;
    _dockerVerbosity = explicitDockerVerbosity ??
        (wantsVerbose ? DockerVerbosity.standard : defaultDockerVerbosity /* errorOnly - keeps errors, hides chatter */);
  }

  @override
  Future<void> run() async {
    final exitCode = await DockerGoldenContainer().buildAndRun(
      assembleDockerContainerRequest(),
    );

    // Propagate a non-zero result (image build failure or failing tests) so the
    // process fails - important for CI, especially in silent mode.
    if (exitCode != 0) {
      io.exitCode = exitCode;
    }
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
        silent: silent,
        flutterVersion: flutterVersion,
        ubuntuVersion: ubuntuVersion,
        mountPaths: mountPaths,
        pathToProjectRoot: pathToProjectRoot,
        containerWorkingDirectory: containerWorkingDirectory,
        command: command,
      );
}
