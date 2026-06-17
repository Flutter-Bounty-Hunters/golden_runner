import 'package:golden_runner/golden_runner.dart';
import 'package:path/path.dart' as path;

class FakeGoldensCommandEnvironment extends GoldensCommandEnvironment {
  FakeGoldensCommandEnvironment({
    required this.currentDirectoryPath,
    Set<String> directories = const {},
    Set<String> files = const {},
  })  : _directories = directories.map((directory) => path.normalize(directory)).toSet(),
        _files = files.map((file) => path.normalize(file)).toSet();

  @override
  final String currentDirectoryPath;

  final Set<String> _directories;
  final Set<String> _files;

  @override
  bool directoryExists(String directoryPath) {
    return _directories.contains(_absolutePath(directoryPath));
  }

  @override
  bool fileExists(String filePath) {
    return _files.contains(_absolutePath(filePath));
  }

  String _absolutePath(String filePath) {
    return path.normalize(
      path.isAbsolute(filePath) //
          ? filePath
          : path.join(currentDirectoryPath, filePath),
    );
  }
}
