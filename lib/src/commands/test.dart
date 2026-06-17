import 'package:golden_runner/src/commands/command_base_goldens.dart';

/// Command that runs Flutter Golden tests, comparing new test output to existing Golden files.
///
/// Failure scene images are generated for Golden mismatches, as per usual Flutter Golden behavior.
class TestGoldensCommand extends GoldensCommand {
  TestGoldensCommand({
    super.environment,
  });

  @override
  List<String> get command => [
        'flutter',
        'test',
        ...testCommandArguments,
      ];
}
