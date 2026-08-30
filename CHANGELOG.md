## 0.2.3
 * Feature: Diagnose Docker out-of-memory failures. When the container's Dart compiler is killed mid-compile, Flutter reports only the cryptic "The Dart compiler exited unexpectedly" with a Dart stack trace — which almost always means Docker ran out of memory, not a test or compiler bug. golden_runner now watches the container's output for that signature and, when it appears, prints a plain-language explanation with fixes (raise Docker's memory limit, add `--concurrency=1`, target a smaller test directory). The diagnosis surfaces even in `--silent` mode. The live interactive display (color and in-place line updates) is unchanged: the default run still inherits your terminal directly, and golden_runner scans the container's captured logs after it exits rather than intercepting the stream.
 * Feature: Support local `path:` dependencies that live outside the copied project (e.g. an absolute `dependency_overrides` path to a local `super_editor`). golden_runner detects them — across dependencies/dev_dependencies/dependency_overrides, transitively and across pub-workspace members — and bind-mounts each read-only into the container at its absolute path so `pub get` resolves them.
 * Feature: Add `--silent` (for CI) and `--verbose`/`-v` (for debugging) verbosity controls. `--silent` stays quiet on success, but on failure it surfaces the container's output (the golden test failure summary) plus errors, and always exits non-zero — so CI fails loudly instead of looking like a silent success. `--verbose` enables maximum output: full Docker build logs, fine-grained internal debug logs, and verbose `flutter test`. The default is unchanged. `--docker-verbosity` remains as an advanced override of the Docker passthrough level.
 * Fix: Propagate the container's exit code, so a failing image build or failing golden tests make the process (and CI) fail. Previously the process exited 0 even when tests failed.
 * Improvement: When the package under test is a Dart pub workspace member whose workspace root wouldn't be copied into the container, fail early with a clear message that suggests the `--path-to-project-root` value to pass.
 * Fix: Install a C toolchain (`clang`, `build-essential`) in the default Docker image so packages with Dart native-asset build hooks (`package:native_toolchain_c`) can compile inside the container. The toolchain is included only when the project actually has a native-asset build hook (`hook/build.dart`) — detected from `.dart_tool/package_config.json` — so projects without one get a lighter, faster image. Detection errs toward including the toolchain when it can't tell.
 * Change: The built-in Dockerfile now defaults to Flutter's `stable` channel (`git clone --branch stable`) instead of the repository's default branch (`master`). Most projects use stable, and `master` is bleeding-edge and far less reproducible. Pass `--flutter-version master` for the old behavior.
 * Feature: Add a `--flutter-version` option to pin the container's Flutter version (any `flutter/flutter` git ref, e.g. `3.44.6` or `stable`), so the container's SDK can match the project and CI.
 * Feature: Auto-detect the Flutter version from a project's FVM config (`.fvmrc`, or legacy `.fvm/fvm_config.json`) when `--flutter-version` isn't passed — walking up from the package under test to the project root, and logging the inferred version. An explicit `--flutter-version` still takes precedence.
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
 
