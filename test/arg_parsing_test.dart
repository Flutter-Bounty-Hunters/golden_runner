import 'package:golden_runner/golden_runner.dart';
import 'package:test/test.dart';

void main() {
  group("Argument parsing >", () {
    group("test command >", () {
      test("with defaults", () async {
        final goldenRequest = parseTestCommandArguments([]);

        // Defaults.
        expect(goldenRequest.dockerFilePath, null);
        expect(goldenRequest.dockerImageName, 'golden_tester');
        expect(goldenRequest.pathToProjectRoot, '.');
        expect(goldenRequest.testBaseDirectory, 'test_goldens');
        expect(goldenRequest.testCommandArguments, []);
        expect(goldenRequest.dockerVerbosity, DockerVerbosity.errorOnly);
      });

      test("with all arguments", () async {
        final goldenRequest = parseTestCommandArguments([
          "--docker-file-path", "./some-dir/golden_tester.Dockerfile", //
          "--docker-image-name", "my_tester_image", //
          "--docker-verbosity", "standard", //
          "--path-to-project-root", "../", //
          "--plain-name", "my test", //
          "--verbose",
          "special_test_goldens",
        ]);

        // Provided values.
        expect(goldenRequest.dockerFilePath, "./some-dir/golden_tester.Dockerfile");
        expect(goldenRequest.dockerImageName, 'my_tester_image');
        expect(goldenRequest.pathToProjectRoot, '../');
        expect(goldenRequest.testBaseDirectory, 'special_test_goldens');
        expect(goldenRequest.testCommandArguments, ["--plain-name", "my test", "--verbose", "special_test_goldens"]);
        expect(goldenRequest.dockerVerbosity, DockerVerbosity.standard);
      });
    });

    test("docker verbosity levels", () async {
      expect(
        parseTestCommandArguments([]).dockerVerbosity,
        DockerVerbosity.errorOnly,
      );

      expect(
        parseTestCommandArguments([
          "--docker-verbosity",
          "standard",
        ]).dockerVerbosity,
        DockerVerbosity.standard,
      );

      expect(
        parseTestCommandArguments([
          "--docker-verbosity",
          "quiet",
        ]).dockerVerbosity,
        DockerVerbosity.quiet,
      );

      expect(
        parseTestCommandArguments([
          "--docker-verbosity",
          "error",
        ]).dockerVerbosity,
        DockerVerbosity.errorOnly,
      );

      expect(
        parseTestCommandArguments([
          "--docker-verbosity",
          "none",
        ]).dockerVerbosity,
        DockerVerbosity.none,
      );
    });
  });
}
