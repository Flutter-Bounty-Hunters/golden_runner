import 'package:golden_runner/golden_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group("Path dependency resolver >", () {
    test("mounts an absolute path override outside the project", () {
      final files = {
        "/repo/pubspec.yaml": "name: app\n"
            "dependency_overrides:\n"
            "  super_editor:\n"
            "    path: /Users/me/super_editor/super_editor\n",
      };

      final external = _resolve(files, copiedRoot: "/repo", dirs: {"/Users/me/super_editor/super_editor"});
      expect(external, {"/Users/me/super_editor/super_editor"});
    });

    test("ignores path deps that live inside the copied tree", () {
      final files = {
        "/repo/pubspec.yaml": "name: app\n"
            "dependencies:\n"
            "  local_pkg:\n"
            "    path: packages/local_pkg\n",
      };

      final external = _resolve(files, copiedRoot: "/repo", dirs: {"/repo/packages/local_pkg"});
      expect(external, isEmpty);
    });

    test("resolves transitive path deps of an external dependency", () {
      final files = {
        "/repo/pubspec.yaml": "name: app\n"
            "dependency_overrides:\n"
            "  super_editor:\n"
            "    path: /ext/super_editor/super_editor\n",
        // The external dep references a sibling by relative path.
        "/ext/super_editor/super_editor/pubspec.yaml": "name: super_editor\n"
            "dependencies:\n"
            "  super_text_layout:\n"
            "    path: ../super_text_layout\n",
      };

      final external = _resolve(
        files,
        copiedRoot: "/repo",
        dirs: {"/ext/super_editor/super_editor", "/ext/super_editor/super_text_layout"},
      );
      expect(external, {
        "/ext/super_editor/super_editor",
        "/ext/super_editor/super_text_layout",
      });
    });

    test("follows workspace members", () {
      final files = {
        "/repo/pubspec.yaml": "name: workspace\n"
            "workspace:\n"
            "  - packages/chat\n",
        "/repo/packages/chat/pubspec.yaml": "name: chat\n"
            "dependency_overrides:\n"
            "  super_editor:\n"
            "    path: /ext/super_editor\n",
      };

      final external = _resolve(files, copiedRoot: "/repo", dirs: {"/ext/super_editor"});
      expect(external, {"/ext/super_editor"});
    });

    test("skips external paths that don't exist on the host", () {
      final files = {
        "/repo/pubspec.yaml": "name: app\n"
            "dependency_overrides:\n"
            "  gone:\n"
            "    path: /ext/gone\n",
      };

      final external = _resolve(files, copiedRoot: "/repo", dirs: const {});
      expect(external, isEmpty);
    });

    test("returns nothing when there are no path deps", () {
      final files = {"/repo/pubspec.yaml": "name: app\ndependencies:\n  http: ^1.0.0\n"};
      expect(_resolve(files, copiedRoot: "/repo", dirs: const {}), isEmpty);
    });
  });
}

/// Runs the resolver seeded at `<copiedRoot>/pubspec.yaml`, backed by in-memory
/// [files] and a set of [dirs] that "exist" on the host.
Set<String> _resolve(
  Map<String, String> files, {
  required String copiedRoot,
  required Set<String> dirs,
}) {
  final normalizedFiles = files.map((key, value) => MapEntry(path.normalize(key), value));
  final normalizedDirs = dirs.map(path.normalize).toSet();
  return const PathDependencyResolver().resolveExternalPathDependencies(
    copiedRoot: copiedRoot,
    seedPubspecs: [path.join(copiedRoot, "pubspec.yaml")],
    readFile: (p) => normalizedFiles[path.normalize(p)],
    directoryExists: (p) => normalizedDirs.contains(path.normalize(p)),
  );
}
