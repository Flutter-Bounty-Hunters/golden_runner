## 0.3.0
 * [BREAKING] Change: The built-in Dockerfile now defaults to Flutter's `stable` channel.
 * Feature: Auto-detect the Flutter version from a project's FVM config (`.fvmrc`, or legacy `.fvm/fvm_config.json`).
 * Feature: Can use a custom Flutter version. Use `--flutter-version` flag.
 * Feature: Can use a custom Ubuntu version. Use `--ubuntu-version` flag.
 * Feature: Automatically applies a `.dockerignore` to large codebases to dramatically reduce image copy time and image size.
 * Feature: Can use local Pub dependencies in host project.
 * Feature: Can use dependencies with native assets in host project. Installs `clang` and `build-essential` in Docker image.
 * Feature: Users now notified if test run fails due to Docker out-of-memory crash.
 * Adjustment: Add `--silent` (for CI) and `--verbose`/`-v` (for debugging) verbosity controls.
 * Adjustment: Notify user when they likely forgot to specify the path to the root of the project.
 * Fix: Propagate the container's exit code, so a failing image build or failing golden tests make the process (and CI) fail.

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
 
