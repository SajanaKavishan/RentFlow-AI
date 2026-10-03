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
  'canCancel': status == 0 || status == 1,
  'cancellationDeadline': status == 1 ? '2030-01-02T05:00:00Z' : null,
  'tenantMessage': tenantMessage,
  'landlordResponse': landlordResponse,
  'createdAt': '2026-09-14T10:00:00Z',
  'updatedAt': updatedAt,
};

Map<String, dynamic> _propertyJson(String id) => {
  'id': id,
  'landlordId': 'landlord',
  'title': id == '33333333-3333-3333-3333-333333333333'
      ? 'Orchard House'
      : 'Harbour View Residence',
  'description': 'A real property returned by the API.',
  'address': 'Kureepoththa, Pothuhera',
  'city': 'Kurunegala',
  'monthlyRent': 100000,
  'bedrooms': 2,
  'bathrooms': 1,
  'isAvailable': true,
  'createdAt': '2026-09-14T10:00:00Z',
  'updatedAt': null,
  'amenities': <String>[],
};

Future<void> _pumpScreen(
  WidgetTester tester,
  Future<http.Response> Function(http.Request request) handler, {
  double textScale = 1,
  bool resolveProperties = true,
}) async {
  final apiClient = ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient((request) {
      if (resolveProperties &&
          request.url.path.startsWith('/api/properties/')) {
        return Future.value(
          http.Response(
            jsonEncode(_propertyJson(request.url.pathSegments.last)),
            200,
          ),
        );
      }
      return handler(request);
    }),
    tokenStorage: _MemoryTokenStorage(),
  );
  addTearDown(apiClient.close);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: MyViewingsScreen(viewingApiService: ViewingApiService(apiClient)),
    ),
  );
}

void main() {
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('compact cards fit ${width.toInt()}px at ${scale}x text', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.reset);
        await _pumpScreen(
          tester,
          (_) async => http.Response(
            jsonEncode([
              _viewingJson(
                id: 'pending',
                propertyId: 'property',
                status: 0,
                tenantMessage:
                    'Could I see the outdoor space during the viewing?',
              ),
              _viewingJson(
                id: 'approved',
                propertyId: 'property',
                status: 1,
                landlordResponse:
                    'Your viewing is confirmed. Please meet at reception.',
              ),
            ]),
            200,
          ),
          textScale: scale,
        );
        await tester.pumpAndSettle();
        expect(find.text('Pending requests appear first.'), findsOneWidget);
        expect(
          find.text('Could I see the outdoor space during the viewing?'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Your viewing is confirmed. Please meet at reception.'),
          200,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'property lookups are shared by viewings and failure preserves the schedule',
    (tester) async {
      var propertyCalls = 0;
      await _pumpScreen(tester, (request) async {
        if (request.url.path.startsWith('/api/properties/')) {
          propertyCalls++;
          return http.Response('{}', 404);
        }
        return http.Response(
          jsonEncode([
            _viewingJson(id: 'pending', propertyId: 'same-property', status: 0),
            _viewingJson(
              id: 'approved',
              propertyId: 'same-property',
              status: 1,
            ),
          ]),
          200,
        );
      }, resolveProperties: false);
      await tester.pumpAndSettle();
      expect(propertyCalls, 1);
      expect(find.text('Property details unavailable'), findsNWidgets(2));
      expect(find.text('same-property'), findsNothing);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Cancel request'), findsNWidgets(2));
      expect(find.byTooltip('View property'), findsNothing);
    },
  );

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

    expect(find.text('YOUR SCHEDULE'), findsOneWidget);
    expect(find.text('My viewings'), findsOneWidget);
    expect(find.text('Pending requests appear first.'), findsOneWidget);
    expect(find.text('PROPERTY VIEWING'), findsNothing);
    expect(
      find.byKey(const ValueKey('viewing-card-pending-viewing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('viewing-card-completed-viewing')),
      findsOneWidget,
    );
    expect(find.text('Date'), findsNothing);
    expect(find.text('Time'), findsNothing);
    expect(find.text('Property reference'), findsNothing);
    expect(find.text(pendingProperty), findsNothing);
    expect(find.text('Harbour View Residence'), findsOneWidget);
    expect(find.text('Kureepoththa, Pothuhera, Kurunegala'), findsNWidgets(2));
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('No message provided.'), findsNothing);
    expect(find.text('No response yet.'), findsNothing);
    expect(find.textContaining('Requested:'), findsNothing);
    expect(find.text('Cancel request'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Orchard House'), 300);
    await tester.pumpAndSettle();
    expect(find.text(completedProperty), findsNothing);
    expect(find.text('Orchard House'), findsOneWidget);
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
    expect(find.text('Cancel request'), findsNWidgets(2));
    expect(find.text('Afternoon works best.'), findsOneWidget);
    expect(find.text('Please arrive at 2 PM.'), findsOneWidget);
    expect(find.textContaining('Last updated '), findsNWidgets(4));
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
