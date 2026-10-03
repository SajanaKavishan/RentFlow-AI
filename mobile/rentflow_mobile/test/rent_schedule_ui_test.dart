import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/rent_schedules/screens/lease_rent_schedule_screen.dart';
import 'package:rentflow_mobile/features/rent_schedules/services/rent_schedule_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

const _leaseId = '22222222-2222-4222-8222-222222222222';
const _pendingId = '11111111-1111-4111-8111-111111111111';
const _paidId = '33333333-3333-4333-8333-333333333333';
const _overdueId = '44444444-4444-4444-8444-444444444444';

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => 'rent-test-token';

  @override
  Future<void> saveToken(String value) async {}
}

Map<String, dynamic> _itemJson(String id, int status) => {
  'id': id,
  'leaseAgreementId': _leaseId,
  'dueDate': '2030-02-28',
  'amount': 1250.75,
  'status': status,
  'createdAt': '2030-01-15T09:00:00Z',
  'updatedAt': null,
};

Map<String, dynamic> _summaryJson({
  double pending = 1250.75,
  double overdue = 0,
  double total = 1250.75,
  List<dynamic>? items,
}) => {
  'totalPending': pending,
  'totalOverdue': overdue,
  'totalOutstanding': total,
  'items': items ?? [_itemJson(_pendingId, 0)],
};

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient(handler),
      tokenStorage: _MemoryTokenStorage(),
    );

Future<void> _show(WidgetTester tester, RentScheduleApiService service) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: LeaseRentScheduleScreen(
        rentScheduleApiService: service,
        leaseAgreementId: _leaseId,
      ),
    ),
  );
}

void main() {
  testWidgets('shows loading while both lease requests are pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    final client = _client((request) async {
      await pending.future;
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/outstanding')
              ? _summaryJson()
              : [_itemJson(_pendingId, 0)],
        ),
        200,
      );
    });
    addTearDown(client.close);
    await _show(tester, RentScheduleApiService(client));
    await tester.pump();
    expect(find.text('Loading rent schedule'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('shows items, summary totals, timestamps, and bearer requests', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = _client((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/outstanding')) {
        return http.Response(jsonEncode(_summaryJson()), 200);
      }
      return http.Response(jsonEncode([_itemJson(_pendingId, 0)]), 200);
    });
    addTearDown(client.close);
    await _show(tester, RentScheduleApiService(client));
    await tester.pumpAndSettle();

    expect(find.text('Outstanding summary'), findsOneWidget);
    expect(find.text('Pending'), findsNWidgets(2));
    expect(find.text('Due date'), findsOneWidget);
    expect(find.text('2030-02-28'), findsOneWidget);
    expect(find.text('Rs. 1,250.75'), findsNWidgets(3));
    expect(requests.map((request) => request.url.path), [
      '/api/rent-schedules/lease/$_leaseId',
      '/api/rent-schedules/lease/$_leaseId/outstanding',
    ]);
    expect(
      requests.every(
        (request) =>
            request.headers['Authorization'] == 'Bearer rent-test-token',
      ),
      isTrue,
    );
  });

  testWidgets(
    'renders Pending, Paid, Overdue and action only for unpaid items',
    (tester) async {
      final client = _client((request) async {
        final items = [
          _itemJson(_pendingId, 0),
          _itemJson(_paidId, 1),
          _itemJson(_overdueId, 2),
        ];
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/outstanding')
                ? _summaryJson(items: [items[0], items[2]])
                : items,
          ),
          200,
        );
      });
      addTearDown(client.close);
      await _show(tester, RentScheduleApiService(client));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsNWidgets(2));
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Overdue'), findsNWidgets(2));
      expect(
        find.byKey(ValueKey('rent-payment-placeholder-$_pendingId')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('rent-payment-placeholder-$_overdueId')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('rent-payment-placeholder-$_paidId')),
        findsNothing,
      );
    },
  );

  testWidgets('shows clean zero totals and lists paid items normally', (
    tester,
  ) async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/outstanding')
              ? _summaryJson(pending: 0, overdue: 0, total: 0, items: const [])
              : [_itemJson(_paidId, 1)],
        ),
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, RentScheduleApiService(client));
    await tester.pumpAndSettle();
    expect(find.text('Rs. 0.00'), findsNWidgets(3));
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('No rent schedule items'), findsNothing);
    expect(
      find.byKey(ValueKey('rent-payment-placeholder-$_paidId')),
      findsNothing,
    );
  });

  testWidgets('shows empty state when a lease has no schedule items', (
    tester,
  ) async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/outstanding')
              ? _summaryJson(pending: 0, overdue: 0, total: 0, items: const [])
              : [],
        ),
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, RentScheduleApiService(client));
    await tester.pumpAndSettle();
    expect(find.text('No rent schedule items'), findsOneWidget);
    expect(find.text('Rs. 0.00'), findsNWidgets(3));
  });

  for (final (status, message) in [
    (403, 'You do not have permission to access this resource.'),
    (404, 'The requested rent schedule is unavailable.'),
    (503, 'The rent schedule request failed. Please try again.'),
  ]) {
    testWidgets('shows safe retryable state for HTTP $status', (tester) async {
      var first = true;
      final client = _client((request) async {
        if (first) {
          first = false;
          return http.Response('secret backend details', status);
        }
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/outstanding')
                ? _summaryJson()
                : [_itemJson(_pendingId, 0)],
          ),
          200,
        );
      });
      addTearDown(client.close);
      await _show(tester, RentScheduleApiService(client));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('secret backend'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });
  }

  testWidgets('shows safe state for connection errors and retry recovers', (
    tester,
  ) async {
    var shouldFail = true;
    final client = _client((request) async {
      if (shouldFail) {
        shouldFail = false;
        throw http.ClientException('private socket detail');
      }
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/outstanding')
              ? _summaryJson()
              : [_itemJson(_pendingId, 0)],
        ),
        200,
      );
    });
    addTearDown(client.close);
    await _show(tester, RentScheduleApiService(client));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to connect to the rent schedule service.'),
      findsOneWidget,
    );
    expect(find.textContaining('private socket'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule items'), findsOneWidget);
  });

  testWidgets('malformed responses show a safe error state', (tester) async {
    final client = _client(
      (request) async => http.Response(
        request.url.path.endsWith('/outstanding') ? '{' : '[{}]',
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, RentScheduleApiService(client));
    await tester.pumpAndSettle();
    expect(
      find.text('The rent schedule service returned an invalid response.'),
      findsOneWidget,
    );
  });

  testWidgets('retry reloads both list and outstanding summary', (
    tester,
  ) async {
    var calls = 0;
    var failOnce = true;
    final client = _client((request) async {
      calls++;
      if (failOnce) {
        failOnce = false;
        return http.Response('{}', 503);
      }
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/outstanding')
              ? _summaryJson()
              : [_itemJson(_pendingId, 0)],
        ),
        200,
      );
    });
    addTearDown(client.close);
    await _show(tester, RentScheduleApiService(client));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 4);
  });

  testWidgets('pull to refresh reloads both list and summary', (tester) async {
    var calls = 0;
    final client = _client((request) async {
      calls++;
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/outstanding')
              ? _summaryJson()
              : [_itemJson(_pendingId, 0)],
        ),
        200,
      );
    });
    addTearDown(client.close);
    await _show(tester, RentScheduleApiService(client));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(calls, 4);
  });

  testWidgets('payment action opens only the integration pending state', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = _client((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/outstanding')
              ? _summaryJson()
              : [_itemJson(_pendingId, 0)],
        ),
        200,
      );
    });
    addTearDown(client.close);
    await _show(tester, RentScheduleApiService(client));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('rent-payment-placeholder-$_pendingId')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pay securely'), findsNWidgets(2));
    expect(
      find.text(
        'Payment services are unavailable right now. Return to the lease and try again. No payment has been made.',
      ),
      findsOneWidget,
    );
    expect(requests, hasLength(2));
    expect(requests.every((request) => request.method == 'GET'), isTrue);
  });
}
