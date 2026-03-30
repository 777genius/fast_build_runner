// ignore_for_file: implementation_imports

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
}
