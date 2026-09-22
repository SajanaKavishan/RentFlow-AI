import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/viewings/models/viewing.dart';
import 'package:rentflow_mobile/features/viewings/screens/landlord_viewing_request_details_screen.dart';
import 'package:rentflow_mobile/features/viewings/screens/landlord_viewing_requests_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

class _TokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => 'landlord-viewing-token';

  @override
  Future<void> saveToken(String value) async {}
}

const _propertyId = '22222222-2222-4222-8222-222222222222';
const _tenantId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _viewingJson(
  int status, {
  String id = '33333333-3333-4333-8333-333333333333',
  String propertyId = _propertyId,
  String tenantId = _tenantId,
  String? landlordResponse,
}) => {
  'id': id,
  'tenantId': tenantId,
  'propertyId': propertyId,
  'requestedDateTime': '2030-02-03T14:30:00Z',
  'status': status,
  'tenantMessage': 'Please confirm whether parking is available.',
  'landlordResponse': landlordResponse,
  'createdAt': '2026-09-14T10:00:00Z',
  'updatedAt': status == 0 ? null : '2026-09-15T11:30:00Z',
};

Viewing _viewing(int status) => Viewing.fromJson(_viewingJson(status));

ApiClient _apiClient(http.Client client) => ApiClient(
  baseUrl: 'http://test',
  tokenStorage: _TokenStorage(),
  httpClient: client,
);

Future<void> _pumpQueue(
  WidgetTester tester, {
  required double width,
  required http.Client client,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1600);
  final apiClient = _apiClient(client);
  addTearDown(apiClient.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: LandlordViewingRequestsScreen(
        propertyId: _propertyId,
        viewingApiService: ViewingApiService(apiClient),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetails(
  WidgetTester tester, {
  required http.Client client,
  Viewing? viewing,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 900);
  final apiClient = _apiClient(client);
  addTearDown(apiClient.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: LandlordViewingRequestDetailsScreen(
        viewing: viewing ?? _viewing(0),
        viewingApiService: ViewingApiService(apiClient),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final queue = [
    _viewingJson(
      1,
      id: '33333333-3333-4333-8333-333333333331',
      tenantId: '11111111-1111-4111-8111-111111111101',
    ),
    _viewingJson(
      2,
      id: '33333333-3333-4333-8333-333333333332',
      tenantId: '11111111-1111-4111-8111-111111111102',
      landlordResponse: 'The requested time is unavailable.',
    ),
    _viewingJson(
      0,
      id: '33333333-3333-4333-8333-333333333330',
      tenantId: '11111111-1111-4111-8111-111111111100',
    ),
  ];

  for (final width in [360.0, 390.0, 412.0, 430.0]) {
    testWidgets(
      'landlord queue fits ${width.toInt()}px and puts Pending first',
      (tester) async {
        addTearDown(tester.view.reset);
        await _pumpQueue(
          tester,
          width: width,
          client: MockClient((request) async {
            expect(request.url.path, '/api/viewings/property/$_propertyId');
            expect(
              request.headers['Authorization'],
              'Bearer landlord-viewing-token',
            );
            return http.Response(jsonEncode(queue), 200);
          }),
        );

        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('Approved'), findsOneWidget);
        expect(find.text('Rejected'), findsOneWidget);
        expect(find.text('Property reference'), findsNWidgets(3));
        expect(find.text('Tenant reference'), findsNWidgets(3));
        expect(
          find.text('Please confirm whether parking is available.'),
          findsNWidgets(3),
        );
        final pendingTop = tester
            .getTopLeft(
              find.byKey(
                const ValueKey(
                  'landlord-viewing-card-33333333-3333-4333-8333-333333333330',
                ),
              ),
            )
            .dy;
        final approvedTop = tester
            .getTopLeft(
              find.byKey(
                const ValueKey(
                  'landlord-viewing-card-33333333-3333-4333-8333-333333333331',
                ),
              ),
            )
            .dy;
        expect(pendingTop, lessThan(approvedTop));
        expect(find.textContaining('property name'), findsNothing);
        expect(find.textContaining('tenant name'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('queue error retries to the real empty state', (tester) async {
    addTearDown(tester.view.reset);
    var calls = 0;
    await _pumpQueue(
      tester,
      width: 390,
      client: MockClient((_) async {
        calls++;
        return calls == 1 ? http.Response('{}', 500) : http.Response('[]', 200);
      }),
    );

    expect(find.text('Something went wrong'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No viewing requests'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('approve waits for and uses the authoritative API response', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final response = Completer<http.Response>();
    late http.Request request;
    await _pumpDetails(
      tester,
      client: MockClient((incoming) {
        request = incoming;
        return response.future;
      }),
    );

    expect(find.text(_propertyId), findsOneWidget);
    expect(find.text(_tenantId), findsOneWidget);
    expect(
      find.text('Please confirm whether parking is available.'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('approve-viewing-request')),
    );
    await tester.tap(find.byKey(const ValueKey('approve-viewing-request')));
    await tester.pump();
    expect(find.text('Approving...'), findsOneWidget);
    expect(find.text('Viewing approved.'), findsNothing);

    response.complete(http.Response(jsonEncode(_viewingJson(1)), 200));
    await tester.pumpAndSettle();

    expect(request.method, 'PATCH');
    expect(
      request.url.path,
      '/api/viewings/33333333-3333-4333-8333-333333333333/approve',
    );
    expect(request.headers['Authorization'], 'Bearer landlord-viewing-token');
    expect(jsonDecode(request.body), {'status': 1, 'landlordResponse': null});
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Viewing approved.'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reject requires a response and reports API failure honestly', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    var requests = 0;
    await _pumpDetails(
      tester,
      client: MockClient((_) async {
        requests++;
        return http.Response(
          jsonEncode({'detail': 'This request was already updated.'}),
          409,
        );
      }),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('reject-viewing-request')),
    );
    await tester.tap(find.byKey(const ValueKey('reject-viewing-request')));
    await tester.pumpAndSettle();
    expect(
      find.text('Add a landlord response before rejecting this request.'),
      findsOneWidget,
    );
    expect(requests, 0);

    await tester.enterText(
      find.byKey(const ValueKey('landlord-viewing-response')),
      'The requested time is unavailable.',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('reject-viewing-request')),
    );
    await tester.tap(find.byKey(const ValueKey('reject-viewing-request')));
    await tester.pumpAndSettle();

    expect(find.text('This request was already updated.'), findsWidgets);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reject sends the required response and trusts API success', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    late http.Request request;
    await _pumpDetails(
      tester,
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode(
            _viewingJson(
              2,
              landlordResponse: 'The requested time is unavailable.',
            ),
          ),
          200,
        );
      }),
    );

    await tester.enterText(
      find.byKey(const ValueKey('landlord-viewing-response')),
      'The requested time is unavailable.',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('reject-viewing-request')),
    );
    await tester.tap(find.byKey(const ValueKey('reject-viewing-request')));
    await tester.pumpAndSettle();

    expect(request.method, 'PATCH');
    expect(
      request.url.path,
      '/api/viewings/33333333-3333-4333-8333-333333333333/reject',
    );
    expect(jsonDecode(request.body), {
      'status': 2,
      'landlordResponse': 'The requested time is unavailable.',
    });
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Viewing rejected.'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
