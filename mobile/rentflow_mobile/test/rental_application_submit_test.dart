import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/my_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';

class _TokenStorage implements TokenStorage {
  @override
  Future<String?> readToken() async => 'submit-test-token';

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> deleteToken() async {}
}

const _applicationId = '33333333-3333-4333-8333-333333333333';

Map<String, dynamic> _applicationJson(int status) => {
  'id': _applicationId,
  'tenantId': '11111111-1111-4111-8111-111111111111',
  'propertyId': '22222222-2222-4222-8222-222222222222',
  'moveInDate': '2030-02-03',
  'monthlyIncome': 2500,
  'occupation': 'Engineer',
  'numberOfOccupants': 2,
  'tenantNote': null,
  'status': status,
  'landlordResponse': null,
  'createdAt': '2026-09-14T10:00:00Z',
  'submittedAt': status == 0 ? null : '2026-09-14T10:01:00Z',
  'updatedAt': status == 0 ? null : '2026-09-14T10:01:00Z',
};

Future<void> _pumpApplicationsScreen(
  WidgetTester tester,
  http.Client httpClient,
) async {
  final apiClient = ApiClient(
    baseUrl: 'http://test',
    httpClient: httpClient,
    tokenStorage: _TokenStorage(),
  );
  addTearDown(apiClient.close);
  await tester.pumpWidget(
    MaterialApp(
      home: MyRentalApplicationsScreen(
        rentalApplicationApiService: RentalApplicationApiService(apiClient),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _confirmSubmit(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  final confirmationButton = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, label),
  );
  expect(confirmationButton, findsOneWidget);
  await tester.tap(confirmationButton);
  await tester.pumpAndSettle();
}

void _expectSubmitRequest(http.Request request) {
  expect(request.method, 'PATCH');
  expect(request.url.path, '/api/rental-applications/$_applicationId/submit');
  expect(request.url.queryParameters, isEmpty);
  expect(request.headers['Authorization'], 'Bearer submit-test-token');
}

void main() {
  testWidgets(
    'empty-body submit is rejected instead of creating local success',
    (tester) async {
      var listCalls = 0;
      final client = MockClient((request) async {
        if (request.method == 'PATCH') {
          _expectSubmitRequest(request);
          return http.Response('', 200);
        }
        listCalls++;
        return http.Response(jsonEncode([_applicationJson(0)]), 200);
      });
      await _pumpApplicationsScreen(tester, client);

      await _confirmSubmit(tester, 'Submit application');

      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Submitted'), findsNothing);
      expect(
        find.text(
          'The rental application service returned an invalid response.',
        ),
        findsOneWidget,
      );
      expect(listCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful submit and failed refresh retain Submitted without submit error',
    (tester) async {
      var listCalls = 0;
      final client = MockClient((request) async {
        if (request.method == 'PATCH') {
          _expectSubmitRequest(request);
          return http.Response(jsonEncode(_applicationJson(1)), 200);
        }
        listCalls++;
        if (listCalls == 1) {
          return http.Response(jsonEncode([_applicationJson(0)]), 200);
        }
        return http.Response('{}', 500);
      });
      await _pumpApplicationsScreen(tester, client);

      await _confirmSubmit(tester, 'Submit application');

      expect(find.text('Submitted'), findsOneWidget);
      expect(
        find.text(
          'Application submitted, but your applications could not be refreshed.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Unable to submit'), findsNothing);
      expect(listCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('genuine submit conflict shows the API conflict message', (
    tester,
  ) async {
    var listCalls = 0;
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        _expectSubmitRequest(request);
        return http.Response(
          jsonEncode({'detail': 'The application cannot be submitted.'}),
          409,
        );
      }
      listCalls++;
      return http.Response(jsonEncode([_applicationJson(0)]), 200);
    });
    await _pumpApplicationsScreen(tester, client);

    await _confirmSubmit(tester, 'Submit application');

    expect(find.text('The application cannot be submitted.'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Submitted'), findsNothing);
    expect(listCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ChangesRequested application follows safe resubmit path', (
    tester,
  ) async {
    var listCalls = 0;
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        _expectSubmitRequest(request);
        return http.Response(jsonEncode(_applicationJson(1)), 200);
      }
      listCalls++;
      return http.Response(
        jsonEncode([_applicationJson(listCalls == 1 ? 3 : 1)]),
        200,
      );
    });
    await _pumpApplicationsScreen(tester, client);

    await _confirmSubmit(tester, 'Resubmit application');

    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Application resubmitted successfully.'), findsOneWidget);
    expect(find.textContaining('Unable to submit'), findsNothing);
    expect(listCalls, 2);
    expect(tester.takeException(), isNull);
  });
}
