import 'package:golden_runner/src/commands/command_base_goldens.dart';

/// Command that updates Flutter Golden images.
class UpdateGoldensCommand extends GoldensCommand {
  UpdateGoldensCommand({
    super.environment,
  });

  @override
  List<String> get command => [
        'flutter',
        'test',
        '--update-goldens',
        ...testCommandArguments,
      ];
}
