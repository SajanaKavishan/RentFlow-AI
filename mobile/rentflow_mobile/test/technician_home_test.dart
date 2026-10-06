import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';
import 'package:rentflow_mobile/features/notifications/services/notification_api_service.dart';
import 'package:rentflow_mobile/shared/shell/shared_app_shell.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'widget_test.dart' as fixtures;

void main() {
  testWidgets('technician home shows real counts and up to three active jobs', (
    tester,
  ) async {
    final jobs = [
      _job('active-1', 'Sink repair', 2, property: 'Garden House'),
      _job('active-2', 'Air conditioner', 8, property: 'City Apartment'),
      _job('active-3', 'Door lock', 6),
      _job('active-4', 'Fuse box', 3),
      _job(
        'completed',
        'Completed job',
        9,
        completedAt: DateTime.now().toUtc().toIso8601String(),
      ),
      _job('rejected', 'Rejected job', 7),
      _job('cancelled', 'Cancelled job', 10),
    ];
    final harness = await _pumpShell(tester, jobs: jobs, unreadCount: 4);
    addTearDown(harness.dispose);

    expect(find.text('Welcome, Casey Technician'), findsOneWidget);
    expect(find.text('You have 4 active jobs'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Completed this week'), findsOneWidget);
    expect(find.text('Garden House'), findsOneWidget);
    expect(find.text('City Apartment'), findsOneWidget);
    expect(find.text('Fuse box'), findsNothing);
    expect(find.text('Completed job'), findsNothing);
    expect(find.text('Workspace'), findsNothing);
    expect(find.byTooltip('Open profile'), findsNothing);
    expect(find.text('Open job'), findsNWidgets(3));
  });

  testWidgets(
    'technician notification bell uses unread count and opens inbox',
    (tester) async {
      final harness = await _pumpShell(tester, jobs: const [], unreadCount: 4);
      addTearDown(harness.dispose);

      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsWidgets);
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(harness.notificationLoads, 1);
    },
  );
}

Future<_Harness> _pumpShell(
  WidgetTester tester, {
  required List<Map<String, dynamic>> jobs,
  required int unreadCount,
}) async {
  final storage = fixtures.MemoryTokenStorage('token');
  final controller = fixtures.buildController(
    storage,
    role: UserRole.maintenanceTechnician,
  );
  await controller.restoreSession();
  var notificationLoads = 0;
  final client = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: storage,
    httpClient: MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/maintenance-requests/technician/')) {
        return http.Response(jsonEncode(jobs), 200);
      }
      if (path.endsWith('/notifications/unread-count')) {
        return http.Response(jsonEncode({'unreadCount': unreadCount}), 200);
      }
      if (path == '/api/notifications') {
        notificationLoads++;
        return http.Response(
          jsonEncode({
            'items': <Object>[],
            'pagination': {
              'page': 1,
              'pageSize': 20,
              'totalCount': 0,
              'totalPages': 0,
              'hasNextPage': false,
              'hasPreviousPage': false,
            },
          }),
          200,
        );
      }
      return http.Response('[]', 200);
    }),
  );
  final user = CurrentUser.fromJson({
    ...fixtures.userJson(UserRole.maintenanceTechnician),
    'fullName': 'Casey Technician',
  });
  await tester.pumpWidget(
    AuthScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: SharedAppShell(
          user: user,
          maintenanceApiService: MaintenanceApiService(client),
          notificationApiService: NotificationApiService(client),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(
    client: client,
    controller: controller,
    notificationLoadsProvider: () => notificationLoads,
  );
}

Map<String, dynamic> _job(
  String id,
  String title,
  int status, {
  String? property,
  String? completedAt,
}) => {
  'id': id,
  'referenceCode':
      'MR-${id.hashCode.abs().toRadixString(36).toUpperCase().padLeft(6, '0').substring(0, 6)}',
  'propertyId': 'property-$id',
  'propertyTitle': property,
  'tenantId': 'tenant-1',
  'technicianId': '11111111-1111-1111-1111-111111111112',
  'title': title,
  'description': 'Job details',
  'category': 0,
  'priority': 1,
  'status': status,
  'tenantAccessNotes': null,
  'triageNotes': null,
  'assignmentNotes': null,
  'cancellationReason': null,
  'completedAt': completedAt,
  'createdAt': '2026-10-01T08:00:00Z',
  'updatedAt': null,
};

class _Harness {
  const _Harness({
    required this.client,
    required this.controller,
    required this.notificationLoadsProvider,
  });

  final ApiClient client;
  final AuthController controller;
  final int Function() notificationLoadsProvider;

  int get notificationLoads => notificationLoadsProvider();

  void dispose() {
    controller.dispose();
    client.close();
  }
}
