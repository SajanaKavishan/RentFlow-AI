import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/shared/profile/help_support_screen.dart';

import 'helpers/support_backend.dart';

void main() {
  late SupportBackend backend;
  setUp(() => backend = SupportBackend());
  tearDown(() => backend.dispose());

  for (final role in UserRole.values) {
    testWidgets('Profile support visibility and navigation for ${role.name}', (
      tester,
    ) async {
      backend.dispose();
      backend = SupportBackend(role: role);
      await backend.pump(tester, fromProfile: true);
      expect(find.text('Feedback'), findsNothing);
      if (role == UserRole.admin) {
        expect(find.text('Support'), findsNothing);
        expect(find.text('Help & support'), findsNothing);
      } else {
        expect(find.text('Support'), findsOneWidget);
        await tapSupport(tester, find.text('Help & support'));
        expect(find.byType(HelpSupportScreen), findsOneWidget);
        expect(backend.loads, hasLength(1));
        await tapSupport(tester, find.byTooltip('Back to Profile'));
        expect(find.byType(HelpSupportScreen), findsNothing);
      }
    });
  }

  testWidgets('initial load has no invented history or empty state', (
    tester,
  ) async {
    backend.pendingGet = Completer<http.Response>();
    await backend.pump(tester, settle: false);
    expect(find.text('Loading support requests…'), findsOneWidget);
    expect(find.byType(SupportTicketCard), findsNothing);
    expect(find.text('No support requests yet.'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('support-new-request')))
          .onPressed,
      isNull,
    );
    backend.pendingGet!.complete(
      http.Response(jsonEncode(backend.tickets), 200),
    );
    await tester.pumpAndSettle();
    expect(find.text('Loading support requests…'), findsNothing);
    expect(find.byType(SupportTicketCard), findsOneWidget);
  });

  testWidgets(
    'real history preserves API order and displays all status labels',
    (tester) async {
      backend.tickets = [
        ticketJson(
          id: 'newest',
          subject: 'Newest request',
          category: 'TechnicalIssue',
          status: 'Open',
        ),
        ticketJson(
          id: 'middle',
          subject: 'Middle request',
          category: 'AccountLogin',
          status: 'InProgress',
        ),
        ticketJson(
          id: 'oldest',
          subject: 'Oldest request',
          category: 'Other',
          status: 'Resolved',
        ),
      ];
      await backend.pump(tester);
      final cards = tester
          .widgetList<SupportTicketCard>(find.byType(SupportTicketCard))
          .toList();
      expect(cards.map((card) => card.ticket.id), [
        'newest',
        'middle',
        'oldest',
      ]);
      for (final text in [
        'Open',
        'In progress',
        'Resolved',
        'Technical issue',
        'Account & login',
        'Other',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('InProgress'), findsNothing);
      final context = tester.element(find.byType(HelpSupportScreen));
      final date = MaterialLocalizations.of(
        context,
      ).formatShortDate(cards.first.ticket.createdAt.toLocal());
      expect(find.text('Created $date'), findsNWidgets(3));
      await tapSupport(tester, find.text('Newest request'));
      expect(find.text('Original message'), findsOneWidget);
      expect(find.text('The upload does not finish.'), findsOneWidget);
      final updated = MaterialLocalizations.of(
        context,
      ).formatShortDate(cards.first.ticket.updatedAt.toLocal());
      expect(find.text('Updated $updated'), findsOneWidget);
      expect(backend.creates, isEmpty);
      expect(
        backend.requests.where((r) => r.url.path.startsWith(supportPath)),
        hasLength(1),
      );
    },
  );

  testWidgets('empty history offers a working new request action', (
    tester,
  ) async {
    backend.tickets = [];
    await backend.pump(tester);
    expect(find.text('No support requests yet.'), findsOneWidget);
    expect(
      find.text('Need help? Create a request and our team can review it.'),
      findsOneWidget,
    );
    await openNewSupport(tester);
    expect(find.text('New request'), findsOneWidget);
  });

  testWidgets('load failure shows safe error and Retry recovers', (
    tester,
  ) async {
    backend.getStatus = 500;
    backend.getBody = 'private backend trace';
    await backend.pump(tester);
    expect(find.text('Support requests unavailable'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    expect(find.text('No support requests yet.'), findsNothing);
    expect(find.byType(SupportTicketCard), findsNothing);
    backend.getStatus = 200;
    backend.getBody = null;
    await tapSupport(tester, find.text('Retry'));
    expect(backend.loads, hasLength(2));
    expect(find.text('Support requests unavailable'), findsNothing);
    expect(find.byType(SupportTicketCard), findsOneWidget);
  });

  testWidgets('confirmed creation survives a subsequent failed history Retry', (
    tester,
  ) async {
    backend.getStatus = 500;
    await backend.pump(tester);
    await openNewSupport(tester);
    await fillSupport(tester);
    await tapSupport(tester, find.byKey(const Key('support-submit')));
    expect(find.text('Support request submitted.'), findsOneWidget);
    expect(
      tester
          .widget<SupportTicketCard>(find.byType(SupportTicketCard))
          .ticket
          .id,
      'created-by-server',
    );
    await tapSupport(tester, find.text('Retry'));
    expect(find.text('Support requests unavailable'), findsOneWidget);
    expect(find.byType(SupportTicketCard), findsOneWidget);
    expect(find.text('No support requests yet.'), findsNothing);
  });

  testWidgets('history actions, status and loading have readable semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await backend.pump(tester);
    expect(
      find.bySemanticsLabel(RegExp('New support request')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Open')), findsWidgets);
    expect(find.byTooltip('Back to Profile'), findsOneWidget);
    semantics.dispose();
  });

  for (final device in [
    (320.0, 780.0, 1.0),
    (720.0, 1560.0, 2.0),
    (1080.0, 2340.0, 3.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'history long content fits ${device.$1}×${device.$2} at ${scale}x',
        (tester) async {
          tester.view.physicalSize = Size(device.$1, device.$2);
          tester.view.devicePixelRatio = device.$3;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          backend.tickets = [
            ticketJson(
              category: 'PropertyApplication',
              status: 'InProgress',
              subject:
                  'Long translated-looking subject with difficult words ' * 4,
              message:
                  'Long multiline explanation with detailed information.\n' *
                  75,
            ),
          ];
          await backend.pump(tester, scale: scale);
          final card = find.byType(SupportTicketCard);
          await tapSupport(
            tester,
            find.descendant(of: card, matching: find.byIcon(Icons.expand_more)),
          );
          await tester.ensureVisible(find.text('Original message'));
          await tester.pumpAndSettle();
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            MediaQuery.textScalerOf(tester.element(card)).scale(14),
            14 * scale,
          );
        },
      );
    }
  }
}
