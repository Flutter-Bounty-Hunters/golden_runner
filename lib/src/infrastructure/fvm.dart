import 'dart:convert';

import 'package:path/path.dart' as path;

/// Resolves the Flutter version an FVM-configured project is pinned to.
///
/// [FVM](https://fvm.app) records a project's Flutter version in a config file at
/// the project root: the modern `.fvmrc` (`{"flutter": "<version>"}`) or the legacy
/// `.fvm/fvm_config.json` (`{"flutterSdkVersion": "<version>"}`). golden_runner uses
/// this to pin the container's Flutter to the version the developer builds with
/// locally (and in CI), so goldens match - without the caller passing
/// `--flutter-version` explicitly.
class FvmVersionResolver {
  const FvmVersionResolver();

  /// Returns the Flutter version pinned by FVM, found by walking up from
  /// [startDirectory] to [stopDirectory] (inclusive) - mirroring how FVM resolves
  /// config from a subdirectory up to the project root.
  ///
  /// The returned value is whatever FVM records: a release like `3.44.6`, or a
  /// channel like `stable`. Returns `null` if no FVM config is found. [readFile]
  /// returns a file's contents, or `null` when the file doesn't exist.
  String? resolve(
    String startDirectory,
    String stopDirectory, {
    required String? Function(String path) readFile,
  }) {
    var directory = path.normalize(startDirectory);
    final stop = path.normalize(stopDirectory);

    while (true) {
      final version = _versionInDirectory(directory, readFile);
      if (version != null) {
        return version;
      }

      if (directory == stop) {
        // Checked the boundary (project root); don't walk above it.
        return null;
      }

      final parent = path.dirname(directory);
      if (parent == directory) {
        // Reached the filesystem root.
        return null;
      }
      directory = parent;
    }
  }

  String? _versionInDirectory(String directory, String? Function(String) readFile) {
    // Modern config: `.fvmrc` -> {"flutter": "3.44.6"}.
    final fvmrc = readFile(path.join(directory, ".fvmrc"));
    if (fvmrc != null) {
      final version = _stringField(fvmrc, "flutter");
      if (version != null) {
        return version;
      }
    }

    // Legacy config: `.fvm/fvm_config.json` -> {"flutterSdkVersion": "3.44.6"}.
    final legacy = readFile(path.join(directory, ".fvm", "fvm_config.json"));
    if (legacy != null) {
      final version = _stringField(legacy, "flutterSdkVersion");
      if (version != null) {
        return version;
      }
    }

    return null;
  }

  String? _stringField(String jsonContent, String field) {
    try {
      final decoded = jsonDecode(jsonContent);
      if (decoded is Map && decoded[field] is String) {
        final value = (decoded[field] as String).trim();
        return value.isEmpty ? null : value;
      }
    } catch (_) {
      // Not valid JSON - ignore.
    }
    return null;
  }
}
