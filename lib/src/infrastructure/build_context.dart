import 'dart:io';

import 'package:path/path.dart' as path;

/// Whether golden_runner should apply its default `.dockerignore` for a build.
enum BuildContextIgnoreDecision {
  /// Leave the context as-is: it's missing, small enough, or already has a
  /// `.dockerignore`.
  none,

  /// Apply golden_runner's default `.dockerignore` for this build.
  applyDefault,
}

/// The result of [BuildContextGuard.assess].
class BuildContextAssessment {
  const BuildContextAssessment(
    this.decision, {
    this.contextPath = "",
    this.measuredBytes = 0,
    this.keptBytes = 0,
    this.isApproximate = false,
  });

  final BuildContextIgnoreDecision decision;

  /// Normalized, absolute path to the build context (best effort).
  final String contextPath;

  /// The total size measured for the context, or 0 when the context wasn't
  /// measured (missing, or it already has a `.dockerignore`).
  final int measuredBytes;

  /// The estimated size that would remain after applying the default
  /// `.dockerignore` (see [BuildContextGuard.defaultDockerignore]). This is an
  /// estimate - it applies the default's directory/file exclusions to the walk.
  final int keptBytes;

  /// The estimated bytes excluded by the default `.dockerignore`.
  int get savedBytes => (measuredBytes - keptBytes).clamp(0, measuredBytes);

  /// Whether [measuredBytes] is a lower bound rather than the exact total - true
  /// only if measurement hit its safety cap on a pathologically large tree.
  final bool isApproximate;
}

/// Decides whether golden_runner should apply a default `.dockerignore` for a build.
///
/// golden_runner builds an image whose context is the project root, and the
/// Dockerfile copies that whole context into the image. Without a `.dockerignore`,
/// generated output (`build/`, `.dart_tool/`, `.git`, ...) is sent to Docker and
/// copied on every run, which can add many minutes to each build.
///
/// This guard only *decides* - it never writes to the project. When it says
/// [BuildContextIgnoreDecision.applyDefault], the caller applies [defaultDockerignore]
/// via a Dockerfile-adjacent ignore file in a temp directory, so nothing lands in
/// the user's project. It defers to a `.dockerignore` the user already manages.
class BuildContextGuard {
  const BuildContextGuard({
    this.thresholdBytes = defaultThresholdBytes,
    this.entryScanCap = defaultEntryScanCap,
  });

  /// A context at or above this size (with no `.dockerignore`) is treated as "too
  /// large" and gets the default `.dockerignore`.
  static const defaultThresholdBytes = 2 * 1024 * 1024 * 1024; // 2 GiB

  /// Safety cap on the number of filesystem entries scanned, so measuring the
  /// context can't run away on a pathologically large tree. Set well above the
  /// file counts of real projects (a large Flutter mono-repo is ~180k files, and
  /// a full walk of it takes only a few seconds), so the measured size is normally
  /// exact; hitting this cap makes the reported size a lower bound instead.
  static const defaultEntryScanCap = 5000000;

  final int thresholdBytes;
  final int entryScanCap;

  /// Assesses the build context at [contextPath] and decides whether golden_runner
  /// should apply its default `.dockerignore`.
  ///
  /// [contextPath] may be relative; it's resolved against the current directory,
  /// matching how Docker resolves the build context.
  Future<BuildContextAssessment> assess(String contextPath) async {
    final contextDir = Directory(contextPath);
    if (!contextDir.existsSync()) {
      return const BuildContextAssessment(BuildContextIgnoreDecision.none);
    }

    final normalized = path.normalize(contextDir.absolute.path);

    // Defer to a `.dockerignore` the user already manages.
    if (File(path.join(contextDir.path, ".dockerignore")).existsSync()) {
      return BuildContextAssessment(BuildContextIgnoreDecision.none, contextPath: normalized);
    }

    final measurement = await _measureSize(Directory(normalized));
    final decision =
        measurement.full >= thresholdBytes ? BuildContextIgnoreDecision.applyDefault : BuildContextIgnoreDecision.none;
    return BuildContextAssessment(
      decision,
      contextPath: normalized,
      measuredBytes: measurement.full,
      keptBytes: measurement.kept,
      isApproximate: measurement.isLowerBound,
    );
  }

  /// Walks the whole tree under [absContextDir] (an absolute, normalized path),
  /// summing the size of every file ([full]) and the size of the files that would
  /// survive the default `.dockerignore` ([kept]). A ~180k-file mono-repo takes a
  /// few seconds; it stops early only if it hits [entryScanCap], in which case the
  /// totals are lower bounds (`isLowerBound` is true).
  Future<({int full, int kept, bool isLowerBound})> _measureSize(Directory absContextDir) async {
    var full = 0;
    var kept = 0;
    var scanned = 0;
    var isLowerBound = false;
    final base = absContextDir.path;
    try {
      // followLinks: false avoids walking into symlinked SDKs (e.g. `.fvm`) and
      // matches Docker, which doesn't follow symlinks out of the context.
      // handleError skips unreadable entries and keeps walking.
      final entries = absContextDir.list(recursive: true, followLinks: false).handleError((Object _) {});
      await for (final entity in entries) {
        scanned += 1;
        if (scanned > entryScanCap) {
          isLowerBound = true;
          break;
        }
        if (entity is! File) {
          continue;
        }
        int size;
        try {
          size = entity.lengthSync();
        } catch (_) {
          // Unreadable or vanished file - skip it.
          continue;
        }
        full += size;

        // Path relative to the context root (starts with "/"), so the context's
        // own path segments can't accidentally match an exclusion.
        var relativePath = entity.path;
        if (relativePath.length > base.length && relativePath.startsWith(base)) {
          relativePath = relativePath.substring(base.length);
        }
        if (!_isExcludedByDefaultIgnore(relativePath)) {
          kept += size;
        }
      }
    } catch (_) {
      // Unexpected stream termination: treat the running totals as lower bounds.
      isLowerBound = true;
    }
    return (full: full, kept: kept, isLowerBound: isLowerBound);
  }

  /// Directory segments the default `.dockerignore` excludes. Keep in sync with
  /// [defaultDockerignore]; used only to estimate the post-ignore size.
  static const _excludedDirSegments = [
    ".git",
    ".dart_tool",
    "build",
    ".fvm",
    "Pods",
    ".symlinks",
    "ephemeral",
    ".gradle",
    "DerivedData",
    "coverage",
    ".idea",
  ];

  static final _excludedDirNeedles = [for (final segment in _excludedDirSegments) "/$segment/"];

  /// Exact file names the default `.dockerignore` excludes (plus a `*.iml` rule).
  static const _excludedFileNames = [
    ".packages",
    ".flutter-plugins",
    ".flutter-plugins-dependencies",
  ];

  /// Whether the default `.dockerignore` would exclude [relativePath] (which starts
  /// with "/"). An approximation matched to [defaultDockerignore]'s patterns, used
  /// only to estimate the post-ignore size.
  static bool _isExcludedByDefaultIgnore(String relativePath) {
    for (final needle in _excludedDirNeedles) {
      if (relativePath.contains(needle)) {
        return true;
      }
    }
    final lastSlash = relativePath.lastIndexOf("/");
    final name = lastSlash >= 0 ? relativePath.substring(lastSlash + 1) : relativePath;
    return _excludedFileNames.contains(name) || name.endsWith(".iml");
  }

  /// Formats [bytes] as a compact human-readable size, e.g. `512 B`, `2.4 GB`.
  static String formatBytes(int bytes) {
    const units = ["B", "KB", "MB", "GB", "TB"];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    final rounded =
        (size >= 100 || size == size.roundToDouble()) ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
    return "$rounded ${units[unit]}";
  }

  /// A conservative default `.dockerignore` for Flutter/Dart projects.
  ///
  /// It excludes generated output and local SDKs that aren't needed to run tests
  /// inside the container (which runs its own `flutter pub get`). It intentionally
  /// keeps all sources, `pubspec.yaml`/`pubspec.lock`, and test directories, so a
  /// pub workspace still resolves.
  ///
  /// golden_runner applies this by writing it next to its generated Dockerfile in a
  /// temp directory (a Dockerfile-adjacent ignore file), so it never lands in the
  /// user's project.
  static const defaultDockerignore = '''# Applied automatically by golden_runner for this build - NOT written to your
# project. This project's Docker build context was large and had no .dockerignore,
# so golden_runner excludes generated output that isn't needed to run tests in the
# container (which runs its own `flutter pub get`). Sources, pubspec.yaml/pubspec.lock,
# and test directories are kept, so a pub workspace still resolves. Add your own
# .dockerignore to the project to customize what's sent to Docker.

# Version control
.git

# Dart & Flutter generated output (regenerated by pub get / build)
.dart_tool/
**/.dart_tool/
build/
**/build/
.packages
**/.packages
.flutter-plugins
.flutter-plugins-dependencies
**/.flutter-plugins
**/.flutter-plugins-dependencies

# FVM-managed local SDK (the container installs its own Flutter)
.fvm/
**/.fvm/

# Native build output (not needed for widget/golden tests on Linux)
**/ios/Pods/
**/ios/.symlinks/
**/ios/Flutter/ephemeral/
**/macos/Pods/
**/macos/Flutter/ephemeral/
**/android/.gradle/
**/.gradle/
**/DerivedData/
**/windows/flutter/ephemeral/
**/linux/flutter/ephemeral/

# Coverage & IDE files
coverage/
**/coverage/
.idea/
**/*.iml
''';
}
