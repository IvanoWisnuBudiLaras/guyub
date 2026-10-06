import 'weather_suggestion.dart';

/// Protected read boundary for human-reviewed weather suggestions.
abstract interface class WeatherSuggestionBoundary {
  Future<List<WeatherSuggestion>> listWeatherSuggestions();

  Future<void> ignoreWeatherSuggestion({required String suggestionId});
}
