class FastProjectWatchRequest {
  final String repoRoot;
  final String internalPackageRootPath;
  final String projectDirectoryPath;
  final bool deleteConflictingOutputs;
  final int settleBuildDelayMs;
  final bool trustBuildScriptFreshness;

  const FastProjectWatchRequest({
    required this.repoRoot,
    required this.internalPackageRootPath,
    required this.projectDirectoryPath,
    this.deleteConflictingOutputs = false,
    this.settleBuildDelayMs = 150,
    this.trustBuildScriptFreshness = true,
  });
}
