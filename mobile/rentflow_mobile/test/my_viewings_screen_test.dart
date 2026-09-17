import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/viewings/screens/my_viewings_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

class _MemoryTokenStorage implements TokenStorage {
  String? token = 'tenant-token';

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;
}

Map<String, dynamic> _viewingJson({
  required String id,
  required String propertyId,
  required int status,
  String? tenantMessage,
  String? landlordResponse,
}) => {
  'id': id,
  'tenantId': '11111111-1111-1111-1111-111111111111',
  'propertyId': propertyId,
  'requestedDateTime': '2030-01-02T10:00:00Z',
  'status': status,
  'tenantMessage': tenantMessage,
  'landlordResponse': landlordResponse,
  'createdAt': '2026-09-14T10:00:00Z',
  'updatedAt': null,
};

Future<void> _pumpScreen(
  WidgetTester tester,
  Future<http.Response> Function(http.Request request) handler,
) async {
  final apiClient = ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient(handler),
    tokenStorage: _MemoryTokenStorage(),
  );
  addTearDown(apiClient.close);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: MyViewingsScreen(viewingApiService: ViewingApiService(apiClient)),
    ),
  );
}

void main() {
  testWidgets('viewing cards prioritize schedule, property, and status', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    const pendingProperty = '22222222-2222-2222-2222-222222222222';
    const completedProperty = '33333333-3333-3333-3333-333333333333';
    await _pumpScreen(
      tester,
      (_) async => http.Response(
        jsonEncode([
          _viewingJson(
            id: 'pending-viewing',
            propertyId: pendingProperty,
            status: 0,
          ),
          _viewingJson(
            id: 'completed-viewing',
            propertyId: completedProperty,
            status: 4,
          ),
        ]),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Viewing schedule'), findsOneWidget);
    expect(find.text('2 viewings'), findsOneWidget);
    expect(find.text('VIEWING APPOINTMENT'), findsNWidgets(2));
    expect(find.text('Time'), findsNWidgets(2));
    expect(find.text('Property reference'), findsNWidgets(2));
    expect(find.text(pendingProperty), findsOneWidget);
    expect(find.text(completedProperty), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Cancel viewing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading transitions to the useful empty state', (tester) async {
    final response = Completer<http.Response>();
    await _pumpScreen(tester, (_) => response.future);
    await tester.pump();

    expect(find.text('Loading your viewings'), findsOneWidget);
    expect(find.text('Getting your latest viewing schedule.'), findsOneWidget);

    response.complete(http.Response('[]', 200));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('viewings-empty')), findsOneWidget);
    expect(find.text('No viewings yet'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets('error state retries through the existing API flow', (
    tester,
  ) async {
    var calls = 0;
    await _pumpScreen(tester, (_) async {
      calls++;
      return calls == 1 ? http.Response('{}', 500) : http.Response('[]', 200);
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('viewings-error')), findsOneWidget);
    expect(find.text('Could not load viewings'), findsOneWidget);
    expect(
      find.text('The viewing request failed. Please try again.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('No viewings yet'), findsOneWidget);
  });
}
