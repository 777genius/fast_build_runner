import 'dart:convert';
import 'dart:io';

class ProjectMutationProfile {
  final String name;
  final String sourceFileRelativePath;
  final String generatedFileRelativePath;
  final List<ProjectMutationStep> steps;

  const ProjectMutationProfile({
    required this.name,
    required this.sourceFileRelativePath,
    required this.generatedFileRelativePath,
    required this.steps,
  });

  factory ProjectMutationProfile.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final sourceFileRelativePath = json['sourceFileRelativePath'];
    final generatedFileRelativePath = json['generatedFileRelativePath'];
    final rawSteps = json['steps'];
    if (name is! String || name.isEmpty) {
      throw StateError('Mutation profile is missing a valid "name".');
    }
    if (sourceFileRelativePath is! String || sourceFileRelativePath.isEmpty) {
      throw StateError(
        'Mutation profile "$name" is missing "sourceFileRelativePath".',
      );
    }
    if (generatedFileRelativePath is! String ||
        generatedFileRelativePath.isEmpty) {
      throw StateError(
        'Mutation profile "$name" is missing "generatedFileRelativePath".',
      );
    }
    if (rawSteps is! List || rawSteps.isEmpty) {
      throw StateError(
        'Mutation profile "$name" must define at least one step.',
      );
    }
    return ProjectMutationProfile(
      name: name,
      sourceFileRelativePath: sourceFileRelativePath,
      generatedFileRelativePath: generatedFileRelativePath,
      steps: rawSteps
          .map(
            (step) => ProjectMutationStep.fromJson(
              Map<String, Object?>.from(step as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  factory ProjectMutationProfile.load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('Mutation profile does not exist: $path');
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw StateError('Mutation profile must decode to a JSON object: $path');
    }
    return ProjectMutationProfile.fromJson(Map<String, Object?>.from(decoded));
  }

  ProjectMutationStep stepForCycle(int cycleIndex) {
    if (cycleIndex < 0 || cycleIndex >= steps.length) {
      throw StateError(
        'Mutation profile "$name" does not define step ${cycleIndex + 1}.',
      );
    }
    return steps[cycleIndex];
  }
}

class ProjectMutationStep {
  final String name;
  final List<ProjectTextReplacement> replacements;
  final List<String> generatedMarkers;

  const ProjectMutationStep({
    required this.name,
    required this.replacements,
    required this.generatedMarkers,
  });

  factory ProjectMutationStep.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final rawReplacements = json['replacements'];
    final rawGeneratedMarkers = json['generatedMarkers'];
    if (name is! String || name.isEmpty) {
      throw StateError('Mutation profile step is missing a valid "name".');
    }
    if (rawReplacements is! List || rawReplacements.isEmpty) {
      throw StateError(
        'Mutation profile step "$name" must define replacements.',
      );
    }
    if (rawGeneratedMarkers is! List || rawGeneratedMarkers.isEmpty) {
      throw StateError(
        'Mutation profile step "$name" must define generatedMarkers.',
      );
    }
    final generatedMarkers = rawGeneratedMarkers
        .map((marker) {
          if (marker is! String || marker.isEmpty) {
            throw StateError(
              'Mutation profile step "$name" contains an invalid generated marker.',
            );
          }
          return marker;
        })
        .toList(growable: false);
    return ProjectMutationStep(
      name: name,
      replacements: rawReplacements
          .map(
            (replacement) => ProjectTextReplacement.fromJson(
              Map<String, Object?>.from(replacement as Map),
            ),
          )
          .toList(growable: false),
      generatedMarkers: generatedMarkers,
    );
  }

  String apply(String originalSource) {
    var updated = originalSource;
    for (final replacement in replacements) {
      updated = replacement.apply(updated, stepName: name);
    }
    return updated;
  }
}

class ProjectTextReplacement {
  final String from;
  final String to;

  const ProjectTextReplacement({required this.from, required this.to});

  factory ProjectTextReplacement.fromJson(Map<String, Object?> json) {
    final from = json['from'];
    final to = json['to'];
    if (from is! String || from.isEmpty) {
      throw StateError('Mutation profile replacement is missing "from".');
    }
    if (to is! String || to.isEmpty) {
      throw StateError('Mutation profile replacement is missing "to".');
    }
    return ProjectTextReplacement(from: from, to: to);
  }

  String apply(String originalSource, {required String stepName}) {
    if (originalSource.contains(to)) {
      return originalSource;
    }
    if (!originalSource.contains(from)) {
      return _applyWithNormalizedLineEndings(
        originalSource,
        stepName: stepName,
      );
    }
    return originalSource.replaceFirst(from, to);
  }

  String _applyWithNormalizedLineEndings(
    String originalSource, {
    required String stepName,
  }) {
    final normalizedOriginal = _normalizeLineEndings(originalSource);
    final normalizedFrom = _normalizeLineEndings(from);
    final normalizedTo = _normalizeLineEndings(to);
    if (normalizedOriginal.contains(normalizedTo)) {
      return originalSource;
    }
    if (!normalizedOriginal.contains(normalizedFrom)) {
      throw StateError(
        'Mutation profile step "$stepName" could not find expected source snippet.',
      );
    }
    final updated = normalizedOriginal.replaceFirst(normalizedFrom, normalizedTo);
    return _restoreLineEndings(updated, template: originalSource);
  }

  String _normalizeLineEndings(String source) {
    return source.replaceAll('\r\n', '\n');
  }

  String _restoreLineEndings(String source, {required String template}) {
    if (template.contains('\r\n')) {
      return source.replaceAll('\n', '\r\n');
    }
    return source;
  }
}
