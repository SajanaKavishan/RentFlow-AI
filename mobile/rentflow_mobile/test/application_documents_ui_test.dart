import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/application_documents/screens/application_documents_screen.dart';
import 'package:rentflow_mobile/features/application_documents/services/application_document_api_service.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

class _TokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => 'documents-ui-token';

  @override
  Future<void> saveToken(String value) async {}
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
  'updatedAt': status == 0 ? null : '2026-09-15T11:30:00Z',
};

Map<String, dynamic> _documentJson(int type, String name, int size) => {
  'id': '55555555-5555-4555-8555-55555555555$type',
  'applicationId': _applicationId,
  'documentType': type,
  'originalFileName': name,
  'contentType': name.endsWith('.pdf') ? 'application/pdf' : 'image/png',
  'fileSizeBytes': size,
  'uploadedAt': '2026-09-14T10:01:00Z',
};

Future<void> _pumpDocuments(
  WidgetTester tester, {
  required double width,
  required int applicationStatus,
  required List<Map<String, dynamic>> documents,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  final apiClient = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: _TokenStorage(),
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/rental-applications/$_applicationId') {
        return http.Response(
          jsonEncode(_applicationJson(applicationStatus)),
          200,
        );
      }
      if (request.url.path ==
          '/api/rental-applications/$_applicationId/documents') {
        return http.Response(jsonEncode(documents), 200);
      }
      return http.Response('{}', 404);
    }),
  );
  addTearDown(apiClient.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: ApplicationDocumentsScreen(
        applicationId: _applicationId,
        applicationDocumentApiService: ApplicationDocumentApiService(apiClient),
        rentalApplicationApiService: RentalApplicationApiService(apiClient),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final allDocumentTypes = [
    _documentJson(0, 'identity.pdf', 1536),
    _documentJson(1, 'income.pdf', 2 * 1024 * 1024),
    _documentJson(2, 'employment.pdf', 3200),
    _documentJson(3, 'other.png', 980),
  ];

  for (final width in [360.0, 390.0, 412.0, 430.0]) {
    testWidgets('document UI fits ${width.toInt()}px with real metadata', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      await _pumpDocuments(
        tester,
        width: width,
        applicationStatus: 0,
        documents: allDocumentTypes,
      );

      expect(find.text('Required documents'), findsOneWidget);
      expect(find.text('0 Missing'), findsNothing);
      await tester.scrollUntilVisible(find.text('Document guide'), 300);
      expect(find.text('Required'), findsWidgets);
      expect(find.text('Recommended'), findsWidgets);
      expect(find.text('Optional'), findsWidgets);
      await tester.scrollUntilVisible(find.text('identity.pdf'), 300);
      expect(find.text('1.5 KB'), findsOneWidget);
      expect(find.text('View Document'), findsWidgets);
      expect(find.text('Delete'), findsWidgets);
      expect(find.textContaining('Uploaded '), findsWidgets);
      expect(find.textContaining('LangGraph'), findsNothing);
      expect(find.textContaining('workflow'), findsNothing);
      expect(find.text('Application check completed'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('submitted application is read only and reports missing files', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _pumpDocuments(
      tester,
      width: 360,
      applicationStatus: 1,
      documents: [_documentJson(0, 'identity.pdf', 1536)],
    );

    expect(find.text('Read Only'), findsWidgets);
    expect(find.text('1 Missing'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('View Document'), 300);
    expect(find.text('View Document'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    final uploadButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Upload document'),
    );
    expect(uploadButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
