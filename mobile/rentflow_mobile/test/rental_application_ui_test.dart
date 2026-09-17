import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/rental_applications/models/rental_application.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/my_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_details_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_form_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

class _TokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => 'application-ui-token';

  @override
  Future<void> saveToken(String value) async {}
}

String _dateOnly(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

Map<String, dynamic> _applicationJson(int status, {String? id}) => {
  'id': id ?? '33333333-3333-4333-8333-333333333333',
  'tenantId': '11111111-1111-4111-8111-111111111111',
  'propertyId': '22222222-2222-4222-8222-222222222222',
  'moveInDate': _dateOnly(DateTime.now().add(const Duration(days: 30))),
  'monthlyIncome': 2500,
  'occupation': 'Engineer',
  'numberOfOccupants': 2,
  'tenantNote': 'Quiet household.',
  'status': status,
  'landlordResponse': status == 3 ? 'Please update your income.' : null,
  'createdAt': '2026-09-14T10:00:00Z',
  'submittedAt': status == 0 ? null : '2026-09-14T10:01:00Z',
  'updatedAt': status == 0 ? null : '2026-09-15T11:30:00Z',
};

RentalApplication _application(int status) =>
    RentalApplication.fromJson(_applicationJson(status));

Future<ApiClient> _pump(
  WidgetTester tester, {
  required Widget Function(RentalApplicationApiService service) builder,
  required Future<http.Response> Function(http.Request request) handler,
}) async {
  final client = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: _TokenStorage(),
    httpClient: MockClient(handler),
  );
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: builder(RentalApplicationApiService(client)),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

void main() {
  testWidgets('all statuses render and action-required applications lead', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 7000);
    addTearDown(tester.view.reset);

    final statuses = [0, 1, 2, 4, 5, 6, 3];
    await _pump(
      tester,
      builder: (service) =>
          MyRentalApplicationsScreen(rentalApplicationApiService: service),
      handler: (_) async => http.Response(
        jsonEncode([
          for (final status in statuses)
            _applicationJson(
              status,
              id: '33333333-3333-4333-8333-33333333333$status',
            ),
        ]),
        200,
      ),
    );

    for (final label in [
      'Draft',
      'Submitted',
      'Under Review',
      'Changes Requested',
      'Approved',
      'Rejected',
      'Withdrawn',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('ACTION NEEDED'), findsOneWidget);
    expect(find.text('Please update your income.'), findsOneWidget);
    expect(find.textContaining('Created '), findsNWidgets(7));
    expect(find.textContaining('Submitted '), findsNWidgets(6));
    expect(find.textContaining('Updated '), findsNWidgets(6));
    expect(
      tester
          .getTopLeft(
            find.byKey(
              const ValueKey(
                'application-card-33333333-3333-4333-8333-333333333333',
              ),
            ),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey(
                  'application-card-33333333-3333-4333-8333-333333333330',
                ),
              ),
            )
            .dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('details show real timeline, documents, and permitted actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      builder: (service) => RentalApplicationDetailsScreen(
        application: _application(3),
        rentalApplicationApiService: service,
      ),
      handler: (request) async {
        if (request.url.path.endsWith('/documents')) {
          return http.Response(
            jsonEncode([
              {
                'id': '55555555-5555-4555-8555-555555555555',
                'applicationId': '33333333-3333-4333-8333-333333333333',
                'documentType': 0,
                'originalFileName': 'identity.pdf',
                'contentType': 'application/pdf',
                'fileSizeBytes': 128,
                'uploadedAt': '2026-09-15T10:00:00Z',
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
      },
    );

    expect(find.text('Action required'), findsOneWidget);
    expect(find.text('22222222-2222-4222-8222-222222222222'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Last updated'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1 document uploaded'), 500);
    expect(find.text('1 document uploaded'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Edit application'), 500);
    expect(find.text('Edit application'), findsOneWidget);
    expect(find.text('Resubmit application'), findsOneWidget);
    expect(find.text('Withdraw application'), findsOneWidget);
    expect(find.textContaining('AI validation'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ChangesRequested form updates before authoritative resubmit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.reset);
    final requests = <http.Request>[];

    await _pump(
      tester,
      builder: (service) => RentalApplicationFormScreen(
        propertyId: '22222222-2222-4222-8222-222222222222',
        application: _application(3),
        rentalApplicationApiService: service,
      ),
      handler: (request) async {
        requests.add(request);
        if (request.method == 'PUT') {
          return http.Response(jsonEncode(_applicationJson(3)), 200);
        }
        if (request.method == 'PATCH') {
          return http.Response(jsonEncode(_applicationJson(1)), 200);
        }
        return http.Response('{}', 404);
      },
    );

    expect(find.text('Personal'), findsWidgets);
    expect(find.text('Please update your income.'), findsOneWidget);
    for (final step in ['Employment/Financial', 'Documents']) {
      await tester.ensureVisible(
        find.byKey(const ValueKey('application-next-step')),
      );
      await tester.tap(find.byKey(const ValueKey('application-next-step')));
      await tester.pumpAndSettle();
      expect(find.text(step), findsWidgets);
    }
    await tester.ensureVisible(
      find.byKey(const ValueKey('application-next-step')),
    );
    await tester.tap(find.byKey(const ValueKey('application-next-step')));
    await tester.pumpAndSettle();
    expect(find.text('Review & Submit'), findsWidgets);

    await tester.ensureVisible(find.byKey(const ValueKey('save-application')));
    await tester.tap(find.byKey(const ValueKey('save-application')));
    await tester.pumpAndSettle();
    expect(requests.single.method, 'PUT');
    expect(find.text('Application changes saved.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('submit-application')),
    );
    await tester.tap(find.byKey(const ValueKey('submit-application')));
    await tester.pumpAndSettle();
    expect(requests.map((request) => request.method), ['PUT', 'PATCH']);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Application resubmitted successfully.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
