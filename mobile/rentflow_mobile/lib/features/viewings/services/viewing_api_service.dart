import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/viewing.dart';
import '../models/viewing_slots.dart';

class ViewingApiService {
  const ViewingApiService(this.apiClient);

  final ApiClient apiClient;

  Future<Viewing> createViewing({
    required String propertyId,
    required DateTime requestedDateTime,
    String? tenantMessage,
    String? requestedDateTimeIso,
  }) async {
    final uri = apiClient.buildUri(ApiConstants.viewingsPath);
    final body = jsonEncode({
      'propertyId': propertyId,
      'requestedDateTime':
          requestedDateTimeIso ?? requestedDateTime.toUtc().toIso8601String(),
      'tenantMessage': tenantMessage,
    });

    final response = await _send(() => apiClient.post(uri, body: body));
    return _parseViewing(response.body);
  }

  Future<Viewing> getViewingById(String id) async {
    final uri = apiClient.buildUri('${ApiConstants.viewingsPath}/$id');
    final response = await _send(() => apiClient.get(uri));
    return _parseViewing(response.body);
  }

  Future<ViewingSlots> getViewingSlots({
    required String propertyId,
    required String date,
  }) async {
    final uri = apiClient.buildUri(
      '/api/properties/$propertyId/viewing-slots',
      queryParameters: {'date': date, 'includeUnavailable': 'true'},
    );
    final response = await _send(() => apiClient.get(uri));
    try {
      final parsed = ViewingSlots.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      if (parsed.date != date) {
        throw const FormatException('Wrong availability date.');
      }
      return parsed;
    } on FormatException {
      throw const ViewingApiException(
        'The viewing service returned invalid availability.',
      );
    } on TypeError {
      throw const ViewingApiException(
        'The viewing service returned invalid availability.',
      );
    }
  }

  Future<List<Viewing>> getMyViewings() async {
    final uri = apiClient.buildUri(ApiConstants.viewingsPath);
    final response = await _send(() => apiClient.get(uri));
    return _parseViewingList(response.body);
  }

  Future<List<Viewing>> getViewingsByProperty(String propertyId) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.viewingsPath}/property/$propertyId',
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseViewingList(response.body);
  }

  Future<Viewing> cancelViewing({required String id}) async {
    final uri = apiClient.buildUri('${ApiConstants.viewingsPath}/$id/cancel');
    final response = await _send(() => apiClient.patch(uri));
    return _parseViewing(response.body);
  }

  Future<Viewing> approveViewing({
    required String id,
    String? landlordResponse,
  }) async {
    final uri = apiClient.buildUri('${ApiConstants.viewingsPath}/$id/approve');
    final response = await _send(
      () => apiClient.patch(
        uri,
        body: jsonEncode({
          'status': ViewingStatus.approved.value,
          'landlordResponse': _nullableTrimmed(landlordResponse),
        }),
      ),
    );
    return _parseStatusTransition(
      response.body,
      expectedStatus: ViewingStatus.approved,
    );
  }

  Future<Viewing> rejectViewing({
    required String id,
    required String landlordResponse,
  }) async {
    final uri = apiClient.buildUri('${ApiConstants.viewingsPath}/$id/reject');
    final response = await _send(
      () => apiClient.patch(
        uri,
        body: jsonEncode({
          'status': ViewingStatus.rejected.value,
          'landlordResponse': landlordResponse.trim(),
        }),
      ),
    );
    return _parseStatusTransition(
      response.body,
      expectedStatus: ViewingStatus.rejected,
    );
  }

  String? _nullableTrimmed(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const ViewingApiException(
        'Unable to connect to the viewing service.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ViewingApiException(
        _safeErrorMessage(response) ??
            'The viewing request failed. Please try again.',
        statusCode: response.statusCode,
      );
    }

    return response;
  }

  String? _safeErrorMessage(http.Response response) {
    if (response.statusCode == 403) {
      return 'You do not have permission to access this resource.';
    }
    if (response.statusCode == 404) {
      return 'The requested resource is unavailable.';
    }
    if (response.statusCode >= 500) return null;
    return _readErrorMessage(response.body);
  }

  Viewing _parseViewing(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      return Viewing.fromJson(decoded);
    } on FormatException {
      throw const ViewingApiException(
        'The viewing service returned an invalid response.',
      );
    }
  }

  Viewing _parseStatusTransition(
    String body, {
    required ViewingStatus expectedStatus,
  }) {
    final viewing = _parseViewing(body);
    if (viewing.status != expectedStatus) {
      throw const ViewingApiException(
        'The viewing service did not confirm the requested status change.',
      );
    }
    return viewing;
  }

  List<Viewing> _parseViewingList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List<dynamic>) {
        throw const FormatException();
      }

      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException();
            }
            return Viewing.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const ViewingApiException(
        'The viewing service returned an invalid response.',
      );
    }
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

      for (final key in ['detail', 'title', 'message']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    } on FormatException {
      return null;
    }

    return null;
  }
}

class ViewingApiException implements Exception {
  const ViewingApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
