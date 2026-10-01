import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/properties/services/property_api_service.dart';

import '../property_details_test.dart' as fixture;

const preferencesPath = '/api/tenant/property-preferences';
const favoritesPath = '/api/tenant/property-favorites';
const matchesPath = '/api/properties/matches';
const savedPreferences = <String, dynamic>{
  'isConfigured': true,
  'preferredCity': 'Kurunegala',
  'maximumMonthlyRent': 100000,
  'minimumBedrooms': 2,
  'minimumBathrooms': 1,
  'preferredAmenities': ['Wi-Fi', 'Parking', 'Custom terrace'],
};

class DiscoveryBackend {
  Map<String, dynamic> preferences = Map.of(savedPreferences);
  final Set<String> favorites = {};
  final List<http.Request> requests = [];
  final Map<String, int?> scores = {fixture.id: 94};
  List<Map<String, dynamic>> properties = [fixture.propertyJson()];
  Future<http.Response?> Function(http.Request)? intercept;
  late final ApiClient client;
  late final PropertyApiService service;

  DiscoveryBackend() {
    client = ApiClient(
      baseUrl: 'https://test.example',
      tokenStorage: fixture.MemoryTokenStorage(),
      httpClient: MockClient((request) async {
        requests.add(request);
        final intercepted = await intercept?.call(request);
        if (intercepted != null) return intercepted;
        final path = request.url.path;
        if (path == preferencesPath) {
          if (request.method == 'PUT') {
            preferences = {
              ...jsonDecode(request.body) as Map<String, dynamic>,
              'isConfigured': true,
            };
          }
          if (request.method == 'DELETE') {
            preferences = {
              'isConfigured': false,
              'preferredAmenities': <String>[],
            };
            return http.Response('', 204);
          }
          return json(preferences);
        }
        if (path == favoritesPath) {
          return json({'propertyIds': favorites.toList()});
        }
        if (path.startsWith('$favoritesPath/')) {
          final id = path.split('/').last;
          if (request.method == 'PUT') favorites.add(id);
          if (request.method == 'DELETE') favorites.remove(id);
          return http.Response('', 204);
        }
        if (path == matchesPath) {
          return json({
            'summary': 'AI summary that must never appear in discovery',
            'matches': [
              for (final property in properties)
                if (scores.containsKey(property['id']))
                  {
                    'propertyId': property['id'],
                    'title': property['title'],
                    'city': property['city'],
                    'monthlyRent': property['monthlyRent'],
                    'bedrooms': property['bedrooms'],
                    'bathrooms': property['bathrooms'],
                    'amenities': property['amenities'],
                    'matchScore': scores[property['id']],
                    'matchReasons': ['Matches your preferred city.'],
                  },
            ],
          });
        }
        if (path == '/api/properties') return json(properties);
        if (path.endsWith('/images')) return json([]);
        for (final property in properties) {
          if (path == '/api/properties/${property['id']}') {
            return json(property);
          }
        }
        return http.Response('', 404);
      }),
    );
    service = PropertyApiService(client);
  }

  static http.Response json(Object value) =>
      http.Response(jsonEncode(value), 200);
  int calls(String path, [String method = 'GET']) => requests
      .where((request) => request.url.path == path && request.method == method)
      .length;
  void close() => client.close();
}
