import 'package:golden_runner/golden_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'tools/docker_container_requests.dart';
import 'tools/fake_goldens_command_environment.dart';

void main() {
  group("Goldens test command >", () {
    group("argument parsing >", () {
      test("with defaults", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([]);

        expect(command.dockerFilePath, null);
        expect(command.dockerImageName, "golden_tester");
        expect(command.dockerVerbosity, DockerVerbosity.errorOnly);
        expect(command.pathToProjectRoot, ".");
        expect(command.packageDirectory, "my_app");
        expect(command.packagePathFromProjectRoot, ".");
        expect(command.hostTestDirectoryPath, "/workspace/my_app/test_goldens");
        expect(command.containerTestDirectoryPath, "test_goldens");
        expect(command.containerWorkingDirectory, "/golden_tester");
        expect(command.mountPaths, {
          "/workspace/my_app/test_goldens:/golden_tester/test_goldens",
        });
        expect(command.testBaseDirectory, "test_goldens");
        expect(command.testCommandArguments, ["test_goldens"]);
        expect(command.command, ["flutter", "test", "test_goldens"]);
      });

      test("with all arguments", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/my_app",
            directories: {
              "/workspace/repo/my_app/special_test_goldens",
            },
          ),
        )..parseArguments([
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
        expect(command.packageDirectory, "my_app");
        expect(command.packagePathFromProjectRoot, "my_app");
        expect(command.hostTestDirectoryPath, "/workspace/repo/my_app/special_test_goldens");
        expect(command.containerTestDirectoryPath, "special_test_goldens");
        expect(command.containerWorkingDirectory, "/golden_tester/my_app");
        expect(command.mountPaths, {
          "/workspace/repo/my_app/special_test_goldens:/golden_tester/my_app/special_test_goldens",
        });
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

      test("handles named arguments when there's no specified test directory", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--plain-name",
            "My test name",
          ]);

        expect(command.dockerFilePath, null);
        expect(command.dockerImageName, "golden_tester");
        expect(command.dockerVerbosity, DockerVerbosity.errorOnly);
        expect(command.pathToProjectRoot, ".");
        expect(command.packageDirectory, "my_app");
        expect(command.packagePathFromProjectRoot, ".");
        expect(command.hostTestDirectoryPath, "/workspace/my_app/test_goldens");
        expect(command.containerTestDirectoryPath, "test_goldens");
        expect(command.containerWorkingDirectory, "/golden_tester");
        expect(command.mountPaths, {
          "/workspace/my_app/test_goldens:/golden_tester/test_goldens",
        });
        expect(command.testBaseDirectory, "test_goldens");
        expect(command.testCommandArguments, ["--plain-name", "My test name", "test_goldens"]);
        expect(command.command, [
          "flutter",
          "test",
          "--plain-name",
          "My test name",
          "test_goldens",
        ]);
      });

      test("throws when given a test target that doesn't exist", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        );

        expect(
          () => command.parseArguments(["missing_goldens"]),
          throwsA(
            predicate(
              (Object error) => error.toString().contains(
                    "No such golden test directory or file: missing_goldens",
                  ),
            ),
          ),
        );
      });

      test("docker verbosity levels", () {
        final commandWithDefaultVerbosity = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([]);
        expect(commandWithDefaultVerbosity.dockerVerbosity, DockerVerbosity.errorOnly);

        final commandWithStandardVerbosity = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--docker-verbosity",
            "standard",
          ]);
        expect(commandWithStandardVerbosity.dockerVerbosity, DockerVerbosity.standard);

        final commandWithQuietVerbosity = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--docker-verbosity",
            "quiet",
          ]);
        expect(commandWithQuietVerbosity.dockerVerbosity, DockerVerbosity.quiet);

        final commandWithErrorVerbosity = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--docker-verbosity",
            "error",
          ]);
        expect(commandWithErrorVerbosity.dockerVerbosity, DockerVerbosity.errorOnly);

        final commandWithNoVerbosity = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--docker-verbosity",
            "none",
          ]);
        expect(commandWithNoVerbosity.dockerVerbosity, DockerVerbosity.none);
      });
    });

    group("directory mapping >", () {
      test("default - single project repository", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([]);

        expect(
          command.assembleDockerContainerRequest(),
          equalsDockerContainerRequest(RunDockerContainerRequest(
            dockerFilePath: null,
            dockerImageName: "golden_tester",
            dockerVerbosity: DockerVerbosity.errorOnly,
            pathToProjectRoot: ".",
            containerWorkingDirectory: "/golden_tester",
            mountPaths: {
              "/workspace/my_app/test_goldens:/golden_tester/test_goldens",
            },
            command: ["flutter", "test", "test_goldens"],
          )),
        );
      });

      test("mono-repo with project at /repo/my_app", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/my_app",
          ),
        )..parseArguments([
            "--path-to-project-root",
            "..",
          ]);

        expect(
          command.assembleDockerContainerRequest(),
          equalsDockerContainerRequest(RunDockerContainerRequest(
            dockerFilePath: null,
            dockerImageName: "golden_tester",
            dockerVerbosity: DockerVerbosity.errorOnly,
            pathToProjectRoot: "..",
            containerWorkingDirectory: "/golden_tester/my_app",
            mountPaths: {
              "/workspace/repo/my_app/test_goldens:/golden_tester/my_app/test_goldens",
            },
            command: ["flutter", "test", "test_goldens"],
          )),
        );
      });

      test("mono-repo with project at /repo/packages/my_app", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/packages/my_app",
          ),
        )..parseArguments([
            "--path-to-project-root",
            "../..",
          ]);

        expect(
          command.assembleDockerContainerRequest(),
          equalsDockerContainerRequest(RunDockerContainerRequest(
            dockerFilePath: null,
            dockerImageName: "golden_tester",
            dockerVerbosity: DockerVerbosity.errorOnly,
            pathToProjectRoot: "../..",
            containerWorkingDirectory: "/golden_tester/packages/my_app",
            mountPaths: {
              "/workspace/repo/packages/my_app/test_goldens:/golden_tester/packages/my_app/test_goldens",
            },
            command: ["flutter", "test", "test_goldens"],
          )),
        );
      });

      test("mono-repo with custom named test directory", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/packages/my_app",
            directories: {
              "/workspace/repo/packages/my_app/my_test_dir",
            },
          ),
        )..parseArguments([
            "--path-to-project-root",
            "../..",
            "my_test_dir",
          ]);

        expect(
          command.assembleDockerContainerRequest(),
          equalsDockerContainerRequest(RunDockerContainerRequest(
            dockerFilePath: null,
            dockerImageName: "golden_tester",
            dockerVerbosity: DockerVerbosity.errorOnly,
            pathToProjectRoot: "../..",
            containerWorkingDirectory: "/golden_tester/packages/my_app",
            mountPaths: {
              "/workspace/repo/packages/my_app/my_test_dir:/golden_tester/packages/my_app/my_test_dir",
            },
            command: ["flutter", "test", "my_test_dir"],
          )),
        );
      });

      test("mono-repo when targeting a single test file", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/packages/my_app",
            files: {
              "/workspace/repo/packages/my_app/test_goldens/button_test.dart",
            },
          ),
        )..parseArguments([
            "--path-to-project-root",
            "../..",
            path.join("test_goldens", "button_test.dart"),
          ]);

        expect(
          command.assembleDockerContainerRequest(),
          equalsDockerContainerRequest(RunDockerContainerRequest(
            dockerFilePath: null,
            dockerImageName: "golden_tester",
            dockerVerbosity: DockerVerbosity.errorOnly,
            pathToProjectRoot: "../..",
            containerWorkingDirectory: "/golden_tester/packages/my_app",
            mountPaths: {
              "/workspace/repo/packages/my_app/test_goldens:/golden_tester/packages/my_app/test_goldens",
            },
            command: [
              "flutter",
              "test",
              path.join("test_goldens", "button_test.dart"),
            ],
          )),
        );
      });

      test("targeting a test directory with an absolute path", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/packages/my_app",
            directories: {
              "/workspace/repo/packages/my_app/my_test_dir",
            },
          ),
        )..parseArguments([
            "--path-to-project-root",
            "../..",
            "/workspace/repo/packages/my_app/my_test_dir",
          ]);

        expect(
          command.assembleDockerContainerRequest(),
          equalsDockerContainerRequest(RunDockerContainerRequest(
            dockerFilePath: null,
            dockerImageName: "golden_tester",
            dockerVerbosity: DockerVerbosity.errorOnly,
            pathToProjectRoot: "../..",
            containerWorkingDirectory: "/golden_tester/packages/my_app",
            mountPaths: {
              "/workspace/repo/packages/my_app/my_test_dir:/golden_tester/packages/my_app/my_test_dir",
            },
            command: [
              "flutter",
              "test",
              // Notice that the absolute path that was passed in was reworked so that the specified
              // test directory is relative to the current working directory within the Docker Container.
              "my_test_dir",
            ],
          )),
        );
      });

      test("targeting a single test file with an absolute path", () {
        final command = TestGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/packages/my_app",
            files: {
              "/workspace/repo/packages/my_app/test_goldens/button_test.dart",
            },
          ),
        )..parseArguments([
            "--path-to-project-root",
            "../..",
            "/workspace/repo/packages/my_app/test_goldens/button_test.dart",
          ]);

        expect(
          command.assembleDockerContainerRequest(),
          equalsDockerContainerRequest(RunDockerContainerRequest(
            dockerFilePath: null,
            dockerImageName: "golden_tester",
            dockerVerbosity: DockerVerbosity.errorOnly,
            pathToProjectRoot: "../..",
            containerWorkingDirectory: "/golden_tester/packages/my_app",
            mountPaths: {
              "/workspace/repo/packages/my_app/test_goldens:/golden_tester/packages/my_app/test_goldens",
            },
            command: [
              "flutter",
              "test",
              // Notice that the absolute path that was passed in was reworked so that the specified
              // test file is relative to the current working directory within the Docker Container.
              path.join("test_goldens", "button_test.dart"),
            ],
          )),
        );
      });
    });
  });
}
