import 'package:golden_runner/golden_runner.dart';
import 'package:test/test.dart';

void main() {
  group("Built-in Dockerfile >", () {
    test("defaults to Flutter's stable channel when no version is given", () {
      final dockerfile = createGoldenTesterDockerfile();

      // Clones the stable branch explicitly (not the repo's default branch, master).
      expect(dockerfile, contains("git clone https://github.com/flutter/flutter.git --branch stable"));
      // Keeps the cache-bust so new stable releases are picked up.
      expect(dockerfile, contains("refs/heads/stable"));
      // Never clones without a branch (which would grab master).
      expect(dockerfile, isNot(contains(r"git clone https://github.com/flutter/flutter.git ${FLUTTER_HOME}")));
    });

    test("clones the pinned version when one is given, without the cache-bust", () {
      final dockerfile = createGoldenTesterDockerfile(flutterVersion: "3.44.6");

      expect(dockerfile, contains("git clone https://github.com/flutter/flutter.git --branch 3.44.6"));
      // A pinned version never moves, so there's no stable cache-bust.
      expect(dockerfile, isNot(contains("refs/heads/stable")));
    });

    test("includes the C toolchain by default", () {
      expect(createGoldenTesterDockerfile(), contains("apt install -y git curl unzip clang build-essential"));
    });

    test("omits the C toolchain when not needed", () {
      final dockerfile = createGoldenTesterDockerfile(includeCToolchain: false);

      expect(dockerfile, contains("apt install -y git curl unzip\n"));
      expect(dockerfile, isNot(contains("clang")));
      expect(dockerfile, isNot(contains("build-essential")));
    });

    test("copies the project into the image", () {
      expect(createGoldenTesterDockerfile(), contains("COPY ./ /golden_tester"));
    });
  });
}
