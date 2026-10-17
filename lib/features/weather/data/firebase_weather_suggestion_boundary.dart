import '../../../core/network/callable_client.dart';

import '../application/weather_suggestion.dart';
import '../application/weather_suggestion_boundary.dart';

/// Callable adapter; clients cannot read or mutate task_suggestions directly.
final class FirebaseWeatherSuggestionBoundary
    implements WeatherSuggestionBoundary {
  FirebaseWeatherSuggestionBoundary(this._client);

  final CallableClient _client;

  @override
  Future<List<WeatherSuggestion>> listWeatherSuggestions() async {
    final response = await _client.call(
      'listWeatherSuggestions',
      const <String, Object?>{},
    );
    final envelope = _asMap(response);
    if (envelope.length != 1 || !envelope.containsKey('suggestions')) {
      throw const FormatException('Invalid weather suggestion response.');
    }
    final items = envelope['suggestions'];
    if (items is! List || items.length > 50) {
      throw const FormatException('Invalid weather suggestion response.');
    }
    return List.unmodifiable(
      items.map((item) => WeatherSuggestion.fromJson(_asMap(item))),
    );
  }

  @override
  Future<void> ignoreWeatherSuggestion({required String suggestionId}) async {
    final response = await _client.call(
      'ignoreWeatherSuggestion',
      <String, Object?>{'suggestionId': suggestionId},
    );
    final envelope = _asMap(response);
    if (envelope.length != 1 || envelope['ignored'] != true) {
      throw const FormatException('Invalid weather suggestion response.');
    }
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Invalid weather suggestion response.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Invalid weather suggestion response.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}
