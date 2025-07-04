# Golden Runner
CLI app that runs golden tests within an Ubuntu Docker container, to help reduce flakiness.

In short, this CLI app replaces the following Flutter commands...

    flutter test

    flutter test --update-goldens

with the following...

    goldens test

    goldens update

The purpose of the `goldens` command is to run your golden tests in an environment that can
reasonably be replicated between local developers and CI systems. Generally speaking, the
only environment that can be freely configured and simulated across every other platform is
Linux. More specifically, if we factor in the importance of GitHub Runners, that platform
is Ubuntu. Therefore, the `goldens` command builds and runs an Ubuntu image, and within that
image it runs golden tests.

When a developer on your team creates, updates, or compares goldens, that developer should
use the `goldens` command locally. This way, whether your developer is running Mac, Windows,
or Linux, the goldens will be painted as if they're running on Ubuntu.

Then, in CI, run your golden tests on an Ubuntu runner.

This approach isn't perfect. Sometimes there are still mismatches between the goldens painted
by the Ubuntu Docker container vs the goldens painted by the GitHub Ubuntu runner. However, we've
found that this approach greatly reduces such mismatches.

## Activate the package:
To use the `goldens` command, you must first activate the `golden_runner` package.

Activate from Pub:

    dart pub global activate golden_runner

Activate from local source:

    dart pub global activate --source path ./golden_runner


## Run golden tests:
The `goldens` command must be run from the directory of the app/package under test.

```
# Run all tests.
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
# Update all goldens.
goldens update

# Update all goldens in a directory.
goldens update test_goldens/my_dir

# Update goldens with a given test name.
goldens update --plain-name="something"

# Update select goldens in a directory.
goldens update --plain-name "something" test_goldens/my_dir
```

## A Hanging Command
Sometimes the golden runner hangs at "building image". It's not clear why this happens, or what
exactly can be done about it. However, to see the Docker image build process with log output, you can
run the image build directly.

Run the following command from your project directory:

    docker build -f [path_to]/golden_tester.Dockerfile -t golden_tester .

One theory about this hanging command problem is that the process to download the Flutter engine
is taking a very long time. But we're not sure.