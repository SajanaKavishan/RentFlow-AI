import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/notifications/screens/notifications_screen.dart';
import 'package:rentflow_mobile/features/notifications/services/notification_api_service.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_details_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/viewings/screens/landlord_viewing_request_details_screen.dart';
import 'package:rentflow_mobile/features/viewings/screens/my_viewings_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
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

  testWidgets('tenant application notification opens application details', (
    tester,
  ) async {
    final apiClient = _clientForNotification(
      notification: _notificationJson(
        eventType: 'rental_application.approved',
        resourceType: 'RentalApplication',
        resourceId: 'application-1',
      ),
      resourceResponse: _applicationJson,
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(_screen(apiClient));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewing approved'));
    await tester.pumpAndSettle();

    expect(find.byType(RentalApplicationDetailsScreen), findsOneWidget);
  });

  testWidgets('tenant viewing notification opens My Viewings fallback', (
    tester,
  ) async {
    final apiClient = _clientForNotification(
      notification: _notificationJson(
        eventType: 'viewing.approved',
        resourceType: 'ViewingRequest',
        resourceId: 'viewing-1',
      ),
      resourceResponse: [],
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(_screen(apiClient));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewing approved'));
    await tester.pumpAndSettle();

    expect(find.byType(MyViewingsScreen), findsOneWidget);
  });

  testWidgets('landlord viewing notification opens authorized detail', (
    tester,
  ) async {
    final apiClient = _clientForNotification(
      notification: _notificationJson(
        eventType: 'viewing.created',
        resourceType: 'ViewingRequest',
        resourceId: 'viewing-1',
      ),
      resourceResponse: _viewingJson,
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(_screen(apiClient, role: UserRole.landlord));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewing approved'));
    await tester.pumpAndSettle();

    expect(find.byType(LandlordViewingRequestDetailsScreen), findsOneWidget);
  });

  testWidgets('unsupported notification is reported without resource access', (
    tester,
  ) async {
    var resourceCalls = 0;
    final apiClient = _clientForNotification(
      notification: _notificationJson(
        eventType: 'unknown.event',
        resourceType: 'UnknownResource',
        resourceId: 'resource-1',
      ),
      resourceResponse: null,
      onResource: () => resourceCalls++,
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(_screen(apiClient));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewing approved'));
    await tester.pumpAndSettle();

    expect(resourceCalls, 0);
    expect(
      find.text('This notification does not have a supported destination.'),
      findsOneWidget,
    );
  });

  testWidgets('inaccessible resource shows an API error without navigation', (
    tester,
  ) async {
    final apiClient = _clientForNotification(
      notification: _notificationJson(
        eventType: 'rental_application.approved',
        resourceType: 'RentalApplication',
        resourceId: 'missing-application',
      ),
      resourceStatus: 404,
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(_screen(apiClient));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewing approved'));
    await tester.pumpAndSettle();

    expect(find.text('The requested resource is unavailable.'), findsOneWidget);
    expect(find.byType(RentalApplicationDetailsScreen), findsNothing);
  });
}

Widget _screen(ApiClient apiClient, {UserRole role = UserRole.tenant}) =>
    MaterialApp(
      theme: AppTheme.build(),
      home: NotificationsScreen(
        notificationApiService: NotificationApiService(apiClient),
        userRole: role,
        viewingApiService: ViewingApiService(apiClient),
        rentalApplicationApiService: RentalApplicationApiService(apiClient),
      ),
    );

ApiClient _clientForNotification({
  required Map<String, dynamic> notification,
  Object? resourceResponse,
  int resourceStatus = 200,
  VoidCallback? onResource,
}) => ApiClient(
  baseUrl: 'http://test',
  tokenStorage: fixtures.MemoryTokenStorage('test-token'),
  httpClient: MockClient((request) async {
    if (request.method == 'PATCH') {
      return http.Response(jsonEncode({...notification, 'isRead': true}), 200);
    }
    if (request.url.path == '/api/notifications') {
      return http.Response(
        jsonEncode({
          'items': [notification],
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
    }
    onResource?.call();
    if (resourceResponse == null) return http.Response('{}', resourceStatus);
    return http.Response(jsonEncode(resourceResponse), resourceStatus);
  }),
);

Map<String, dynamic> _notificationJson({
  bool isRead = false,
  String eventType = 'viewing.approved',
  String resourceType = 'ViewingRequest',
  String resourceId = 'viewing-1',
}) => {
  'id': 'notification-1',
  'eventType': eventType,
  'relatedResourceType': resourceType,
  'relatedResourceId': resourceId,
  'title': 'Viewing approved',
  'message': 'Your viewing request was approved.',
  'createdAt': '2026-09-20T10:15:00Z',
  'readAt': isRead ? '2026-09-20T10:20:00Z' : null,
  'isRead': isRead,
};

Map<String, dynamic> get _viewingJson => {
  'id': 'viewing-1',
  'tenantId': 'tenant-1',
  'propertyId': 'property-1',
  'requestedDateTime': '2026-10-01T10:00:00Z',
  'status': 0,
  'tenantMessage': null,
  'landlordResponse': null,
  'createdAt': '2026-09-20T10:00:00Z',
  'updatedAt': null,
};

Map<String, dynamic> get _applicationJson => {
  'id': 'application-1',
  'tenantId': 'tenant-1',
  'propertyId': 'property-1',
  'moveInDate': '2026-10-01',
  'monthlyIncome': 2500,
  'occupation': 'Engineer',
  'numberOfOccupants': 2,
  'tenantNote': null,
  'status': 4,
  'landlordResponse': null,
  'createdAt': '2026-09-20T10:00:00Z',
  'submittedAt': '2026-09-20T10:00:00Z',
  'updatedAt': null,
};
