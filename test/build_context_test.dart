import 'dart:io';

import 'package:golden_runner/golden_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group("Build context guard >", () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync("gr_context_test");
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test("decides to apply the default for a large context with no .dockerignore", () async {
      _writeFile(tempDir, "a.bin", 80);
      _writeFile(tempDir, "b.bin", 80);

      // A tiny threshold stands in for the real 2 GiB, so the test doesn't need
      // to write gigabytes.
      const guard = BuildContextGuard(thresholdBytes: 100);
      final assessment = await guard.assess(tempDir.path);

      expect(assessment.decision, BuildContextIgnoreDecision.applyDefault);
      expect(assessment.contextPath, path.normalize(tempDir.absolute.path));
      // Never writes to the project.
      expect(File(path.join(tempDir.path, ".dockerignore")).existsSync(), isFalse);
    });

    test("reports the FULL context size, not just the threshold", () async {
      _writeFile(tempDir, "a.bin", 200);
      _writeFile(tempDir, "b.bin", 200);
      _writeFile(tempDir, "c.bin", 200);

      // Threshold is crossed at 100 bytes, but the reported size must be the full
      // 600, not a value truncated at the threshold.
      const guard = BuildContextGuard(thresholdBytes: 100);
      final assessment = await guard.assess(tempDir.path);

      expect(assessment.decision, BuildContextIgnoreDecision.applyDefault);
      expect(assessment.measuredBytes, 600);
      expect(assessment.isApproximate, isFalse);
    });

    test("estimates the kept size and savings after the default ignore", () async {
      // Kept by the default ignore.
      _writeFile(tempDir, path.join("lib", "keep.dart"), 300);
      // Excluded by the default ignore (build/ and .dart_tool/).
      _writeFile(tempDir, path.join("build", "out.bin"), 500);
      _writeFile(tempDir, path.join("packages", "chat", ".dart_tool", "x.json"), 200);

      const guard = BuildContextGuard(thresholdBytes: 100);
      final assessment = await guard.assess(tempDir.path);

      expect(assessment.measuredBytes, 1000); // 300 + 500 + 200
      expect(assessment.keptBytes, 300); // only lib/keep.dart survives
      expect(assessment.savedBytes, 700); // build/ + nested .dart_tool/
    });

    test("marks the size approximate when the scan cap is hit", () async {
      for (var i = 0; i < 5; i += 1) {
        _writeFile(tempDir, "f$i.bin", 100);
      }

      // A tiny cap forces early termination, so the total is a lower bound.
      const guard = BuildContextGuard(thresholdBytes: 100, entryScanCap: 2);
      final assessment = await guard.assess(tempDir.path);

      expect(assessment.decision, BuildContextIgnoreDecision.applyDefault);
      expect(assessment.isApproximate, isTrue);
    });

    test("defers to a .dockerignore the user already manages", () async {
      _writeFile(tempDir, "a.bin", 80);
      _writeFile(tempDir, "b.bin", 80);
      File(path.join(tempDir.path, ".dockerignore")).writeAsStringSync("custom_dir/\n");

      const guard = BuildContextGuard(thresholdBytes: 100);
      final assessment = await guard.assess(tempDir.path);

      expect(assessment.decision, BuildContextIgnoreDecision.none);
    });

    test("leaves a context under the threshold alone", () async {
      _writeFile(tempDir, "a.bin", 10);

      const guard = BuildContextGuard(thresholdBytes: 1000000);
      expect((await guard.assess(tempDir.path)).decision, BuildContextIgnoreDecision.none);
    });

    test("does nothing when the context directory doesn't exist", () async {
      const guard = BuildContextGuard(thresholdBytes: 1);
      final assessment = await guard.assess(path.join(tempDir.path, "missing"));
      expect(assessment.decision, BuildContextIgnoreDecision.none);
    });

    test("counts files in nested directories when measuring size", () async {
      _writeFile(tempDir, path.join("nested", "deep", "big.bin"), 200);

      const guard = BuildContextGuard(thresholdBytes: 100);
      expect((await guard.assess(tempDir.path)).decision, BuildContextIgnoreDecision.applyDefault);
    });
  });

  group("Default .dockerignore >", () {
    test("excludes generated output but keeps sources and manifests", () {
      final contents = BuildContextGuard.defaultDockerignore;
      expect(contents, contains("build/"));
      expect(contents, contains(".dart_tool/"));
      expect(contents, contains(".git"));

      // Check the actual ignore patterns, not the explanatory comments.
      final patternLines = contents
          .split("\n")
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith("#"));
      expect(patternLines.any((line) => line.contains("pubspec")), isFalse);
      expect(patternLines.any((line) => line.contains("lib/")), isFalse);
    });
  });

  group("Build context size formatting >", () {
    test("formats bytes across units", () {
      expect(BuildContextGuard.formatBytes(512), "512 B");
      expect(BuildContextGuard.formatBytes(2048), "2 KB");
      expect(BuildContextGuard.formatBytes(5 * 1024 * 1024), "5 MB");
      expect(BuildContextGuard.formatBytes(2 * 1024 * 1024 * 1024), "2 GB");
      expect(BuildContextGuard.formatBytes((2.4 * 1024 * 1024 * 1024).round()), "2.4 GB");
    });
  });
}

/// Writes a file of [bytes] zero-bytes at [relativePath] within [dir], creating
/// parent directories as needed.
void _writeFile(Directory dir, String relativePath, int bytes) {
  final file = File(path.join(dir.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(List.filled(bytes, 0));
}
