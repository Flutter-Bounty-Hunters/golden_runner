import 'dart:async';

abstract interface class Command {
  void parseArguments(List<String> arguments);

  FutureOr<void> run();
}
