import 'dart:io';

import 'package:fast_build_runner_internal/fast_build_runner_internal.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'real app generated outputs match upstream for dart source engine',
    () async {
      final realAppPath =
          Platform.environment['FAST_BUILD_RUNNER_REAL_APP_PATH'];
      if (realAppPath == null || realAppPath.isEmpty) {
        stderr.writeln(
          'Skipping real app compatibility test: FAST_BUILD_RUNNER_REAL_APP_PATH is not set.',
        );
        return;
      }

      final fixtureDirectory = Directory(realAppPath);
      if (!fixtureDirectory.existsSync()) {
        stderr.writeln(
          'Skipping real app compatibility test: fixture missing at $realAppPath.',
        );
        return;
      }

      final repoRoot = Directory.current.path;
      final baseWorkDir = Directory(
        p.join(repoRoot, '.dart_tool', 'test_wah_output_compatibility'),
      );
      if (baseWorkDir.existsSync()) {
        await baseWorkDir.delete(recursive: true);
      }
      await baseWorkDir.create(recursive: true);

      Future<FastWatchAlphaResult> runForEngine(String engine) {
        return FastWatchAlphaRunner().run(
          FastWatchAlphaRequest(
            repoRoot: repoRoot,
            fixtureTemplatePath: realAppPath,
            workDirectoryPath: p.join(baseWorkDir.path, engine),
            keepRunDirectory: true,
            mutationProfilePath: p.join(
              repoRoot,
              'profiles',
              'real_app',
              'analytics_service_injection.json',
            ),
            sourceEngine: engine,
          ),
        );
      }

      final upstreamResult = await runForEngine('upstream');
      final dartResult = await runForEngine('dart');

      addTearDown(() async {
        if (baseWorkDir.existsSync()) {
          await baseWorkDir.delete(recursive: true);
        }
      });

      expect(upstreamResult.status, 'success');
      expect(dartResult.status, 'success');

      final upstreamDir = Directory(upstreamResult.runDirectory);
      final dartDir = Directory(dartResult.runDirectory);
      expect(upstreamDir.existsSync(), isTrue);
      expect(dartDir.existsSync(), isTrue);

      final generatedFiles = <String>{
        ...await _collectGeneratedFiles(upstreamDir),
        ...await _collectGeneratedFiles(dartDir),
      }.toList()..sort();

      expect(
        generatedFiles.length,
        greaterThan(50),
        reason: 'Expected a meaningful generated surface for the real app.',
      );

      final diffs = <String>[];
      for (final relativePath in generatedFiles) {
        final upstreamFile = File(p.join(upstreamDir.path, relativePath));
        final dartFile = File(p.join(dartDir.path, relativePath));
        if (!upstreamFile.existsSync() || !dartFile.existsSync()) {
          diffs.add(relativePath);
          continue;
        }
        if (!_listsEqual(
          upstreamFile.readAsBytesSync(),
          dartFile.readAsBytesSync(),
        )) {
          diffs.add(relativePath);
        }
      }

      expect(diffs, isEmpty, reason: 'Generated outputs diverged: $diffs');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<List<String>> _collectGeneratedFiles(Directory root) async {
  const suffixes = [
    '.g.dart',
    '.freezed.dart',
    '.config.dart',
    '.gr.dart',
    '.mocks.dart',
  ];

  final files = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final relativePath = p.relative(entity.path, from: root.path);
    if (relativePath.startsWith('.dart_tool${p.separator}') ||
        relativePath == 'pubspec.lock') {
      continue;
    }
    if (suffixes.any(relativePath.endsWith)) {
      files.add(relativePath);
    }
  }
  return files;
}

bool _listsEqual(List<int> a, List<int> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
