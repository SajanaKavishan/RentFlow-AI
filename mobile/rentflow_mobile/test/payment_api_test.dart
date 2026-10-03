import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/payments/models/payment.dart';
import 'package:rentflow_mobile/features/payments/services/payment_api_service.dart';

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage(this.token);

  String? token;

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;
}

const _paymentId = '11111111-1111-4111-8111-111111111111';
const _scheduleItemId = '22222222-2222-4222-8222-222222222222';
const _tenantId = '33333333-3333-4333-8333-333333333333';

Map<String, dynamic> _paymentJson({
  int status = 0,
  String? transactionReference = 'txn-123',
  Object? paidAt = '2030-02-01T12:15:00-04:00',
  Object? updatedAt = '2030-02-01T12:15:00Z',
}) => {
  'id': _paymentId,
  'rentScheduleItemId': _scheduleItemId,
  'tenantId': _tenantId,
  'amount': 1250.75,
  'paymentMethod': 'Bank transfer',
  'transactionReference': transactionReference,
  'status': status,
  'paidAt': paidAt,
  'createdAt': '2030-01-15T09:00:00+05:30',
  'updatedAt': updatedAt,
};

ApiClient _client(
  Future<http.Response> Function(http.Request) handler, {
  TokenStorage? storage,
}) => ApiClient(
  baseUrl: 'http://test',
  httpClient: MockClient(handler),
  tokenStorage: storage ?? _MemoryTokenStorage('payment-test-token'),
);

void main() {
  group('Payment model', () {
    test('parses fields, decimal amount, and DateTimeOffset timestamps', () {
      final payment = Payment.fromJson(_paymentJson());
      expect(payment.id, _paymentId);
      expect(payment.rentScheduleItemId, _scheduleItemId);
      expect(payment.tenantId, _tenantId);
      expect(payment.amount, 1250.75);
      expect(payment.paymentMethod, 'Bank transfer');
      expect(payment.transactionReference, 'txn-123');
      expect(payment.status, PaymentStatus.pending);
      expect(payment.paidAt, DateTime.utc(2030, 2, 1, 16, 15));
      expect(payment.createdAt, DateTime.utc(2030, 1, 15, 3, 30));
      expect(payment.updatedAt, DateTime.utc(2030, 2, 1, 12, 15));
    });

    test('accepts nullable transactionReference, paidAt, and updatedAt', () {
      final payment = Payment.fromJson(
        _paymentJson(transactionReference: null, paidAt: null, updatedAt: null),
      );
      expect(payment.transactionReference, isNull);
      expect(payment.paidAt, isNull);
      expect(payment.updatedAt, isNull);
    });

    test('maps Pending, Completed, and Failed numeric statuses', () {
      expect(
        Payment.fromJson(_paymentJson(status: 0)).status,
        PaymentStatus.pending,
      );
      expect(
        Payment.fromJson(_paymentJson(status: 1)).status,
        PaymentStatus.completed,
      );
      expect(
        Payment.fromJson(_paymentJson(status: 2)).status,
        PaymentStatus.failed,
      );
      expect(
        () => Payment.fromJson(_paymentJson(status: 3)),
        throwsFormatException,
      );
      expect(
        () => Payment.fromJson(_paymentJson()..['status'] = 'Pending'),
        throwsFormatException,
      );
    });

    test('rejects malformed and missing required fields', () {
      for (final malformed in [
        _paymentJson()..remove('id'),
        _paymentJson()..['rentScheduleItemId'] = null,
        _paymentJson()..['tenantId'] = '',
        _paymentJson()..['amount'] = '1250.75',
        _paymentJson()..['paymentMethod'] = '  ',
        _paymentJson()..['transactionReference'] = 1,
        _paymentJson()..['paidAt'] = 'not-a-timestamp',
        _paymentJson()..['createdAt'] = '2030-01-15T09:00:00',
        _paymentJson()..['updatedAt'] = 1,
      ]) {
        expect(() => Payment.fromJson(malformed), throwsFormatException);
      }
    });
  });

  group('PaymentApiService', () {
    test(
      'Stripe create uses only schedule ID and parses backend contract',
      () async {
        late http.Request recorded;
        final client = _client((request) async {
          recorded = request;
          return http.Response(
            jsonEncode({
              'paymentId': _paymentId,
              'clientSecret': 'test-client-secret',
              'publishableKey': 'test-publishable-key',
              'amount': 1250.75,
              'currency': 'lkr',
              'paymentStatus': 0,
              'status': 'requires_payment_method',
            }),
            200,
          );
        });
        addTearDown(client.close);
        final intent = await PaymentApiService(
          client,
        ).createStripeIntent(_scheduleItemId);
        expect(recorded.method, 'POST');
        expect(recorded.url.path, '/api/payments/stripe/create-intent');
        expect(recorded.headers['Authorization'], 'Bearer payment-test-token');
        expect(jsonDecode(recorded.body), {
          'rentScheduleItemId': _scheduleItemId,
        });
        expect(intent.paymentId, _paymentId);
        expect(intent.clientSecret, 'test-client-secret');
        expect(intent.publishableKey, 'test-publishable-key');
        expect(intent.amount, 1250.75);
        expect(intent.currency, 'lkr');
        expect(intent.paymentStatus, PaymentStatus.pending);
        expect(intent.status, 'requires_payment_method');
      },
    );

    test('Stripe status uses exact route and parses settled state', () async {
      late http.Request recorded;
      final client = _client((request) async {
        recorded = request;
        return http.Response(
          jsonEncode({
            'paymentId': _paymentId,
            'paymentStatus': 1,
            'status': 'succeeded',
            'paidAt': '2030-02-01T12:15:00Z',
          }),
          200,
        );
      });
      addTearDown(client.close);
      final status = await PaymentApiService(
        client,
      ).getStripeStatus(_paymentId);
      expect(recorded.method, 'GET');
      expect(recorded.url.path, '/api/payments/$_paymentId/stripe-status');
      expect(status.paymentStatus, PaymentStatus.completed);
      expect(status.status, 'succeeded');
      expect(status.paidAt, DateTime.utc(2030, 2, 1, 12, 15));
    });

    test(
      'Stripe endpoints reject unsafe responses and hide server failures',
      () async {
        final malformed = _client((_) async => http.Response('{}', 200));
        addTearDown(malformed.close);
        await expectLater(
          PaymentApiService(malformed).createStripeIntent(_scheduleItemId),
          throwsA(isA<PaymentApiException>()),
        );
        final failed = _client(
          (_) async => http.Response('private provider data', 503),
        );
        addTearDown(failed.close);
        await expectLater(
          PaymentApiService(failed).getStripeStatus(_paymentId),
          throwsA(
            isA<PaymentApiException>().having(
              (error) => error.message,
              'message',
              'The payment request failed. Please try again.',
            ),
          ),
        );
      },
    );

    test(
      'POST uses exact route, bearer header, contract body, and 201 response',
      () async {
        late http.Request recorded;
        final client = _client((request) async {
          recorded = request;
          return http.Response(jsonEncode(_paymentJson()), 201);
        });
        addTearDown(client.close);

        final result = await PaymentApiService(client).createPayment(
          rentScheduleItemId: _scheduleItemId,
          paymentMethod: '  Bank transfer  ',
          transactionReference: '  txn-789  ',
        );
        final body = jsonDecode(recorded.body) as Map<String, dynamic>;

        expect(result.id, _paymentId);
        expect(recorded.method, 'POST');
        expect(recorded.url.path, '/api/payments');
        expect(recorded.headers['Authorization'], 'Bearer payment-test-token');
        expect(body.keys.toSet(), {
          'rentScheduleItemId',
          'paymentMethod',
          'transactionReference',
        });
        expect(body['rentScheduleItemId'], _scheduleItemId);
        expect(body['paymentMethod'], 'Bank transfer');
        expect(body['transactionReference'], 'txn-789');
        for (final forbidden in ['amount', 'tenantId', 'status', 'paidAt']) {
          expect(body, isNot(contains(forbidden)));
        }
      },
    );

    test(
      'POST sends null transactionReference for null or whitespace input',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final client = _client((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(_paymentJson()), 201);
        });
        addTearDown(client.close);
        final service = PaymentApiService(client);

        await service.createPayment(
          rentScheduleItemId: _scheduleItemId,
          paymentMethod: 'Cash',
        );
        await service.createPayment(
          rentScheduleItemId: _scheduleItemId,
          paymentMethod: 'Cash',
          transactionReference: '   ',
        );
        expect(bodies.map((body) => body['transactionReference']), [
          null,
          null,
        ]);
      },
    );

    test(
      'rejects blank and overlong payment method without network calls',
      () async {
        var requests = 0;
        final client = _client((_) async {
          requests++;
          return http.Response('{}', 201);
        });
        addTearDown(client.close);
        final service = PaymentApiService(client);

        for (final method in ['', '   ', List.filled(101, 'm').join()]) {
          await expectLater(
            service.createPayment(
              rentScheduleItemId: _scheduleItemId,
              paymentMethod: method,
            ),
            throwsA(isA<PaymentApiException>()),
          );
        }
        expect(requests, 0);
      },
    );

    test(
      'rejects overlong transaction reference without network calls',
      () async {
        var requests = 0;
        final client = _client((_) async {
          requests++;
          return http.Response('{}', 201);
        });
        addTearDown(client.close);
        await expectLater(
          PaymentApiService(client).createPayment(
            rentScheduleItemId: _scheduleItemId,
            paymentMethod: 'Cash',
            transactionReference: List.filled(201, 'r').join(),
          ),
          throwsA(isA<PaymentApiException>()),
        );
        expect(requests, 0);
      },
    );

    test(
      'GET mine and detail use exact routes and parse payment responses',
      () async {
        final requests = <http.Request>[];
        final client = _client((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/mine')
                  ? [_paymentJson(), _paymentJson(status: 1)]
                  : _paymentJson(status: 2),
            ),
            200,
          );
        });
        addTearDown(client.close);
        final service = PaymentApiService(client);

        final payments = await service.getMyPayments();
        final detail = await service.getPayment(_paymentId);
        expect(payments, hasLength(2));
        expect(payments[0].status, PaymentStatus.pending);
        expect(payments[1].status, PaymentStatus.completed);
        expect(detail.status, PaymentStatus.failed);
        expect(requests.map((request) => request.method), ['GET', 'GET']);
        expect(requests.map((request) => request.url.path), [
          '/api/payments/mine',
          '/api/payments/$_paymentId',
        ]);
        expect(
          requests.every(
            (request) =>
                request.headers['Authorization'] == 'Bearer payment-test-token',
          ),
          isTrue,
        );
      },
    );

    for (final (status, message) in [
      (400, 'The payment request is invalid. Check the details and try again.'),
      (403, 'You do not have permission to access this resource.'),
      (404, 'The requested payment or rent schedule item is unavailable.'),
      (
        409,
        'This payment conflicts with the current rent schedule. Refresh and try again.',
      ),
      (500, 'The payment request failed. Please try again.'),
    ]) {
      test('handles HTTP $status safely', () async {
        final client = _client(
          (_) async => http.Response('private backend internals', status),
        );
        addTearDown(client.close);
        await expectLater(
          PaymentApiService(client).getPayment(_paymentId),
          throwsA(
            isA<PaymentApiException>()
                .having((error) => error.statusCode, 'statusCode', status)
                .having((error) => error.message, 'message', message),
          ),
        );
      });
    }

    test('401 uses shared unauthorized handling', () async {
      final storage = _MemoryTokenStorage('payment-test-token');
      final client = _client(
        (_) async => http.Response('private backend internals', 401),
        storage: storage,
      );
      addTearDown(client.close);
      await expectLater(
        PaymentApiService(client).getMyPayments(),
        throwsA(
          isA<PaymentApiException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having(
                (error) => error.message,
                'message',
                'Your session has expired.',
              ),
        ),
      );
      expect(storage.token, isNull);
    });

    test('wraps malformed JSON and DTO responses safely', () async {
      for (final body in ['{', '{}', '[{}]']) {
        final client = _client((_) async => http.Response(body, 200));
        try {
          await expectLater(
            PaymentApiService(client).getMyPayments(),
            throwsA(isA<PaymentApiException>()),
          );
        } finally {
          client.close();
        }
      }
    });

    test('wraps connection errors without exposing details', () async {
      final client = _client(
        (_) async => throw http.ClientException('private socket detail'),
      );
      addTearDown(client.close);
      await expectLater(
        PaymentApiService(client).getMyPayments(),
        throwsA(
          isA<PaymentApiException>().having(
            (error) => error.message,
            'message',
            'Unable to connect to the payment service.',
          ),
        ),
      );
    });
  });
}
