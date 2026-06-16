import 'dart:async';

import 'package:meta/meta.dart';

abstract interface class Command {
  @mustCallSuper
  void parseArguments(List<String> arguments);

  FutureOr<void> run();
}
