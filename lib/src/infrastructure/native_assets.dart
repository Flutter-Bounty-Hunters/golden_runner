import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Detects whether a project needs a C/C++ toolchain (clang) installed in the
/// container to build its tests.
///
/// A project needs one when any resolved package has a Dart native-asset build
/// hook (`hook/build.dart`) - the mechanism `package:native_toolchain_c` and
/// friends use to compile native code during `flutter test`. Most Flutter
/// projects have none, so the container can skip installing a compiler entirely.
class NativeAssetDetector {
  const NativeAssetDetector();

  /// Whether the project rooted at [projectRoot] appears to need a C toolchain.
  ///
  /// Enumerates the resolved packages from
  /// `<projectRoot>/.dart_tool/package_config.json` and checks each for a
  /// `hook/build.dart`. Errs on the side of `true` whenever it can't tell (missing
  /// or unparseable package config), so a missing toolchain never causes a cryptic
  /// build failure deep inside a native hook.
  bool needsCToolchain(String projectRoot) {
    final packageConfigFile = File(path.join(projectRoot, ".dart_tool", "package_config.json"));
    if (!packageConfigFile.existsSync()) {
      // Can't enumerate dependencies - assume a toolchain might be needed.
      return true;
    }

    final List<dynamic> packages;
    try {
      final decoded = jsonDecode(packageConfigFile.readAsStringSync());
      packages = (decoded as Map<String, dynamic>)["packages"] as List<dynamic>;
    } catch (_) {
      // Unparseable / unexpected shape - be safe.
      return true;
    }

    // Package `rootUri`s are resolved relative to the package_config.json's own
    // directory (`.dart_tool/`); absolute `file://` URIs resolve to themselves.
    final configDirUri = packageConfigFile.parent.uri;
    for (final entry in packages) {
      if (entry is! Map) {
        continue;
      }
      final rootUri = entry["rootUri"];
      if (rootUri is! String) {
        continue;
      }

      final String packageRoot;
      try {
        packageRoot = configDirUri.resolve(rootUri).toFilePath();
      } catch (_) {
        // An odd rootUri we can't resolve - skip it rather than over-installing.
        continue;
      }

      if (File(path.join(packageRoot, "hook", "build.dart")).existsSync()) {
        return true;
      }
    }

    return false;
  }
}
