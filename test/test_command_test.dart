import 'dart:io';

import 'package:golden_runner/golden_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group("Goldens test command argument parsing >", () {
    test("with defaults", () {
      final command = TestGoldensCommand()
        ..parseArguments([
          "--docker-file-path",
          "./golden_tester.Dockerfile",
        ]);

      expect(command.dockerFilePath, "./golden_tester.Dockerfile");
      expect(command.dockerImageName, "golden_tester");
      expect(command.dockerVerbosity, DockerVerbosity.errorOnly);
      expect(command.pathToProjectRoot, ".");
      expect(command.packageDirectory, path.basename(Directory.current.path));
      expect(command.testBaseDirectory, "test_goldens");
      expect(command.testCommandArguments, []);
      expect(command.command, ["flutter", "test"]);
    });

    test("with all arguments", () {
      final command = TestGoldensCommand()
        ..parseArguments([
          "--docker-file-path",
          "./some-dir/golden_tester.Dockerfile",
          "--docker-image-name",
          "my_tester_image",
          "--docker-verbosity",
          "standard",
          "--path-to-project-root",
          "../",
          "--plain-name",
          "my test",
          "--verbose",
          "special_test_goldens",
        ]);

      expect(command.dockerFilePath, "./some-dir/golden_tester.Dockerfile");
      expect(command.dockerImageName, "my_tester_image");
      expect(command.dockerVerbosity, DockerVerbosity.standard);
      expect(command.pathToProjectRoot, "../");
      expect(command.packageDirectory, path.basename(Directory.current.path));
      expect(command.testBaseDirectory, "special_test_goldens");
      expect(command.testCommandArguments, [
        "--plain-name",
        "my test",
        "--verbose",
        "special_test_goldens",
      ]);
      expect(command.command, [
        "flutter",
        "test",
        "--plain-name",
        "my test",
        "--verbose",
        "special_test_goldens",
      ]);
    });

    test("docker verbosity levels", () {
      final commandWithDefaultVerbosity = TestGoldensCommand()
        ..parseArguments([
          "--docker-file-path",
          "./golden_tester.Dockerfile",
        ]);
      expect(commandWithDefaultVerbosity.dockerVerbosity, DockerVerbosity.errorOnly);

      final commandWithStandardVerbosity = TestGoldensCommand()
        ..parseArguments([
          "--docker-file-path",
          "./golden_tester.Dockerfile",
          "--docker-verbosity",
          "standard",
        ]);
      expect(commandWithStandardVerbosity.dockerVerbosity, DockerVerbosity.standard);

      final commandWithQuietVerbosity = TestGoldensCommand()
        ..parseArguments([
          "--docker-file-path",
          "./golden_tester.Dockerfile",
          "--docker-verbosity",
          "quiet",
        ]);
      expect(commandWithQuietVerbosity.dockerVerbosity, DockerVerbosity.quiet);

      final commandWithErrorVerbosity = TestGoldensCommand()
        ..parseArguments([
          "--docker-file-path",
          "./golden_tester.Dockerfile",
          "--docker-verbosity",
          "error",
        ]);
      expect(commandWithErrorVerbosity.dockerVerbosity, DockerVerbosity.errorOnly);

      final commandWithNoVerbosity = TestGoldensCommand()
        ..parseArguments([
          "--docker-file-path",
          "./golden_tester.Dockerfile",
          "--docker-verbosity",
          "none",
        ]);
      expect(commandWithNoVerbosity.dockerVerbosity, DockerVerbosity.none);
    });
  });
}
