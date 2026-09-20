import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/notifications/services/notification_api_service.dart';

import 'widget_test.dart' as fixtures;

void main() {
  test('notification service uses authenticated paginated routes', () async {
    final requests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/unread-count')) {
        return http.Response(jsonEncode({'unreadCount': 2}), 200);
      }
      if (request.url.path.endsWith('/read')) {
        return http.Response(jsonEncode(_notificationJson(isRead: true)), 200);
      }
      return http.Response(
        jsonEncode({
          'items': [_notificationJson()],
          'pagination': {
            'page': 2,
            'pageSize': 10,
            'totalCount': 11,
            'totalPages': 2,
            'hasNextPage': false,
            'hasPreviousPage': true,
          },
        }),
        200,
      );
    });
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      httpClient: client,
      tokenStorage: fixtures.MemoryTokenStorage('test-token'),
    );
    addTearDown(apiClient.close);
    final service = NotificationApiService(apiClient);

    final page = await service.getNotifications(page: 2, pageSize: 10);
    final count = await service.getUnreadCount();
    final read = await service.markAsRead('notification-1');

    expect(page.pagination.page, 2);
    expect(page.items.single.title, 'Viewing approved');
    expect(count, 2);
    expect(read.isRead, isTrue);
    expect(requests[0].url.queryParameters, {'page': '2', 'pageSize': '10'});
    expect(requests[0].headers['Authorization'], 'Bearer test-token');
    expect(requests[1].url.path, '/api/notifications/unread-count');
    expect(requests[2].url.path, '/api/notifications/notification-1/read');
  });

  test('notification service exposes failed API responses', () async {
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async => http.Response('{}', 503)),
      tokenStorage: fixtures.MemoryTokenStorage('test-token'),
    );
    addTearDown(apiClient.close);

    await expectLater(
      NotificationApiService(apiClient).getUnreadCount(),
      throwsA(isA<NotificationApiException>()),
    );
  });
}

Map<String, dynamic> _notificationJson({bool isRead = false}) => {
  'id': 'notification-1',
  'eventType': 'viewing.approved',
  'relatedResourceType': 'ViewingRequest',
  'relatedResourceId': 'viewing-1',
  'title': 'Viewing approved',
  'message': 'Your viewing request was approved.',
  'createdAt': '2026-09-20T10:15:00Z',
  'readAt': isRead ? '2026-09-20T10:20:00Z' : null,
  'isRead': isRead,
};
