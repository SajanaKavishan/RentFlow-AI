import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/application_validation.dart';

class ApplicationValidationApiService {
  const ApplicationValidationApiService(this.apiClient);

  final ApiClient apiClient;

  Future<List<ApplicationValidationRun>> getRunsForApplication(
    String applicationId,
  ) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.rentalApplicationsPath}/$applicationId/validation-runs',
    );
    late final http.Response response;
    try {
      response = await apiClient.get(uri);
    } on http.ClientException {
      throw const ApplicationValidationApiException(
        'Unable to connect to the application review service.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApplicationValidationApiException(
        _safeError(response) ??
            'The application review request failed. Please try again.',
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List<dynamic>) throw const FormatException();
      return decoded.map((item) {
        if (item is! Map<String, dynamic>) throw const FormatException();
        return ApplicationValidationRun.fromJson(item);
      }).toList(growable: false);
    } on FormatException {
      throw const ApplicationValidationApiException(
        'The application review service returned an invalid response.',
      );
    }
  }

  String? _safeError(http.Response response) {
    if (response.statusCode == 403) {
      return 'You do not have permission to view this application review.';
    }
    if (response.statusCode == 404) {
      return 'The application review is unavailable.';
    }
    if (response.statusCode >= 500 || response.body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(response.body);
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

class ApplicationValidationApiException implements Exception {
  const ApplicationValidationApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
