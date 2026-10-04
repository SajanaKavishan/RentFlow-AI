import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../models/support_ticket.dart';

class SupportTicketApiService {
  const SupportTicketApiService(this.apiClient);
  final ApiClient apiClient;
  static const _path = '/api/support-tickets';

  Future<List<SupportTicket>> getMySupportTickets() async {
    final json = await _request(
      () => apiClient.get(apiClient.buildUri('$_path/mine')),
      fallback: 'Your support requests could not be loaded. Please try again.',
    );
    try {
      if (json is! List) throw const FormatException();
      return List.unmodifiable(
        json.map((item) {
          if (item is! Map<String, dynamic>) throw const FormatException();
          return SupportTicket.fromJson(item);
        }),
      );
    } on FormatException {
      throw const SupportTicketApiException(
        'The support service returned an invalid response. Please try again.',
      );
    }
  }

  Future<SupportTicket> createSupportTicket(
    CreateSupportTicketRequest request,
  ) async {
    final error = request.validate();
    if (error != null) throw SupportTicketApiException(error);
    final json = await _request(
      () => apiClient.post(
        apiClient.buildUri(_path),
        body: jsonEncode(request.toJson()),
      ),
      fallback:
          'Your support request could not be submitted. Please try again.',
    );
    try {
      if (json is! Map<String, dynamic>) throw const FormatException();
      return SupportTicket.fromJson(json);
    } on FormatException {
      throw const SupportTicketApiException(
        'The support service returned an invalid response. Please try again.',
      );
    }
  }

  Future<Object?> _request(
    Future<http.Response> Function() request, {
    required String fallback,
  }) async {
    try {
      final response = await request();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SupportTicketApiException(
          response.statusCode == 401
              ? 'Your session is no longer valid. Please sign in again.'
              : fallback,
          statusCode: response.statusCode,
        );
      }
      return jsonDecode(response.body);
    } on http.ClientException {
      throw const SupportTicketApiException(
        'Unable to connect. Please try again.',
      );
    } on FormatException {
      throw const SupportTicketApiException(
        'The support service returned an invalid response. Please try again.',
      );
    }
  }
}

class SupportTicketApiException implements Exception {
  const SupportTicketApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
