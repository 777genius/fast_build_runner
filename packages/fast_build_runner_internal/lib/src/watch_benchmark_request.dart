class FastWatchBenchmarkRequest {
  final String repoRoot;
  final String fixtureTemplatePath;
  final String workDirectoryPath;
  final bool keepRunDirectory;
  final int incrementalCycles;
  final int repeats;
  final int noiseFilesPerCycle;
  final bool continuousScheduling;
  final int extraFixtureModels;
  final int settleBuildDelayMs;
  final bool trustBuildScriptFreshness;

  const FastWatchBenchmarkRequest({
    required this.repoRoot,
    required this.fixtureTemplatePath,
    required this.workDirectoryPath,
    required this.keepRunDirectory,
    this.incrementalCycles = 1,
    this.repeats = 1,
    this.noiseFilesPerCycle = 0,
    this.continuousScheduling = false,
    this.extraFixtureModels = 0,
    this.settleBuildDelayMs = 0,
    this.trustBuildScriptFreshness = false,
  });
}
