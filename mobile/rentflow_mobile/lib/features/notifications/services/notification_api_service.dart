import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/notification.dart';

class NotificationApiService {
  const NotificationApiService(this.apiClient);

  final ApiClient apiClient;

  Future<NotificationPage> getNotifications({
    int page = 1,
    int pageSize = 20,
  }) async {
    final uri = apiClient.buildUri(
      ApiConstants.notificationsPath,
      queryParameters: {'page': '$page', 'pageSize': '$pageSize'},
    );
    final response = await _send(() => apiClient.get(uri));
    return _parsePage(response.body);
  }

  Future<int> getUnreadCount() async {
    final response = await _send(
      () => apiClient.get(
        apiClient.buildUri('${ApiConstants.notificationsPath}/unread-count'),
      ),
    );
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['unreadCount'] as int;
    } on FormatException {
      throw const NotificationApiException(
        'The notification service returned an invalid unread count.',
      );
    } on TypeError {
      throw const NotificationApiException(
        'The notification service returned an invalid unread count.',
      );
    }
  }

  Future<AppNotification> markAsRead(String id) async {
    final response = await _send(
      () => apiClient.patch(
        apiClient.buildUri('${ApiConstants.notificationsPath}/$id/read'),
      ),
    );
    return _parseNotification(response.body);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const NotificationApiException(
        'Unable to connect to the notification service.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NotificationApiException(
        response.statusCode == 404
            ? 'The notification is no longer available.'
            : 'The notification request failed. Please try again.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  NotificationPage _parsePage(String body) {
    try {
      return NotificationPage.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    } on FormatException catch (_) {
      throw const NotificationApiException(
        'The notification service returned an invalid response.',
      );
    } on TypeError catch (_) {
      throw const NotificationApiException(
        'The notification service returned an invalid response.',
      );
    }
  }

  AppNotification _parseNotification(String body) {
    try {
      return AppNotification.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } on FormatException catch (_) {
      throw const NotificationApiException(
        'The notification service returned an invalid response.',
      );
    } on TypeError catch (_) {
      throw const NotificationApiException(
        'The notification service returned an invalid response.',
      );
    }
  }
}

class NotificationApiException implements Exception {
  const NotificationApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
