import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/application_documents/models/application_document.dart';
import 'package:rentflow_mobile/features/application_documents/services/application_document_api_service.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/features/viewings/screens/my_viewings_screen.dart';

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage(this.token);

  String? token;

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;
}

const _tenantId = '11111111-1111-1111-1111-111111111112';
const _propertyId = '22222222-2222-2222-2222-222222222222';
const _applicationId = '33333333-3333-3333-3333-333333333333';
const _viewingId = '44444444-4444-4444-4444-444444444444';
const _documentId = '55555555-5555-5555-5555-555555555555';

Map<String, dynamic> get _viewingJson => {
  'id': _viewingId,
  'tenantId': _tenantId,
  'propertyId': _propertyId,
  'requestedDateTime': '2030-01-02T10:00:00Z',
  'status': 0,
  'tenantMessage': null,
  'landlordResponse': null,
  'createdAt': '2026-09-14T10:00:00Z',
  'updatedAt': null,
};

Map<String, dynamic> get _applicationJson => {
  'id': _applicationId,
  'tenantId': _tenantId,
  'propertyId': _propertyId,
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

Map<String, dynamic> get _documentJson => {
  'id': _documentId,
  'applicationId': _applicationId,
  'documentType': 0,
  'originalFileName': 'identity.pdf',
  'contentType': 'application/pdf',
  'fileSizeBytes': 128,
  'uploadedAt': '2026-09-14T10:00:00Z',
};

void expectJwtOwnedRequest(http.BaseRequest request, String path) {
  expect(request.url.path, path);
  expect(request.url.queryParameters, isEmpty);
  expect(request.headers['Authorization'], 'Bearer test-token');
}

void main() {
  test('viewing list, create, and cancel use JWT-owned routes', () async {
    final requests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        request.method == 'GET' ? '[]' : jsonEncode(_viewingJson),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      httpClient: client,
      tokenStorage: _MemoryTokenStorage('test-token'),
    );
    final service = ViewingApiService(apiClient);

    await service.getMyViewings();
    await service.createViewing(
      propertyId: _propertyId,
      requestedDateTime: DateTime.utc(2030, 1, 2, 10),
    );
    await service.cancelViewing(id: _viewingId);

    expect(requests.map((request) => request.method), ['GET', 'POST', 'PATCH']);
    expectJwtOwnedRequest(requests[0], '/api/viewings');
    expectJwtOwnedRequest(requests[1], '/api/viewings');
    expectJwtOwnedRequest(requests[2], '/api/viewings/$_viewingId/cancel');
  });

  test('viewing cancellation requires the API-confirmed resource', () async {
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        expectJwtOwnedRequest(request, '/api/viewings/$_viewingId/cancel');
        return http.Response('', 204);
      }),
      tokenStorage: _MemoryTokenStorage('test-token'),
    );

    await expectLater(
      ViewingApiService(apiClient).cancelViewing(id: _viewingId),
      throwsA(
        isA<ViewingApiException>().having(
          (error) => error.message,
          'message',
          'The viewing service returned an invalid response.',
        ),
      ),
    );
  });

  test('viewing cancellation still reports a 409 conflict', () async {
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': 'Only pending viewings can be cancelled.'}),
          409,
          headers: {'content-type': 'application/json'},
        ),
      ),
      tokenStorage: _MemoryTokenStorage('test-token'),
    );

    await expectLater(
      ViewingApiService(apiClient).cancelViewing(id: _viewingId),
      throwsA(
        isA<ViewingApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having(
              (error) => error.message,
              'message',
              'Only pending viewings can be cancelled.',
            ),
      ),
    );
  });

  testWidgets(
    'successful cancel stays cancelled when the post-cancel refresh fails',
    (tester) async {
      var listCalls = 0;
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          if (request.method == 'PATCH') {
            return http.Response(
              jsonEncode({
                ..._viewingJson,
                'status': 3,
                'updatedAt': '2026-09-14T10:05:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          listCalls++;
          if (listCalls > 1) {
            return http.Response(
              jsonEncode({'detail': 'Sensitive infrastructure failure.'}),
              500,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode([_viewingJson]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        tokenStorage: _MemoryTokenStorage('test-token'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MyViewingsScreen(
            viewingApiService: ViewingApiService(apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel viewing'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel viewing'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Viewing cancelled.'), findsOneWidget);
      expect(
        find.text('Unable to cancel the viewing right now. Please try again.'),
        findsNothing,
      );
    },
  );

  testWidgets('genuine cancel conflict shows its failure message', (
    tester,
  ) async {
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH') {
          return http.Response(
            jsonEncode({'detail': 'Only pending viewings can be cancelled.'}),
            409,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode([_viewingJson]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      tokenStorage: _MemoryTokenStorage('test-token'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MyViewingsScreen(viewingApiService: ViewingApiService(apiClient)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel viewing'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel viewing'));
    await tester.pumpAndSettle();

    expect(
      find.text('Only pending viewings can be cancelled.'),
      findsOneWidget,
    );
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Cancelled'), findsNothing);
  });

  test(
    'application tenant actions use resource IDs without tenantId',
    () async {
      final requests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          request.method == 'GET' ? '[]' : jsonEncode(_applicationJson),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        httpClient: client,
        tokenStorage: _MemoryTokenStorage('test-token'),
      );
      final service = RentalApplicationApiService(apiClient);

      await service.getMyApplications();
      await service.createApplication(
        propertyId: _propertyId,
        moveInDate: DateTime(2030, 2, 3),
        monthlyIncome: 2500,
        occupation: 'Engineer',
        numberOfOccupants: 2,
      );
      await service.updateApplication(
        id: _applicationId,
        moveInDate: DateTime(2030, 2, 3),
        monthlyIncome: 2600,
        occupation: 'Engineer',
        numberOfOccupants: 2,
      );
      await service.submitApplication(id: _applicationId);
      await service.withdrawApplication(id: _applicationId);

      expect(requests.map((request) => request.method), [
        'GET',
        'POST',
        'PUT',
        'PATCH',
        'PATCH',
      ]);
      expectJwtOwnedRequest(requests[0], '/api/rental-applications');
      expectJwtOwnedRequest(requests[1], '/api/rental-applications');
      expectJwtOwnedRequest(
        requests[2],
        '/api/rental-applications/$_applicationId',
      );
      expectJwtOwnedRequest(
        requests[3],
        '/api/rental-applications/$_applicationId/submit',
      );
      expectJwtOwnedRequest(
        requests[4],
        '/api/rental-applications/$_applicationId/withdraw',
      );
    },
  );

  test(
    'document operations omit tenantId and multipart keeps bearer token',
    () async {
      final requests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'DELETE') return http.Response('', 204);
        if (request.url.path.endsWith('/download')) {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://files.test/signed'},
          );
        }
        return http.Response(
          request.method == 'GET' ? '[]' : jsonEncode(_documentJson),
          request.method == 'POST' ? 201 : 200,
          headers: {'content-type': 'application/json'},
        );
      });
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        httpClient: client,
        tokenStorage: _MemoryTokenStorage('test-token'),
      );
      final service = ApplicationDocumentApiService(apiClient);

      await service.getDocumentsForApplication(applicationId: _applicationId);
      await service.uploadDocument(
        applicationId: _applicationId,
        documentType: ApplicationDocumentType.identityDocument,
        fileName: 'identity.pdf',
        contentType: 'application/pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      await service.deleteDocument(documentId: _documentId);
      final signedUrl = await service.requestDownloadUrl(
        documentId: _documentId,
      );

      expect(
        requests.every((request) => request.url.queryParameters.isEmpty),
        isTrue,
      );
      expect(
        requests.every(
          (request) => request.headers['Authorization'] == 'Bearer test-token',
        ),
        isTrue,
      );
      expect(
        requests[1].headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(signedUrl, Uri.parse('https://files.test/signed'));
    },
  );

  test('authenticated client clears the session once on 401', () async {
    final storage = _MemoryTokenStorage('expired-token');
    var unauthorizedCalls = 0;
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async => http.Response('{}', 401)),
      tokenStorage: storage,
    );
    apiClient.setUnauthorizedHandler(() => unauthorizedCalls++);

    await apiClient.get(apiClient.buildUri('/api/viewings'));

    expect(storage.token, isNull);
    expect(unauthorizedCalls, 1);
  });
}
