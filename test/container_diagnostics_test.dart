import 'package:golden_runner/golden_runner.dart';
import 'package:test/test.dart';

void main() {
  group("StreamingMatcher >", () {
    test("finds the needle within a single chunk", () {
      final matcher = StreamingMatcher("needle");
      matcher.add("a haystack with a needle inside");
      expect(matcher.found, isTrue);
    });

    test("finds the needle split across two chunks", () {
      final matcher = StreamingMatcher("needle")
        ..add("...the nee")
        ..add("dle is here...");
      expect(matcher.found, isTrue);
    });

    test("finds the needle when fed one character at a time", () {
      final matcher = StreamingMatcher("needle");
      for (final char in "a needle".split("")) {
        matcher.add(char);
      }
      expect(matcher.found, isTrue);
    });

    test("stays false when the needle never appears", () {
      final matcher = StreamingMatcher("needle")
        ..add("nothing to see")
        ..add(" here at all");
      expect(matcher.found, isFalse);
    });

    test("ignores an empty needle", () {
      final matcher = StreamingMatcher("")..add("anything");
      expect(matcher.found, isFalse);
    });
  });

  group("ContainerFailureDiagnostics >", () {
    test("diagnoses the Dart compiler crash (Docker OOM)", () {
      const output = "01:16 +1 -1: some_test.dart [E]\n"
          "  Error: The Dart compiler exited unexpectedly.\n"
          "  package:flutter_tools/src/base/common.dart 34:3  throwToolExit";

      final diagnostic = const ContainerFailureDiagnostics().diagnose(output);
      expect(diagnostic, isNotNull);
      expect(diagnostic, contains("out of memory"));
      expect(diagnostic, contains("--concurrency=1"));
    });

    test("returns null for ordinary output", () {
      final diagnostic = const ContainerFailureDiagnostics().diagnose(
        "00:12 +8: All tests passed!",
      );
      expect(diagnostic, isNull);
    });
  });
}
