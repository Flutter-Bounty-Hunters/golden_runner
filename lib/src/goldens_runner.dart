import 'package:golden_runner/src/commands/clean.dart';
import 'package:golden_runner/src/commands/command_base.dart';
import 'package:golden_runner/src/commands/test.dart';
import 'package:golden_runner/src/commands/update.dart';
import 'package:golden_runner/src/infrastructure/logging.dart';

/// Runs golden tests or golden updates, based on the given CLI [arguments].
class GoldensRunner {
  Future<void> run(List<String> arguments) async {
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
    command.parseArguments(arguments);

    // Run the command, now that the arguments have been parsed.
    GrLog.commands.fine("Running the command");
    await command.run();
  }
}
