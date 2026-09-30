import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/payment.dart';

class PaymentApiService {
  const PaymentApiService(this.apiClient);

  final ApiClient apiClient;

  Future<Payment> createPayment({
    required String rentScheduleItemId,
    required String paymentMethod,
    String? transactionReference,
  }) async {
    final normalizedMethod = paymentMethod.trim();
    if (normalizedMethod.isEmpty) {
      throw const PaymentApiException('Payment method is required.');
    }
    if (normalizedMethod.length > 100) {
      throw const PaymentApiException(
        'Payment method must be 100 characters or fewer.',
      );
    }
    final normalizedReference = transactionReference?.trim();
    if (normalizedReference != null && normalizedReference.length > 200) {
      throw const PaymentApiException(
        'Transaction reference must be 200 characters or fewer.',
      );
    }

    final uri = apiClient.buildUri(ApiConstants.paymentsPath);
    final response = await _send(
      () => apiClient.post(
        uri,
        body: jsonEncode({
          'rentScheduleItemId': rentScheduleItemId,
          'paymentMethod': normalizedMethod,
          'transactionReference': normalizedReference?.isEmpty ?? true
              ? null
              : normalizedReference,
        }),
      ),
    );
    return _parsePayment(response.body);
  }

  Future<List<Payment>> getMyPayments() async {
    final response = await _send(
      () => apiClient.get(
        apiClient.buildUri('${ApiConstants.paymentsPath}/mine'),
      ),
    );
    return _parseList(response.body);
  }

  Future<Payment> getPayment(String id) async {
    final response = await _send(
      () =>
          apiClient.get(apiClient.buildUri('${ApiConstants.paymentsPath}/$id')),
    );
    return _parsePayment(response.body);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const PaymentApiException(
        'Unable to connect to the payment service.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PaymentApiException(
        _safeErrorMessage(response) ??
            'The payment request failed. Please try again.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  String? _safeErrorMessage(http.Response response) {
    if (response.statusCode == 400) {
      return _readErrorMessage(response.body) ??
          'The payment request is invalid. Check the details and try again.';
    }
    if (response.statusCode == 401) return 'Your session has expired.';
    if (response.statusCode == 403) {
      return 'You do not have permission to access this resource.';
    }
    if (response.statusCode == 404) {
      return 'The requested payment or rent schedule item is unavailable.';
    }
    if (response.statusCode == 409) {
      return 'This payment conflicts with the current rent schedule. Refresh and try again.';
    }
    if (response.statusCode >= 500) return null;
    return _readErrorMessage(response.body);
  }

  Payment _parsePayment(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return Payment.fromJson(decoded);
    } on FormatException {
      throw const PaymentApiException(
        'The payment service returned an invalid response.',
      );
    }
  }

  List<Payment> _parseList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List<dynamic>) throw const FormatException();
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) throw const FormatException();
            return Payment.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const PaymentApiException(
        'The payment service returned an invalid response.',
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

class PaymentApiException implements Exception {
  const PaymentApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
