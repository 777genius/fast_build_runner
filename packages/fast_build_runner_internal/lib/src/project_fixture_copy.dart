import 'dart:io';

import 'package:path/path.dart' as p;

final Set<String> _transientFixturePathSegments = {
  '.dart_tool',
  '.git',
  '.gradle',
  '.idea',
  '.symlinks',
  '.vscode',
  'Pods',
  'build',
  'node_modules',
};

Future<void> copyProjectFixture(Directory source, Directory destination) async {
  await _copyDirectory(
    sourceRoot: source,
    source: source,
    destination: destination,
  );
}

Future<void> _copyDirectory({
  required Directory sourceRoot,
  required Directory source,
  required Directory destination,
}) async {
  await for (final entity in source.list(recursive: false)) {
    final relativePath = p.relative(entity.path, from: sourceRoot.path);
    if (_shouldSkipFixtureRelativePath(relativePath)) {
      continue;
    }

    final targetPath = p.join(destination.path, p.basename(entity.path));
    if (entity is Directory) {
      final targetDirectory = Directory(targetPath)..createSync(recursive: true);
      await _copyDirectory(
        sourceRoot: sourceRoot,
        source: entity,
        destination: targetDirectory,
      );
    } else if (entity is File) {
      await entity.copy(targetPath);
    }
  }
}

bool _shouldSkipFixtureRelativePath(String relativePath) {
  final normalized = p.normalize(relativePath);
  if (normalized == '.' || normalized.isEmpty) return false;

  for (final segment in p.split(normalized)) {
    if (_transientFixturePathSegments.contains(segment)) {
      return true;
    }
  }
  return false;
}
