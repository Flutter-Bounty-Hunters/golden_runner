import 'package:golden_runner/golden_runner.dart';
import 'package:test/test.dart';

void main() {
  group("Checkpoints > duration formatting >", () {
    test("sub-second durations show milliseconds", () {
      expect(GrCheckpoints.formatDuration(const Duration(milliseconds: 0)), "0ms");
      expect(GrCheckpoints.formatDuration(const Duration(milliseconds: 850)), "850ms");
      expect(GrCheckpoints.formatDuration(const Duration(milliseconds: 999)), "999ms");
    });

    test("seconds show one decimal place", () {
      expect(GrCheckpoints.formatDuration(const Duration(seconds: 1)), "1.0s");
      expect(GrCheckpoints.formatDuration(const Duration(milliseconds: 8400)), "8.4s");
      expect(GrCheckpoints.formatDuration(const Duration(milliseconds: 59900)), "59.9s");
    });

    test("minutes show zero-padded seconds", () {
      expect(GrCheckpoints.formatDuration(const Duration(minutes: 1)), "1m 00s");
      expect(GrCheckpoints.formatDuration(const Duration(minutes: 2, seconds: 3)), "2m 03s");
      expect(GrCheckpoints.formatDuration(const Duration(minutes: 8, seconds: 12)), "8m 12s");
    });

    test("hours show zero-padded minutes and seconds", () {
      expect(GrCheckpoints.formatDuration(const Duration(hours: 1, minutes: 4, seconds: 12)), "1h 04m 12s");
    });
  });
}
