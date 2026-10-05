import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';

class TenantLeasePaymentsApiService {
  const TenantLeasePaymentsApiService(this.apiClient);
  final ApiClient apiClient;

  Future<List<Map<String, dynamic>>> getMyLeases() =>
      _list('/api/lease-agreements/mine');
  Future<List<Map<String, dynamic>>> getMyPayments() =>
      _list('/api/payments/mine');
  Future<List<Map<String, dynamic>>> getSchedule(String leaseId) =>
      _list('/api/rent-schedules/lease/${Uri.encodeComponent(leaseId)}');

  Future<List<Map<String, dynamic>>> _list(String path) async {
    final response = await _send(() => apiClient.get(apiClient.buildUri(path)));
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Invalid account response.');
    }
    return decoded.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid account item.');
      }
      return item;
    }).toList();
  }

  /// The server creates a pending record; only the landlord/admin can complete it.
  Future<Map<String, dynamic>> createPayment({
    required String scheduleItemId,
    required String paymentMethod,
    String? transactionReference,
  }) async {
    final response = await _send(
      () => apiClient.post(
        apiClient.buildUri('/api/payments'),
        body: jsonEncode({
          'rentScheduleItemId': scheduleItemId,
          'paymentMethod': paymentMethod.trim(),
          'transactionReference': transactionReference?.trim().isEmpty == true
              ? null
              : transactionReference?.trim(),
        }),
      ),
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['id'] is! String ||
        (decoded['id'] as String).isEmpty ||
        decoded['status'] is! int ||
        decoded['amount'] is! num) {
      throw const FormatException('Invalid payment response.');
    }
    return decoded;
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const TenantLeasePaymentsApiException(
        'Unable to connect. Please try again.',
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    String? message;
    if (response.statusCode == 400 || response.statusCode == 409) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['message'] is String) {
          message = decoded['message'] as String;
        }
      } catch (_) {
        /* Use a safe fallback for malformed error responses. */
      }
    }
    throw TenantLeasePaymentsApiException(
      message ??
          switch (response.statusCode) {
            401 => 'Your session has expired. Please sign in again.',
            403 => 'You do not have permission to access this item.',
            404 => 'This item is no longer available. Please refresh.',
            409 => 'This action is no longer available. Please refresh.',
            _ =>
              'Unable to load lease or payment information. Please try again.',
          },
      statusCode: response.statusCode,
    );
  }
}

class TenantLeasePaymentsApiException implements Exception {
  const TenantLeasePaymentsApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
