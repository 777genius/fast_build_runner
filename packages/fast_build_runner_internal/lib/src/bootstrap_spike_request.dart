class FastBootstrapSpikeRequest {
  final String repoRoot;
  final String fixtureTemplatePath;
  final String workDirectoryPath;
  final bool keepRunDirectory;

  const FastBootstrapSpikeRequest({
    required this.repoRoot,
    required this.fixtureTemplatePath,
    required this.workDirectoryPath,
    required this.keepRunDirectory,
  });
}

