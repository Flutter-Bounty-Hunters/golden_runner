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

## Activate the package:
To use the `goldens` command, you must first activate the `golden_runner` package.

Activate from Pub:

    dart pub global activate golden_runner

Or, activate from local source:

    # From outside the `golden_runner` directory:
    dart pub global activate --source path ./golden_runner

    # From within the `golden_runner` directory:
    dart pub global activate --source path .

## Run golden tests:
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

## Update golden files:
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

## Clean golden failure artifacts:
The `goldens` command must be run from the directory of the app/package under test.

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

Note: The `golden_runner` package internally sends a Dockerfile to Docker over stdin. When running the
Docker build directly, you'll need to provide that Dockerfile, either as a file, or through stdin. Here's
a Dockerfile that should work for you:

```
FROM ubuntu:latest

ENV FLUTTER_HOME=${HOME}/sdks/flutter 
ENV PATH ${PATH}:${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin

USER root

RUN apt update

RUN apt install -y git curl unzip

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
