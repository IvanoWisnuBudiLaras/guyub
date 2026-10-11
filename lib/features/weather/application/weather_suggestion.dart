/// A reviewed weather-rule match presented only as a suggestion.
enum WeatherSuggestionState { suggested }

final class WeatherSuggestedTemplateVersion {
  const WeatherSuggestedTemplateVersion({
    required this.templateId,
    required this.version,
  });

  final String templateId;
  final int version;
}

final class WeatherSuggestion {
  WeatherSuggestion({
    required this.id,
    required this.sourceSnapshotId,
    required this.ruleId,
    required List<String> recommendedTemplateIds,
    required this.createdAt,
    List<WeatherSuggestedTemplateVersion> recommendedTemplateVersions =
        const [],
    this.sourceUpdatedAt,
    this.fetchedAt,
    this.rainfallMm,
    this.explanation = '',
    this.isStale = false,
  }) : recommendedTemplateIds = List.unmodifiable(recommendedTemplateIds),
       recommendedTemplateVersions = List.unmodifiable(
         recommendedTemplateVersions,
       );

  /// Deterministic ID makes repeating the same snapshot/rule evaluation replay-safe.
  final String id;
  final String sourceSnapshotId;
  final String ruleId;
  final List<String> recommendedTemplateIds;
  final List<WeatherSuggestedTemplateVersion> recommendedTemplateVersions;
  final DateTime createdAt;
  final DateTime? sourceUpdatedAt;
  final DateTime? fetchedAt;
  final double? rainfallMm;
  final String explanation;
  final bool isStale;

  String get source => 'BMKG';
  WeatherSuggestionState get state => WeatherSuggestionState.suggested;

  factory WeatherSuggestion.fromJson(Map<String, Object?> json) {
    const expectedKeys = {
      'suggestionId',
      'source',
      'snapshotId',
      'sourceUpdatedAt',
      'fetchedAt',
      'rainfallMm',
      'ruleId',
      'ruleVersion',
      'recommendedTemplateVersions',
      'explanation',
      'state',
      'createdAt',
      'isStale',
    };
    if (json.keys.toSet().difference(expectedKeys).isNotEmpty ||
        json.keys.toSet().length != expectedKeys.length ||
        json['source'] != 'BMKG' ||
        json['state'] != 'SUGGESTED' ||
        json['isStale'] is! bool ||
        json['explanation'] is! String) {
      throw const FormatException('Weather suggestion fields are invalid.');
    }
    final id = _requiredString(json['suggestionId']);
    final snapshotId = _requiredString(json['snapshotId']);
    final ruleId = _requiredString(json['ruleId']);
    final createdAt = _requiredDate(json['createdAt']);
    final sourceUpdatedAt = _requiredDate(json['sourceUpdatedAt']);
    final fetchedAt = _requiredDate(json['fetchedAt']);
    final rainfall = json['rainfallMm'];
    final ruleVersion = json['ruleVersion'];
    final explanation = (json['explanation'] as String).trim();
    final rawVersions = json['recommendedTemplateVersions'];
    if (!_hash40Pattern.hasMatch(id) ||
        !_hash40Pattern.hasMatch(snapshotId) ||
        !_ruleIdPattern.hasMatch(ruleId) ||
        ruleVersion is! int ||
        ruleVersion < 1 ||
        rainfall is! num ||
        !rainfall.isFinite ||
        rainfall < 0 ||
        explanation.isEmpty ||
        explanation.runes.length > 240 ||
        explanation.runes.any((rune) => rune < 0x20 || rune == 0x7f) ||
        rawVersions is! List ||
        rawVersions.isEmpty ||
        rawVersions.length > 10) {
      throw const FormatException('Weather suggestion fields are invalid.');
    }
    final versions = <WeatherSuggestedTemplateVersion>[];
    final seen = <String>{};
    for (final raw in rawVersions) {
      if (raw is! Map) {
        throw const FormatException('Weather template reference is invalid.');
      }
      final item = <String, Object?>{};
      for (final entry in raw.entries) {
        if (entry.key is! String) {
          throw const FormatException('Weather template reference is invalid.');
        }
        item[entry.key as String] = entry.value;
      }
      if (item.length != 2 ||
          item.keys.toSet().difference({'templateId', 'version'}).isNotEmpty) {
        throw const FormatException('Weather template reference is invalid.');
      }
      final templateId = item['templateId'];
      final version = item['version'];
      if (templateId is! String ||
          !_templateIdPattern.hasMatch(templateId) ||
          version is! int ||
          version < 1 ||
          !seen.add('$templateId:$version')) {
        throw const FormatException('Weather template reference is invalid.');
      }
      versions.add(
        WeatherSuggestedTemplateVersion(
          templateId: templateId,
          version: version,
        ),
      );
    }
    return WeatherSuggestion(
      id: id,
      sourceSnapshotId: snapshotId,
      ruleId: ruleId,
      recommendedTemplateIds: versions.map((item) => item.templateId).toList(),
      recommendedTemplateVersions: versions,
      createdAt: createdAt,
      sourceUpdatedAt: sourceUpdatedAt,
      fetchedAt: fetchedAt,
      rainfallMm: rainfall.toDouble(),
      explanation: explanation,
      isStale: json['isStale'] as bool,
    );
  }
}

String _requiredString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Weather suggestion fields are invalid.');
  }
  return value;
}

DateTime _requiredDate(Object? value) {
  if (value is! String) {
    throw const FormatException('Weather suggestion fields are invalid.');
  }
  final date = DateTime.tryParse(value);
  if (date == null) {
    throw const FormatException('Weather suggestion fields are invalid.');
  }
  return date;
}

final _hash40Pattern = RegExp(r'^[a-f0-9]{40}$');
final _ruleIdPattern = RegExp(r'^[a-z][a-z0-9_-]{0,63}$');
final _templateIdPattern = RegExp(r'^[a-z][a-z0-9_-]{0,63}$');
