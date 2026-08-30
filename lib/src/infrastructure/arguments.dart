String? parseArgumentOption(List<String> arguments, String name) {
  String? value;
  for (int i = arguments.length - 1; i >= 0; i -= 1) {
    if (arguments[i] == name) {
      if (value != null) {
        throw Exception("Multiple values found for parameter: $name");
      }

      if (i == arguments.length - 1 || _isLongArgumentName(arguments[i + 1])) {
        throw Exception("Missing value for parameter: $name");
      }

      value = arguments[i + 1];
      arguments.removeAt(i + 1);
      arguments.removeAt(i);
      continue;
    }

    if (arguments[i].contains("=")) {
      final pieces = arguments[i].split("=");
      if (pieces.length != 2) {
        continue;
      }

      final key = pieces.first;
      if (key.trim() != name) {
        continue;
      }

      value = pieces.last;
      arguments.removeAt(i);
      continue;
    }
  }

  return value;
}

/// Returns `true` if the boolean flag [name] is present in [arguments], removing
/// every occurrence of it from the list.
bool parseArgumentFlag(List<String> arguments, String name) {
  final lengthBefore = arguments.length;
  arguments.removeWhere((argument) => argument == name);
  return arguments.length != lengthBefore;
}

/// Returns `true` if any of [names] is present in [arguments], WITHOUT removing
/// them (so they can still be forwarded, e.g. to `flutter test`).
bool hasArgumentFlag(List<String> arguments, List<String> names) {
  return arguments.any(names.contains);
}

bool _isLongArgumentName(String argument) {
  return argument.startsWith("--") && argument.length > "--".length;
}
