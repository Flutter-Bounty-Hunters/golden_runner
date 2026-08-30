import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Finds local `path:` dependencies that live OUTSIDE the project tree copied into
/// the Docker container, so they can be mounted in.
///
/// golden_runner copies the project (`--path-to-project-root`) into the image, so a
/// `path:` dependency (in `dependencies`, `dev_dependencies`, or `dependency_overrides`)
/// that resolves to a location outside that tree - e.g.
/// `dependency_overrides: super_editor: { path: /Users/me/super_editor/super_editor }` -
/// won't exist in the container, and `pub get` fails. Such dependencies are bind-mounted
/// read-only at their absolute path (so an absolute `path:` resolves as-is).
class PathDependencyResolver {
  const PathDependencyResolver();

  /// Returns the absolute host directories of `path:` dependencies that resolve
  /// outside [copiedRoot] and that exist (per [directoryExists]).
  ///
  /// Scans [seedPubspecs] and follows pub-workspace members and path dependencies
  /// transitively. [readFile] returns a file's contents or `null` if missing.
  Set<String> resolveExternalPathDependencies({
    required String copiedRoot,
    required List<String> seedPubspecs,
    required String? Function(String path) readFile,
    required bool Function(String path) directoryExists,
  }) {
    final normalizedRoot = path.normalize(copiedRoot);
    final external = <String>{};
    final visited = <String>{};
    final queue = [for (final pubspec in seedPubspecs) path.normalize(pubspec)];

    while (queue.isNotEmpty) {
      final pubspecPath = queue.removeLast();
      if (!visited.add(pubspecPath)) {
        continue;
      }

      final content = readFile(pubspecPath);
      if (content == null) {
        continue;
      }

      final Map yaml;
      try {
        final document = loadYaml(content);
        if (document is! Map) {
          continue;
        }
        yaml = document;
      } catch (_) {
        continue;
      }

      final pubspecDir = path.dirname(pubspecPath);

      // Follow pub-workspace members so their path dependencies are discovered too.
      final workspace = yaml["workspace"];
      if (workspace is List) {
        for (final member in workspace) {
          if (member is String) {
            queue.add(path.normalize(path.join(pubspecDir, member, "pubspec.yaml")));
          }
        }
      }

      for (final depPath in _pathDependencies(yaml)) {
        final resolved = path.normalize(
          path.isAbsolute(depPath) ? depPath : path.join(pubspecDir, depPath),
        );

        // Recurse into the dependency for its own (possibly external) path deps.
        queue.add(path.join(resolved, "pubspec.yaml"));

        final withinCopiedTree = path.equals(normalizedRoot, resolved) || path.isWithin(normalizedRoot, resolved);
        if (!withinCopiedTree && directoryExists(resolved)) {
          external.add(resolved);
        }
      }
    }

    return external;
  }

  /// The `path:` values declared across a pubspec's dependency sections.
  Iterable<String> _pathDependencies(Map yaml) sync* {
    for (final section in const ["dependencies", "dev_dependencies", "dependency_overrides"]) {
      final deps = yaml[section];
      if (deps is! Map) {
        continue;
      }
      for (final spec in deps.values) {
        if (spec is Map && spec["path"] is String) {
          yield spec["path"] as String;
        }
      }
    }
  }
}
