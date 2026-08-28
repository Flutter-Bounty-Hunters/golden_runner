import 'dart:io';

import 'package:golden_runner/golden_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group("Native asset detector >", () {
    late Directory projectRoot;

    setUp(() {
      projectRoot = Directory.systemTemp.createTempSync("gr_native_test");
    });

    tearDown(() {
      if (projectRoot.existsSync()) {
        projectRoot.deleteSync(recursive: true);
      }
    });

    test("needs a toolchain when a package has a hook/build.dart", () {
      // Two packages; the second has a native-asset build hook.
      _writePackageConfig(projectRoot, ["../", "../packages/native_audio"]);
      _writeBuildHook(projectRoot, "packages/native_audio");

      expect(const NativeAssetDetector().needsCToolchain(projectRoot.path), isTrue);
    });

    test("does NOT need a toolchain when no package has a build hook", () {
      _writePackageConfig(projectRoot, ["../", "../packages/chat", "../packages/data_model"]);
      Directory(path.join(projectRoot.path, "packages", "chat", "lib")).createSync(recursive: true);
      Directory(path.join(projectRoot.path, "packages", "data_model", "lib")).createSync(recursive: true);

      expect(const NativeAssetDetector().needsCToolchain(projectRoot.path), isFalse);
    });

    test("errs toward true when there's no package_config.json", () {
      // Nothing written - can't enumerate dependencies.
      expect(const NativeAssetDetector().needsCToolchain(projectRoot.path), isTrue);
    });

    test("errs toward true when package_config.json is malformed", () {
      File(path.join(projectRoot.path, ".dart_tool", "package_config.json"))
        ..createSync(recursive: true)
        ..writeAsStringSync("{ not valid json");

      expect(const NativeAssetDetector().needsCToolchain(projectRoot.path), isTrue);
    });

    test("resolves absolute file:// rootUris", () {
      // A package outside the project (like a pub-cache package) with a build hook.
      final external = Directory.systemTemp.createTempSync("gr_native_ext");
      addTearDown(() => external.deleteSync(recursive: true));
      File(path.join(external.path, "hook", "build.dart"))
        ..createSync(recursive: true)
        ..writeAsStringSync("void main() {}");

      _writePackageConfig(projectRoot, ["../", external.uri.toString()]);

      expect(const NativeAssetDetector().needsCToolchain(projectRoot.path), isTrue);
    });
  });
}

/// Writes a `.dart_tool/package_config.json` under [projectRoot] listing
/// [packageRootUris] (each a `rootUri` relative to `.dart_tool/`).
void _writePackageConfig(Directory projectRoot, List<String> packageRootUris) {
  final packages = packageRootUris
      .asMap()
      .entries
      .map((e) => '{"name": "pkg${e.key}", "rootUri": "${e.value}", "packageUri": "lib/"}')
      .join(",\n    ");
  File(path.join(projectRoot.path, ".dart_tool", "package_config.json"))
    ..createSync(recursive: true)
    ..writeAsStringSync('{\n  "configVersion": 2,\n  "packages": [\n    $packages\n  ]\n}');
}

/// Writes a native-asset build hook at `<packageDirRelativeToRoot>/hook/build.dart`
/// under [projectRoot].
void _writeBuildHook(Directory projectRoot, String packageDirRelativeToRoot) {
  File(path.join(projectRoot.path, packageDirRelativeToRoot, "hook", "build.dart"))
    ..createSync(recursive: true)
    ..writeAsStringSync("void main() {}");
}
