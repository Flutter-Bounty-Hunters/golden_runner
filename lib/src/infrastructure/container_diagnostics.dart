/// Recognizes known container-failure signatures in `flutter test` output and
/// turns them into a plain-language explanation.
///
/// Some container failures surface as cryptic errors that look like a test or
/// compiler bug, but are really an environment problem. The prime example is the
/// Dart frontend compiler being killed when Docker runs out of memory: Flutter
/// reports only "The Dart compiler exited unexpectedly" plus a Dart async stack
/// trace - there's no "out of memory" text - so a memory problem masquerades as a
/// tooling crash. golden_runner watches the container's output for these
/// signatures and prints a clear diagnosis so the user knows what actually happened.
class ContainerFailureDiagnostics {
  const ContainerFailureDiagnostics();

  /// The line flutter_tools prints when the frontend compiler process dies
  /// unexpectedly. Inside a container this is almost always the Linux OOM killer
  /// reaping the compiler because Docker ran out of memory.
  static const compilerCrashMarker = "The Dart compiler exited unexpectedly";

  /// A plain-language explanation of a [compilerCrashMarker] failure, printed when
  /// that marker is seen in the container's output.
  static const compilerCrashDiagnostic =
      "The Dart compiler was killed while compiling the tests. Inside a container this is almost "
      "always Docker running out of memory - not a test failure or a compiler bug. There's no "
      '"out of memory" message because the OS kills the compiler process abruptly.\n'
      "  Try one or more of:\n"
      "    - Raise Docker's memory limit (Docker Desktop -> Settings -> Resources); a large app may need 8 GB+.\n"
      "    - Lower test parallelism by adding `--concurrency=1` to your `goldens` command (it forwards to `flutter test`).\n"
      "    - Run fewer test files at once by targeting a smaller test directory.";

  /// Returns a diagnostic message for known signatures found in [output], or `null`
  /// if nothing recognizable was seen.
  String? diagnose(String output) => output.contains(compilerCrashMarker) ? compilerCrashDiagnostic : null;
}

/// Detects whether [needle] appears anywhere across a stream of text chunks, using
/// only O(needle length) memory - so a container's entire (potentially huge) output
/// can be scanned without buffering all of it.
///
/// Feed each chunk to [add]; [found] flips to `true` once [needle] has appeared,
/// even when it straddles a chunk boundary.
class StreamingMatcher {
  StreamingMatcher(this.needle);

  final String needle;

  /// Whether [needle] has been seen so far.
  bool found = false;

  /// The tail of previously-seen text, kept so a match spanning two chunks is
  /// still detected. Never longer than `needle.length - 1`.
  String _carry = "";

  void add(String chunk) {
    if (found || needle.isEmpty) {
      return;
    }

    final window = _carry + chunk;
    if (window.contains(needle)) {
      found = true;
      _carry = "";
      return;
    }

    // Retain just enough of the tail that a needle split across this chunk and the
    // next one is still caught.
    final keep = needle.length - 1;
    _carry = window.length > keep ? window.substring(window.length - keep) : window;
  }
}
