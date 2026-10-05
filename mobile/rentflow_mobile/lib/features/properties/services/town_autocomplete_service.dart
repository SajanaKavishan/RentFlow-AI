import 'package:flutter/services.dart';

class TownPrediction {
  const TownPrediction({
    required this.placeId,
    required this.town,
    required this.description,
  });
  final String placeId;
  final String town;
  final String description;
}

/// Uses the Android Places SDK so Android application restrictions apply to the key.
/// Unsupported platforms and missing configuration leave manual city entry available.
class TownAutocompleteService {
  const TownAutocompleteService();
  static const _channel = MethodChannel('rentflow/places');
  static const _apiKey = String.fromEnvironment('GOOGLE_PLACES_API_KEY');

  Future<List<TownPrediction>> suggest(String query) async {
    final values = await _channel
        .invokeListMethod<dynamic>('suggestTowns', {
          'query': query.trim(),
          'apiKey': _apiKey,
        })
        .timeout(const Duration(seconds: 10));
    return [
      for (final value in values ?? [])
        TownPrediction(
          placeId: value['placeId'] as String,
          town: value['town'] as String,
          description: value['description'] as String,
        ),
    ];
  }

  Future<String> select(TownPrediction prediction) async =>
      await _channel
          .invokeMethod<String>('selectTown', {
            'placeId': prediction.placeId,
            'fallbackTown': prediction.town,
          })
          .timeout(const Duration(seconds: 10)) ??
      prediction.town;

  Future<void> endSession() async {
    try {
      await _channel.invokeMethod<void>('endSession');
    } on MissingPluginException {
      // There is no native session on unsupported platforms or widget tests.
    } on PlatformException {
      // Abandoning a session must not prevent closing or clearing filters.
    }
  }
}
