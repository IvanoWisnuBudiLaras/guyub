import 'package:cloud_functions/cloud_functions.dart';

import '../application/weather_suggestion.dart';
import '../application/weather_suggestion_boundary.dart';

/// Callable adapter; clients cannot read or mutate task_suggestions directly.
final class FirebaseWeatherSuggestionBoundary
    implements WeatherSuggestionBoundary {
  FirebaseWeatherSuggestionBoundary(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<List<WeatherSuggestion>> listWeatherSuggestions() async {
    final response = await _functions
        .httpsCallable('listWeatherSuggestions')
        .call<Object?>(const <String, Object?>{});
    final envelope = _asMap(response.data);
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
