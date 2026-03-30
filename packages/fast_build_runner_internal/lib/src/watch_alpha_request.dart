class FastWatchAlphaRequest {
  final String repoRoot;
  final String fixtureTemplatePath;
  final String workDirectoryPath;
  final bool keepRunDirectory;
  final bool mutateBuildScriptBeforeIncremental;
  final bool simulateDroppedSourceUpdateOnIncremental;
  final String sourceEngine;
  final int incrementalCycles;

  const FastWatchAlphaRequest({
    required this.repoRoot,
    required this.fixtureTemplatePath,
    required this.workDirectoryPath,
    required this.keepRunDirectory,
    this.mutateBuildScriptBeforeIncremental = false,
    this.simulateDroppedSourceUpdateOnIncremental = false,
    this.sourceEngine = 'dart',
    this.incrementalCycles = 1,
  });
}
