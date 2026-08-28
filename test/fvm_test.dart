import 'package:golden_runner/golden_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group("FVM version resolver >", () {
    test("reads the flutter version from .fvmrc in the start directory", () {
      final read = _reader({
        "/repo/.fvmrc": '{"flutter": "3.44.6", "updateVscodeSettings": false}',
      });
      expect(const FvmVersionResolver().resolve("/repo", "/repo", readFile: read), "3.44.6");
    });

    test("walks up from a subdirectory to the project root", () {
      final read = _reader({
        "/repo/.fvmrc": '{"flutter": "3.44.6"}',
      });
      final version = const FvmVersionResolver().resolve(
        "/repo/packages/chat",
        "/repo",
        readFile: read,
      );
      expect(version, "3.44.6");
    });

    test("supports a channel value", () {
      final read = _reader({"/repo/.fvmrc": '{"flutter": "stable"}'});
      expect(const FvmVersionResolver().resolve("/repo", "/repo", readFile: read), "stable");
    });

    test("falls back to legacy .fvm/fvm_config.json", () {
      final read = _reader({
        "/repo/.fvm/fvm_config.json": '{"flutterSdkVersion": "3.10.0"}',
      });
      expect(const FvmVersionResolver().resolve("/repo", "/repo", readFile: read), "3.10.0");
    });

    test(".fvmrc takes precedence over legacy config in the same directory", () {
      final read = _reader({
        "/repo/.fvmrc": '{"flutter": "3.44.6"}',
        "/repo/.fvm/fvm_config.json": '{"flutterSdkVersion": "3.10.0"}',
      });
      expect(const FvmVersionResolver().resolve("/repo", "/repo", readFile: read), "3.44.6");
    });

    test("returns null when there's no FVM config", () {
      final read = _reader({});
      expect(const FvmVersionResolver().resolve("/repo/packages/chat", "/repo", readFile: read), isNull);
    });

    test("does not walk above the stop directory", () {
      // Config exists ABOVE the project root; it must not be picked up.
      final read = _reader({"/.fvmrc": '{"flutter": "1.0.0"}'});
      expect(const FvmVersionResolver().resolve("/repo/packages/chat", "/repo", readFile: read), isNull);
    });

    test("ignores malformed or empty config", () {
      expect(
        const FvmVersionResolver().resolve("/repo", "/repo", readFile: _reader({"/repo/.fvmrc": "{ not json"})),
        isNull,
      );
      expect(
        const FvmVersionResolver().resolve("/repo", "/repo", readFile: _reader({"/repo/.fvmrc": '{"flutter": "  "}'})),
        isNull,
      );
    });
  });
}

/// Builds a `readFile` backed by a map of absolute path -> contents.
String? Function(String) _reader(Map<String, String> files) {
  final normalized = files.map((key, value) => MapEntry(path.normalize(key), value));
  return (p) => normalized[path.normalize(p)];
}
