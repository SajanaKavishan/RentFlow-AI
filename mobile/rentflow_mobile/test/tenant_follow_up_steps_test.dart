import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_details_screen.dart';
import 'package:rentflow_mobile/features/viewing_follow_ups/widgets/viewing_follow_up_dialog.dart';
import 'viewing_follow_up_test.dart' as flow;
import 'rental_application_wizard_test.dart' as wizard;

const reviewPath = '/api/viewings/viewing-1/review';

Future<void> rate(WidgetTester tester) async {
  await flow.choose(tester, find.byKey(const Key('property-rating-4')));
  await flow.choose(tester, find.byKey(const Key('landlord-rating-5')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'review save in flight blocks duplicate saves and Skip; no application step before acknowledgment',
    (tester) async {
      final backend = flow.Backend()..reviewSaveGate = Completer<void>();
      await flow.pump(tester, backend);
      await rate(tester);
      await flow.choose(tester, flow.submitReview);
      await tester.pump();
      expect(tester.widget<FilledButton>(flow.submitReview).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(flow.skipReview).onPressed, isNull);
      expect(flow.applicationStep, findsNothing);
      expect(flow.reviewStep, findsOneWidget);
      expect(backend.discovery.calls(reviewPath, 'PUT'), 1);
      expect(backend.discovery.calls(flow.respondPath, 'POST'), 0);
      backend.reviewSaveGate!.complete();
      await tester.pumpAndSettle();
      expect(flow.reviewStep, findsNothing);
      expect(flow.applicationStep, findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(backend.discovery.calls(reviewPath, 'PUT'), 1);
    },
  );
  testWidgets(
    'ratings alone allow Submit; review save alone never responds or creates an application',
    (tester) async {
      final backend = flow.Backend();
      await flow.pump(tester, backend);
      await rate(tester);
      expect(
        tester.widget<FilledButton>(flow.submitReview).onPressed,
        isNotNull,
      );
      await flow.choose(tester, flow.submitReview);
      await tester.pumpAndSettle();
      expect(backend.review!['propertyRating'], 4);
      expect(backend.review!['landlordRating'], 5);
      expect(backend.review!['comment'], '');
      expect(flow.applicationStep, findsOneWidget);
      expect(flow.reviewStep, findsNothing);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(backend.discovery.calls(flow.respondPath, 'POST'), 0);
      expect(backend.discovery.calls('/api/rental-applications', 'POST'), 0);
    },
  );

  testWidgets('Skip with edits preserves the existing persisted review', (
    tester,
  ) async {
    final saved = {
      'id': 'review-1',
      'viewingId': 'viewing-1',
      'propertyRating': 2,
      'landlordRating': 3,
      'comment': 'Already saved',
    };
    final backend = flow.Backend()..review = Map.of(saved);
    await flow.pump(tester, backend);
    await rate(tester);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Unsubmitted changes');
    await flow.choose(tester, flow.skipReview);
    await tester.pumpAndSettle();
    expect(backend.review, saved);
    expect(backend.discovery.calls(reviewPath, 'PUT'), 0);
    expect(backend.discovery.calls(reviewPath, 'DELETE'), 0);
    expect(backend.discovery.calls(flow.respondPath, 'POST'), 0);
    expect(flow.applicationStep, findsOneWidget);
  });

  testWidgets(
    'editing back to original review continues without rewriting unchanged data',
    (tester) async {
      final backend = flow.Backend()
        ..review = {
          'id': 'review-1',
          'viewingId': 'viewing-1',
          'propertyRating': 2,
          'landlordRating': 3,
          'comment': 'Saved',
        };
      await flow.pump(tester, backend);
      await flow.choose(tester, find.byKey(const Key('property-rating-5')));
      await tester.pumpAndSettle();
      expect(find.text('Update review'), findsOneWidget);
      await flow.choose(tester, find.byKey(const Key('property-rating-2')));
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '  Saved  ');
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      await flow.choose(tester, flow.submitReview);
      await tester.pumpAndSettle();
      expect(backend.discovery.calls(reviewPath, 'PUT'), 0);
      expect(flow.applicationStep, findsOneWidget);
    },
  );

  testWidgets(
    'review load failure disables submission and supports retry or explicit Skip',
    (tester) async {
      final backend = flow.Backend()..failReviewLoad = true;
      await flow.pump(tester, backend);
      expect(find.text('Could not load your viewing review.'), findsOneWidget);
      expect(tester.widget<FilledButton>(flow.submitReview).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(flow.skipReview).onPressed,
        isNotNull,
      );
      backend.failReviewLoad = false;
      await flow.choose(tester, find.text('Retry review'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(backend.discovery.calls(reviewPath, 'GET'), 2);
      expect(backend.discovery.calls(flow.respondPath, 'POST'), 0);
    },
  );

  testWidgets('loading review is announced and cannot Submit while pending', (
    tester,
  ) async {
    final backend = flow.Backend()..reviewGate = Completer<void>();
    await flow.pump(tester, backend);
    expect(find.text('Loading your viewing review...'), findsOneWidget);
    expect(tester.widget<FilledButton>(flow.submitReview).onPressed, isNull);
    backend.reviewGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('comment limit is 500; trim before existing PUT', (tester) async {
    final backend = flow.Backend();
    await flow.pump(tester, backend);
    await rate(tester);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(
      find.byType(TextField),
      List.filled(510, 'a').join(),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLength, 500);
    expect(field.controller!.text.length, 500);
    await tester.enterText(find.byType(TextField), '  A useful viewing  ');
    await flow.choose(tester, flow.submitReview);
    await tester.pumpAndSettle();
    expect(backend.review!['comment'], 'A useful viewing');
  });

  testWidgets(
    'review saved before app interruption is prefilled on reclaimed same follow-up',
    (tester) async {
      final backend = flow.Backend();
      await flow.pump(tester, backend);
      await rate(tester);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
        find.byType(TextField),
        'Saved before interruption',
      );
      await flow.choose(tester, flow.submitReview);
      await tester.pumpAndSettle();
      expect(flow.applicationStep, findsOneWidget);
      expect(backend.discovery.calls(flow.respondPath, 'POST'), 0);
      await tester.pumpWidget(const SizedBox());
      await flow.pump(tester, backend);
      expect(find.byType(Dialog), findsNothing);
      backend.prompts.add({
        ...flow.prompt(),
        'claimedAt': '2030-01-02T10:10:00Z',
        'claimExpiresAt': '2030-01-02T10:20:00Z',
      });
      await flow.resume(tester);
      expect(flow.reviewStep, findsOneWidget);
      expect(
        tester
            .widget<ViewingFollowUpDialog>(find.byType(ViewingFollowUpDialog))
            .followUp
            .id,
        'follow-up-1',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Saved before interruption',
      );
      expect(find.text('Continue'), findsOneWidget);
      await flow.choose(tester, flow.submitReview);
      await tester.pumpAndSettle();
      expect(backend.discovery.calls(reviewPath, 'PUT'), 1);
      expect(backend.discovery.calls(flow.respondPath, 'POST'), 0);
      await flow.choose(tester, flow.notNow);
      await tester.pumpAndSettle();
      expect(backend.discovery.calls(flow.respondPath, 'POST'), 1);
    },
  );

  testWidgets(
    'Apply eligibility recovery retries navigation without rewriting saved decision',
    (tester) async {
      final backend = flow.Backend();
      await flow.pump(tester, backend);
      backend.canApply = false;
      await flow.choose(tester, flow.applyNow);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This property is currently unavailable. Your choice was saved.',
        ),
        findsOneWidget,
      );
      expect(flow.notNow, findsNothing);
      backend.canApply = true;
      backend.applicationStatus = 1;
      backend.fixture.application['status'] = 1;
      await flow.choose(tester, find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(RentalApplicationDetailsScreen), findsOneWidget);
      expect(
        tester
            .widget<RentalApplicationDetailsScreen>(
              find.byType(RentalApplicationDetailsScreen),
            )
            .application
            .id,
        wizard.id,
      );
      expect(backend.discovery.calls(flow.respondPath, 'POST'), 1);
      expect(
        jsonDecode(
          backend.discovery.requests
              .singleWhere((r) => r.url.path == flow.respondPath)
              .body,
        ),
        {'decision': 'ApplyNow'},
      );
      expect(
        backend.discovery.calls(flow.eligibilityPath),
        greaterThanOrEqualTo(2),
      );
      expect(backend.discovery.calls('/api/rental-applications', 'POST'), 0);
    },
  );

  testWidgets('Not now preserves later authoritative application eligibility', (
    tester,
  ) async {
    final backend = flow.Backend();
    await flow.pump(tester, backend);
    await flow.choose(tester, flow.notNow);
    await tester.pumpAndSettle();
    expect(backend.discovery.calls('/api/rental-applications', 'POST'), 0);
    final response = await backend.discovery.client.get(
      backend.discovery.client.buildUri(flow.eligibilityPath),
    );
    expect(response.statusCode, 200);
    expect(
      (jsonDecode(response.body) as Map<String, dynamic>)['canApply'],
      true,
    );
    expect(
      jsonDecode(
        backend.discovery.requests
            .singleWhere((r) => r.url.path == flow.respondPath)
            .body,
      ),
      {'decision': 'NotNow'},
    );
    expect(backend.review, isNull);
  });

  testWidgets(
    'modal title, star selections and actions have accessible names and sizes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final backend = flow.Backend();
      await flow.pump(tester, backend);
      final title = tester
          .getSemantics(find.text('How did your viewing go?'))
          .getSemanticsData();
      expect(title.flagsCollection.namesRoute, true);
      expect(title.flagsCollection.isHeader, true);
      await flow.choose(tester, find.byKey(const Key('property-rating-4')));
      await tester.pumpAndSettle();
      final star = tester
          .getSemantics(find.byKey(const Key('property-rating-4')))
          .getSemanticsData();
      expect(star.label, contains('Property during the viewing: 4 of 5'));
      expect(star.flagsCollection.isSelected.toBoolOrNull(), true);
      expect(
        tester.getSize(find.byKey(const Key('property-rating-4'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byKey(const Key('property-rating-4'))).width,
        greaterThanOrEqualTo(48),
      );
      await flow.choose(tester, flow.skipReview);
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.text('Would you like to apply?'))
            .getSemanticsData()
            .flagsCollection
            .namesRoute,
        true,
      );
      expect(
        tester.getSemantics(flow.notNow).getSemanticsData().label,
        contains('Not now'),
      );
      expect(
        tester.getSemantics(flow.applyNow).getSemanticsData().label,
        contains('Apply now'),
      );
      semantics.dispose();
    },
  );

  for (final display in [
    (320.0, 720.0, 1.0),
    (720.0, 1560.0, 2.0),
    (1080.0, 2340.0, 3.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'both steps fit ${display.$1}x${display.$2} at ${scale * 100}% with long context, keyboard, 500-char comment',
        (tester) async {
          final backend = flow.Backend()
            ..prompts = [
              flow.prompt(
                title: List.filled(5, 'Port city residence').join(' '),
                address: List.filled(7, 'WRPP+8C, Port City Colombo').join(' '),
              ),
            ];
          await flow.pump(tester, backend);
          tester.view.physicalSize = Size(display.$1, display.$2);
          tester.view.devicePixelRatio = display.$3;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpAndSettle();
          await rate(tester);
          await tester.ensureVisible(find.byType(TextField));
          await tester.tap(find.byType(TextField));
          tester.view.viewInsets = FakeViewPadding(bottom: 280 * display.$3);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField),
            List.filled(500, 'a').join(),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await flow.choose(tester, flow.submitReview);
          await tester.pumpAndSettle();
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
          expect(backend.review!['comment'].length, 500);
          expect(flow.reviewStep, findsNothing);
          expect(flow.applicationStep, findsOneWidget);
          expect(find.byType(Dialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await flow.choose(tester, flow.notNow);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
