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

Map<String, dynamic> _propertyJson() => {
  'id': '22222222-2222-4222-8222-222222222222',
  'landlordId': '44444444-4444-4444-8444-444444444444',
  'title': 'Maple Mews',
  'description': 'A home from the property API.',
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

Future<ApiClient> _pump(
  WidgetTester tester, {
  required Widget Function(RentalApplicationApiService service) builder,
  required Future<http.Response> Function(http.Request request) handler,
}) async {
  final client = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: _TokenStorage(),
    httpClient: MockClient((request) async {
      if (request.url.path ==
          '/api/properties/22222222-2222-4222-8222-222222222222') {
        return http.Response(jsonEncode(_propertyJson()), 200);
      }
      return handler(request);
    }),
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
      'DRAFT',
      'SUBMITTED',
      'UNDER REVIEW',
      'ACTION REQUIRED',
      'APPROVED',
      'REJECTED',
      'WITHDRAWN',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('RENTAL JOURNEY'), findsOneWidget);
    expect(find.text('My applications'), findsOneWidget);
    expect(find.text('Maple Mews'), findsNWidgets(7));
    expect(find.text('Please update your income.'), findsOneWidget);
    expect(find.textContaining('Created '), findsNWidgets(7));
    expect(find.textContaining('Submitted '), findsNWidgets(6));
    expect(find.textContaining('Updated '), findsNWidgets(5));
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
        if (request.url.path ==
            '/api/rental-applications/33333333-3333-4333-8333-333333333333') {
          return http.Response(jsonEncode(_applicationJson(3)), 200);
        }
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

    expect(find.text('ACTION REQUIRED'), findsOneWidget);
    expect(find.text('Maple Mews'), findsOneWidget);
    expect(find.text('22222222-2222-4222-8222-222222222222'), findsNothing);
    expect(find.text('Application created'), findsOneWidget);
    expect(find.text('Application submitted'), findsOneWidget);
    expect(find.text('Last updated'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1 document uploaded'), 500);
    expect(find.text('1 document uploaded'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Resubmit application'), 500);
    expect(find.text('Continue application'), findsOneWidget);
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
    var status = 3;

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
          status = 1;
          return http.Response(jsonEncode(_applicationJson(1)), 200);
        }
        if (request.url.path.endsWith('/documents')) {
          return http.Response(
            jsonEncode([
              for (final type in [0, 1])
                {
                  'id': 'document-$type',
                  'applicationId': '33333333-3333-4333-8333-333333333333',
                  'documentType': type,
                  'originalFileName': 'document-$type.pdf',
                  'contentType': 'application/pdf',
                  'fileSizeBytes': 128,
                  'uploadedAt': '2026-09-15T10:00:00Z',
                },
            ]),
            200,
          );
        }
        if (request.url.path ==
            '/api/rental-applications/33333333-3333-4333-8333-333333333333') {
          return http.Response(jsonEncode(_applicationJson(status)), 200);
        }
        return http.Response('{}', 404);
      },
    );

    expect(find.text('Personal'), findsWidgets);
    expect(find.text('Please update your income.'), findsOneWidget);
    for (final step in ['Financial information', 'Documents information']) {
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
    expect(find.text('Review information'), findsOneWidget);
    expect(requests.where((request) => request.method == 'PUT'), hasLength(2));
    await tester.ensureVisible(
      find.byKey(const ValueKey('submit-application')),
    );
    await tester.tap(find.byKey(const ValueKey('submit-application')));
    await tester.pumpAndSettle();
    expect(
      requests
          .where((request) => request.method != 'GET')
          .map((request) => request.method),
      ['PUT', 'PUT', 'PUT', 'PATCH'],
    );
    expect(find.byType(RentalApplicationDetailsScreen), findsOneWidget);
    expect(find.text('SUBMITTED'), findsOneWidget);
    expect(find.text('Continue application'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
