import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/rent_schedule_item.dart';
import '../models/rent_schedule_outstanding_summary.dart';

class RentScheduleApiService {
  const RentScheduleApiService(this.apiClient);

  final ApiClient apiClient;

  Future<List<RentScheduleItem>> getMyItems() async {
    final response = await _send(
      () => apiClient.get(
        apiClient.buildUri('${ApiConstants.rentSchedulesPath}/mine'),
      ),
    );
    return _parseList(response.body);
  }

  Future<RentScheduleOutstandingSummary> getMyOutstanding() async {
    final response = await _send(
      () => apiClient.get(
        apiClient.buildUri(
          '${ApiConstants.rentSchedulesPath}/outstanding/mine',
        ),
      ),
    );
    return _parseSummary(response.body);
  }

  Future<List<RentScheduleItem>> getByLease(String leaseAgreementId) async {
    final response = await _send(
      () => apiClient.get(
        apiClient.buildUri(
          '${ApiConstants.rentSchedulesPath}/lease/$leaseAgreementId',
        ),
      ),
    );
    return _parseList(response.body);
  }

  Future<RentScheduleOutstandingSummary> getOutstandingByLease(
    String leaseAgreementId,
  ) async {
    final response = await _send(
      () => apiClient.get(
        apiClient.buildUri(
          '${ApiConstants.rentSchedulesPath}/lease/$leaseAgreementId/outstanding',
        ),
      ),
    );
    return _parseSummary(response.body);
  }

  Future<RentScheduleItem> getItem(String id) async {
    final response = await _send(
      () => apiClient.get(
        apiClient.buildUri('${ApiConstants.rentSchedulesPath}/$id'),
      ),
    );
    return _parseItem(response.body);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const RentScheduleApiException(
        'Unable to connect to the rent schedule service.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RentScheduleApiException(
        _safeErrorMessage(response) ??
            'The rent schedule request failed. Please try again.',
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
      return 'The requested rent schedule is unavailable.';
    }
    if (response.statusCode >= 500) return null;
    return _readErrorMessage(response.body);
  }

  RentScheduleItem _parseItem(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return RentScheduleItem.fromJson(decoded);
    } on FormatException {
      throw const RentScheduleApiException(
        'The rent schedule service returned an invalid response.',
      );
    }
  }

  List<RentScheduleItem> _parseList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List<dynamic>) throw const FormatException();
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) throw const FormatException();
            return RentScheduleItem.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const RentScheduleApiException(
        'The rent schedule service returned an invalid response.',
      );
    }
  }

  RentScheduleOutstandingSummary _parseSummary(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return RentScheduleOutstandingSummary.fromJson(decoded);
    } on FormatException {
      throw const RentScheduleApiException(
        'The rent schedule service returned an invalid response.',
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

class RentScheduleApiException implements Exception {
  const RentScheduleApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
