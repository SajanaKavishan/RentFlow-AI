import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/payments/screens/pay_rent_screen.dart';
import 'package:rentflow_mobile/features/payments/screens/payment_details_screen.dart';
import 'package:rentflow_mobile/features/payments/services/payment_api_service.dart';
import 'package:rentflow_mobile/features/payments/services/stripe_payment_sheet_service.dart';
import 'package:rentflow_mobile/features/rent_schedules/services/rent_schedule_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

const scheduleId = '11111111-1111-4111-8111-111111111111';
const paymentId = '22222222-2222-4222-8222-222222222222';
const legacyId = '33333333-3333-4333-8333-333333333333';
const leaseId = '44444444-4444-4444-8444-444444444444';

class MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}
  @override
  Future<String?> readToken() async => 'test-token';
  @override
  Future<void> saveToken(String value) async {}
}

class FakeSheet implements StripePaymentSheetService {
  String? publishableKey;
  String? clientSecret;
  int initializeCalls = 0;
  int presentCalls = 0;
  Future<void> Function()? onPresent;

  @override
  Future<void> initialize({
    required String publishableKey,
    required String clientSecret,
  }) async {
    this.publishableKey = publishableKey;
    this.clientSecret = clientSecret;
    initializeCalls++;
  }

  @override
  Future<void> present() async {
    presentCalls++;
    await onPresent?.call();
  }
}

Map<String, dynamic> item() => {
  'id': scheduleId,
  'leaseAgreementId': leaseId,
  'dueDate': '2030-02-28',
  'amount': 145000.0,
  'status': 0,
  'createdAt': '2030-01-01T00:00:00Z',
  'updatedAt': null,
};

Map<String, dynamic> summary({bool paid = false}) => {
  'totalPending': paid ? 0 : 145000.0,
  'totalOverdue': 0,
  'totalOutstanding': paid ? 0 : 145000.0,
  'items': paid ? <dynamic>[] : [item()],
};

Map<String, dynamic> payment({
  String id = paymentId,
  String method = 'Stripe',
  int status = 0,
  String? reference,
}) => {
  'id': id,
  'rentScheduleItemId': scheduleId,
  'tenantId': '55555555-5555-4555-8555-555555555555',
  'amount': 145000.0,
  'paymentMethod': method,
  'transactionReference': reference,
  'status': status,
  'paidAt': status == 1 ? '2030-02-01T12:00:00Z' : null,
  'createdAt': '2030-01-30T09:00:00Z',
  'updatedAt': null,
};

Map<String, dynamic> intent() => {
  'paymentId': paymentId,
  'clientSecret': 'test-client-secret',
  'publishableKey': 'test-publishable-key',
  'amount': 145000.0,
  'currency': 'lkr',
  'paymentStatus': 0,
  'status': 'requires_payment_method',
};

Map<String, dynamic> stripeStatus(int status) => {
  'paymentId': paymentId,
  'paymentStatus': status,
  'status': status == 1 ? 'succeeded' : 'processing',
  'paidAt': status == 1 ? '2030-02-01T12:00:00Z' : null,
};

ApiClient client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      baseUrl: 'http://test',
      tokenStorage: MemoryTokenStorage(),
      httpClient: MockClient(handler),
    );

Future<void> showPayRent(
  WidgetTester tester,
  ApiClient apiClient,
  FakeSheet sheet, {
  String? initialItem = scheduleId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: PayRentScreen(
        rentScheduleApiService: RentScheduleApiService(apiClient),
        paymentApiService: PaymentApiService(apiClient),
        stripePaymentSheetService: sheet,
        initialRentScheduleItemId: initialItem,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapPay(WidgetTester tester, {String key = 'pay-securely'}) async {
  final button = find.byKey(ValueKey(key));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selected item shows read-only Rs. amount and secure action', (
    tester,
  ) async {
    final api = client(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine') ? [] : summary(),
        ),
        200,
      ),
    );
    addTearDown(api.close);
    await showPayRent(tester, api, FakeSheet());
    expect(find.text('Rs. 145,000.00'), findsWidgets);
    expect(find.text('Amount: Rs. 145,000.00'), findsWidgets);
    expect(find.byKey(const ValueKey('pay-securely')), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-method-field')), findsNothing);
    expect(
      find.byKey(const ValueKey('transaction-reference-field')),
      findsNothing,
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'sheet success reconciles and refreshes history and outstanding',
    (tester) async {
      var paid = false;
      var historyCalls = 0;
      var outstandingCalls = 0;
      var createCalls = 0;
      var statusCalls = 0;
      final sheet = FakeSheet()
        ..onPresent = () async {
          paid = true;
        };
      final api = client((request) async {
        switch (request.url.path) {
          case '/api/rent-schedules/outstanding/mine':
            outstandingCalls++;
            return http.Response(jsonEncode(summary(paid: paid)), 200);
          case '/api/payments/mine':
            historyCalls++;
            return http.Response(
              jsonEncode(paid ? [payment(status: 1)] : []),
              200,
            );
          case '/api/payments/stripe/create-intent':
            createCalls++;
            expect(jsonDecode(request.body), {
              'rentScheduleItemId': scheduleId,
            });
            return http.Response(jsonEncode(intent()), 200);
          case '/api/payments/$paymentId/stripe-status':
            statusCalls++;
            return http.Response(jsonEncode(stripeStatus(1)), 200);
        }
        return http.Response('{}', 404);
      });
      addTearDown(api.close);
      await showPayRent(tester, api, sheet);
      await tapPay(tester);
      expect(createCalls, 1);
      expect(sheet.initializeCalls, 1);
      expect(sheet.publishableKey, 'test-publishable-key');
      expect(sheet.clientSecret, 'test-client-secret');
      expect(sheet.presentCalls, 1);
      expect(statusCalls, 1);
      expect(historyCalls, 2);
      expect(outstandingCalls, 2);
      expect(find.text('Payment completed successfully.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('outstanding-item-card-$scheduleId')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('payment-history-card-$paymentId')),
        findsOneWidget,
      );
    },
  );

  testWidgets('duplicate tap is disabled while create-intent is in flight', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    var creates = 0;
    final api = client((request) async {
      if (request.url.path.endsWith('/create-intent')) {
        creates++;
        return gate.future;
      }
      if (request.url.path.endsWith('/stripe-status')) {
        return http.Response(jsonEncode(stripeStatus(0)), 200);
      }
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine') ? [] : summary(),
        ),
        200,
      );
    });
    addTearDown(api.close);
    final sheet = FakeSheet();
    await showPayRent(tester, api, sheet);
    final button = find.byKey(const ValueKey('pay-securely'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    expect(creates, 1);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(button);
    expect(creates, 1);
    gate.complete(http.Response(jsonEncode(intent()), 200));
    await tester.pumpAndSettle();
  });

  testWidgets('processing remains Pending with a resume action', (
    tester,
  ) async {
    var created = false;
    final api = client((request) async {
      if (request.url.path.endsWith('/create-intent')) {
        created = true;
        return http.Response(jsonEncode(intent()), 200);
      }
      if (request.url.path.endsWith('/stripe-status')) {
        return http.Response(jsonEncode(stripeStatus(0)), 200);
      }
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine')
              ? (created ? [payment()] : [])
              : summary(),
        ),
        200,
      );
    });
    addTearDown(api.close);
    await showPayRent(tester, api, FakeSheet());
    await tapPay(tester);
    expect(find.textContaining('Payment is processing'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('outstanding-item-card-$scheduleId')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('resume-stripe-payment')), findsOneWidget);
    expect(find.text('Payment completed successfully.'), findsNothing);
  });

  testWidgets('cancellation keeps attempt and retry resumes the same payment', (
    tester,
  ) async {
    var createCalls = 0;
    var statusCalls = 0;
    final sheet = FakeSheet()
      ..onPresent = () async {
        if (createCalls == 1) throw const StripePaymentSheetCanceledException();
      };
    final api = client((request) async {
      if (request.url.path.endsWith('/create-intent')) {
        createCalls++;
        return http.Response(jsonEncode(intent()), 200);
      }
      if (request.url.path.endsWith('/stripe-status')) {
        statusCalls++;
        return http.Response(jsonEncode(stripeStatus(0)), 200);
      }
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine')
              ? (createCalls > 0 ? [payment()] : [])
              : summary(),
        ),
        200,
      );
    });
    addTearDown(api.close);
    await showPayRent(tester, api, sheet);
    await tapPay(tester);
    expect(find.textContaining('Payment canceled'), findsOneWidget);
    expect(find.text('Payment completed successfully.'), findsNothing);
    expect(statusCalls, 0);
    await tapPay(tester, key: 'resume-stripe-payment');
    expect(createCalls, 2);
    expect(sheet.presentCalls, 2);
    expect(statusCalls, 1);
  });

  testWidgets('decline displays safe message and preserves retryable attempt', (
    tester,
  ) async {
    var createCalls = 0;
    final sheet = FakeSheet()
      ..onPresent = () async {
        throw const StripePaymentSheetException();
      };
    final api = client((request) async {
      if (request.url.path.endsWith('/create-intent')) {
        createCalls++;
        return http.Response(jsonEncode(intent()), 200);
      }
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('/payments/mine')
              ? (createCalls > 0 ? [payment()] : [])
              : summary(),
        ),
        200,
      );
    });
    addTearDown(api.close);
    await showPayRent(tester, api, sheet);
    await tapPay(tester);
    expect(
      find.textContaining('Payment could not be completed'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('resume-stripe-payment')), findsOneWidget);
    expect(find.text('Payment completed successfully.'), findsNothing);
  });

  testWidgets(
    'Pending Stripe offers resume and status check; manual Pending blocks Stripe',
    (tester) async {
      var createCalls = 0;
      var statusCalls = 0;
      var manual = false;
      final api = client((request) async {
        if (request.url.path.endsWith('/create-intent')) {
          createCalls++;
          return http.Response(jsonEncode(intent()), 200);
        }
        if (request.url.path.endsWith('/stripe-status')) {
          statusCalls++;
          return http.Response(jsonEncode(stripeStatus(0)), 200);
        }
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/payments/mine')
                ? [payment(method: manual ? 'Bank transfer' : 'Stripe')]
                : summary(),
          ),
          200,
        );
      });
      addTearDown(api.close);
      await showPayRent(tester, api, FakeSheet());
      expect(find.byKey(const ValueKey('pay-securely')), findsNothing);
      await tapPay(tester, key: 'check-stripe-status');
      expect(statusCalls, 1);
      expect(createCalls, 0);
      manual = true;
      await tester.tap(find.byTooltip('Refresh Pay Rent'));
      await tester.pumpAndSettle();
      expect(find.text('Manual payment pending'), findsWidgets);
      expect(find.byKey(const ValueKey('resume-stripe-payment')), findsNothing);
      expect(find.byKey(const ValueKey('pay-securely')), findsNothing);
    },
  );

  testWidgets('conflict refreshes server state and 5xx hides internals', (
    tester,
  ) async {
    var outstandingCalls = 0;
    var historyCalls = 0;
    var conflict = true;
    final api = client((request) async {
      if (request.url.path.endsWith('/create-intent')) {
        return http.Response('private provider data', conflict ? 409 : 503);
      }
      if (request.url.path.endsWith('/payments/mine')) {
        historyCalls++;
        return http.Response('[]', 200);
      }
      outstandingCalls++;
      return http.Response(jsonEncode(summary()), 200);
    });
    addTearDown(api.close);
    await showPayRent(tester, api, FakeSheet());
    await tapPay(tester);
    expect(
      find.textContaining('conflicts with the current rent schedule'),
      findsOneWidget,
    );
    expect(outstandingCalls, 2);
    expect(historyCalls, 2);
    conflict = false;
    await tapPay(tester);
    expect(find.textContaining('private provider'), findsNothing);
    expect(find.textContaining('payment request failed'), findsOneWidget);
  });

  testWidgets('legacy and Stripe history render and details stay read-only', (
    tester,
  ) async {
    final api = client((request) async {
      if (request.url.path.endsWith('/payments/mine')) {
        return http.Response(
          jsonEncode([
            payment(
              id: legacyId,
              method: 'Bank transfer',
              status: 1,
              reference: 'legacy-ref',
            ),
            payment(status: 0),
          ]),
          200,
        );
      }
      if (request.url.path == '/api/payments/$paymentId') {
        return http.Response(jsonEncode(payment()), 200);
      }
      return http.Response(jsonEncode(summary()), 200);
    });
    addTearDown(api.close);
    await showPayRent(tester, api, FakeSheet(), initialItem: null);
    expect(
      find.byKey(const ValueKey('payment-history-card-$legacyId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payment-history-card-$paymentId')),
      findsOneWidget,
    );
    expect(find.text('Payment method: Bank transfer'), findsOneWidget);
    expect(find.text('Payment method: Stripe'), findsOneWidget);
    expect(find.text('Transaction reference: legacy-ref'), findsOneWidget);
    final card = find.byKey(const ValueKey('payment-history-card-$paymentId'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentDetailsScreen), findsOneWidget);
    expect(find.text('Rs. 145,000.00'), findsOneWidget);
    expect(find.text('Stripe'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Complete payment'), findsNothing);
    expect(find.text('Fail payment'), findsNothing);
  });

  testWidgets('loading error is safe and retryable', (tester) async {
    var calls = 0;
    final api = client((request) async {
      if (request.url.path.endsWith('/payments/mine')) {
        calls++;
        if (calls == 1) return http.Response('private server error', 503);
        return http.Response('[]', 200);
      }
      return http.Response(jsonEncode(summary()), 200);
    });
    addTearDown(api.close);
    await showPayRent(tester, api, FakeSheet());
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Outstanding summary'), findsOneWidget);
  });
}
