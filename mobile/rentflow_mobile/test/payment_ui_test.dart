import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/payments/screens/payment_details_screen.dart';
import 'package:rentflow_mobile/features/payments/screens/pay_rent_screen.dart';
import 'package:rentflow_mobile/features/payments/services/payment_api_service.dart';
import 'package:rentflow_mobile/features/rent_schedules/services/rent_schedule_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

const _leaseId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _pendingId = '11111111-1111-4111-8111-111111111111';
const _overdueId = '22222222-2222-4222-8222-222222222222';
const _secondPendingId = '33333333-3333-4333-8333-333333333333';
const _paymentId = '44444444-4444-4444-8444-444444444444';

class _MemoryTokenStorage implements TokenStorage {
  String? token = 'pay-rent-test-token';

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;
}

Map<String, dynamic> _item(String id, int status) => {
  'id': id,
  'leaseAgreementId': _leaseId,
  'dueDate': status == 2 ? '2030-01-28' : '2030-02-28',
  'amount': id == _secondPendingId ? 780.5 : 1250.75,
  'status': status,
  'createdAt': '2030-01-15T09:00:00Z',
  'updatedAt': null,
};

Map<String, dynamic> _summary({
  List<dynamic>? items,
  double pending = 2031.25,
  double overdue = 1250.75,
  double outstanding = 3282,
}) => {
  'totalPending': pending,
  'totalOverdue': overdue,
  'totalOutstanding': outstanding,
  'items': items ?? [_item(_pendingId, 0), _item(_overdueId, 2)],
};

Map<String, dynamic> _payment({
  String id = _paymentId,
  String scheduleItemId = _pendingId,
  int status = 0,
  String? transactionReference = 'txn-001',
  Object? paidAt,
}) => {
  'id': id,
  'rentScheduleItemId': scheduleItemId,
  'tenantId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'amount': 1250.75,
  'paymentMethod': 'Bank transfer',
  'transactionReference': transactionReference,
  'status': status,
  'paidAt': paidAt,
  'createdAt': '2030-01-30T09:00:00Z',
  'updatedAt': null,
};

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient(handler),
      tokenStorage: _MemoryTokenStorage(),
    );

ApiClient _timeoutClient(
  Future<http.Response> Function(http.Request) handler, {
  required Duration requestTimeout,
}) => ApiClient(
  baseUrl: 'http://test',
  requestTimeout: requestTimeout,
  httpClient: MockClient(handler),
  tokenStorage: _MemoryTokenStorage(),
);

Future<void> _show(
  WidgetTester tester,
  ApiClient client, {
  String? initialRentScheduleItemId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: PayRentScreen(
        rentScheduleApiService: RentScheduleApiService(client),
        paymentApiService: PaymentApiService(client),
        initialRentScheduleItemId: initialRentScheduleItemId,
      ),
    ),
  );
}

Future<void> _showDetails(
  WidgetTester tester,
  ApiClient client, {
  String paymentId = _paymentId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: PaymentDetailsScreen(
        paymentApiService: PaymentApiService(client),
        paymentId: paymentId,
      ),
    ),
  );
}

Future<void> _selectItem(WidgetTester tester, String itemId) async {
  final finder = find.byKey(ValueKey('outstanding-item-card-$itemId'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('submit-payment'));
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads outstanding summary and payment history', (tester) async {
    final paths = <String>[];
    final outstandingResponse = Completer<http.Response>();
    final paymentsResponse = Completer<http.Response>();
    final client = _client((request) async {
      paths.add(request.url.path);
      return request.url.path.endsWith('/payments/mine')
          ? paymentsResponse.future
          : outstandingResponse.future;
    });
    addTearDown(client.close);
    await _show(tester, client);
    await tester.pump();
    expect(find.text('Loading Pay Rent'), findsOneWidget);
    outstandingResponse.complete(http.Response(jsonEncode(_summary()), 200));
    paymentsResponse.complete(http.Response(jsonEncode([_payment()]), 200));
    await tester.pumpAndSettle();
    expect(paths, [
      '/api/rent-schedules/outstanding/mine',
      '/api/payments/mine',
    ]);
    expect(find.text('Total pending'), findsOneWidget);
    expect(find.text('Total overdue'), findsOneWidget);
    expect(find.text('Total outstanding'), findsOneWidget);
    expect(find.text('Payment history'), findsOneWidget);
    expect(
      find.byKey(ValueKey('payment-history-card-$_paymentId')),
      findsOneWidget,
    );
  });

  testWidgets('shows Pending and Overdue items and preselects an initial ID', (
    tester,
  ) async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine') ? [] : _summary(),
        ),
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, client, initialRentScheduleItemId: _overdueId);
    await tester.pumpAndSettle();
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.byKey(const ValueKey('selected-payment-item')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('selected-payment-item')),
        matching: find.text('Amount: 1250.75'),
      ),
      findsOneWidget,
    );
    expect(find.text('Due date: 2030-01-28'), findsOneWidget);
    expect(find.text('Status: Overdue'), findsOneWidget);
    expect(find.byKey(const ValueKey('submit-payment')), findsOneWidget);
  });

  testWidgets('ignores an initial ID absent from outstanding items', (
    tester,
  ) async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine')
              ? []
              : _summary(items: [_item(_pendingId, 0)]),
        ),
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, client, initialRentScheduleItemId: _overdueId);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected-payment-item')), findsNothing);
    expect(find.byKey(const ValueKey('submit-payment')), findsNothing);
  });

  testWidgets(
    'shows zero totals and separate empty outstanding and history states',
    (tester) async {
      final client = _client(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('/payments/mine')
                ? []
                : _summary(
                    items: const [],
                    pending: 0,
                    overdue: 0,
                    outstanding: 0,
                  ),
          ),
          200,
        ),
      );
      addTearDown(client.close);
      await _show(tester, client);
      await tester.pumpAndSettle();
      expect(find.text('0.00'), findsNWidgets(3));
      expect(find.text('No outstanding rent payments.'), findsOneWidget);
      expect(find.text('No payment records yet'), findsOneWidget);
    },
  );

  testWidgets('history displays Pending, Completed, and Failed records', (
    tester,
  ) async {
    final history = [
      _payment(status: 0),
      _payment(
        id: '55555555-5555-4555-8555-555555555555',
        status: 1,
        paidAt: '2030-02-01T09:00:00Z',
      ),
      _payment(
        id: '66666666-6666-4666-8666-666666666666',
        status: 2,
        transactionReference: null,
      ),
    ];
    final client = _client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine')
              ? history
              : _summary(items: [_item(_pendingId, 0)]),
        ),
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, client);
    await tester.pumpAndSettle();
    expect(find.text('Pending'), findsNWidgets(2));
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Transaction reference: txn-001'), findsNWidgets(2));
    expect(find.textContaining('Paid at:'), findsOneWidget);
  });

  testWidgets('history still appears when no outstanding items remain', (
    tester,
  ) async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine')
              ? [_payment(status: 1, paidAt: '2030-02-01T09:00:00Z')]
              : _summary(
                  items: const [],
                  pending: 0,
                  overdue: 0,
                  outstanding: 0,
                ),
        ),
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, client);
    await tester.pumpAndSettle();
    expect(find.text('No outstanding rent payments.'), findsOneWidget);
    expect(
      find.byKey(ValueKey('payment-history-card-$_paymentId')),
      findsOneWidget,
    );
  });

  testWidgets('no selection prevents payment submission', (tester) async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine') ? [] : _summary(),
        ),
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, client);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('submit-payment')), findsNothing);
    expect(find.byKey(const ValueKey('selected-payment-item')), findsNothing);
  });

  testWidgets('blank payment method is rejected by form validation', (
    tester,
  ) async {
    var posts = 0;
    final client = _client((request) async {
      if (request.method == 'POST') posts++;
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine')
              ? []
              : request.method == 'POST'
              ? _payment()
              : _summary(),
        ),
        request.method == 'POST' ? 201 : 200,
      );
    });
    addTearDown(client.close);
    await _show(tester, client);
    await tester.pumpAndSettle();
    await _selectItem(tester, _pendingId);
    await _tapSubmit(tester);
    expect(find.text('Payment method is required.'), findsOneWidget);
    expect(posts, 0);
  });

  testWidgets('payment method longer than 100 characters is rejected', (
    tester,
  ) async {
    var posts = 0;
    final client = _client((request) async {
      if (request.method == 'POST') posts++;
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine') ? [] : _summary(),
        ),
        200,
      );
    });
    addTearDown(client.close);
    await _show(tester, client);
    await tester.pumpAndSettle();
    await _selectItem(tester, _pendingId);
    await tester.enterText(
      find.byKey(const ValueKey('payment-method-field')),
      List.filled(101, 'm').join(),
    );
    await _tapSubmit(tester);
    expect(
      find.text('Payment method must be 100 characters or fewer.'),
      findsOneWidget,
    );
    expect(posts, 0);
  });

  testWidgets('optional blank transaction reference is sent as null', (
    tester,
  ) async {
    Map<String, dynamic>? postedBody;
    final client = _client((request) async {
      if (request.method == 'POST') {
        postedBody = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine')
              ? []
              : request.method == 'POST'
              ? _payment()
              : _summary(),
        ),
        request.method == 'POST' ? 201 : 200,
      );
    });
    addTearDown(client.close);
    await _show(tester, client);
    await tester.pumpAndSettle();
    await _selectItem(tester, _pendingId);
    await tester.enterText(
      find.byKey(const ValueKey('payment-method-field')),
      '  Cash deposit  ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-reference-field')),
      '   ',
    );
    await _tapSubmit(tester);
    expect(postedBody?['rentScheduleItemId'], _pendingId);
    expect(postedBody?['paymentMethod'], 'Cash deposit');
    expect(postedBody?['transactionReference'], isNull);
    expect(postedBody, isNot(contains('amount')));
  });

  testWidgets('transaction reference longer than 200 characters is rejected', (
    tester,
  ) async {
    var posts = 0;
    final client = _client((request) async {
      if (request.method == 'POST') posts++;
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine') ? [] : _summary(),
        ),
        200,
      );
    });
    addTearDown(client.close);
    await _show(tester, client);
    await tester.pumpAndSettle();
    await _selectItem(tester, _pendingId);
    await tester.enterText(
      find.byKey(const ValueKey('payment-method-field')),
      'Cash',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-reference-field')),
      List.filled(201, 'r').join(),
    );
    await _tapSubmit(tester);
    expect(
      find.text('Transaction reference must be 200 characters or fewer.'),
      findsOneWidget,
    );
    expect(posts, 0);
  });

  testWidgets('amount is read-only and has no editable amount field', (
    tester,
  ) async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine') ? [] : _summary(),
        ),
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, client, initialRentScheduleItemId: _pendingId);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('selected-payment-item')),
        matching: find.text('Amount: 1250.75'),
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Amount'), findsNothing);
    expect(find.widgetWithText(TextField, 'Amount'), findsNothing);
  });

  testWidgets(
    'submitting disables duplicate action and uses selected item only',
    (tester) async {
      final postResult = Completer<http.Response>();
      var posts = 0;
      final postedBodies = <Map<String, dynamic>>[];
      final client = _client((request) async {
        if (request.method == 'POST') {
          posts++;
          postedBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return postResult.future;
        }
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/payments/mine') ? [] : _summary(),
          ),
          200,
        );
      });
      addTearDown(client.close);
      await _show(tester, client);
      await tester.pumpAndSettle();
      await _selectItem(tester, _overdueId);
      await tester.enterText(
        find.byKey(const ValueKey('payment-method-field')),
        '  Cash  ',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('submit-payment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('submit-payment')));
      await tester.pump();
      expect(posts, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('submit-payment')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('submit-payment')));
      expect(posts, 1);
      postResult.complete(
        http.Response(jsonEncode(_payment(scheduleItemId: _overdueId)), 201),
      );
      await tester.pumpAndSettle();
      expect(postedBodies.single['rentScheduleItemId'], _overdueId);
      expect(postedBodies.single, isNot(contains('amount')));
    },
  );

  testWidgets('success shows accurate wording and refreshes both resources', (
    tester,
  ) async {
    var outstandingCalls = 0;
    var historyCalls = 0;
    final client = _client((request) async {
      if (request.url.path == '/api/rent-schedules/outstanding/mine') {
        outstandingCalls++;
        return http.Response(jsonEncode(_summary()), 200);
      }
      if (request.url.path == '/api/payments/mine') {
        historyCalls++;
        return http.Response(
          jsonEncode(historyCalls > 1 ? [_payment()] : []),
          200,
        );
      }
      if (request.method == 'POST') {
        return http.Response(jsonEncode(_payment()), 201);
      }
      return http.Response('{}', 404);
    });
    addTearDown(client.close);
    await _show(tester, client, initialRentScheduleItemId: _pendingId);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-method-field')),
      'Bank transfer',
    );
    await _tapSubmit(tester);
    expect(find.text('Payment record submitted.'), findsOneWidget);
    expect(find.text('Payment completed.'), findsNothing);
    expect(outstandingCalls, 2);
    expect(historyCalls, 2);
    expect(
      find.byKey(ValueKey('payment-history-card-$_paymentId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pending-payment-guard-$_pendingId')),
      findsOneWidget,
    );
  });

  testWidgets('Pending history record guards the same item from resubmission', (
    tester,
  ) async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine')
              ? [_payment()]
              : _summary(items: [_item(_pendingId, 0)]),
        ),
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, client, initialRentScheduleItemId: _pendingId);
    await tester.pumpAndSettle();
    expect(find.text('Payment record already Pending'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('pending-payment-guard-$_pendingId')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('payment-history-card-$_paymentId')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('submit-payment')), findsNothing);
  });

  testWidgets('Failed payment does not block another payment record', (
    tester,
  ) async {
    final failed = _payment(status: 2);
    final client = _client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine')
              ? [failed]
              : _summary(items: [_item(_pendingId, 0)]),
        ),
        200,
      ),
    );
    addTearDown(client.close);
    await _show(tester, client, initialRentScheduleItemId: _pendingId);
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsOneWidget);
    expect(find.byKey(const ValueKey('submit-payment')), findsOneWidget);
  });

  testWidgets('400 submission error is safe and keeps the form available', (
    tester,
  ) async {
    final client = _client((request) async {
      if (request.method == 'POST') {
        return http.Response(
          jsonEncode({'message': 'Payment method is invalid.'}),
          400,
        );
      }
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine') ? [] : _summary(),
        ),
        200,
      );
    });
    addTearDown(client.close);
    await _show(tester, client, initialRentScheduleItemId: _pendingId);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-method-field')),
      'Cash',
    );
    await _tapSubmit(tester);
    expect(find.text('Payment method is invalid.'), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-method-field')), findsOneWidget);
  });

  testWidgets('409 shows conflict and refreshes both resources', (
    tester,
  ) async {
    var outstandingCalls = 0;
    var historyCalls = 0;
    final client = _client((request) async {
      if (request.url.path == '/api/rent-schedules/outstanding/mine') {
        outstandingCalls++;
        return http.Response(jsonEncode(_summary()), 200);
      }
      if (request.url.path == '/api/payments/mine') {
        historyCalls++;
        return http.Response('[]', 200);
      }
      if (request.method == 'POST') return http.Response('{}', 409);
      return http.Response('{}', 404);
    });
    addTearDown(client.close);
    await _show(tester, client, initialRentScheduleItemId: _pendingId);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment-method-field')),
      'Cash',
    );
    await _tapSubmit(tester);
    expect(
      find.text(
        'This payment conflicts with the current rent schedule. Refresh and try again.',
      ),
      findsOneWidget,
    );
    expect(outstandingCalls, 2);
    expect(historyCalls, 2);
    expect(find.byKey(const ValueKey('payment-method-field')), findsOneWidget);
  });

  testWidgets('403 load error is safe and can retry', (tester) async {
    var fail = true;
    final client = _client((request) async {
      if (request.url.path == '/api/rent-schedules/outstanding/mine' && fail) {
        fail = false;
        return http.Response('private server details', 403);
      }
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine') ? [] : _summary(),
        ),
        200,
      );
    });
    addTearDown(client.close);
    await _show(tester, client);
    await tester.pumpAndSettle();
    expect(
      find.text('You do not have permission to access this resource.'),
      findsOneWidget,
    );
    expect(find.textContaining('private server'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Outstanding summary'), findsOneWidget);
  });

  testWidgets('connection and 5xx load errors remain safe and retryable', (
    tester,
  ) async {
    final failures = {
      '/api/payments/mine',
      '/api/rent-schedules/outstanding/mine',
    };
    final client = _client((request) async {
      if (failures.remove(request.url.path)) {
        if (request.url.path == '/api/payments/mine') {
          throw http.ClientException('private socket details');
        }
        return http.Response('private server details', 503);
      }
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine') ? [] : _summary(),
        ),
        200,
      );
    });
    addTearDown(client.close);
    await _show(tester, client);
    await tester.pumpAndSettle();
    expect(find.textContaining('private'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Outstanding summary'), findsOneWidget);
  });

  testWidgets(
    'Payment Details shows loading then fetches the authoritative ID',
    (tester) async {
      final response = Completer<http.Response>();
      final requests = <http.Request>[];
      final client = _client((request) async {
        requests.add(request);
        return response.future;
      });
      addTearDown(client.close);
      await _showDetails(tester, client);
      await tester.pump();
      expect(find.text('Loading payment'), findsOneWidget);
      expect(requests.single.url.path, '/api/payments/$_paymentId');
      response.complete(http.Response(jsonEncode(_payment(status: 0)), 200));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('payment-details-card')),
        findsOneWidget,
      );
    },
  );

  for (final (status, label, explanation) in [
    (
      0,
      'Pending',
      'This payment record is awaiting later processing or review.',
    ),
    (1, 'Completed', 'The backend has marked this payment record completed.'),
    (
      2,
      'Failed',
      'This payment record failed. The associated rent schedule item may remain payable.',
    ),
  ]) {
    testWidgets('Payment Details displays $label status and meaning', (
      tester,
    ) async {
      final client = _client(
        (request) async =>
            http.Response(jsonEncode(_payment(status: status)), 200),
      );
      addTearDown(client.close);
      await _showDetails(tester, client);
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(find.text(explanation), findsOneWidget);
      expect(find.textContaining('Gateway'), findsNothing);
      expect(find.textContaining('bank confirmation'), findsNothing);
    });
  }

  testWidgets('Payment Details displays supported populated fields read-only', (
    tester,
  ) async {
    final payment = _payment(
      status: 1,
      transactionReference: 'txn-detail-42',
      paidAt: '2030-02-01T09:00:00Z',
    )..['updatedAt'] = '2030-02-02T09:30:00Z';
    final client = _client(
      (request) async => http.Response(jsonEncode(payment), 200),
    );
    addTearDown(client.close);
    await _showDetails(tester, client);
    await tester.pumpAndSettle();
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('1250.75'), findsOneWidget);
    expect(find.text('Payment method'), findsOneWidget);
    expect(find.text('Bank transfer'), findsOneWidget);
    expect(find.text('Transaction reference'), findsOneWidget);
    expect(find.text('txn-detail-42'), findsOneWidget);
    expect(find.text('Rent schedule item ID'), findsOneWidget);
    expect(find.text(_pendingId), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('Paid at'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('Complete payment'), findsNothing);
    expect(find.text('Fail payment'), findsNothing);
  });

  testWidgets('Payment Details omits nullable reference and timestamps', (
    tester,
  ) async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode(_payment(transactionReference: null, paidAt: null)),
        200,
      ),
    );
    addTearDown(client.close);
    await _showDetails(tester, client);
    await tester.pumpAndSettle();
    expect(find.text('Transaction reference'), findsNothing);
    expect(find.text('Paid at'), findsNothing);
    expect(find.text('Updated'), findsNothing);
  });

  for (final (status, message) in [
    (403, 'You do not have permission to view this payment.'),
    (404, 'This payment was not found or is no longer available.'),
  ]) {
    testWidgets('Payment Details handles $status safely', (tester) async {
      final client = _client(
        (request) async =>
            http.Response('private backend details should stay hidden', status),
      );
      addTearDown(client.close);
      await _showDetails(tester, client);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('private backend'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });
  }

  testWidgets('Payment Details retries 5xx and safely handles malformed JSON', (
    tester,
  ) async {
    var attempts = 0;
    final client = _client((request) async {
      attempts++;
      if (attempts == 1) {
        return http.Response('private server exception', 503);
      }
      if (attempts == 2) return http.Response('{bad json', 200);
      return http.Response(jsonEncode(_payment()), 200);
    });
    addTearDown(client.close);
    await _showDetails(tester, client);
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load payment details. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private server'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('invalid response'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payment-details-card')), findsOneWidget);
    expect(attempts, 3);
  });

  testWidgets('Payment Details retries after a connection error', (
    tester,
  ) async {
    var attempts = 0;
    final client = _client((request) async {
      attempts++;
      if (attempts == 1) throw http.ClientException('private connection data');
      return http.Response(jsonEncode(_payment()), 200);
    });
    addTearDown(client.close);
    await _showDetails(tester, client);
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load payment details. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private connection'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payment-details-card')), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('Payment Details shows a safe retry state after timeout', (
    tester,
  ) async {
    final client = _timeoutClient(
      (request) => Completer<http.Response>().future,
      requestTimeout: const Duration(milliseconds: 5),
    );
    addTearDown(client.close);
    await _showDetails(tester, client);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load payment details. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('Payment Details 401 uses the shared unauthorized handler', (
    tester,
  ) async {
    final tokenStorage = _MemoryTokenStorage();
    var unauthorizedCalls = 0;
    final client = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: tokenStorage,
      httpClient: MockClient(
        (request) async => http.Response('private details', 401),
      ),
    )..setUnauthorizedHandler(() => unauthorizedCalls++);
    addTearDown(client.close);
    await _showDetails(tester, client);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Your session has expired. Sign in again to view this payment.',
      ),
      findsOneWidget,
    );
    expect(tokenStorage.token, isNull);
    expect(unauthorizedCalls, 1);
    expect(find.textContaining('private details'), findsNothing);
  });

  testWidgets('history opens authoritative details and refreshes on return', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: _MemoryTokenStorage(),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/payments/mine') {
          return http.Response(jsonEncode([_payment()]), 200);
        }
        if (request.url.path == '/api/payments/$_paymentId') {
          return http.Response(jsonEncode(_payment()), 200);
        }
        return http.Response(jsonEncode(_summary()), 200);
      }),
    );
    addTearDown(apiClient.close);
    final scheduleService = RentScheduleApiService(apiClient);
    final paymentService = PaymentApiService(apiClient);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: PayRentScreen(
          rentScheduleApiService: scheduleService,
          paymentApiService: paymentService,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final historyCallsBefore = requests
        .where((request) => request.url.path == '/api/payments/mine')
        .length;
    final historyCard = find.byKey(
      const ValueKey('payment-history-card-$_paymentId'),
    );
    await tester.ensureVisible(historyCard);
    await tester.pumpAndSettle();
    await tester.tap(historyCard);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentDetailsScreen), findsOneWidget);
    final details = tester.widget<PaymentDetailsScreen>(
      find.byType(PaymentDetailsScreen),
    );
    expect(details.paymentId, _paymentId);
    expect(identical(details.paymentApiService, paymentService), isTrue);
    expect(requests.last.url.path, '/api/payments/$_paymentId');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PayRentScreen), findsOneWidget);
    expect(
      requests
          .where((request) => request.url.path == '/api/payments/mine')
          .length,
      historyCallsBefore + 1,
    );
  });
}
