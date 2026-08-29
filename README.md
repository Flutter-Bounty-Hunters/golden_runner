<p align="center">
  <a href="https://flutterbountyhunters.com" target="_blank">
    <img src="https://github.com/Flutter-Bounty-Hunters/flutter_test_robots/assets/7259036/1b19720d-3dad-4ade-ac76-74313b67a898" alt="Built by the Flutter Bounty Hunters">
  </a>
</p>

---

# Golden Runner
CLI app that runs golden tests within an Ubuntu Docker container, to help reduce flakiness.

In short, this CLI app replaces the following Flutter commands...

    flutter test

    flutter test --update-goldens

with the following...

    goldens test

    goldens update

    goldens clean

The purpose of the `goldens` command is to run your golden tests in an environment that produces
consistent results. 

 * To get consistent results: Runs in a Docker Container.
 * To keep it free: Runs in an Ubuntu image.
 * To minimize GitHub runner costs: Runs in an Ubuntu image.

When testing or updating goldens locally, use `goldens` instead of `flutter test`.

Then, in CI, run your golden tests on an Ubuntu runner.

This approach isn't perfect. Sometimes there are still mismatches between the goldens painted
by the Ubuntu Docker container vs the goldens painted by the GitHub Ubuntu runner. However, we've
found that this approach greatly reduces such mismatches.

## Activate the package
To use the `goldens` command, you must first activate the `golden_runner` package.

Activate from Pub:

    dart pub global activate golden_runner

Or, activate from local source:

    # From outside the `golden_runner` directory:
    dart pub global activate --source path ./golden_runner

    # From within the `golden_runner` directory:
    dart pub global activate --source path .

## Run golden tests
The `goldens` command must be run from the directory of the app/package under test.

```
# Run all tests in a test_goldens directory.
goldens test

# Run tests with a given name.
goldens test --plain-name="something"

# Run all tests in a directory.
goldens test test_goldens/my_dir

# Run select tests in a directory.
goldens test --plain-name="something" test_goldens/my_dir
```

Projects that live in a mono-repo/workspace need to specify the path to the root of the
workspace.

```
# Assume this project sits in ./packages/app_under_test, so the root is up two
# directories: ../..
goldens test --path-to-project-root ../..
```

## Update golden files
The `goldens` command must be run from the directory of the app/package under test.

```
# Update all goldens in a test_goldens directory.
goldens update

# Update all goldens in a directory.
goldens update test_goldens/my_dir

# Update goldens with a given test name.
goldens update --plain-name="something"

# Update select goldens in a directory.
goldens update --plain-name "something" test_goldens/my_dir
```

Projects that live in a mono-repo/workspace need to specify the path to the root of the
workspace.

```
# Assume this project sits in ./packages/app_under_test, so the root is up two
# directories: ../..
goldens update --path-to-project-root ../..
```

## Specific Flutter Version
By default, `golden_runner` uses the latest Flutter `stable` version. To use a different version,
use the `--flutter-version` flag.

```
goldens update --flutter-version 3.44.6

goldens test --flutter-version beta
```

If you provide your own custom Dockerfile, this flag is ignored and you'll need to specify the
desired Flutter version, yourself.

### FVM projects
If your project uses [FVM](https://fvm.app), you don't need to pass `--flutter-version` at all.

The `golden_runner` CLI reads the pinned version from your FVM config — `.fvmrc` (or legacy
`.fvm/fvm_config.json`) — walking up from the package under test to the project root, and pins the
container's Flutter to it automatically. 

An explicit `--flutter-version` always overrides this.

## Output verbosity
By default, `golden_runner` prints high-level progress (build → test → cleanup, with per-step timing),
any errors, and streams `flutter test` output.

Two flags adjust this:

```
# Silent — for CI. Suppresses normal output on success, but on failure it surfaces the container's
# output (the golden test failure summary) and errors, and exits non-zero — so CI fails loudly.
goldens update --silent

# Verbose — maximum detail for debugging: full Docker build logs, fine-grained internal
# debug logs, and verbose `flutter test` output.
goldens test --verbose   # or -v
```

`golden_runner` exits non-zero when the image build fails or the golden tests fail, so a failing run
fails your CI job — including in `--silent` mode.

For fine-grained control of just the Docker passthrough, `--docker-verbosity <standard|quiet|error|none>`
overrides the level derived from the flags above.

## Local path dependencies
If your project uses a local `path:` dependency that lives **outside** the project tree — for
example an absolute override:

```
dependency_overrides:
  super_editor:
    path: /Users/me/Projects/super_editor/super_editor
```

that directory isn't copied into the container, so the container's `pub get` couldn't find it.
`golden_runner` detects such dependencies (across `dependencies`, `dev_dependencies`, and
`dependency_overrides`, transitively and across pub-workspace members) and bind-mounts each one
**read-only into the container at its absolute path**, so an absolute `path:` resolves as-is. It
tells you what it mounted.

Note: this works for **absolute** path dependencies (and the relative path deps *within* those
external packages). A relative `path:` in your own project that points *above* the copied project
root isn't supported — use an absolute path, or widen `--path-to-project-root` to include it.

## Large projects and the build context
`golden_runner` copies your project into the Docker image to run tests. Without a `.dockerignore`,
the *entire* directory — including generated output like `build/` and `.dart_tool/`, plus `.git` —
is sent to Docker and copied into the image on every run, which can add many minutes to each build
(especially in a mono-repo).

To avoid this, when the build context is large (2 GiB or more) and has no `.dockerignore`,
`golden_runner` applies a sensible default Flutter/Dart `.dockerignore`, **for that build only**,
which reduces the amount of data that needs to be copied. The `.dockerignore`. file is written next 
to golden_runner's generated Dockerfile in a temp directory, so **no file is written into your 
project**. 

The default `.dockerignore` excludes generated output that the container regenerates anyway, and 
keeps all sources, `pubspec.yaml`/`pubspec.lock`, and test directories so a pub workspace still 
resolves.

`golden_runner` tells you when it applies the default, and it always **defers to a `.dockerignore` 
you already have** in the project. Add your own `.dockerignore` to fully control what's sent to 
Docker.

## Native build hooks
Some packages ship a Dart native-asset build hook (`hook/build.dart`) that compiles native code
during `flutter test` (via `package:native_toolchain_c`), which needs a C compiler in the container.

To support native asset compilation, `clang` must be added to the Docker image, but `clang` is
otherwise not required.

`golden_runner` detects whether any resolved package has such a hook (from
`.dart_tool/package_config.json`) and installs a C toolchain (`clang`, `build-essential`) in its
built-in image **only when needed**, so projects without native hooks get a lighter, faster image.
If it can't tell (e.g. no `.dart_tool/package_config.json`), it includes the toolchain to be safe.

## Clean golden failure artifacts
Golden failures produce a lot of new files, which are only needed while fixing/updating code.
It can be a big pain to delete all of these failure files strewn about a codebase.

`golden_runner` provides a `clean` command, which attempts to find and delete all such files.

By default, `goldens clean` deletes directories named `failures` under `test_goldens`.

```
# Delete failure directories under test_goldens.
goldens clean

# Delete failure directories under a specific directory.
goldens clean test_goldens/my_dir

# Preview what would be deleted.
goldens clean --dry-run

# Also delete loose Flutter golden failure PNG files.
goldens clean --loose-files

# Print every deleted directory and file.
goldens clean --verbose

# Print nothing.
goldens clean --silent
```

Loose failure files are deleted only when `--loose-files` is passed. The command uses a conservative
name allowlist: `*.masterImage.png`, `*.testImage.png`, `*.isolatedDiff.png`, `*.maskedDiff.png`,
and `failure_*.png`.

## A Hanging Command
Sometimes the golden runner hangs at "building image". It's not clear why this happens, or what
exactly can be done about it. However, to see the Docker image build process with log output, you can
run the image build directly.

Run the following command from your project directory:

    docker build -f [path_to]/golden_tester.Dockerfile -t golden_tester .

Note: The `golden_runner` package internally writes its Dockerfile to a temp directory and points
`docker build -f` at it (which also lets it attach a default `.dockerignore` without touching your
project). When running the Docker build directly, you'll need to provide that Dockerfile yourself,
either as a file or through stdin. Here's a Dockerfile that should work for you:

```
FROM ubuntu:latest

ENV FLUTTER_HOME=${HOME}/sdks/flutter 
ENV PATH ${PATH}:${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin

USER root

RUN apt update

# clang/build-essential are only needed if a package has a Dart native-asset build hook
# (package:native_toolchain_c); drop them for a lighter image if none of yours do. golden_runner's
# generated Dockerfile adds them only when needed, but this static reference always includes them.
RUN apt install -y git curl unzip clang build-essential

# Print the Ubuntu version. Useful when there are failing tests.
RUN cat /etc/lsb-release

# Invalidate the cache when flutter pushes a new commit.
ADD https://api.github.com/repos/flutter/flutter/git/refs/heads/stable ./flutter-latest-stable

RUN git clone https://github.com/flutter/flutter.git ${FLUTTER_HOME}

RUN flutter doctor

# Copy the whole repo, which makes it possible for one package to reference
# other packages within a mono-repo.
COPY ./ /golden_tester
```

This Dockerfile might fall out of date from time to time, if we change the version of it
inside the package. If it ever looks like the above Dockerfile is the problem, check inside
the package for the version that's used by default, and use that instead.

You can either save the above Dockerfile to a file, or you can paste it via stdin, beginning
with the following command:

    docker build -f - -t golden_tester .

One theory about this hanging command problem is that the process to download the Flutter engine
is taking a very long time. But we're not sure.
