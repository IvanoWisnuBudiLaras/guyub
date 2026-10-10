import 'weather_snapshot.dart';
import 'weather_suggestion.dart';

/// Configurable weather rule. No threshold is selected by application code.
final class WeatherRule {
  WeatherRule({
    required this.id,
    required this.minimumRainfallMm,
    required List<String> suggestedTemplateIds,
    required this.enabled,
  }) : suggestedTemplateIds = List.unmodifiable(suggestedTemplateIds) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    if (!minimumRainfallMm.isFinite || minimumRainfallMm < 0) {
      throw ArgumentError.value(
        minimumRainfallMm,
        'minimumRainfallMm',
        'Must be finite and non-negative.',
      );
    }
    if (this.suggestedTemplateIds.isEmpty ||
        this.suggestedTemplateIds.any(
          (templateId) => templateId.trim().isEmpty,
        )) {
      throw ArgumentError.value(
        suggestedTemplateIds,
        'suggestedTemplateIds',
        'At least one non-empty reviewed template ID is required.',
      );
    }
  }

  final String id;
  final double minimumRainfallMm;
  final List<String> suggestedTemplateIds;
  final bool enabled;

  bool matches(WeatherSnapshot snapshot) =>
      enabled && snapshot.rainfallMm >= minimumRainfallMm;
}

/// Evaluates configuration and returns suggestions only, never active tasks.
final class WeatherRuleEvaluator {
  List<WeatherSuggestion> evaluate({
    required WeatherSnapshot snapshot,
    required Iterable<WeatherRule> rules,
    required DateTime evaluatedAt,
    required Duration maximumSnapshotAge,
  }) {
    if (snapshot.isStaleAt(now: evaluatedAt, maximumAge: maximumSnapshotAge)) {
      return const [];
    }

    final results = <WeatherSuggestion>[];
    final seenRuleIds = <String>{};
    for (final rule in rules) {
      if (!seenRuleIds.add(rule.id)) {
        throw ArgumentError.value(rule.id, 'rules', 'Rule IDs must be unique.');
      }
      if (rule.matches(snapshot)) {
        results.add(
          WeatherSuggestion(
            id: '${snapshot.id}:${rule.id}',
            sourceSnapshotId: snapshot.id,
            ruleId: rule.id,
            recommendedTemplateIds: rule.suggestedTemplateIds,
            createdAt: evaluatedAt,
          ),
        );
      }
    }
    return List.unmodifiable(results);
  }
}
