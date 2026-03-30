// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:build_runner/src/bootstrap/aot_compiler.dart';
import 'package:build_runner/src/bootstrap/bootstrapper.dart';
import 'package:build_runner/src/bootstrap/compiler.dart';
import 'package:build_runner/src/bootstrap/depfile.dart';
import 'package:build_runner/src/bootstrap/kernel_compiler.dart';

class FastBootstrapper extends Bootstrapper {
  final Compiler _compiler;

  FastBootstrapper({required super.workspace, required super.compileAot})
    : _compiler = compileAot ? AotCompiler() : KernelCompiler();

  String get entrypointExecutablePath =>
      compileAot ? entrypointAotPath : entrypointDillPath;

  String get _depfilePath =>
      compileAot ? entrypointAotDepfilePath : entrypointDillDepfilePath;

  Future<CompileResult> ensureCompiled({Iterable<String>? experiments}) async {
    final freshness = _compiler.checkFreshness(digestsAreFresh: false);
    if (freshness.outputIsFresh) {
      return CompileResult(messages: null);
    }
    return _compiler.compile(experiments: experiments);
  }

  @override
  Future<FreshnessResult> checkCompileFreshness({
    required bool digestsAreFresh,
  }) async {
    if (digestsAreFresh) {
      final maybeResult = _compiler.checkFreshness(digestsAreFresh: true);
      if (maybeResult.outputIsFresh) return maybeResult;
    }
    return _compiler.checkFreshness(digestsAreFresh: false);
  }

  @override
  bool isCompileDependency(String path) => _compiler.isDependency(path);

  Set<String> readCompileDependencyPaths() {
    final depfile = File(_depfilePath);
    if (!depfile.existsSync()) {
      return const <String>{};
    }
    return _parseDepfile(depfile.readAsStringSync());
  }

  Set<String> compileDependencyPathsWithinRoot(String rootPath) {
    final root = Directory(rootPath).absolute.path;
    final paths = <String>{};
    for (final dependencyPath in readCompileDependencyPaths()) {
      final absolutePath = File(dependencyPath).absolute.path;
      if (absolutePath == root ||
          absolutePath.startsWith('$root${Platform.pathSeparator}')) {
        paths.add(absolutePath);
      }
    }
    return paths;
  }

  Set<String> _parseDepfile(String deps) {
    final items = deps
        .replaceAll(r'\ ', '\u0000')
        .replaceAll(r'\\', r'\')
        .split(' ');

    final result = <String>{};
    for (var i = 1; i != items.length; ++i) {
      final item = items[i];
      final path = item.replaceAll('\u0000', ' ');
      result.add(
        i == items.length - 1 ? path.substring(0, path.length - 1) : path,
      );
    }
    return result;
  }
}
