import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';
import 'package:rentflow_mobile/features/notifications/services/notification_api_service.dart';
import 'package:rentflow_mobile/features/properties/services/property_api_service.dart';
import 'package:rentflow_mobile/features/properties/screens/property_matching_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/home/tenant_dashboard_data.dart';
import 'package:rentflow_mobile/shared/home/tenant_home.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'widget_test.dart' as fixtures;

Map<String, Object?> property(String id, {bool available = true}) => {
  'id': id,
  'landlordId': 'landlord',
  'title': 'A spacious home in $id',
  'description': 'A real property',
  'address': 'Main Street',
  'city': 'Colombo',
  'monthlyRent': 125000,
  'bedrooms': 2,
  'bathrooms': 1,
  'isAvailable': available,
  'createdAt': '2026-09-01T00:00:00Z',
  'amenities': [],
};
Map<String, Object?> match(String id, int? score) => {
  'propertyId': id,
  'title': 'Match $id',
  'city': 'Colombo',
  'monthlyRent': 125000,
  'bedrooms': 2,
  'bathrooms': 1,
  'amenities': [],
  'matchScore': score,
  'matchReasons': [],
};
ApiClient clientFor(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient(handler),
      tokenStorage: fixtures.MemoryTokenStorage('token'),
    );
http.Response ok(Object value) => http.Response(jsonEncode(value), 200);

void main() {
  test(
    'merges six real sources newest first and keeps maintenance and payments inert',
    () async {
      final client = clientFor((request) async {
        switch (request.url.path) {
          case '/api/notifications':
            return ok({
              'items': [
                {
                  'id': 'notification',
                  'eventType': 'document.reviewed',
                  'title': 'Income proof reviewed',
                  'message': 'Your document check is complete',
                  'createdAt': '2026-09-30T10:00:00Z',
                },
              ],
              'pagination': {},
            });
          case '/api/viewings':
            return ok([
              {
                'id': 'viewing',
                'tenantId': 'tenant',
                'propertyId': 'home',
                'status': 1,
                'requestedDateTime': '2026-10-03T10:00:00Z',
                'createdAt': '2026-09-29T10:00:00Z',
              },
            ]);
          case '/api/rental-applications':
            return ok([
              {
                'id': 'application',
                'tenantId': 'tenant',
                'propertyId': 'home',
                'status': 2,
                'moveInDate': '2026-10-01',
                'monthlyIncome': 250000,
                'occupation': 'Engineer',
                'numberOfOccupants': 1,
                'createdAt': '2026-09-28T10:00:00Z',
              },
            ]);
          case '/api/lease-agreements/mine':
            return ok([
              {
                'id': 'lease',
                'propertyId': 'home',
                'status': 1,
                'startDate': '2026-09-01',
                'endDate': '2027-09-01',
                'createdAt': '2026-09-27T10:00:00Z',
              },
            ]);
          case '/api/payments/mine':
            return ok([
              {
                'id': 'payment',
                'status': 1,
                'amount': 125000,
                'paidAt': '2026-09-26T10:00:00Z',
              },
            ]);
          case '/api/maintenance-requests/tenant/tenant':
            return ok([
              {
                'id': 'repair',
                'tenantId': 'tenant',
                'propertyId': 'home',
                'title': 'Leaking tap',
                'description': 'Kitchen tap',
                'category': 0,
                'priority': 1,
                'status': 8,
                'createdAt': '2026-09-25T10:00:00Z',
              },
            ]);
          case '/api/rent-schedules/lease/lease':
            return ok([]);
          case '/api/properties/home':
            return ok(property('home'));
        }
        return http.Response('', 404);
      });
      addTearDown(client.close);
      final data = await TenantDashboardService(client).load(
        tenantId: 'tenant',
        now: DateTime.utc(2026, 10, 1),
        viewings: ViewingApiService(client),
        applications: RentalApplicationApiService(client),
        notifications: NotificationApiService(client),
        maintenance: MaintenanceApiService(client),
        properties: PropertyApiService(client),
      );
      expect(data.failedSources, isEmpty);
      expect(data.activities.map((item) => item.title), [
        'Income proof reviewed',
        'Viewing confirmed',
        'Application under review',
        'Lease activated',
        'Payment received',
        'Repair in progress',
      ]);
      expect(data.activities.last.destination, isNull);
      expect(data.activities[4].destination, isNull);
      expect(data.journey!.title, 'Your application is being reviewed');
      expect(data.journey!.subtitle, 'A spacious home in home');
    },
  );

  test(
    'partial failure preserves successful sources and distinguishes unknown journey',
    () async {
      final client = clientFor(
        (request) async => request.url.path == '/api/payments/mine'
            ? ok([
                {
                  'status': 1,
                  'amount': 100000,
                  'paidAt': '2026-09-30T10:00:00Z',
                },
              ])
            : http.Response('', 500),
      );
      addTearDown(client.close);
      final data = await TenantDashboardService(client).load(
        tenantId: 'tenant',
        now: DateTime.utc(2026, 10, 1),
        applications: RentalApplicationApiService(client),
      );
      expect(data.activities.single.title, 'Payment received');
      expect(data.failedSources, containsAll(['leases', 'applications']));
      expect(data.journeyUnavailable, isTrue);
    },
  );

  test('only confirmed future viewings become the hero', () async {
    final client = clientFor(
      (request) async => ok(
        request.url.path == '/api/viewings'
            ? [
                for (final item in [
                  (1, '2026-09-01'),
                  (0, '2026-10-02'),
                  (1, '2026-10-04'),
                  (1, '2026-10-03'),
                ])
                  {
                    'id': item.$2,
                    'tenantId': 'tenant',
                    'propertyId': 'home',
                    'status': item.$1,
                    'requestedDateTime': '${item.$2}T10:00:00Z',
                    'createdAt': '2026-09-29T10:00:00Z',
                  },
              ]
            : [],
      ),
    );
    addTearDown(client.close);
    final data = await TenantDashboardService(client).load(
      tenantId: 'tenant',
      now: DateTime.utc(2026, 10, 1),
      viewings: ViewingApiService(client),
    );
    expect(data.journey!.status, 'Upcoming');
    expect(data.journey!.helper, contains('Oct 3, 2026'));
  });

  test('active lease uses the earliest outstanding rent schedule', () async {
    final client = clientFor((request) async {
      if (request.url.path == '/api/lease-agreements/mine') {
        return ok([
          {
            'id': 'lease',
            'propertyId': 'home',
            'status': 1,
            'startDate': '2026-09-01',
            'endDate': '2027-09-01',
            'createdAt': '2026-09-27T10:00:00Z',
          },
        ]);
      }
      if (request.url.path.contains('/rent-schedules/')) {
        return ok([
          for (final item in [
            (0, '2026-11-01'),
            (1, '2026-09-01'),
            (2, '2026-10-01'),
          ])
            {
              'status': item.$1,
              'dueDate': item.$2,
              'amount': 125000,
              'createdAt': '2026-09-01T00:00:00Z',
            },
        ]);
      }
      return ok([]);
    });
    addTearDown(client.close);
    final data = await TenantDashboardService(
      client,
    ).load(tenantId: 'tenant', now: DateTime.utc(2026, 10, 1));
    expect(data.journey!.title, 'Lease is active');
    expect(data.journey!.helper, 'Next rent due Oct 1, 2026');
    expect(data.activities, hasLength(4));
  });

  test(
    'recommendations are sorted, deduplicated and filtered against current availability',
    () async {
      final client = clientFor((request) async {
        if (request.url.path.endsWith('/property-preferences')) {
          return ok({'isConfigured': true});
        }
        if (request.url.path.endsWith('/matches')) {
          return ok({
            'matches': [
              match('low', 30),
              match('unavailable', 99),
              match('high', 95),
              match('high', 95),
              match('broken', 94),
              match('medium', 80),
              match('last', null),
            ],
          });
        }
        final id = request.url.path.split('/').last;
        if (id == 'broken') return http.Response('', 500);
        return ok(property(id, available: id != 'unavailable'));
      });
      addTearDown(client.close);
      final data = await TenantDashboardService.recommendations(
        PropertyApiService(client),
      );
      expect(data.items.map((item) => item.property.id), [
        'high',
        'medium',
        'low',
      ]);
      expect(data.partialFailure, isTrue);
    },
  );

  test('unconfigured preferences do not request matches', () async {
    final paths = <String>[];
    final client = clientFor((request) async {
      paths.add(request.url.path);
      return ok({'isConfigured': false});
    });
    addTearDown(client.close);
    expect(
      (await TenantDashboardService.recommendations(
        PropertyApiService(client),
      )).configured,
      isFalse,
    );
    expect(paths, ['/api/tenant/property-preferences']);
  });

  testWidgets(
    'recommendation cards precede actions, use real scores, and fit enlarged text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final client = clientFor((request) async {
        if (request.url.path.endsWith('/property-preferences')) {
          return ok({'isConfigured': true});
        }
        if (request.url.path.endsWith('/matches')) {
          return ok({
            'matches': [match('home', 81), match('other', null)],
          });
        }
        if (request.url.path.endsWith('/images')) return ok([]);
        if (request.url.path.startsWith('/api/properties/')) {
          return ok(property(request.url.path.split('/').last));
        }
        return ok([]);
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: TenantHome(
              user: CurrentUser.fromJson(fixtures.userJson(UserRole.tenant)),
              propertyApiService: PropertyApiService(client),
              now: () => DateTime.utc(2026, 10, 1),
              onDestinationSelected: (_) {},
              onOpenViewings: () {},
              onOpenDocuments: () {},
              onOpenNotifications: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('81% match'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Recommended for You')).dy,
        lessThan(tester.getTopLeft(find.text('What would you like to do?')).dy),
      );
      await tester.ensureVisible(find.text('Documents'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('See all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.byType(PropertyMatchingScreen), findsOneWidget);
      expect(find.text('Match home'), findsOneWidget);
      expect(find.text('Match other'), findsOneWidget);
    },
  );

  testWidgets('confirmed viewing hero opens the viewing screen callback', (
    tester,
  ) async {
    final client = clientFor(
      (request) async => ok(
        request.url.path == '/api/viewings'
            ? [
                {
                  'id': 'viewing',
                  'tenantId': 'tenant',
                  'propertyId': 'home',
                  'status': 1,
                  'requestedDateTime': '2026-10-03T10:00:00Z',
                  'createdAt': '2026-09-29T10:00:00Z',
                },
              ]
            : [],
      ),
    );
    addTearDown(client.close);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: TenantHome(
            user: CurrentUser.fromJson(fixtures.userJson(UserRole.tenant)),
            viewingApiService: ViewingApiService(client),
            now: () => DateTime.utc(2026, 10, 1),
            onDestinationSelected: (_) =>
                fail('Viewings are outside the tenant bottom navigation.'),
            onOpenViewings: () => opened = true,
            onOpenDocuments: () {},
            onOpenNotifications: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viewing confirmed').first);
    expect(opened, isTrue);
  });
}
