import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/viewing_reviews/screens/landlord_reviews_screen.dart';
import 'package:rentflow_mobile/features/viewing_reviews/services/viewing_review_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'helpers/discovery_backend.dart';

void main() {
  for (final empty in [false, true]) {
    testWidgets(
      'Landlord feedback is anonymous, read-only and scaled ($empty)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 800);
        addTearDown(tester.view.reset);
        final backend = DiscoveryBackend();
        addTearDown(backend.close);
        final reviews = [
          {
            'rating': 4,
            'comment': 'Clear explanation.',
            'reviewMonth': '2026-09',
            'tenantId': 'secret-author',
            'email': 'private@example.test',
          },
          {'rating': 2, 'comment': ' ', 'reviewMonth': '2026-08'},
        ];
        backend.intercept = (_) async => DiscoveryBackend.json({
          'landlord': {
            'averageRating': empty ? null : 4.8,
            'reviewCount': empty ? 0 : 12,
            'reviews': empty ? [] : reviews,
          },
          'properties': [
            {
              'propertyId': 'owned-property',
              'title': 'My home',
              'averageRating': empty ? null : 3.5,
              'reviewCount': empty ? 0 : 1,
              'recentReviews': empty ? [] : reviews,
            },
          ],
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: LandlordReviewsScreen(
              apiService: ViewingReviewApiService(backend.client),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (empty) {
          expect(find.text('No viewing feedback yet'), findsOneWidget);
          expect(find.textContaining('0.0'), findsNothing);
        } else {
          expect(find.text('Your landlord experience'), findsOneWidget);
          expect(find.text('4.8 ★'), findsOneWidget);
          expect(find.text('12 verified viewings'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('My home'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('3.5 ★'), findsOneWidget);
          expect(find.text('1 verified viewing'), findsOneWidget);
          expect(find.text('Clear explanation.'), findsNWidgets(2));
          expect(find.textContaining('Verified viewing ·'), findsNWidgets(2));
        }
        for (final text in [
          'Delete',
          'Hide',
          'Edit',
          'secret-author',
          'private@example.test',
        ]) {
          expect(find.textContaining(text), findsNothing);
        }
        expect(backend.requests, hasLength(1));
        expect(backend.requests.single.method, 'GET');
        expect(
          backend.requests.single.url.path,
          '/api/landlord/viewing-reviews/summary',
        );
        expect(backend.requests.single.headers['Authorization'], isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Failed owner summary offers retry, never a fabricated empty rating',
    (tester) async {
      final backend = DiscoveryBackend();
      addTearDown(backend.close);
      backend.intercept = (_) async => http.Response('{}', 503);
      await tester.pumpWidget(
        MaterialApp(
          home: LandlordReviewsScreen(
            apiService: ViewingReviewApiService(backend.client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load viewing feedback.'), findsOneWidget);
      expect(find.text('No viewing feedback yet'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(backend.requests, hasLength(2));
    },
  );
}
