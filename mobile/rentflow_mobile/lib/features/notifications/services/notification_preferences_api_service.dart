import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../models/notification_preferences.dart';

class NotificationPreferencesApiService {
  const NotificationPreferencesApiService(this.apiClient);

  final ApiClient apiClient;
  static const _path = '/api/notification-preferences';

  Future<NotificationPreferences> getNotificationPreferences() => _request(
    () => apiClient.get(apiClient.buildUri(_path)),
    fallback: 'Notification preferences could not be loaded. Please try again.',
  );

  Future<NotificationPreferences> updateNotificationPreferences({
    required bool viewingUpdatesEnabled,
    required bool rentalApplicationUpdatesEnabled,
  }) => _request(
    () => apiClient.put(
      apiClient.buildUri(_path),
      body: jsonEncode({
        'viewingUpdatesEnabled': viewingUpdatesEnabled,
        'rentalApplicationUpdatesEnabled': rentalApplicationUpdatesEnabled,
        'accountSecurityUpdatesEnabled': true,
      }),
    ),
    fallback: 'Notification preferences could not be saved. Please try again.',
  );

  Future<NotificationPreferences> _request(
    Future<http.Response> Function() request, {
    required String fallback,
  }) async {
    try {
      final response = await request();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NotificationPreferencesApiException(
          response.statusCode == 401
              ? 'Your session is no longer valid. Please sign in again.'
              : fallback,
          statusCode: response.statusCode,
        );
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) throw const FormatException();
      return NotificationPreferences.fromJson(json);
    } on http.ClientException {
      throw const NotificationPreferencesApiException(
        'Unable to connect. Please try again.',
      );
    } on FormatException {
      throw const NotificationPreferencesApiException(
        'The service returned invalid notification preferences. Please try again.',
      );
    }
  }
}

class NotificationPreferencesApiException implements Exception {
  const NotificationPreferencesApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
