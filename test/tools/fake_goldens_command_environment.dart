import 'package:golden_runner/golden_runner.dart';
import 'package:path/path.dart' as path;

class FakeGoldensCommandEnvironment extends GoldensCommandEnvironment {
  FakeGoldensCommandEnvironment({
    required this.currentDirectoryPath,
    Set<String> directories = const {},
    Set<String> files = const {},
    Map<String, String> fileContents = const {},
  })  : _directories = directories.map((directory) => path.normalize(directory)).toSet(),
        _files = files.map((file) => path.normalize(file)).toSet(),
        _fileContents = fileContents.map(
          (file, contents) => MapEntry(path.normalize(file), contents),
        );

  @override
  final String currentDirectoryPath;

  final Set<String> _directories;
  final Set<String> _files;
  final Map<String, String> _fileContents;

  @override
  bool directoryExists(String directoryPath) {
    return _directories.contains(_absolutePath(directoryPath));
  }

  @override
  bool fileExists(String filePath) {
    final absolutePath = _absolutePath(filePath);
    return _files.contains(absolutePath) || _fileContents.containsKey(absolutePath);
  }

  @override
  String? readFileAsString(String filePath) {
    return _fileContents[_absolutePath(filePath)];
  }

  String _absolutePath(String filePath) {
    return path.normalize(
      path.isAbsolute(filePath) //
          ? filePath
          : path.join(currentDirectoryPath, filePath),
    );
  }
}
