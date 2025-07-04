import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:golden_runner/golden_runner.dart';

/// Entrypoint for the `golden_runner` CLI app, which is run at the command
/// line with the `goldens` keyword.
Future<void> main(List<String> arguments) async {
  if (arguments.contains("--verbose") || arguments.contains("-v")) {
    GrLog.initAllLogs();
  }

  try {
    await GoldensRunner().run(arguments);
  } on UsageException catch (e) {
    stdout.write(e);
  }
}
