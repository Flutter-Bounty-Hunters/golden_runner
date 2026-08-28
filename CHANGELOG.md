## 0.2.3
 * Improvement: When the package under test is a Dart pub workspace member whose workspace root wouldn't be copied into the container, fail early with a clear message that suggests the `--path-to-project-root` value to pass.
 * Fix: Install a C toolchain (`clang`, `build-essential`) in the default Docker image so packages with Dart native-asset build hooks (`package:native_toolchain_c`) can compile inside the container. The toolchain is included only when the project actually has a native-asset build hook (`hook/build.dart`) — detected from `.dart_tool/package_config.json` — so projects without one get a lighter, faster image. Detection errs toward including the toolchain when it can't tell.
 * Feature: Add a `--flutter-version` option to pin the container's Flutter version (any `flutter/flutter` git ref, e.g. `3.44.6` or `stable`), so the container's SDK can match the project and CI.
 * Improvement: Print always-visible progress checkpoints with per-step timing (build image, run tests, clean up) and a total, so a long run isn't a silent wait. Suppressed with `--docker-verbosity none`.
 * Improvement: When the Docker build context is large (2 GiB+) and has no `.dockerignore`, apply a sensible default Flutter/Dart `.dockerignore` for that build so the whole directory (including generated output) isn't copied into the image every run. It's applied via a Dockerfile-adjacent ignore file in a temp directory, so no file is written into the project; a user's own `.dockerignore` is always respected. The log reports the context's full measured size, the estimated size after the ignore, and the savings (e.g. "29.5 GB ... shrinks it to ~214 MB (saving ~29.3 GB, 99%)") so the cost is clear. golden_runner now writes its built-in Dockerfile to a temp file (via `docker build -f`) instead of piping it over stdin.

## 0.2.2
### June 17, 2026
 * Feature: Add a `goldens clean` command to delete failure directories and files.

## 0.2.1
### April 26, 2026
 * Fix: Listen to Docker stdout and stderr concurrently to prevent deadlock.

## 0.2.0
### Aug 11, 2025
 * A Dockerfile is no longer required - a default Dockerfile is sent to Docker by this package.
 * Docker verbosity is configurable - you can now stop most/all Docker output to terminal.
 * `flutter test` output now displays in color, and also updates itself via interactive terminal, instead of printing many lines per test run.

## 0.1.0
Initial Release:
 * CLI app called `goldens`.
   * Test goldens with `goldens test`.
   * Update updates with `goldens update`.
   * Uses a Docker container to run goldens as Ubuntu.
 
