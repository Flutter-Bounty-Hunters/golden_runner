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

bool _isLongArgumentName(String argument) {
  return argument.startsWith("--") && argument.length > "--".length;
}
