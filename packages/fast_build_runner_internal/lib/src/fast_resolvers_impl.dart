import 'dart:async';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/src/dart/analysis/analysis_options.dart';
import 'package:analyzer/src/dart/analysis/experiments.dart';
import 'package:build/build.dart';
import 'package:build/experiments.dart';
import 'package:package_config/package_config.dart';
import 'package:pool/pool.dart';

import 'package:build_runner/src/bootstrap/build_process_state.dart';
import 'package:build_runner/src/build/asset_graph/graph.dart';
import 'package:build_runner/src/build/build_step_impl.dart';
import 'package:build_runner/src/build/library_cycle_graph/phased_asset_deps.dart';
import 'package:build_runner/src/build/resolver/analysis_driver.dart';
import 'package:build_runner/src/build/resolver/analysis_driver_model.dart';
import 'package:build_runner/src/build/resolver/build_resolver.dart';
import 'package:build_runner/src/build/resolver/sdk_summary.dart';
import 'package:build_runner/src/logging/build_log.dart';

import 'fast_build_step_resolver.dart';

/// Narrow fork of upstream [ResolversImpl] that swaps in
/// [FastBuildStepResolver] for per-action resolver caching.
class FastResolversImpl implements Resolvers {
  final _initializationPool = Pool(1);
  final _driverPool = Pool(1);
  final _sharedResolveSyncCache = <String, Future<void>>{};

  BuildResolver? _buildResolver;
  AnalysisDriverModel _analysisDriverModel;
  PackageConfig? _packageConfig;

  factory FastResolversImpl.custom({
    PackageConfig? packageConfig,
    AnalysisDriverModel? analysisDriverModel,
  }) => FastResolversImpl(
    packageConfig: packageConfig,
    analysisDriverModel: analysisDriverModel ?? AnalysisDriverModel(),
  );

  FastResolversImpl({
    PackageConfig? packageConfig,
    required AnalysisDriverModel analysisDriverModel,
  }) : _packageConfig = packageConfig,
       _analysisDriverModel = analysisDriverModel;

  @override
  Future<FastBuildStepResolver> get(BuildStep buildStep) async {
    await _initializationPool.withResource(() async {
      if (_buildResolver != null) return;
      _warnOnLanguageVersionMismatch();
      final loadedConfig = _packageConfig ??= await loadPackageConfigUri(
        Uri.parse(buildProcessState.packageConfigUri),
      );
      final driver = analysisDriver(
        _analysisDriverModel,
        AnalysisOptionsImpl()
          ..contextFeatures = _featureSet(
            enableExperiments: enabledExperiments,
          ),
        await defaultSdkSummaryGenerator(),
        loadedConfig,
      );

      _buildResolver = BuildResolver(driver, _driverPool, _analysisDriverModel);
    });

    return FastBuildStepResolver(
      _buildResolver!,
      buildStep as BuildStepImpl,
      sharedResolveSyncCache: _sharedResolveSyncCache,
    );
  }

  Future<void> takeLockAndStartBuild(AssetGraph assetGraph) {
    _sharedResolveSyncCache.clear();
    return _analysisDriverModel.takeLockAndStartBuild(assetGraph);
  }

  PhasedAssetDeps phasedAssetDeps() => _analysisDriverModel.phasedAssetDeps();

  @override
  void reset() {
    _sharedResolveSyncCache.clear();
    _analysisDriverModel.endBuildAndUnlock();
  }
}

void _warnOnLanguageVersionMismatch() async {
  if (sdkLanguageVersion <= ExperimentStatus.currentVersion) return;

  final upgradeCommand = isFlutter
      ? 'flutter packages upgrade'
      : 'dart pub upgrade';
  buildLog.warning(
    'SDK language version $sdkLanguageVersion is newer than `analyzer` '
    'language version ${ExperimentStatus.currentVersion}. '
    'Run `$upgradeCommand`.',
  );
}

FeatureSet _featureSet({List<String> enableExperiments = const []}) {
  if (enableExperiments.isNotEmpty &&
      sdkLanguageVersion > ExperimentStatus.currentVersion) {
    buildLog.warning('''
Attempting to enable experiments `$enableExperiments`, but the current SDK
language version does not match your `analyzer` package language version:

Analyzer language version: ${ExperimentStatus.currentVersion}
SDK language version: $sdkLanguageVersion

In order to use experiments you may need to upgrade or downgrade your
`analyzer` package dependency such that its language version matches that of
your current SDK, see https://github.com/dart-lang/build/issues/2685.

Note that you may or may not have a direct dependency on the `analyzer`
package in your `pubspec.yaml`, so you may have to add that. You can see your
current version by running `pub deps`.
''');
  }
  return FeatureSet.fromEnableFlags2(
    sdkLanguageVersion: sdkLanguageVersion,
    flags: enableExperiments,
  );
}
