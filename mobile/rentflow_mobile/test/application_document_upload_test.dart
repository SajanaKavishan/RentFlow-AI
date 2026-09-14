import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/application_documents/screens/application_documents_screen.dart';
import 'package:rentflow_mobile/features/application_documents/services/application_document_api_service.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';

class _TokenStorage implements TokenStorage {
  @override
  Future<String?> readToken() async => 'upload-test-token';

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> deleteToken() async {}
}

const _applicationId = '33333333-3333-4333-8333-333333333333';
const _documentId = '55555555-5555-4555-8555-555555555555';

Map<String, dynamic> get _applicationJson => {
  'id': _applicationId,
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

Map<String, dynamic> get _documentJson => {
  'id': _documentId,
  'applicationId': _applicationId,
  'documentType': 0,
  'originalFileName': 'identity.pdf',
  'contentType': 'application/pdf',
  'fileSizeBytes': 3,
  'uploadedAt': '2026-09-14T10:01:00Z',
};

SelectedDocumentFile get _selectedFile => SelectedDocumentFile(
  name: 'identity.pdf',
  extension: 'pdf',
  size: 3,
  bytes: Uint8List.fromList([1, 2, 3]),
);

Future<void> _pumpDocumentsScreen(
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
      home: ApplicationDocumentsScreen(
        applicationId: _applicationId,
        applicationDocumentApiService: ApplicationDocumentApiService(apiClient),
        rentalApplicationApiService: RentalApplicationApiService(apiClient),
        documentPicker: () async => _selectedFile,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose file'));
  await tester.pumpAndSettle();
  expect(find.text('identity.pdf'), findsOneWidget);
}

void _expectAuthenticatedMultipart(http.Request request) {
  expect(
    request.url.path,
    '/api/rental-applications/$_applicationId/documents',
  );
  expect(request.url.queryParameters, isEmpty);
  expect(request.headers['Authorization'], 'Bearer upload-test-token');
  expect(request.headers['content-type'], startsWith('multipart/form-data;'));
}

void main() {
  testWidgets(
    'successful empty-body upload and successful refresh show no error',
    (tester) async {
      var documentListCalls = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          _expectAuthenticatedMultipart(request);
          return http.Response('', 201);
        }
        if (request.url.path == '/api/rental-applications/$_applicationId') {
          return http.Response(jsonEncode(_applicationJson), 200);
        }
        documentListCalls++;
        return http.Response(
          jsonEncode(documentListCalls == 1 ? [] : [_documentJson]),
          200,
        );
      });
      await _pumpDocumentsScreen(tester, client);

      await tester.tap(find.text('Upload document'));
      await tester.pumpAndSettle();

      expect(find.text('identity.pdf'), findsOneWidget);
      expect(find.textContaining('Unable to upload'), findsNothing);
      expect(find.textContaining('could not be refreshed'), findsNothing);
      expect(documentListCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful upload and failed list refresh keep document without upload error',
    (tester) async {
      var documentListCalls = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          _expectAuthenticatedMultipart(request);
          return http.Response(jsonEncode(_documentJson), 201);
        }
        if (request.url.path == '/api/rental-applications/$_applicationId') {
          return http.Response(jsonEncode(_applicationJson), 200);
        }
        documentListCalls++;
        if (documentListCalls == 1) return http.Response('[]', 200);
        return http.Response('{}', 500);
      });
      await _pumpDocumentsScreen(tester, client);

      await tester.tap(find.text('Upload document'));
      await tester.pumpAndSettle();

      expect(find.text('identity.pdf'), findsOneWidget);
      expect(
        find.text(
          'Document uploaded, but the document list could not be refreshed.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Unable to upload'), findsNothing);
      expect(documentListCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('genuine upload failure shows its API error', (tester) async {
    var documentListCalls = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        _expectAuthenticatedMultipart(request);
        return http.Response(
          jsonEncode({'detail': 'Documents cannot be changed right now.'}),
          409,
        );
      }
      if (request.url.path == '/api/rental-applications/$_applicationId') {
        return http.Response(jsonEncode(_applicationJson), 200);
      }
      documentListCalls++;
      return http.Response('[]', 200);
    });
    await _pumpDocumentsScreen(tester, client);

    await tester.tap(find.text('Upload document'));
    await tester.pumpAndSettle();

    expect(find.text('Documents cannot be changed right now.'), findsOneWidget);
    expect(find.text('identity.pdf'), findsOneWidget);
    expect(documentListCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
