import 'dart:io';

import 'package:analyzer/file_system/file_system.dart' show ResourceProvider;
import 'package:analyzer/src/clients/build_resolvers/build_resolvers.dart';
import 'package:package_config/package_config.dart' show PackageConfig;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'fast_analysis_driver_filesystem.dart';
import 'fast_analysis_driver_model.dart';

AnalysisDriverForPackageBuild fastAnalysisDriver(
  FastAnalysisDriverModel analysisDriverModel,
  AnalysisOptions analysisOptions,
  String sdkSummaryPath,
  PackageConfig packageConfig,
) {
  return createAnalysisDriver(
    analysisOptions: analysisOptions,
    packages: _buildAnalyzerPackages(
      packageConfig,
      analysisDriverModel.filesystem,
    ),
    resourceProvider: analysisDriverModel.filesystem,
    fileContentCache: analysisDriverModel.filesystem,
    sdkSummaryBytes: File(sdkSummaryPath).readAsBytesSync(),
    uriResolvers: [analysisDriverModel.filesystem],
  );
}

Packages _buildAnalyzerPackages(
  PackageConfig packageConfig,
  ResourceProvider resourceProvider,
) => Packages({
  for (final package in packageConfig.packages)
    package.name: Package(
      name: package.name,
      languageVersion:
          package.languageVersion == null
              ? sdkLanguageVersion
              : Version(
                  package.languageVersion!.major,
                  package.languageVersion!.minor,
                  0,
                ),
      rootFolder: resourceProvider.getFolder(
        p.url.normalize(
          FastAnalysisDriverFilesystem.assetPathFor(
            package: package.name,
            path: '',
          ),
        ),
      ),
      libFolder: resourceProvider.getFolder(
        p.url.normalize(
          FastAnalysisDriverFilesystem.assetPathFor(
            package: package.name,
            path: 'lib',
          ),
        ),
      ),
    ),
});

final sdkLanguageVersion = () {
  final sdkVersion = Version.parse(Platform.version.split(' ').first);
  return Version(sdkVersion.major, sdkVersion.minor, 0);
}();
