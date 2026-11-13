import 'package:golden_runner/golden_runner.dart';
import 'package:test/test.dart';

void main() {
  group("Built-in Dockerfile >", () {
    test("defaults to Flutter's stable channel when no version is given", () {
      final dockerfile = createGoldenTesterDockerfile();

      // Clones the stable branch explicitly (not the repo's default branch, master).
      expect(dockerfile, contains("--single-branch --branch stable https://github.com/flutter/flutter.git"));
      // Keeps the cache-bust so new stable releases are picked up.
      expect(dockerfile, contains("refs/heads/stable"));
      expect(dockerfile, isNot(contains("flutter_infra_release")));
    });

    test("installs a pinned stable release from its archive, cloning only as a fallback", () {
      final dockerfile = createGoldenTesterDockerfile(flutterVersion: "3.44.6");

      expect(
        dockerfile,
        contains(
          "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.6-stable.tar.xz",
        ),
      );
      // The archive is x64-only, so other architectures (and failed downloads) clone the tag.
      expect(dockerfile, contains(r'if [ "$(dpkg --print-architecture)" = amd64 ]'));
      expect(dockerfile, contains("--branch 3.44.6 https://github.com/flutter/flutter.git"));
      // A pinned version never moves, so there's no stable cache-bust.
      expect(dockerfile, isNot(contains("refs/heads/stable")));
    });

    test("installs a pinned beta release from the beta archive", () {
      expect(
        createGoldenTesterDockerfile(flutterVersion: "3.51.0-0.1.pre"),
        contains("releases/beta/linux/flutter_linux_3.51.0-0.1.pre-beta.tar.xz"),
      );
    });

    test("clones a pinned branch, since branches have no archive", () {
      final dockerfile = createGoldenTesterDockerfile(flutterVersion: "beta");

      expect(dockerfile, contains("--single-branch --branch beta https://github.com/flutter/flutter.git"));
      expect(dockerfile, isNot(contains("flutter_infra_release")));
    });

    test("checks out a pinned commit, which git clone --branch can't take", () {
      final dockerfile = createGoldenTesterDockerfile(flutterVersion: "ee80f08bb");

      expect(dockerfile, contains(r'checkout ee80f08bb'));
      expect(dockerfile, isNot(contains("--branch ee80f08bb")));
    });

    test("clones without blobs or trees but keeps history, which Flutter's version detection needs", () {
      for (final version in [null, "3.44.6", "beta", "ee80f08bb"]) {
        final dockerfile = createGoldenTesterDockerfile(flutterVersion: version);

        expect(dockerfile, contains("git clone --filter=tree:0"), reason: "version: $version");
        expect(dockerfile, isNot(contains("--depth")), reason: "version: $version");
      }
    });

    test("includes the C toolchain by default", () {
      expect(createGoldenTesterDockerfile(), contains("apt install -y git curl unzip xz-utils clang build-essential"));
    });

    test("omits the C toolchain when not needed", () {
      final dockerfile = createGoldenTesterDockerfile(includeCToolchain: false);

      expect(dockerfile, contains("apt install -y git curl unzip xz-utils\n"));
      expect(dockerfile, isNot(contains("clang")));
      expect(dockerfile, isNot(contains("build-essential")));
    });

    test("copies the project into the image", () {
      expect(createGoldenTesterDockerfile(), contains("COPY ./ /golden_tester"));
    });

    test("defaults the base image to ubuntu:latest", () {
      expect(createGoldenTesterDockerfile(), contains("FROM ubuntu:latest"));
    });

    test("uses the pinned Ubuntu version when one is given", () {
      final dockerfile = createGoldenTesterDockerfile(ubuntuVersion: "24.04");

      expect(dockerfile, contains("FROM ubuntu:24.04"));
      expect(dockerfile, isNot(contains("FROM ubuntu:latest")));
    });
  });
}
