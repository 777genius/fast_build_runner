class FastWatchBenchmarkRequest {
  final String repoRoot;
  final String fixtureTemplatePath;
  final String workDirectoryPath;
  final bool keepRunDirectory;
  final int incrementalCycles;
  final int repeats;

  const FastWatchBenchmarkRequest({
    required this.repoRoot,
    required this.fixtureTemplatePath,
    required this.workDirectoryPath,
    required this.keepRunDirectory,
    this.incrementalCycles = 1,
    this.repeats = 1,
  });
}
