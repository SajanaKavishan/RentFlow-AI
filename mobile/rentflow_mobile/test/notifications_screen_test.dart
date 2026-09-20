import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/notifications/screens/notifications_screen.dart';
import 'package:rentflow_mobile/features/notifications/services/notification_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'widget_test.dart' as fixtures;

void main() {
  testWidgets(
    'notifications screen shows real states and confirmed read state',
    (tester) async {
      var markReadCalls = 0;
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: fixtures.MemoryTokenStorage('test-token'),
        httpClient: MockClient((request) async {
          if (request.method == 'PATCH') {
            markReadCalls++;
            return http.Response(
              jsonEncode(_notificationJson(isRead: true)),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [_notificationJson()],
              'pagination': {
                'page': 1,
                'pageSize': 20,
                'totalCount': 1,
                'totalPages': 1,
                'hasNextPage': false,
                'hasPreviousPage': false,
              },
            }),
            200,
          );
        }),
      );
      addTearDown(apiClient.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: NotificationsScreen(
            notificationApiService: NotificationApiService(apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Viewing approved'), findsOneWidget);
      expect(find.text('2026-09-20 15:45'), findsOneWidget);
      await tester.tap(find.text('Viewing approved'));
      await tester.pumpAndSettle();

      expect(markReadCalls, 1);
      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
      expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'notifications screen keeps unread state when mark-as-read fails',
    (tester) async {
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: fixtures.MemoryTokenStorage('test-token'),
        httpClient: MockClient((request) async {
          if (request.method == 'PATCH') return http.Response('{}', 500);
          return http.Response(
            jsonEncode({
              'items': [_notificationJson()],
              'pagination': {
                'page': 1,
                'pageSize': 20,
                'totalCount': 1,
                'totalPages': 1,
                'hasNextPage': false,
                'hasPreviousPage': false,
              },
            }),
            200,
          );
        }),
      );
      addTearDown(apiClient.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: NotificationsScreen(
            notificationApiService: NotificationApiService(apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viewing approved'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(
        find.text('The notification request failed. Please try again.'),
        findsOneWidget,
      );
    },
  );
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
