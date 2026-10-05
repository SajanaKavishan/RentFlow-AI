import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/support/models/support_ticket.dart';
import 'package:rentflow_mobile/shared/profile/create_support_request_screen.dart';
import 'package:rentflow_mobile/shared/profile/help_support_screen.dart';

import 'helpers/support_backend.dart';

void main() {
  late SupportBackend backend;
  setUp(() => backend = SupportBackend());
  tearDown(() => backend.dispose());

  Future<void> open(WidgetTester tester) async {
    await backend.pump(tester);
    await openNewSupport(tester);
  }

  testWidgets('category must be selected and exposes only supported labels', (
    tester,
  ) async {
    await open(tester);
    await fillSupport(tester, category: null);
    expect(supportSubmit(tester).onPressed, isNull);
    expect(backend.creates, isEmpty);
    await tapSupport(tester, find.byKey(const Key('support-category-picker')));
    for (final category in SupportCategory.values) {
      expect(
        find.byKey(ValueKey('support-category-${category.value}')),
        findsOneWidget,
      );
      expect(find.text(category.label), findsOneWidget);
    }
    await tapSupport(tester, find.text('Payment'));
    expect(supportSubmit(tester).onPressed, isNotNull);
  });

  for (final entry in [
    ('subject required', '', 'Valid message', 'Enter a subject.'),
    ('subject whitespace', ' \n ', 'Valid message', 'Enter a subject.'),
    (
      'subject maximum',
      's' * 201,
      'Valid message',
      'Use no more than 200 characters.',
    ),
    ('message required', 'Valid subject', '', 'Enter a message.'),
    ('message whitespace', 'Valid subject', ' \n ', 'Enter a message.'),
    (
      'message maximum',
      'Valid subject',
      'm' * 4001,
      'Use no more than 4,000 characters.',
    ),
  ]) {
    testWidgets('${entry.$1} rejects invalid input without POST', (
      tester,
    ) async {
      await open(tester);
      await fillSupport(tester);
      await fillSupport(
        tester,
        category: null,
        subject: entry.$2,
        message: entry.$3,
      );
      expect(supportSubmit(tester).onPressed, isNull);
      expect(find.text(entry.$4), findsOneWidget);
      expect(backend.creates, isEmpty);
    });
  }

  testWidgets('maximum trimmed lengths are valid', (tester) async {
    await open(tester);
    await fillSupport(
      tester,
      subject: ' ${'s' * 200} ',
      message: ' ${'m' * 4000} ',
    );
    expect(supportSubmit(tester).onPressed, isNotNull);
    await tapSupport(tester, find.byKey(const Key('support-submit')));
    expect(backend.creates, hasLength(1));
    final body =
        jsonDecode(backend.creates.single.body) as Map<String, dynamic>;
    expect((body['subject'] as String).length, 200);
    expect((body['message'] as String).length, 4000);
    expect(find.text('Support request submitted.'), findsOneWidget);
  });

  testWidgets(
    'valid submission trims input and inserts only the authoritative returned ticket',
    (tester) async {
      backend.createdOverride = ticketJson(
        id: 'real-response-id',
        category: 'AccountLogin',
        subject: 'Server-confirmed subject',
        message: 'Server-confirmed message',
        status: 'InProgress',
        created: '2031-05-06T12:00:00Z',
        updated: '2031-05-07T12:00:00Z',
      );
      await open(tester);
      await fillSupport(
        tester,
        subject: '  Local subject  ',
        message: '\n Local message  ',
      );
      await tapSupport(tester, find.byKey(const Key('support-submit')));
      expect(find.byType(CreateSupportRequestScreen), findsNothing);
      expect(find.text('Support request submitted.'), findsOneWidget);
      expect(jsonDecode(backend.creates.single.body), {
        'category': 'Other',
        'subject': 'Local subject',
        'message': 'Local message',
      });
      final cards = tester
          .widgetList<SupportTicketCard>(find.byType(SupportTicketCard))
          .toList();
      expect(cards.map((card) => card.ticket.id), [
        'real-response-id',
        'server-ticket',
      ]);
      expect(cards.first.ticket.status, SupportStatus.inProgress);
      expect(cards.first.ticket.createdAt, DateTime.utc(2031, 5, 6, 12));
      expect(find.text('Server-confirmed subject'), findsOneWidget);
      expect(find.text('Local subject'), findsNothing);
      expect(find.text('In progress'), findsOneWidget);
      expect(backend.loads, hasLength(1));
    },
  );

  testWidgets('pending submission locks draft and prevents duplicate POST', (
    tester,
  ) async {
    backend.pendingPost = Completer<http.Response>();
    await open(tester);
    await fillSupport(tester);
    final submit = supportSubmit(tester).onPressed!;
    submit();
    submit();
    await tester.pumpAndSettle();
    expect(backend.creates, hasLength(1));
    expect(supportSubmit(tester).onPressed, isNull);
    expect(find.text('Submitting request…'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('support-subject')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('support-message')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('support-category-picker')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Back to support',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Support request submitted.'), findsNothing);
    expect(
      tester.widgetList<SupportTicketCard>(
        find.byType(SupportTicketCard, skipOffstage: false),
      ),
      hasLength(1),
    );
    backend.pendingPost!.complete(
      http.Response(jsonEncode(ticketJson(id: 'confirmed')), 201),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CreateSupportRequestScreen), findsNothing);
    expect(
      tester
          .widgetList<SupportTicketCard>(find.byType(SupportTicketCard))
          .first
          .ticket
          .id,
      'confirmed',
    );
  });

  for (final failure in ['server', 'network', 'malformed success']) {
    testWidgets('$failure preserves draft, stays open and can retry', (
      tester,
    ) async {
      await open(tester);
      await fillSupport(
        tester,
        category: SupportCategory.propertyApplication,
        subject: ' My subject ',
        message: ' My message\nwith detail ',
      );
      if (failure == 'server') backend.postStatus = 500;
      if (failure == 'network') backend.networkFailure = true;
      if (failure == 'malformed success') backend.postBody = '{}';
      await tapSupport(tester, find.byKey(const Key('support-submit')));
      expect(find.byType(CreateSupportRequestScreen), findsOneWidget);
      expect(find.byKey(const Key('support-create-error')), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
      expect(find.text('Support request submitted.'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('support-subject')))
            .controller!
            .text,
        ' My subject ',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('support-message')))
            .controller!
            .text,
        ' My message\nwith detail ',
      );
      expect(find.text('Property & application'), findsOneWidget);
      expect(supportSubmit(tester).onPressed, isNotNull);
      backend.postStatus = 201;
      backend.networkFailure = false;
      backend.postBody = null;
      await tapSupport(tester, find.byKey(const Key('support-submit')));
      expect(backend.creates, hasLength(2));
      expect(find.text('Support request submitted.'), findsOneWidget);
      expect(find.byType(SupportTicketCard), findsNWidgets(2));
    });
  }

  testWidgets('canceling a draft does not submit or change history', (
    tester,
  ) async {
    await open(tester);
    await fillSupport(tester);
    await tapSupport(tester, find.byTooltip('Back to support'));
    expect(backend.creates, isEmpty);
    expect(find.text('Support request submitted.'), findsNothing);
    expect(find.byType(SupportTicketCard), findsOneWidget);
  });

  testWidgets(
    'form fields and actions are labelled and support multiline input',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester);
      expect(
        find.bySemanticsLabel(RegExp('Choose a category')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Subject')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Message')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Submit request')), findsOneWidget);
      // TextFormField delegates its keyboard configuration to the TextField.
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('support-message')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.minLines, 4);
      expect(field.maxLines, 8);
      expect(field.keyboardType, TextInputType.multiline);
      expect(field.textInputAction, TextInputAction.newline);
      semantics.dispose();
    },
  );

  for (final device in [
    (320.0, 780.0, 1.0),
    (720.0, 1560.0, 2.0),
    (1080.0, 2340.0, 3.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'form and keyboard fit ${device.$1}×${device.$2} at ${scale}x',
        (tester) async {
          tester.view.physicalSize = Size(device.$1, device.$2);
          tester.view.devicePixelRatio = device.$3;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await backend.pump(tester, scale: scale);
          await openNewSupport(tester);
          await fillSupport(
            tester,
            category: SupportCategory.propertyApplication,
            subject: 'Long translated-looking subject ' * 6,
            message: 'Long translated-looking multiline explanation.\n' * 75,
          );
          tester.view.viewInsets = FakeViewPadding(bottom: 280 * device.$3);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('support-message')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('support-submit')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            MediaQuery.textScalerOf(
              tester.element(find.byType(CreateSupportRequestScreen)),
            ).scale(14),
            14 * scale,
          );
          expect(supportSubmit(tester).onPressed, isNotNull);
        },
      );
    }
  }
}
