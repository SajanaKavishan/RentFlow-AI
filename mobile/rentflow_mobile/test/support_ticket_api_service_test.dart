import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/support/models/support_ticket.dart';
import 'package:rentflow_mobile/features/support/services/support_ticket_api_service.dart';

import 'helpers/support_backend.dart';

void main() {
  late SupportBackend backend;
  setUp(() => backend = SupportBackend());
  tearDown(() => backend.dispose());
  CreateSupportTicketRequest request({
    SupportCategory category = SupportCategory.other,
    String subject = 'Suggestion',
    String message = 'Improve the filters.',
  }) => CreateSupportTicketRequest(
    category: category,
    subject: subject,
    message: message,
  );

  test(
    'GET uses JWT-owned mine route without owner ID and preserves API order',
    () async {
      backend.tickets = [
        ticketJson(id: 'first', created: '2026-10-04T12:00:00Z'),
        ticketJson(id: 'second', created: '2026-10-03T12:00:00Z'),
      ];
      final tickets = await backend.service.getMySupportTickets();
      expect(tickets.map((ticket) => ticket.id), ['first', 'second']);
      expect(backend.loads.single.url.path, '$supportPath/mine');
      expect(backend.loads.single.url.query, isEmpty);
      expect(
        backend.loads.single.headers['Authorization'],
        'Bearer support-token',
      );
      expect(tickets.first.createdAt, DateTime.utc(2026, 10, 4, 12));
      expect(tickets.first.message, 'The upload does not finish.');
    },
  );
  test('empty owner history parses as an empty list', () async {
    backend.tickets = [];
    expect(await backend.service.getMySupportTickets(), isEmpty);
  });
  for (final category in SupportCategory.values) {
    test(
      'POST ${category.value} trims input and sends only category/subject/message',
      () async {
        await backend.storage.saveToken('replacement-token');
        final ticket = await backend.service.createSupportTicket(
          request(
            category: category,
            subject: '  Subject  ',
            message: '\n Message \t',
          ),
        );
        final sent = backend.creates.single;
        expect(sent.url.path, supportPath);
        expect(sent.url.query, isEmpty);
        expect(sent.headers['Authorization'], 'Bearer replacement-token');
        expect(sent.headers['Content-Type'], 'application/json');
        expect(jsonDecode(sent.body), {
          'category': category.value,
          'subject': 'Subject',
          'message': 'Message',
        });
        expect(ticket.id, 'created-by-server');
        expect(ticket.category, category);
        expect(ticket.status, SupportStatus.open);
        expect(ticket.createdAt, DateTime.utc(2030, 2, 3, 10));
      },
    );
  }
  test('category/status labels are exact supported mappings', () {
    expect(SupportCategory.values.map((v) => v.value), [
      'TechnicalIssue',
      'AccountLogin',
      'PropertyApplication',
      'Payment',
      'Other',
    ]);
    expect(SupportCategory.values.map((v) => v.label), [
      'Technical issue',
      'Account & login',
      'Property & application',
      'Payment',
      'Other',
    ]);
    expect(SupportStatus.values.map((v) => v.value), [
      'Open',
      'InProgress',
      'Resolved',
    ]);
    expect(SupportStatus.values.map((v) => v.label), [
      'Open',
      'In progress',
      'Resolved',
    ]);
  });
  for (final key in [
    'id',
    'category',
    'subject',
    'message',
    'status',
    'createdAt',
    'updatedAt',
  ]) {
    test('ticket rejects missing $key', () {
      final json = ticketJson()..remove(key);
      expect(() => SupportTicket.fromJson(json), throwsFormatException);
    });
    test('ticket rejects non-string $key', () {
      expect(
        () => SupportTicket.fromJson({...ticketJson(), key: 123}),
        throwsFormatException,
      );
    });
  }
  for (final entry in {
    'id': ' ',
    'subject': ' ',
    'message': ' ',
    'category': 'Technical issue',
    'status': 'In progress',
    'createdAt': 'not a date',
    'updatedAt': 'not a date',
  }.entries) {
    test('ticket rejects invalid ${entry.key} value', () {
      expect(
        () => SupportTicket.fromJson({...ticketJson(), entry.key: entry.value}),
        throwsFormatException,
      );
    });
  }
  for (final value in [null, 'other', '1', 'Unknown']) {
    test('unknown category/status $value is rejected without a fallback', () {
      expect(() => SupportCategory.parse(value), throwsFormatException);
      expect(() => SupportStatus.parse(value), throwsFormatException);
    });
  }
  for (final value in [
    request(subject: ''),
    request(subject: ' \n '),
    request(subject: 'a' * 201),
    request(message: ''),
    request(message: ' \n '),
    request(message: 'a' * 4001),
  ]) {
    test(
      'invalid request is rejected before POST: ${value.validate()}',
      () async {
        await expectLater(
          backend.service.createSupportTicket(value),
          throwsA(isA<SupportTicketApiException>()),
        );
        expect(backend.creates, isEmpty);
      },
    );
  }
  test('trimmed maximum subject/message lengths are accepted', () async {
    await backend.service.createSupportTicket(
      request(subject: ' ${'s' * 200} ', message: ' ${'m' * 4000} '),
    );
    final body = jsonDecode(backend.creates.single.body);
    expect((body['subject'] as String).length, 200);
    expect((body['message'] as String).length, 4000);
  });
  for (final body in [
    'not-json',
    'null',
    '{}',
    '[null]',
    jsonEncode([ticketJson()..remove('id')]),
  ]) {
    test('GET malformed response rejected: $body', () async {
      backend.getBody = body;
      await expectLater(
        backend.service.getMySupportTickets(),
        throwsA(isA<SupportTicketApiException>()),
      );
    });
  }
  for (final body in [
    'not-json',
    'null',
    '[]',
    '{}',
    jsonEncode(ticketJson()..remove('status')),
  ]) {
    test('POST malformed success rejected: $body', () async {
      backend.postBody = body;
      await expectLater(
        backend.service.createSupportTicket(request()),
        throwsA(isA<SupportTicketApiException>()),
      );
    });
  }
  for (final method in ['GET', 'POST']) {
    for (final status in [400, 403, 429, 500]) {
      test('$method $status exposes a safe error', () async {
        backend.getStatus = status;
        backend.postStatus = status;
        backend.getBody = 'private server trace';
        final future = method == 'GET'
            ? backend.service.getMySupportTickets()
            : backend.service.createSupportTicket(request());
        await expectLater(
          future,
          throwsA(
            isA<SupportTicketApiException>()
                .having((e) => e.statusCode, 'status', status)
                .having(
                  (e) => e.message,
                  'safe error',
                  isNot(contains('private')),
                ),
          ),
        );
      });
    }
    test('$method 401 uses existing authenticated-session handling', () async {
      await backend.auth.restoreSession();
      backend.getStatus = 401;
      backend.postStatus = 401;
      final future = method == 'GET'
          ? backend.service.getMySupportTickets()
          : backend.service.createSupportTicket(request());
      await expectLater(
        future,
        throwsA(
          isA<SupportTicketApiException>().having(
            (e) => e.statusCode,
            'status',
            401,
          ),
        ),
      );
      expect(backend.auth.isAuthenticated, isFalse);
      expect(backend.storage.token, isNull);
    });
    test(
      '$method connection failure is retryable and hides internals',
      () async {
        backend.networkFailure = true;
        final future = method == 'GET'
            ? backend.service.getMySupportTickets()
            : backend.service.createSupportTicket(request());
        await expectLater(
          future,
          throwsA(
            isA<SupportTicketApiException>().having(
              (e) => e.message,
              'safe error',
              'Unable to connect. Please try again.',
            ),
          ),
        );
      },
    );
  }
  test('request timeout gives a safe retry error', () async {
    backend.dispose();
    backend = SupportBackend(timeout: const Duration(milliseconds: 20));
    backend.pendingGet = Completer();
    await expectLater(
      backend.service.getMySupportTickets(),
      throwsA(isA<SupportTicketApiException>()),
    );
  });
}
