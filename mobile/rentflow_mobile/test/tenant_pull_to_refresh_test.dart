import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/maintenance/screens/my_maintenance_requests_screen.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';
import 'package:rentflow_mobile/features/properties/screens/property_list_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/my_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'tenant_maintenance_redesign_test.dart' show requestJson;
import 'widget_test.dart' as fixtures;

const _propertyId = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _applicationJson() => {
  'id': '33333333-3333-4333-8333-333333333333',
  'tenantId': '11111111-1111-1111-1111-111111111112',
  'propertyId': _propertyId,
  'moveInDate': '2026-11-01',
  'monthlyIncome': 2500,
  'occupation': 'Engineer',
  'numberOfOccupants': 2,
  'tenantNote': null,
  'status': 1,
  'landlordResponse': null,
  'createdAt': '2026-10-01T10:00:00Z',
  'submittedAt': '2026-10-01T10:01:00Z',
  'updatedAt': null,
};

Map<String, dynamic> _propertyJson() => {
  'id': _propertyId,
  'landlordId': '44444444-4444-4444-8444-444444444444',
  'title': 'Refresh test home',
  'description': 'A property from the existing service.',
  'address': '12 Test Street',
  'city': 'Colombo',
  'monthlyRent': 100000,
  'bedrooms': 2,
  'bathrooms': 1,
  'isAvailable': true,
  'createdAt': '2026-09-01T00:00:00Z',
  'updatedAt': null,
  'amenities': <String>[],
};

Future<void> _mount(
  WidgetTester tester, {
  required bool maintenance,
  required Future<http.Response> Function(http.Request) handler,
  double textScale = 1,
}) async {
  final storage = fixtures.MemoryTokenStorage('token');
  final auth = fixtures.buildController(storage);
  await auth.restoreSession();
  addTearDown(auth.dispose);
  final client = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: storage,
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/properties/$_propertyId') {
        return http.Response(jsonEncode(_propertyJson()), 200);
      }
      return handler(request);
    }),
  );
  addTearDown(client.close);
  var selected = 0;
  await tester.pumpWidget(
    AuthScope(
      controller: auth,
      child: MaterialApp(
        theme: AppTheme.build(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: maintenance
                ? MyMaintenanceRequestsScreen(
                    maintenanceApiService: MaintenanceApiService(client),
                  )
                : MyRentalApplicationsScreen(
                    rentalApplicationApiService: RentalApplicationApiService(
                      client,
                    ),
                  ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (value) =>
                  setState(() => selected = value),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _verticalScrollable() => find
    .descendant(
      of: find.byType(RefreshIndicator),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;

Future<void> _pull(WidgetTester tester) async {
  await tester.drag(_verticalScrollable(), const Offset(0, 400));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  for (final maintenance in [true, false]) {
    final screen = maintenance ? 'Maintenance' : 'Applications';
    final root = maintenance
        ? '/api/maintenance-requests/tenant/11111111-1111-1111-1111-111111111112'
        : '/api/rental-applications';
    final loadedText = maintenance ? 'Existing request' : 'Refresh test home';
    final emptyText = maintenance
        ? 'No maintenance requests yet.'
        : 'No applications yet';
    final errorText = maintenance
        ? 'Could not load maintenance requests'
        : 'Could not load applications';
    final data = jsonEncode([
      maintenance ? requestJson(0, title: loadedText) : _applicationJson(),
    ]);

    for (final initial in ['loaded', 'empty', 'error']) {
      testWidgets(
        '$screen $initial supports a native pull and shares refresh',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var loads = 0;
          final refreshed = Completer<http.Response>();
          await _mount(
            tester,
            maintenance: maintenance,
            handler: (request) async {
              if (request.url.path != root) return http.Response('[]', 200);
              loads++;
              if (loads > 1) return refreshed.future;
              return http.Response(
                initial == 'loaded'
                    ? data
                    : initial == 'empty'
                    ? '[]'
                    : '{}',
                initial == 'error' ? 500 : 200,
              );
            },
          );
          final confirmedText = initial == 'loaded'
              ? loadedText
              : initial == 'empty'
              ? emptyText
              : errorText;
          expect(find.text(confirmedText), findsOneWidget);
          expect(find.text('Refresh'), findsNothing);
          if (!maintenance && initial == 'empty') {
            expect(find.text('Browse properties'), findsOneWidget);
          }

          await _pull(tester);
          expect(loads, 2);
          expect(find.text(confirmedText), findsOneWidget);
          expect(find.byType(RefreshProgressIndicator), findsOneWidget);
          expect(
            find.byKey(const ValueKey('applications-loading')),
            findsNothing,
          );
          expect(
            find.bySemanticsLabel('Loading maintenance requests'),
            findsNothing,
          );
          final indicator = tester.widget<RefreshIndicator>(
            find.byType(RefreshIndicator),
          );
          final repeated = indicator.onRefresh();
          final repeatedAgain = indicator.onRefresh();
          expect(identical(repeated, repeatedAgain), isTrue);
          await tester.pump();
          expect(loads, 2);
          refreshed.complete(http.Response(data, 200));
          await repeated;
          await tester.pumpAndSettle();
          expect(find.text(loadedText), findsOneWidget);
          expect(loads, 2);
          await tester.tap(find.text('Profile'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            1,
          );
          expect(loads, 2);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('$screen explicit error retry reuses the list service', (
      tester,
    ) async {
      var loads = 0;
      await _mount(
        tester,
        maintenance: maintenance,
        handler: (request) async {
          if (request.url.path != root) return http.Response('[]', 200);
          loads++;
          return http.Response(
            loads == 1 ? '{}' : '[]',
            loads == 1 ? 500 : 200,
          );
        },
      );
      expect(find.text(errorText), findsOneWidget);
      await tester.tap(find.text(maintenance ? 'Retry' : 'Try again'));
      await tester.pumpAndSettle();
      expect(find.text(emptyText), findsOneWidget);
      expect(loads, 2);
      expect(find.text('Refresh'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final dimensions in [
      (const Size(320, 800), 1.0),
      (const Size(720, 1560), 2.0),
      (const Size(1080, 2340), 3.0),
    ]) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets(
          '$screen refresh at $dimensions and text scale $textScale',
          (tester) async {
            tester.view.physicalSize = dimensions.$1;
            tester.view.devicePixelRatio = dimensions.$2;
            addTearDown(tester.view.reset);
            var loads = 0;
            await _mount(
              tester,
              maintenance: maintenance,
              textScale: textScale,
              handler: (request) async {
                if (request.url.path == root) loads++;
                return http.Response('[]', 200);
              },
            );
            await _pull(tester);
            await tester.pumpAndSettle();
            expect(loads, 2);
            expect(find.text(emptyText), findsOneWidget);
            expect(find.text('Refresh'), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('Applications empty state keeps Browse properties navigation', (
    tester,
  ) async {
    await _mount(
      tester,
      maintenance: false,
      handler: (_) async => http.Response('[]', 200),
    );
    await tester.tap(find.text('Browse properties'));
    await tester.pumpAndSettle();
    expect(find.byType(PropertyListScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('No applications yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
