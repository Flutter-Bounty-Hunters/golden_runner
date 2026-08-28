import 'dart:async';

import 'package:golden_runner/golden_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'tools/docker_container_requests.dart';
import 'tools/fake_goldens_command_environment.dart';

void main() {
  group("Goldens update command >", () {
    group("argument parsing >", () {
      test("with defaults", () {
        final command = UpdateGoldensCommand(
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
        expect(command.command, ["flutter", "test", "--update-goldens", "test_goldens"]);
      });

      test("with all arguments", () {
        final command = UpdateGoldensCommand(
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
          "--update-goldens",
          "--plain-name",
          "my test",
          "--verbose",
          "special_test_goldens",
        ]);
      });

      test("with a pinned Flutter version", () {
        final command = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--flutter-version",
            "3.44.6",
          ]);

        expect(command.flutterVersion, "3.44.6");
        // The pinned version flows into the Docker request so it reaches the generated Dockerfile.
        expect(command.assembleDockerContainerRequest().flutterVersion, "3.44.6");
        // The version isn't mistaken for the test target.
        expect(command.testCommandArguments, ["test_goldens"]);
      });

      test("defaults to no pinned Flutter version", () {
        final command = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([]);

        expect(command.flutterVersion, null);
        expect(command.assembleDockerContainerRequest().flutterVersion, null);
      });

      test("auto-detects the Flutter version from FVM config (.fvmrc)", () {
        final command = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/packages/my_app",
            fileContents: {
              // .fvmrc at the project root, above the package under test.
              "/workspace/repo/.fvmrc": '{"flutter": "3.44.6"}',
            },
          ),
        )..parseArguments([
            "--path-to-project-root",
            "../..",
          ]);

        expect(command.flutterVersion, "3.44.6");
        expect(command.assembleDockerContainerRequest().flutterVersion, "3.44.6");
      });

      test("logs that the Flutter version was inferred from FVM", () {
        final logs = <String>[];
        runZoned(
          () {
            UpdateGoldensCommand(
              environment: FakeGoldensCommandEnvironment(
                currentDirectoryPath: "/workspace/repo/packages/my_app",
                fileContents: {
                  "/workspace/repo/.fvmrc": '{"flutter": "3.44.6"}',
                },
              ),
            ).parseArguments(["--path-to-project-root", "../.."]);
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => logs.add(line),
          ),
        );

        expect(
          logs.any((line) => line.contains("FVM") && line.contains("3.44.6")),
          isTrue,
          reason: "expected a log line mentioning FVM and the inferred version; got: $logs",
        );
      });

      test("does not log FVM inference when the version is explicit", () {
        final logs = <String>[];
        runZoned(
          () {
            UpdateGoldensCommand(
              environment: FakeGoldensCommandEnvironment(
                currentDirectoryPath: "/workspace/repo/packages/my_app",
                fileContents: {
                  "/workspace/repo/.fvmrc": '{"flutter": "3.44.6"}',
                },
              ),
            ).parseArguments(["--path-to-project-root", "../..", "--flutter-version", "stable"]);
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => logs.add(line),
          ),
        );

        expect(logs.any((line) => line.contains("FVM")), isFalse);
      });

      test("explicit --flutter-version overrides FVM config", () {
        final command = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/packages/my_app",
            fileContents: {
              "/workspace/repo/.fvmrc": '{"flutter": "3.44.6"}',
            },
          ),
        )..parseArguments([
            "--path-to-project-root",
            "../..",
            "--flutter-version",
            "stable",
          ]);

        expect(command.flutterVersion, "stable");
      });

      test("handles named arguments when there's no specified test directory", () {
        final command = UpdateGoldensCommand(
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
          "--update-goldens",
          "--plain-name",
          "My test name",
          "test_goldens",
        ]);
      });

      test("throws when given a test target that doesn't exist", () {
        final command = UpdateGoldensCommand(
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
        final commandWithDefaultVerbosity = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--docker-file-path",
            "./golden_tester.Dockerfile",
          ]);
        expect(commandWithDefaultVerbosity.dockerVerbosity, DockerVerbosity.errorOnly);

        final commandWithStandardVerbosity = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--docker-file-path",
            "./golden_tester.Dockerfile",
            "--docker-verbosity",
            "standard",
          ]);
        expect(commandWithStandardVerbosity.dockerVerbosity, DockerVerbosity.standard);

        final commandWithQuietVerbosity = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--docker-file-path",
            "./golden_tester.Dockerfile",
            "--docker-verbosity",
            "quiet",
          ]);
        expect(commandWithQuietVerbosity.dockerVerbosity, DockerVerbosity.quiet);

        final commandWithErrorVerbosity = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--docker-file-path",
            "./golden_tester.Dockerfile",
            "--docker-verbosity",
            "error",
          ]);
        expect(commandWithErrorVerbosity.dockerVerbosity, DockerVerbosity.errorOnly);

        final commandWithNoVerbosity = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
          ),
        )..parseArguments([
            "--docker-file-path",
            "./golden_tester.Dockerfile",
            "--docker-verbosity",
            "none",
          ]);
        expect(commandWithNoVerbosity.dockerVerbosity, DockerVerbosity.none);
      });
    });

    group("pub workspace validation >", () {
      const workspaceMemberPubspec = "name: my_app\nresolution: workspace\n";
      const workspaceRootPubspec = "name: my_workspace\nworkspace:\n  - packages/my_app\n";

      test("throws with a --path-to-project-root hint when the workspace root won't be copied", () {
        final command = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/packages/my_app",
            fileContents: {
              // The package under test is a workspace member.
              "/workspace/repo/packages/my_app/pubspec.yaml": workspaceMemberPubspec,
              // The workspace root lives at the repo root, above the (default) project root.
              "/workspace/repo/pubspec.yaml": workspaceRootPubspec,
            },
          ),
        );

        expect(
          () => command.parseArguments([]),
          throwsA(
            predicate((Object error) {
              final message = error.toString();
              return message.contains("member of a Dart pub workspace") &&
                  message.contains("--path-to-project-root") &&
                  // The hint suggests the exact relative path from the package to the root.
                  message.contains("--path-to-project-root ../..");
            }),
          ),
        );
      });

      test("passes when --path-to-project-root includes the workspace root", () {
        final command = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/repo/packages/my_app",
            fileContents: {
              "/workspace/repo/packages/my_app/pubspec.yaml": workspaceMemberPubspec,
              "/workspace/repo/pubspec.yaml": workspaceRootPubspec,
            },
          ),
        );

        // Pointing the project root at the repo root includes the workspace root
        // in the container copy, so parsing succeeds.
        expect(() => command.parseArguments(["--path-to-project-root", "../.."]), returnsNormally);
      });

      test("passes for a normal package that isn't a workspace member", () {
        final command = UpdateGoldensCommand(
          environment: FakeGoldensCommandEnvironment(
            currentDirectoryPath: "/workspace/my_app",
            fileContents: {
              "/workspace/my_app/pubspec.yaml": "name: my_app\n",
            },
          ),
        );

        expect(() => command.parseArguments([]), returnsNormally);
      });
    });

    group("directory mapping >", () {
      test("default - single project repository", () {
        final command = UpdateGoldensCommand(
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
            command: ["flutter", "test", "--update-goldens", "test_goldens"],
          )),
        );
      });

      test("mono-repo with project at /repo/my_app", () {
        final command = UpdateGoldensCommand(
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
            command: ["flutter", "test", "--update-goldens", "test_goldens"],
          )),
        );
      });

      test("mono-repo with project at /repo/packages/my_app", () {
        final command = UpdateGoldensCommand(
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
            command: ["flutter", "test", "--update-goldens", "test_goldens"],
          )),
        );
      });

      test("mono-repo with custom named test directory", () {
        final command = UpdateGoldensCommand(
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
            command: ["flutter", "test", "--update-goldens", "my_test_dir"],
          )),
        );
      });

      test("mono-repo when targeting a single test file", () {
        final command = UpdateGoldensCommand(
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
              "--update-goldens",
              path.join("test_goldens", "button_test.dart"),
            ],
          )),
        );
      });

      test("targeting a test directory with an absolute path", () {
        final command = UpdateGoldensCommand(
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
              "--update-goldens",
              // Notice that the absolute path that was passed in was reworked so that the specified
              // test directory is relative to the current working directory within the Docker Container.
              "my_test_dir",
            ],
          )),
        );
      });

      test("targeting a single test file with an absolute path", () {
        final command = UpdateGoldensCommand(
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
              "--update-goldens",
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
