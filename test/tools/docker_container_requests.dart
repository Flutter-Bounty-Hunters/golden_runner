import 'package:collection/collection.dart';
import 'package:golden_runner/golden_runner.dart';
import 'package:test/test.dart';

Matcher equalsDockerContainerRequest(RunDockerContainerRequest expected) {
  return _RunDockerContainerRequestMatcher(expected);
}

class _RunDockerContainerRequestMatcher extends Matcher {
  const _RunDockerContainerRequestMatcher(this._expected);

  final RunDockerContainerRequest _expected;

  @override
  Description describe(Description description) {
    return description.add("RunDockerContainerRequest equal to ${_requestSummary(_expected)}");
  }

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    if (item is! RunDockerContainerRequest) {
      matchState["type"] = item.runtimeType;
      return false;
    }

    final mismatches = <String>[];
    _addMismatch(
      mismatches,
      "dockerFilePath",
      _expected.dockerFilePath,
      item.dockerFilePath,
    );
    _addMismatch(
      mismatches,
      "dockerImageName",
      _expected.dockerImageName,
      item.dockerImageName,
    );
    _addMismatch(
      mismatches,
      "dockerVerbosity",
      _expected.dockerVerbosity,
      item.dockerVerbosity,
    );
    _addMismatch(
      mismatches,
      "mountPaths",
      _sorted(_expected.mountPaths),
      _sorted(item.mountPaths),
    );
    _addMismatch(
      mismatches,
      "pathToProjectRoot",
      _expected.pathToProjectRoot,
      item.pathToProjectRoot,
    );
    _addMismatch(
      mismatches,
      "containerWorkingDirectory",
      _expected.containerWorkingDirectory,
      item.containerWorkingDirectory,
    );
    _addMismatch(
      mismatches,
      "command",
      _expected.command,
      item.command,
    );

    if (mismatches.isEmpty) {
      return true;
    }

    matchState["mismatches"] = mismatches;
    return false;
  }

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    if (item is! RunDockerContainerRequest) {
      return mismatchDescription.add(
        "is ${matchState["type"]}, not a RunDockerContainerRequest",
      );
    }

    final mismatches = matchState["mismatches"] as List<String>? ?? const [];
    if (mismatches.isEmpty) {
      return mismatchDescription.add("does not match");
    }

    return mismatchDescription.add(mismatches.join("; "));
  }
}

void _addMismatch(
  List<String> mismatches,
  String fieldName,
  Object? expected,
  Object? actual,
) {
  if (_valuesEqual(expected, actual)) {
    return;
  }

  mismatches.add(
    "$fieldName expected ${_formatValue(expected)} but was ${_formatValue(actual)}",
  );
}

bool _valuesEqual(Object? expected, Object? actual) {
  if (expected is Iterable && actual is Iterable) {
    return const IterableEquality().equals(expected, actual);
  }

  return expected == actual;
}

List<String> _sorted(Set<String> values) {
  return values.toList()..sort();
}

String _requestSummary(RunDockerContainerRequest request) {
  return "{"
      "dockerFilePath: ${_formatValue(request.dockerFilePath)}, "
      "dockerImageName: ${_formatValue(request.dockerImageName)}, "
      "dockerVerbosity: ${request.dockerVerbosity}, "
      "mountPaths: ${_formatValue(_sorted(request.mountPaths))}, "
      "pathToProjectRoot: ${_formatValue(request.pathToProjectRoot)}, "
      "containerWorkingDirectory: ${_formatValue(request.containerWorkingDirectory)}, "
      "command: ${_formatValue(request.command)}"
      "}";
}

String _formatValue(Object? value) {
  if (value is String) {
    return '"$value"';
  }

  if (value is Iterable) {
    return "[${value.map(_formatValue).join(", ")}]";
  }

  return "$value";
}
