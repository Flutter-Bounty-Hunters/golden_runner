import 'package:golden_runner/golden_runner.dart';
import 'package:test/scaffolding.dart';

void main() {
  group("Docker >", () {
    test("is installed", () async {
      await Docker.instance.isInstalled();
    });

    test("is running", () async {
      await Docker.instance.isRunning();
    });
  });
}
