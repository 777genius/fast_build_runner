class FastBootstrapSpikeRequest {
  final String repoRoot;
  final String internalPackageRootPath;
  final String fixtureTemplatePath;
  final String workDirectoryPath;
  final bool keepRunDirectory;
  final bool mutateBuildScriptBeforeIncremental;

  const FastBootstrapSpikeRequest({
    required this.repoRoot,
    required this.internalPackageRootPath,
    required this.fixtureTemplatePath,
    required this.workDirectoryPath,
    required this.keepRunDirectory,
    this.mutateBuildScriptBeforeIncremental = false,
  });
}
