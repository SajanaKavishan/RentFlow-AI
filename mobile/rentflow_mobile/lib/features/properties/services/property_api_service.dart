import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/property.dart';
import '../models/property_matching.dart';

class PropertyApiService {
  const PropertyApiService(this.apiClient);

  final ApiClient apiClient;

  Future<List<Property>> getProperties({
    String? city,
    double? minRent,
    double? maxRent,
    int? bedrooms,
    int? bathrooms,
    bool? isAvailable,
    String? amenity,
  }) async {
    final queryParameters = <String, String>{};

    if (city != null && city.trim().isNotEmpty) {
      queryParameters['city'] = city.trim();
    }

    if (minRent != null) {
      queryParameters['minRent'] = minRent.toString();
    }

    if (maxRent != null) {
      queryParameters['maxRent'] = maxRent.toString();
    }

    if (bedrooms != null) {
      queryParameters['bedrooms'] = bedrooms.toString();
    }

    if (bathrooms != null) {
      queryParameters['bathrooms'] = bathrooms.toString();
    }

    if (isAvailable != null) {
      queryParameters['isAvailable'] = isAvailable.toString();
    }

    if (amenity != null && amenity.trim().isNotEmpty) {
      queryParameters['amenity'] = amenity.trim();
    }

    final baseUri =
        apiClient.buildUri(ApiConstants.propertiesPath);

    final uri = queryParameters.isEmpty
        ? baseUri
        : baseUri.replace(
            queryParameters: queryParameters,
          );

    final response =
        await _send(() => apiClient.get(uri));

    return _parsePropertyList(response.body);
  }

  Future<Property> getPropertyById(String id) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.propertiesPath}/$id',
    );

    final response =
        await _send(() => apiClient.get(uri));

    return _parseProperty(response.body);
  }

  Future<PropertyMatchingResponse> matchProperties(
    PropertyMatchingRequest preferences,
  ) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.propertiesPath}/match',
    );

    final response = await _send(
      () => apiClient.post(
        uri,
        body: jsonEncode(preferences.toJson()),
        authenticated: false,
      ),
    );

    return _parsePropertyMatchingResponse(
      response.body,
    );
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request,
  ) async {
    late final http.Response response;

    try {
      response = await request();
    } on http.ClientException {
      throw const PropertyApiException(
        'Unable to connect to the property service.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw PropertyApiException(
        _safeErrorMessage(response) ??
            'The property request failed. Please try again.',
        statusCode: response.statusCode,
      );
    }

    return response;
  }

  Property _parseProperty(String body) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }

      return Property.fromJson(decoded);
    } on FormatException {
      throw const PropertyApiException(
        'The property service returned an invalid response.',
      );
    }
  }

  List<Property> _parsePropertyList(String body) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is! List<dynamic>) {
        throw const FormatException();
      }

      return decoded.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException();
        }

        return Property.fromJson(item);
      }).toList(growable: false);
    } on FormatException {
      throw const PropertyApiException(
        'The property service returned an invalid response.',
      );
    }
  }

  PropertyMatchingResponse
      _parsePropertyMatchingResponse(String body) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }

      return PropertyMatchingResponse.fromJson(
        decoded,
      );
    } on FormatException {
      throw const PropertyApiException(
        'The property matching service returned an invalid response.',
      );
    }
  }

  String? _safeErrorMessage(
    http.Response response,
  ) {
    if (response.statusCode == 403) {
      return 'You do not have permission to access this resource.';
    }

    if (response.statusCode == 404) {
      return 'The requested property is unavailable.';
    }

    if (response.statusCode >= 500) {
      return null;
    }

    return _readErrorMessage(response.body);
  }

  String? _readErrorMessage(String body) {
    if (body.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      for (final key in [
        'detail',
        'title',
        'message',
      ]) {
        final value = decoded[key];

        if (value is String &&
            value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    } on FormatException {
      return null;
    }

    return null;
  }
}

class PropertyApiException implements Exception {
  const PropertyApiException(
    this.message, {
    this.statusCode,
  });

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}