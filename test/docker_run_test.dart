import 'dart:io';

import 'package:golden_runner/golden_runner.dart';
import 'package:test/test.dart';

void main() {
  group("consumeSilently (silent output handling) >", () {
    test("dumps stdout AND forwards stderr when the process fails", () async {
      final outs = <String>[];
      final errs = <String>[];
      final process = await Process.start(
        "sh",
        ["-c", "echo 'Some tests failed.'; echo 'a warning' >&2; exit 5"],
      );

      final exitCode = await consumeSilently(process, onStdout: outs.add, onStderr: errs.add);

      expect(exitCode, 5);
      // Failure output (what would be the test failure summary) is surfaced.
      expect(outs.join(), contains("Some tests failed."));
      // stderr is always surfaced.
      expect(errs.join(), contains("a warning"));
    });

    test("hides stdout when the process succeeds", () async {
      final outs = <String>[];
      final errs = <String>[];
      final process = await Process.start(
        "sh",
        ["-c", "echo 'normal progress'; exit 0"],
      );

      final exitCode = await consumeSilently(process, onStdout: outs.add, onStderr: errs.add);

      expect(exitCode, 0);
      // Success stays silent - no stdout surfaced.
      expect(outs, isEmpty);
    });

    test("still forwards stderr on success", () async {
      final errs = <String>[];
      final process = await Process.start(
        "sh",
        ["-c", "echo 'heads up' >&2; exit 0"],
      );

      await consumeSilently(process, onStdout: (_) {}, onStderr: errs.add);
      expect(errs.join(), contains("heads up"));
    });
  });

  group("buildAndRun >", () {
    tearDown(Docker.resetDocker);

    // A custom Dockerfile path skips the (filesystem-touching) context guard and
    // native-asset detection, keeping these tests hermetic. `none` verbosity keeps
    // the checkpoints quiet.
    RunDockerContainerRequest request({bool silent = false}) => RunDockerContainerRequest(
          dockerImageName: "golden_tester",
          dockerVerbosity: DockerVerbosity.none,
          silent: silent,
          dockerFilePath: "custom.Dockerfile",
          command: const ["flutter", "test"],
        );

    test("returns 0 when the build and tests succeed", () async {
      Docker.useDocker(FakeDocker());
      expect(await const DockerGoldenContainer().buildAndRun(request()), 0);
    });

    test("returns the test exit code when tests fail", () async {
      Docker.useDocker(FakeDocker(runContainerExitCode: 3));
      expect(await const DockerGoldenContainer().buildAndRun(request()), 3);
    });

    test("returns the build exit code and skips the container when the build fails", () async {
      final docker = FakeDocker(buildImageExitCode: 7, runContainerExitCode: 0);
      Docker.useDocker(docker);

      expect(await const DockerGoldenContainer().buildAndRun(request()), 7);
      // The container never runs if the image build failed...
      expect(docker.getCallCountFor("runContainer"), 0);
      // ...but the image is still cleaned up.
      expect(docker.getCallCountFor("deleteImage"), 1);
    });

    test("passes the silent flag through to the container run", () async {
      final docker = FakeDocker();
      Docker.useDocker(docker);

      await const DockerGoldenContainer().buildAndRun(request(silent: true));
      expect(docker.lastRunWasSilent, isTrue);

      await const DockerGoldenContainer().buildAndRun(request(silent: false));
      expect(docker.lastRunWasSilent, isFalse);
    });
  });
}
