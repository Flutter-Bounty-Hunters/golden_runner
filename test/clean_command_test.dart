import 'dart:io';

import 'package:golden_runner/golden_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group("Clean command >", () {
    test("parses defaults", () {
      final cleanRequest = parseCleanCommandArguments([]);

      expect(cleanRequest.targetPath, "test_goldens");
      expect(cleanRequest.includeLooseFiles, false);
      expect(cleanRequest.dryRun, false);
      expect(cleanRequest.silent, false);
      expect(cleanRequest.verbose, false);
    });

    test("parses flags and target path", () {
      final cleanRequest = parseCleanCommandArguments([
        "--loose-files",
        "--dry-run",
        "--verbose",
        "test_goldens/buttons",
      ]);

      expect(cleanRequest.targetPath, "test_goldens/buttons");
      expect(cleanRequest.includeLooseFiles, true);
      expect(cleanRequest.dryRun, true);
      expect(cleanRequest.silent, false);
      expect(cleanRequest.verbose, true);
    });

    test("rejects unknown flags", () {
      expect(
        () => parseCleanCommandArguments(["--plain-name", "my test"]),
        throwsA(
          predicate(
            (Object error) => error.toString().contains("Unknown clean option: --plain-name"),
          ),
        ),
      );
    });

    test("rejects multiple positional paths", () {
      expect(
        () => parseCleanCommandArguments(["test_goldens/a", "test_goldens/b"]),
        throwsA(
          predicate(
            (Object error) => error.toString().contains(
                  "Expected at most one clean target path",
                ),
          ),
        ),
      );
    });

    test("rejects silent and verbose", () {
      expect(
        () => parseCleanCommandArguments(["--silent", "--verbose"]),
        throwsA(
          predicate(
            (Object error) => error.toString().contains(
                  "Cannot use --silent with --verbose.",
                ),
          ),
        ),
      );
    });

    test("rejects silent and dry run", () {
      expect(
        () => parseCleanCommandArguments(["--silent", "--dry-run"]),
        throwsA(
          predicate(
            (Object error) => error.toString().contains(
                  "Dry run is intended as a print-only behavior",
                ),
          ),
        ),
      );
    });

    test(
      "deletes failure directories recursively and prints a summary",
      () async {
        await _withTempDirectory((tempDirectory) async {
          final targetDirectory = Directory(
            path.join(tempDirectory.path, "test_goldens"),
          );
          final firstFailureDirectory = Directory(
            path.join(targetDirectory.path, "buttons", "failures"),
          );
          final secondFailureDirectory = Directory(
            path.join(targetDirectory.path, "cards", "nested", "failures"),
          );
          await firstFailureDirectory.create(recursive: true);
          await secondFailureDirectory.create(recursive: true);
          await File(
            path.join(firstFailureDirectory.path, "button.png"),
          ).writeAsString("failure");

          final output = StringBuffer();
          final command = CleanCommand(output)..parseArguments([targetDirectory.path]);
          final result = await command.run();

          expect(result.deletedFailureDirectoryCount, 2);
          expect(result.deletedLooseFailureFileCount, 0);
          expect(await firstFailureDirectory.exists(), false);
          expect(await secondFailureDirectory.exists(), false);
          expect(_outputLines(output), [
            "Deleted 2 failure directories and 0 loose failure files.",
          ]);
        });
      },
    );

    test("doesn't delete loose files by default", () async {
      await _withTempDirectory((tempDirectory) async {
        final targetDirectory = Directory(
          path.join(tempDirectory.path, "test_goldens"),
        );
        await targetDirectory.create(recursive: true);
        final looseFailureFile = File(
          path.join(targetDirectory.path, "button.masterImage.png"),
        );
        await looseFailureFile.writeAsString("failure");

        final command = CleanCommand()..parseArguments(["--silent", targetDirectory.path]);
        await command.run();

        expect(await looseFailureFile.exists(), true);
      });
    });

    test("deletes only loose files that match golden failure naming", () async {
      await _withTempDirectory((tempDirectory) async {
        final targetDirectory = Directory(
          path.join(tempDirectory.path, "test_goldens"),
        );
        await targetDirectory.create(recursive: true);

        final matchingFiles = [
          File(path.join(targetDirectory.path, "button.masterImage.png")),
          File(path.join(targetDirectory.path, "button.testImage.png")),
          File(path.join(targetDirectory.path, "button.isolatedDiff.png")),
          File(path.join(targetDirectory.path, "button.maskedDiff.png")),
          File(path.join(targetDirectory.path, "failure_button.png")),
        ];
        final nonMatchingFiles = [
          File(path.join(targetDirectory.path, "button.diff.png")),
          File(path.join(targetDirectory.path, "failure_button.jpg")),
          File(path.join(targetDirectory.path, "my_failure_button.png")),
          File(path.join(targetDirectory.path, "button.masterImage.jpg")),
        ];

        for (final file in [...matchingFiles, ...nonMatchingFiles]) {
          await file.writeAsString("failure");
        }

        final output = StringBuffer();
        final command = CleanCommand(output)..parseArguments(["--loose-files", targetDirectory.path]);
        final result = await command.run();

        expect(result.deletedFailureDirectoryCount, 0);
        expect(result.deletedLooseFailureFileCount, 5);
        for (final file in matchingFiles) {
          expect(await file.exists(), false);
        }
        for (final file in nonMatchingFiles) {
          expect(await file.exists(), true);
        }
        expect(_outputLines(output), [
          "Deleted 0 failure directories and 5 loose failure files.",
        ]);
      });
    });

    test(
      "dry run prints what would be deleted without deleting anything",
      () async {
        await _withTempDirectory((tempDirectory) async {
          final targetDirectory = Directory(
            path.join(tempDirectory.path, "test_goldens"),
          );
          final failureDirectory = Directory(
            path.join(targetDirectory.path, "buttons", "failures"),
          );
          final looseFailureFile = File(
            path.join(targetDirectory.path, "failure_button.png"),
          );
          await failureDirectory.create(recursive: true);
          await looseFailureFile.create(recursive: true);

          final output = StringBuffer();
          final command = CleanCommand(output)..parseArguments(["--loose-files", "--dry-run", targetDirectory.path]);
          final result = await command.run();

          expect(result.deletedFailureDirectoryCount, 1);
          expect(result.deletedLooseFailureFileCount, 1);
          expect(await failureDirectory.exists(), true);
          expect(await looseFailureFile.exists(), true);
          expect(_outputLines(output), [
            "Would delete 1 failure directory and 1 loose failure file.",
          ]);
        });
      },
    );

    test("verbose mode prints each deleted path", () async {
      await _withTempDirectory((tempDirectory) async {
        final targetDirectory = Directory(
          path.join(tempDirectory.path, "test_goldens"),
        );
        final failureDirectory = Directory(
          path.join(targetDirectory.path, "buttons", "failures"),
        );
        final looseFailureFile = File(
          path.join(targetDirectory.path, "failure_button.png"),
        );
        await failureDirectory.create(recursive: true);
        await looseFailureFile.create(recursive: true);

        final output = StringBuffer();
        final command = CleanCommand(output)..parseArguments(["--loose-files", "--verbose", targetDirectory.path]);
        await command.run();

        final outputLines = _outputLines(output);
        expect(outputLines[0], startsWith("Deleted directory:"));
        expect(outputLines[0], contains("buttons${path.separator}failures"));
        expect(outputLines[1], startsWith("Deleted file:"));
        expect(outputLines[1], contains("failure_button.png"));
        expect(
          outputLines[2],
          "Deleted 1 failure directory and 1 loose failure file.",
        );
      });
    });

    test("file targets clean from their parent directory", () async {
      await _withTempDirectory((tempDirectory) async {
        final targetFile = File(
          path.join(tempDirectory.path, "test_goldens", "button_test.dart"),
        );
        final failureDirectory = Directory(
          path.join(targetFile.parent.path, "failures"),
        );
        await targetFile.create(recursive: true);
        await failureDirectory.create(recursive: true);

        final command = CleanCommand()..parseArguments(["--silent", targetFile.path]);
        await command.run();

        expect(await failureDirectory.exists(), false);
      });
    });

    test("throws when the target path doesn't exist", () async {
      await _withTempDirectory((tempDirectory) async {
        final command = CleanCommand()..parseArguments([path.join(tempDirectory.path, "missing_goldens")]);

        expect(
          () => command.run(),
          throwsA(
            predicate(
              (Object error) => error.toString().contains("No such directory to clean failures"),
            ),
          ),
        );
      });
    });

    test("doesn't follow symlinks", () async {
      if (Platform.isWindows) {
        return;
      }

      await _withTempDirectory((tempDirectory) async {
        final targetDirectory = Directory(
          path.join(tempDirectory.path, "test_goldens"),
        );
        final externalDirectory = Directory(
          path.join(tempDirectory.path, "external"),
        );
        final externalFailureDirectory = Directory(
          path.join(externalDirectory.path, "failures"),
        );
        await targetDirectory.create(recursive: true);
        await externalFailureDirectory.create(recursive: true);

        final symlinkedDirectory = Link(
          path.join(targetDirectory.path, "symlinked_goldens"),
        );
        await symlinkedDirectory.create(externalDirectory.path);
        final symlinkedFailureDirectory = Link(
          path.join(targetDirectory.path, "failures"),
        );
        await symlinkedFailureDirectory.create(externalFailureDirectory.path);

        final command = CleanCommand()..parseArguments(["--loose-files", "--silent", targetDirectory.path]);
        await command.run();

        expect(await symlinkedDirectory.exists(), true);
        expect(await symlinkedFailureDirectory.exists(), true);
        expect(await externalFailureDirectory.exists(), true);
      });
    });
  });
}

Future<void> _withTempDirectory(
  Future<void> Function(Directory directory) runTest,
) async {
  final tempDirectory = await Directory.systemTemp.createTemp(
    "golden_runner_clean_test_",
  );
  try {
    await runTest(tempDirectory);
  } finally {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  }
}

List<String> _outputLines(StringBuffer output) {
  return output.toString().trim().split("\n");
}
