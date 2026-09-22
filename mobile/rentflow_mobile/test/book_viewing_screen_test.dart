import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/viewings/screens/book_viewing_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => 'tenant-token';

  @override
  Future<void> saveToken(String value) async {}
}

const _propertyId = '22222222-2222-4222-8222-222222222222';

Future<void> _pumpBookViewing(
  WidgetTester tester, {
  required Future<http.Response> Function(http.Request request) handler,
  String propertyId = _propertyId,
}) async {
  final apiClient = ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient(handler),
    tokenStorage: _MemoryTokenStorage(),
  );
  addTearDown(apiClient.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: BookViewingScreen(
        propertyId: propertyId,
        viewingApiService: ViewingApiService(apiClient),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectFutureSchedule(WidgetTester tester) async {
  final now = DateTime.now();
  final tomorrow = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 1));

  await tester.ensureVisible(
    find.byKey(const ValueKey('viewing-date-selector')),
  );
  await tester.tap(find.byKey(const ValueKey('viewing-date-selector')));
  await tester.pumpAndSettle();
  if (tomorrow.month != now.month) {
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('${tomorrow.day}').last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  await tester.ensureVisible(
    find.byKey(const ValueKey('viewing-time-selector')),
  );
  await tester.tap(find.byKey(const ValueKey('viewing-time-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 390.0, 412.0, 430.0]) {
    testWidgets('booking form fits a $width logical pixel screen', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);

      await _pumpBookViewing(
        tester,
        handler: (_) async => throw StateError('No request expected.'),
      );

      expect(find.text('Selected property'), findsOneWidget);
      expect(find.text(_propertyId), findsWidgets);
      expect(
        find.textContaining('Property details are not available'),
        findsOneWidget,
      );
      expect(find.text('Date and time'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('confirm-viewing')));
      await tester.pumpAndSettle();
      expect(find.text('Booking summary'), findsOneWidget);
      expect(find.text('Confirm Viewing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing property is honest and cannot submit', (tester) async {
    await _pumpBookViewing(
      tester,
      propertyId: '',
      handler: (_) async => throw StateError('No request expected.'),
    );

    expect(find.text('Integration pending'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
    await tester.ensureVisible(find.byKey(const ValueKey('confirm-viewing')));
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-viewing')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('confirm requires a real date and time', (tester) async {
    await _pumpBookViewing(
      tester,
      handler: (_) async => throw StateError('No request expected.'),
    );

    await tester.ensureVisible(find.byKey(const ValueKey('confirm-viewing')));
    await tester.tap(find.byKey(const ValueKey('confirm-viewing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('book-viewing-error')), findsOneWidget);
    expect(find.text('Choose a date and time before booking.'), findsWidgets);
  });

  testWidgets('success appears only after an authoritative API response', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    Map<String, dynamic>? requestBody;
    await _pumpBookViewing(
      tester,
      handler: (request) {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return response.future;
      },
    );
    await _selectFutureSchedule(tester);
    await tester.enterText(
      find.byKey(const ValueKey('viewing-message')),
      'Please call when you arrive.',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('confirm-viewing')));
    await tester.tap(find.byKey(const ValueKey('confirm-viewing')));
    await tester.pump();

    expect(find.byKey(const ValueKey('viewing-submitting')), findsOneWidget);
    expect(find.textContaining('Viewing request created.'), findsNothing);
    expect(requestBody?['propertyId'], _propertyId);
    expect(requestBody?['tenantMessage'], 'Please call when you arrive.');

    response.complete(
      http.Response(
        jsonEncode({
          'id': '44444444-4444-4444-8444-444444444444',
          'tenantId': '11111111-1111-4111-8111-111111111111',
          'propertyId': _propertyId,
          'requestedDateTime': requestBody!['requestedDateTime'],
          'status': 0,
          'tenantMessage': requestBody!['tenantMessage'],
          'landlordResponse': null,
          'createdAt': '2026-09-18T10:00:00Z',
          'updatedAt': null,
        }),
        201,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Viewing request created. Status: Pending.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('viewing-submitting')), findsNothing);
  });

  testWidgets('API rejection stays an error and never shows success', (
    tester,
  ) async {
    await _pumpBookViewing(
      tester,
      handler: (_) async => http.Response(
        jsonEncode({'detail': 'That viewing time is unavailable.'}),
        409,
        headers: {'content-type': 'application/json'},
      ),
    );
    await _selectFutureSchedule(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('confirm-viewing')));
    await tester.tap(find.byKey(const ValueKey('confirm-viewing')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('book-viewing-error')), findsOneWidget);
    expect(find.text('That viewing time is unavailable.'), findsWidgets);
    expect(find.textContaining('Viewing request created.'), findsNothing);
  });
}
