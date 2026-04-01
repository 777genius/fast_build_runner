class FastWatchAlphaRequest {
  final String repoRoot;
  final String fixtureTemplatePath;
  final String workDirectoryPath;
  final bool keepRunDirectory;
  final String? mutationProfilePath;
  final bool mutateBuildScriptBeforeIncremental;
  final bool simulateDroppedSourceUpdateOnIncremental;
  final String sourceEngine;
  final int incrementalCycles;
  final int noiseFilesPerCycle;
  final bool continuousScheduling;
  final int extraFixtureModels;
  final int settleBuildDelayMs;
  final bool trustBuildScriptFreshness;

  const FastWatchAlphaRequest({
    required this.repoRoot,
    required this.fixtureTemplatePath,
    required this.workDirectoryPath,
    required this.keepRunDirectory,
    this.mutationProfilePath,
    this.mutateBuildScriptBeforeIncremental = false,
    this.simulateDroppedSourceUpdateOnIncremental = false,
    this.sourceEngine = 'dart',
    this.incrementalCycles = 1,
    this.noiseFilesPerCycle = 0,
    this.continuousScheduling = false,
    this.extraFixtureModels = 0,
    this.settleBuildDelayMs = 0,
    this.trustBuildScriptFreshness = true,
  });
}
