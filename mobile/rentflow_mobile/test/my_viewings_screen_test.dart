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
  String? updatedAt,
}) => {
  'id': id,
  'tenantId': '11111111-1111-1111-1111-111111111111',
  'propertyId': propertyId,
  'requestedDateTime': '2030-01-02T10:00:00Z',
  'status': status,
  'tenantMessage': tenantMessage,
  'landlordResponse': landlordResponse,
  'createdAt': '2026-09-14T10:00:00Z',
  'updatedAt': updatedAt,
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
            id: 'completed-viewing',
            propertyId: completedProperty,
            status: 4,
          ),
          _viewingJson(
            id: 'pending-viewing',
            propertyId: pendingProperty,
            status: 0,
          ),
        ]),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Viewing schedule'), findsOneWidget);
    expect(find.text('2 viewings'), findsOneWidget);
    expect(find.text('PROPERTY VIEWING'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('viewing-card-pending-viewing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewing-card-completed-viewing')),
      findsNothing,
    );
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Property reference'), findsOneWidget);
    expect(find.text(pendingProperty), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('No message provided.'), findsOneWidget);
    expect(find.text('No response yet.'), findsOneWidget);
    expect(find.textContaining('Requested:'), findsOneWidget);
    expect(find.text('Cancel viewing'), findsOneWidget);

    await tester.scrollUntilVisible(find.text(completedProperty), 500);
    await tester.pumpAndSettle();
    expect(find.text(completedProperty), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
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

  testWidgets('status badges and cancellation rules use real viewing data', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 3000);
    addTearDown(tester.view.reset);

    await _pumpScreen(
      tester,
      (_) async => http.Response(
        jsonEncode([
          _viewingJson(
            id: 'approved-viewing',
            propertyId: 'approved-property',
            status: 1,
            tenantMessage: 'Afternoon works best.',
            landlordResponse: 'Please arrive at 2 PM.',
            updatedAt: '2026-09-16T12:30:00Z',
          ),
          _viewingJson(
            id: 'rejected-viewing',
            propertyId: 'rejected-property',
            status: 2,
          ),
          _viewingJson(
            id: 'cancelled-viewing',
            propertyId: 'cancelled-property',
            status: 3,
          ),
          _viewingJson(
            id: 'pending-viewing',
            propertyId: 'pending-property',
            status: 0,
          ),
        ]),
        200,
      ),
    );
    await tester.pumpAndSettle();

    for (final status in ['Pending', 'Approved', 'Rejected', 'Cancelled']) {
      expect(find.text(status), findsOneWidget);
    }
    expect(find.text('Cancel viewing'), findsNWidgets(2));
    expect(find.text('Afternoon works best.'), findsOneWidget);
    expect(find.text('Please arrive at 2 PM.'), findsOneWidget);
    expect(find.textContaining('Last updated:'), findsOneWidget);
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('viewing-card-pending-viewing')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('viewing-card-approved-viewing')),
            )
            .dy,
      ),
    );
    expect(tester.takeException(), isNull);
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
