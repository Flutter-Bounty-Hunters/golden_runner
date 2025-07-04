import 'package:golden_runner/golden_runner.dart';
import 'package:test/test.dart';

void main() {
  group("Argument parsing >", () {
    group("test command >", () {
      test("with golden flags", () async {
        final goldenRequest = parseTestCommandArguments([
          "--docker-file-path", "./some-dir/golden_tester.Dockerfile", //
          "--docker-image-name", "my_tester_image", //
          "--path-to-project-root", "../", //
        ]);

        expect(goldenRequest.dockerFilePath, './some-dir/golden_tester.Dockerfile');
        expect(goldenRequest.dockerImageName, 'my_tester_image');
        expect(goldenRequest.pathToProjectRoot, '../');
        expect(goldenRequest.testBaseDirectory, 'test_goldens');
        expect(goldenRequest.testCommandArguments, []);
      });

      test("with test flags", () async {
        final goldenRequest = parseTestCommandArguments(["--verbose", "test_goldens"]);

        expect(goldenRequest.dockerFilePath, './golden_tester.Dockerfile');
        expect(goldenRequest.dockerImageName, 'golden_tester');
        expect(goldenRequest.pathToProjectRoot, '.');
        expect(goldenRequest.testBaseDirectory, 'test_goldens');
        expect(goldenRequest.testCommandArguments, ["--verbose", "test_goldens"]);
      });

      test("with golden flags and test flags", () async {
        final goldenRequest = parseTestCommandArguments([
          "--docker-file-path", "./some-dir/golden_tester.Dockerfile", //
          "--docker-image-name", "my_tester_image", //
          "--path-to-project-root", "../", //
          "--plain-name", "my test", //
          "--verbose",
          "test_goldens",
        ]);

        expect(goldenRequest.dockerFilePath, './some-dir/golden_tester.Dockerfile');
        expect(goldenRequest.dockerImageName, 'my_tester_image');
        expect(goldenRequest.pathToProjectRoot, '../');
        expect(goldenRequest.testBaseDirectory, 'test_goldens');
        expect(goldenRequest.testCommandArguments, ["--plain-name", "my test", "--verbose", "test_goldens"]);
      });
    });
  });
}
