import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/lease_agreement.dart';

class LeaseAgreementApiService {
  const LeaseAgreementApiService(this.apiClient);

  final ApiClient apiClient;

  Future<List<LeaseAgreement>> getMyLeases() async {
    final uri = apiClient.buildUri('${ApiConstants.leaseAgreementsPath}/mine');
    final response = await _send(() => apiClient.get(uri));
    return _parseList(response.body);
  }

  Future<LeaseAgreement> getLease(String id) async {
    final uri = apiClient.buildUri('${ApiConstants.leaseAgreementsPath}/$id');
    final response = await _send(() => apiClient.get(uri));
    return _parseLease(response.body);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const LeaseAgreementApiException(
        'Unable to connect to the lease agreement service.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LeaseAgreementApiException(
        _safeErrorMessage(response) ??
            'The lease agreement request failed. Please try again.',
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
      return 'The requested lease agreement is unavailable.';
    }
    if (response.statusCode >= 500) return null;
    return _readErrorMessage(response.body);
  }

  LeaseAgreement _parseLease(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return LeaseAgreement.fromJson(decoded);
    } on FormatException {
      throw const LeaseAgreementApiException(
        'The lease agreement service returned an invalid response.',
      );
    }
  }

  List<LeaseAgreement> _parseList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List<dynamic>) throw const FormatException();
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) throw const FormatException();
            return LeaseAgreement.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const LeaseAgreementApiException(
        'The lease agreement service returned an invalid response.',
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

class LeaseAgreementApiException implements Exception {
  const LeaseAgreementApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
