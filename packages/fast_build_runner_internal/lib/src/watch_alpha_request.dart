class FastWatchAlphaRequest {
  final String repoRoot;
  final String fixtureTemplatePath;
  final String workDirectoryPath;
  final bool keepRunDirectory;
  final bool mutateBuildScriptBeforeIncremental;
  final String sourceEngine;

  const FastWatchAlphaRequest({
    required this.repoRoot,
    required this.fixtureTemplatePath,
    required this.workDirectoryPath,
    required this.keepRunDirectory,
    this.mutateBuildScriptBeforeIncremental = false,
    this.sourceEngine = 'dart',
  });
}
