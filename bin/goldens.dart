import 'dart:io';

import 'package:args/command_runner.dart' show UsageException;
import 'package:golden_runner/golden_runner.dart';

/// Entrypoint for the `golden_runner` CLI app, which is run at the command
/// line with the `goldens` keyword.
Future<void> main(List<String> arguments) async {
  if (arguments.contains("--verbose") || arguments.contains("-v")) {
    GrLog.initAllLogs();
  }

  try {
    GrLog.commands.info("Goldens runner, running with arguments: $arguments");

    if (arguments.isEmpty) {
      throw Exception("Not enough arguments: '${arguments.join(" ")}'");
    }

    final commandName = arguments.first;
    late final Command command;
    switch (commandName) {
      case "test":
        GrLog.commands.fine("Running golden test comparisons");
        command = TestGoldensCommand();
      case "update":
        GrLog.commands.fine("Updating goldens");
        command = UpdateGoldensCommand();
      case "clean":
        GrLog.commands.fine("Cleaning golden failure artifacts");
        command = CleanCommand();
      default:
        throw Exception("Unknown command: ${arguments.first}");
    }

    // Parse the incoming arguments.
    GrLog.commands.fine("Parsing command arguments");
    command.parseArguments(arguments.sublist(1));

    // Run the command, now that the arguments have been parsed.
    GrLog.commands.fine("Running the command");
    await command.run();
  } on UsageException catch (e) {
    stdout.write(e);
  }
}
