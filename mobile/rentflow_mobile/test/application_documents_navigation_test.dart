import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/application_documents/screens/application_documents_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/my_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';

class _TokenStorage implements TokenStorage {
  @override
  Future<String?> readToken() async => 'navigation-test-token';

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> deleteToken() async {}
}

const _applicationIds = [
  '66666666-6666-4666-8666-666666666666',
  '99999999-9999-4999-8999-999999999999',
];

Map<String, dynamic> _applicationJson(String id) => {
  'id': id,
  'tenantId': '11111111-1111-4111-8111-111111111111',
  'propertyId': '22222222-2222-4222-8222-222222222222',
  'moveInDate': '2030-02-03',
  'monthlyIncome': 2500,
  'occupation': 'Engineer',
  'numberOfOccupants': 2,
  'tenantNote': null,
  'status': 0,
  'landlordResponse': null,
  'createdAt': '2026-09-14T10:00:00Z',
  'submittedAt': null,
  'updatedAt': null,
};

void main() {
  for (final selectedId in _applicationIds) {
    testWidgets(
      'My Applications passes selected ID $selectedId to Documents and GET',
      (tester) async {
        final requests = <http.Request>[];
        final apiClient = ApiClient(
          baseUrl: 'http://test',
          tokenStorage: _TokenStorage(),
          httpClient: MockClient((request) async {
            requests.add(request);
            final path = request.url.path;
            final Object body;
            if (path == '/api/rental-applications') {
              body = _applicationIds.map(_applicationJson).toList();
            } else if (path == '/api/rental-applications/$selectedId') {
              body = _applicationJson(selectedId);
            } else if (path ==
                '/api/rental-applications/$selectedId/documents') {
              body = [];
            } else {
              return http.Response('{}', 404);
            }
            return http.Response(jsonEncode(body), 200);
          }),
        );
        addTearDown(apiClient.close);
        final service = RentalApplicationApiService(apiClient);
        await tester.pumpWidget(
          MaterialApp(
            home: MyRentalApplicationsScreen(
              rentalApplicationApiService: service,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final documentsButton = find.byKey(
          ValueKey('application-documents-$selectedId'),
        );
        await tester.ensureVisible(documentsButton);
        await tester.pumpAndSettle();
        await tester.tap(documentsButton);
        await tester.pumpAndSettle();

        final screen = tester.widget<ApplicationDocumentsScreen>(
          find.byType(ApplicationDocumentsScreen),
        );
        expect(screen.applicationId, selectedId);
        expect(screen.rentalApplicationApiService, same(service));
        expect(
          screen.applicationDocumentApiService!.apiClient,
          same(apiClient),
        );
        expect(requests.map((request) => request.url.toString()), [
          'http://test/api/rental-applications',
          'http://test/api/rental-applications/$selectedId',
          'http://test/api/rental-applications/$selectedId/documents',
        ]);
        for (final request in requests) {
          expect(request.method, 'GET');
          expect(request.url.queryParameters, isEmpty);
          expect(
            request.headers['Authorization'],
            'Bearer navigation-test-token',
          );
        }
        expect(
          find.text('The requested resource is unavailable.'),
          findsNothing,
        );
        await tester.scrollUntilVisible(
          find.text('No documents uploaded'),
          200,
        );
        expect(find.text('No documents uploaded'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('detail 404 is displayed before requesting documents', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final selectedId = _applicationIds.last;
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: _TokenStorage(),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/rental-applications') {
          return http.Response(jsonEncode([_applicationJson(selectedId)]), 200);
        }
        return http.Response('{}', 404);
      }),
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
    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();

    expect(find.text('The requested resource is unavailable.'), findsOneWidget);
    expect(requests.map((request) => request.url.path), [
      '/api/rental-applications',
      '/api/rental-applications/$selectedId',
    ]);
    expect(tester.takeException(), isNull);
  });
}
