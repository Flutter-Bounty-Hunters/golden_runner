import 'dart:io';

import 'package:golden_runner/src/commands/command_base.dart';
import 'package:golden_runner/src/infrastructure/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

/// Command that finds and deletes golden failure directories (and maybe loose files).
///
/// Typically:
///
///     goldens clean my_test_dir
///
/// Arguments:
///  - `[path]`: The directory to search for failure files and directories to delete. Defaults to `test_goldens`.
///  - `--loose-files`: Also deletes loose PNG files with names that match Flutter golden failure
///     artifacts: `*.masterImage.png`, `*.testImage.png`, `*.isolatedDiff.png`, `*.maskedDiff.png`, and `failure_*.png`.
///  - `--dry-run`: Prints what would be deleted without deleting anything.
///  - `--silent`: Prints nothing. Cannot be combined with `--dry-run` or `--verbose`.
///  - `--verbose`, `-v`: Prints every deleted directory and file.
///
/// [commandOutput] is where command text output goes. Defaults to `stdout`.
class CleanCommand implements Command {
  CleanCommand([this._commandOutput]);

  final StringSink? _commandOutput;

  CleanRequest get request => _request!;
  CleanRequest? _request;

  @override
  void parseArguments(List<String> arguments) {
    _request = parseCleanCommandArguments(arguments);
  }

  @override
  Future<CleanResult> run() async {
    return await _cleanGoldenFailures(
      request,
      commandOutput: _commandOutput ?? stdout,
    );
  }
}

@visibleForTesting
CleanRequest parseCleanCommandArguments(List<String> arguments) {
  GrLog.commands.fine("Parsing clean command arguments: $arguments");

  var includeLooseFiles = false;
  var dryRun = false;
  var silent = false;
  var verbose = false;
  final positionalArguments = <String>[];

  for (final argument in arguments) {
    switch (argument) {
      case "--loose-files":
        includeLooseFiles = true;
      case "--dry-run":
        dryRun = true;
      case "--silent":
        silent = true;
      case _argVerbose:
      case _argVerboseShort:
        verbose = true;
      default:
        if (argument.startsWith("-")) {
          throw Exception("Unknown clean option: $argument");
        }

        positionalArguments.add(argument);
    }
  }

  if (positionalArguments.length > 1) {
    throw Exception(
      "Expected at most one clean target path, but found: ${positionalArguments.join(", ")}",
    );
  }

  if (silent && verbose) {
    throw Exception("Cannot use --silent with --verbose.");
  }

  if (silent && dryRun) {
    throw Exception(
      "Cannot use --silent with --dry-run. Dry run is intended as a print-only behavior.",
    );
  }

  return CleanRequest(
    targetPath: positionalArguments.isEmpty ? _defaultCleanTargetPath : positionalArguments.single,
    includeLooseFiles: includeLooseFiles,
    dryRun: dryRun,
    silent: silent,
    verbose: verbose,
  );
}

const _defaultCleanTargetPath = "test_goldens";
const _argVerbose = "--verbose";
const _argVerboseShort = "-v";

Future<CleanResult> _cleanGoldenFailures(
  CleanRequest request, {
  required StringSink commandOutput,
}) async {
  final targetType = FileSystemEntity.typeSync(
    request.targetPath,
    followLinks: false,
  );
  if (targetType == FileSystemEntityType.notFound) {
    throw Exception("No such directory to clean failures: ${request.targetPath}");
  }

  if (targetType == FileSystemEntityType.link) {
    throw Exception("Can't clean symlinks: ${request.targetPath}");
  }

  final targetDirectory = targetType == FileSystemEntityType.file //
      ? Directory(path.dirname(request.targetPath))
      : Directory(request.targetPath);

  final failureDirectories = <Directory>[
    if (path.basename(targetDirectory.path) == "failures") //
      targetDirectory,
  ];
  final looseFailureFiles = <File>[];

  await for (final entity in targetDirectory.list(
    recursive: true,
    followLinks: false,
  )) {
    final entityType = await FileSystemEntity.type(
      entity.path,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.directory && path.basename(entity.path) == "failures") {
      failureDirectories.add(Directory(entity.path));
      continue;
    }

    if (request.includeLooseFiles && entityType == FileSystemEntityType.file && _isLooseFailureFile(entity.path)) {
      looseFailureFiles.add(File(entity.path));
    }
  }

  final failureDirectoriesWithoutDuplicateSubDirectories = _removeDuplicateDirectorySubTrees(
    failureDirectories,
  );
  final looseFilesOutsideFailureDirectories = looseFailureFiles
      .where(
        (file) => !_isWithinAnyDirectory(
          file.path,
          failureDirectoriesWithoutDuplicateSubDirectories.map((directory) => directory.path),
        ),
      )
      .toList();

  if (request.verbose && request.dryRun) {
    for (final directory in failureDirectoriesWithoutDuplicateSubDirectories) {
      commandOutput.writeln(
        "Would delete directory: ${path.relative(directory.path)}",
      );
    }

    for (final file in looseFilesOutsideFailureDirectories) {
      commandOutput.writeln("Would delete file: ${path.relative(file.path)}");
    }
  }

  if (!request.dryRun) {
    for (final directory in failureDirectoriesWithoutDuplicateSubDirectories) {
      await directory.delete(recursive: true);
      if (request.verbose) {
        commandOutput.writeln(
          "Deleted directory: ${path.relative(directory.path)}",
        );
      }
    }

    for (final file in looseFilesOutsideFailureDirectories) {
      await file.delete();
      if (request.verbose) {
        commandOutput.writeln("Deleted file: ${path.relative(file.path)}");
      }
    }
  }

  final result = CleanResult(
    deletedFailureDirectoryCount: failureDirectoriesWithoutDuplicateSubDirectories.length,
    deletedLooseFailureFileCount: looseFilesOutsideFailureDirectories.length,
    dryRun: request.dryRun,
  );

  if (!request.silent) {
    commandOutput.writeln(result.summary);
  }

  return result;
}

bool _isLooseFailureFile(String filePath) {
  final filename = path.basename(filePath);
  return filename.endsWith(".masterImage.png") ||
      filename.endsWith(".testImage.png") ||
      filename.endsWith(".isolatedDiff.png") ||
      filename.endsWith(".maskedDiff.png") ||
      (filename.startsWith("failure_") && filename.endsWith(".png"));
}

/// Given a list of [directories], this method looks for directories that sit beneath other directories, and
/// removes those sub-directories from the list, and then returns it.
///
/// Example:
///
///     Given:
///     /test/failures/
///     /test/failures/something/failures/
///
///     Returns:
///     /test/failures/
List<Directory> _removeDuplicateDirectorySubTrees(List<Directory> directories) {
  final sortedDirectories = [...directories]..sort(
      (a, b) => path.split(a.path).length.compareTo(path.split(b.path).length),
    );

  final directoriesWithoutDuplicateSubDirectories = <Directory>[];
  for (final directory in sortedDirectories) {
    if (!_isWithinAnyDirectory(
      directory.path,
      directoriesWithoutDuplicateSubDirectories.map((directory) => directory.path),
    )) {
      directoriesWithoutDuplicateSubDirectories.add(directory);
    }
  }

  return directoriesWithoutDuplicateSubDirectories;
}

bool _isWithinAnyDirectory(String childPath, Iterable<String> parentPaths) {
  final canonicalChildPath = path.canonicalize(childPath);
  for (final parentPath in parentPaths) {
    final canonicalParentPath = path.canonicalize(parentPath);
    if (path.equals(canonicalChildPath, canonicalParentPath)) {
      continue;
    }

    if (path.isWithin(canonicalParentPath, canonicalChildPath)) {
      return true;
    }
  }

  return false;
}

@visibleForTesting
class CleanRequest {
  const CleanRequest({
    required this.targetPath,
    required this.includeLooseFiles,
    required this.dryRun,
    required this.silent,
    required this.verbose,
  });

  /// The file or directory that scopes the cleanup.
  ///
  /// Directory targets are searched directly. File targets scope cleanup to
  /// the file's parent directory.
  final String targetPath;

  /// Whether to delete loose PNG files that match Flutter golden failure names.
  final bool includeLooseFiles;

  /// Whether to print what would be deleted without deleting anything.
  final bool dryRun;

  /// Whether to suppress command output.
  final bool silent;

  /// Whether to print each deleted path.
  final bool verbose;
}

class CleanResult {
  const CleanResult({
    required this.deletedFailureDirectoryCount,
    required this.deletedLooseFailureFileCount,
    required this.dryRun,
  });

  final int deletedFailureDirectoryCount;
  final int deletedLooseFailureFileCount;
  final bool dryRun;

  String get summary {
    if (deletedFailureDirectoryCount == 0 && deletedLooseFailureFileCount == 0) {
      return dryRun ? "No golden failure artifacts would be deleted." : "No golden failure artifacts found.";
    }

    final prefix = dryRun ? "Would delete" : "Deleted";
    return "$prefix ${_pluralize(deletedFailureDirectoryCount, "failure directory", "failure directories")} "
        "and ${_pluralize(deletedLooseFailureFileCount, "loose failure file", "loose failure files")}.";
  }

  String _pluralize(int count, String singular, String plural) {
    return "$count ${count == 1 ? singular : plural}";
  }
}
