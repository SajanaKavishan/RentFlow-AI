import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/rental_offer.dart';

class RentalOfferApiService {
  const RentalOfferApiService(this.apiClient);

  final ApiClient apiClient;

  Future<List<RentalOffer>> getMyOffers() async {
    final uri = apiClient.buildUri('${ApiConstants.rentalOffersPath}/mine');
    final response = await _send(() => apiClient.get(uri));
    return _parseList(response.body);
  }

  Future<RentalOffer> getOffer(String id) async {
    final response = await _send(() => apiClient.get(_offerUri(id)));
    return _parseOffer(response.body);
  }

  Future<RentalOffer> acceptOffer(String id) => _respond(id, 'accept');

  Future<RentalOffer> rejectOffer(String id) => _respond(id, 'reject');

  Uri _offerUri(String id) =>
      apiClient.buildUri('${ApiConstants.rentalOffersPath}/$id');

  Future<RentalOffer> _respond(String id, String action) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.rentalOffersPath}/$id/$action',
    );
    final response = await _send(() => apiClient.patch(uri));
    return _parseOffer(response.body);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const RentalOfferApiException(
        'Unable to connect to the rental offer service.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RentalOfferApiException(
        _safeErrorMessage(response) ??
            'The rental offer request failed. Please try again.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  String? _safeErrorMessage(http.Response response) {
    if (response.statusCode == 401) return 'Your session has expired.';
    if (response.statusCode == 403) {
      return 'You do not have permission to access this resource.';
    }
    if (response.statusCode == 404) {
      return 'The requested rental offer is unavailable.';
    }
    if (response.statusCode == 409) {
      return 'This offer has changed. Refresh and try again.';
    }
    if (response.statusCode >= 500) return null;
    return _readErrorMessage(response.body);
  }

  RentalOffer _parseOffer(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return RentalOffer.fromJson(decoded);
    } on FormatException {
      throw const RentalOfferApiException(
        'The rental offer service returned an invalid response.',
      );
    }
  }

  List<RentalOffer> _parseList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List<dynamic>) throw const FormatException();
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) throw const FormatException();
            return RentalOffer.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const RentalOfferApiException(
        'The rental offer service returned an invalid response.',
      );
    }
  }

  String? _readErrorMessage(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      for (final key in ['detail', 'title', 'message']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class RentalOfferApiException implements Exception {
  const RentalOfferApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
