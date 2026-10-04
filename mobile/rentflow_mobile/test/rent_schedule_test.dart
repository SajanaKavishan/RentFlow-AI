import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/rent_schedules/models/rent_schedule_item.dart';
import 'package:rentflow_mobile/features/rent_schedules/models/rent_schedule_outstanding_summary.dart';
import 'package:rentflow_mobile/features/rent_schedules/services/rent_schedule_api_service.dart';

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

const _itemId = '11111111-1111-4111-8111-111111111111';
const _leaseId = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _itemJson({int status = 0}) => {
  'id': _itemId,
  'leaseAgreementId': _leaseId,
  'dueDate': '2030-02-28',
  'amount': 1250.75,
  'status': status,
  'createdAt': '2030-01-15T09:00:00+05:30',
  'updatedAt': '2030-02-01T12:15:00-04:00',
};

Map<String, dynamic> _summaryJson({List<dynamic>? items}) => {
  'totalPending': 1250.75,
  'totalOverdue': 500,
  'totalOutstanding': 1750.75,
  'items': items ?? [_itemJson()],
};

ApiClient _client(
  Future<http.Response> Function(http.Request) handler, {
  TokenStorage? storage,
}) => ApiClient(
  baseUrl: 'http://test',
  httpClient: MockClient(handler),
  tokenStorage: storage ?? _MemoryTokenStorage('test-token'),
);

void main() {
  group('RentScheduleItem', () {
    test('parses a valid item, decimal amount, DateOnly, and timestamps', () {
      final item = RentScheduleItem.fromJson(_itemJson());
      expect(item.id, _itemId);
      expect(item.leaseAgreementId, _leaseId);
      expect(item.dueDate, DateTime(2030, 2, 28));
      expect(item.amount, 1250.75);
      expect(item.status, RentScheduleStatus.pending);
      expect(item.createdAt, DateTime.utc(2030, 1, 15, 3, 30));
      expect(item.updatedAt, DateTime.utc(2030, 2, 1, 16, 15));
    });

    test('accepts nullable updatedAt', () {
      expect(
        RentScheduleItem.fromJson(_itemJson()..['updatedAt'] = null).updatedAt,
        isNull,
      );
    });

    test('maps numeric statuses and rejects unknown or non-numeric values', () {
      expect(
        RentScheduleItem.fromJson(_itemJson(status: 0)).status,
        RentScheduleStatus.pending,
      );
      expect(
        RentScheduleItem.fromJson(_itemJson(status: 1)).status,
        RentScheduleStatus.paid,
      );
      expect(
        RentScheduleItem.fromJson(_itemJson(status: 2)).status,
        RentScheduleStatus.overdue,
      );
      expect(
        () => RentScheduleItem.fromJson(_itemJson(status: 3)),
        throwsFormatException,
      );
      expect(
        () => RentScheduleItem.fromJson(_itemJson()..['status'] = 'Pending'),
        throwsFormatException,
      );
    });

    test('rejects malformed and missing required values', () {
      for (final malformed in [
        _itemJson()..remove('id'),
        _itemJson()..['leaseAgreementId'] = '',
        _itemJson()..['dueDate'] = '2030-02-30',
        _itemJson()..['amount'] = '1250.75',
        _itemJson()..remove('status'),
        _itemJson()..['createdAt'] = '2030-01-15T09:00:00',
        _itemJson()..['updatedAt'] = 1,
      ]) {
        expect(
          () => RentScheduleItem.fromJson(malformed),
          throwsFormatException,
        );
      }
    });
  });

  group('RentScheduleOutstandingSummary', () {
    test('parses numeric totals and schedule items', () {
      final summary = RentScheduleOutstandingSummary.fromJson(_summaryJson());
      expect(summary.totalPending, 1250.75);
      expect(summary.totalOverdue, 500);
      expect(summary.totalOutstanding, 1750.75);
      expect(summary.items.single.id, _itemId);
    });

    test('accepts an empty item list', () {
      expect(
        RentScheduleOutstandingSummary.fromJson(
          _summaryJson(items: const []),
        ).items,
        isEmpty,
      );
    });

    test('rejects malformed totals and items', () {
      expect(
        () => RentScheduleOutstandingSummary.fromJson(
          _summaryJson()..['totalPending'] = '1250.75',
        ),
        throwsFormatException,
      );
      expect(
        () => RentScheduleOutstandingSummary.fromJson(
          _summaryJson()..['items'] = {},
        ),
        throwsFormatException,
      );
      expect(
        () =>
            RentScheduleOutstandingSummary.fromJson(_summaryJson(items: [{}])),
        throwsFormatException,
      );
    });
  });

  group('RentScheduleApiService', () {
    test(
      'uses exact routes, authenticated bearer headers, and parses bodies',
      () async {
        final requests = <http.Request>[];
        final client = _client((request) async {
          requests.add(request);
          final path = request.url.path;
          final body =
              path.endsWith('/outstanding') ||
                  path.endsWith('/outstanding/mine')
              ? _summaryJson()
              : path.endsWith('/mine') || path.endsWith('/lease/$_leaseId')
              ? [_itemJson()]
              : _itemJson();
          return http.Response(jsonEncode(body), 200);
        });
        addTearDown(client.close);
        final service = RentScheduleApiService(client);

        expect((await service.getMyItems()).single.id, _itemId);
        expect((await service.getMyOutstanding()).totalOutstanding, 1750.75);
        expect((await service.getByLease(_leaseId)).single.id, _itemId);
        expect(
          (await service.getOutstandingByLease(_leaseId)).items.single.id,
          _itemId,
        );
        expect((await service.getItem(_itemId)).id, _itemId);

        expect(
          requests.map((request) => request.method),
          List.filled(5, 'GET'),
        );
        expect(requests.map((request) => request.url.path), [
          '/api/rent-schedules/mine',
          '/api/rent-schedules/outstanding/mine',
          '/api/rent-schedules/lease/$_leaseId',
          '/api/rent-schedules/lease/$_leaseId/outstanding',
          '/api/rent-schedules/$_itemId',
        ]);
        for (final request in requests) {
          expect(request.headers['Authorization'], 'Bearer test-token');
        }
      },
    );

    test(
      '401 uses shared unauthorized handling and returns a safe error',
      () async {
        final storage = _MemoryTokenStorage('test-token');
        final client = _client(
          (_) async => http.Response('private server details', 401),
          storage: storage,
        );
        addTearDown(client.close);
        await expectLater(
          RentScheduleApiService(client).getMyItems(),
          throwsA(
            isA<RentScheduleApiException>()
                .having((error) => error.statusCode, 'statusCode', 401)
                .having(
                  (error) => error.message,
                  'message',
                  'Your session has expired.',
                ),
          ),
        );
        expect(storage.token, isNull);
      },
    );

    for (final (status, message) in [
      (403, 'You do not have permission to access this resource.'),
      (404, 'The requested rent schedule is unavailable.'),
      (500, 'The rent schedule request failed. Please try again.'),
    ]) {
      test('handles HTTP $status safely', () async {
        final client = _client(
          (_) async => http.Response('private server details', status),
        );
        addTearDown(client.close);
        await expectLater(
          RentScheduleApiService(client).getItem(_itemId),
          throwsA(
            isA<RentScheduleApiException>()
                .having((error) => error.statusCode, 'statusCode', status)
                .having((error) => error.message, 'message', message),
          ),
        );
      });
    }

    test('wraps connection errors safely', () async {
      final client = _client(
        (_) async => throw http.ClientException('private socket detail'),
      );
      addTearDown(client.close);
      await expectLater(
        RentScheduleApiService(client).getMyItems(),
        throwsA(
          isA<RentScheduleApiException>().having(
            (error) => error.message,
            'message',
            'Unable to connect to the rent schedule service.',
          ),
        ),
      );
    });

    test('wraps malformed JSON and malformed DTO responses safely', () async {
      for (final body in ['{', '{}', '[{}]']) {
        final client = _client((_) async => http.Response(body, 200));
        try {
          await expectLater(
            RentScheduleApiService(client).getMyItems(),
            throwsA(isA<RentScheduleApiException>()),
          );
        } finally {
          client.close();
        }
      }
    });
  });
}
