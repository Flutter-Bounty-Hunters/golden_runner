/// Prints high-level, always-visible progress checkpoints with per-step timing.
///
/// A golden run spends most of its time in a few coarse phases (building the Docker image,
/// running the tests, cleaning up). With Docker's output quieted, those phases otherwise
/// produce a silent multi-minute wait. These checkpoints tell the user which phase is running
/// and how long each one took.
class GrCheckpoints {
  GrCheckpoints({
    this.enabled = true,
    this.totalSteps,
  });

  /// Whether checkpoints are printed at all. Disable to keep the run completely silent.
  final bool enabled;

  /// The total number of steps, used to print a `[current/total]` prefix. When `null`, no
  /// counter is shown.
  final int? totalSteps;

  final Stopwatch _overall = Stopwatch()..start();
  int _stepNumber = 0;

  /// Runs [action], printing a checkpoint when it starts and the elapsed time when it finishes
  /// (or fails), then returns [action]'s result.
  Future<T> step<T>(String label, Future<T> Function() action) async {
    if (!enabled) {
      return action();
    }

    _stepNumber += 1;
    final prefix = totalSteps != null ? "[$_stepNumber/$totalSteps] " : "";
    _print("▶ $prefix$label...");

    final stopwatch = Stopwatch()..start();
    try {
      final result = await action();
      stopwatch.stop();
      _print("✓ $prefix$label · ${formatDuration(stopwatch.elapsed)}");
      return result;
    } catch (error) {
      stopwatch.stop();
      _print("✗ $prefix$label · failed after ${formatDuration(stopwatch.elapsed)}");
      rethrow;
    }
  }

  /// Prints a multi-line warning, with the first line marked and the rest
  /// indented beneath it. No-op when checkpoints are disabled.
  void warn(String message) => _printBlock("⚠", message);

  /// Prints a multi-line informational note, formatted like [warn]. No-op when
  /// checkpoints are disabled.
  void info(String message) => _printBlock("ℹ", message);

  void _printBlock(String marker, String message) {
    if (!enabled) {
      return;
    }

    final lines = message.split("\n");
    _print("$marker ${lines.first}");
    for (final line in lines.skip(1)) {
      _print("  $line");
    }
  }

  /// Prints the total elapsed time since this [GrCheckpoints] was created.
  void done() {
    if (!enabled) {
      return;
    }

    _overall.stop();
    _print("Done · total ${formatDuration(_overall.elapsed)}");
  }

  void _print(String message) {
    // ignore: avoid_print
    print("[golden_runner] $message");
  }

  /// Formats [duration] as a compact, human-readable string, e.g. `850ms`, `8.4s`, `2m 03s`,
  /// or `1h 04m 12s`.
  static String formatDuration(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return "${duration.inMilliseconds}ms";
    }

    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return "${hours}h ${_twoDigits(minutes)}m ${_twoDigits(seconds)}s";
    }
    if (minutes > 0) {
      return "${minutes}m ${_twoDigits(seconds)}s";
    }

    final tenths = (duration.inMilliseconds % 1000) ~/ 100;
    return "$seconds.${tenths}s";
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, "0");
}
