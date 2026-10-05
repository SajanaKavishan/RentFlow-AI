import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/properties/models/property.dart';
import 'package:rentflow_mobile/features/properties/screens/property_details_screen.dart';
import 'package:rentflow_mobile/features/properties/screens/public_landlord_profile_screen.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'helpers/discovery_backend.dart';
import 'property_details_test.dart' as fixture;

void main() {
  testWidgets(
    'property-only aggregate is singular and does not become landlord feedback',
    (tester) async {
      final backend = DiscoveryBackend();
      addTearDown(backend.close);
      backend.intercept = (request) async {
        if (request.url.path.endsWith('/landlord-summary')) {
          return DiscoveryBackend.json({
            'displayName': 'Real landlord',
            'memberSinceYear': 2022,
            'hasProfileImage': false,
          });
        }
        if (request.url.path.endsWith('/landlord-viewing-reviews')) {
          return DiscoveryBackend.json({
            'averageRating': null,
            'reviewCount': 0,
            'reviews': [],
          });
        }
        if (request.url.path.endsWith('/viewing-reviews')) {
          return DiscoveryBackend.json({
            'averageRating': 3,
            'reviewCount': 1,
            'reviews': [],
          });
        }
        return null;
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: PropertyDetailsScreen(
            property: Property.fromJson(fixture.propertyJson()),
            propertyApiService: backend.service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final compact = find.byKey(const Key('details-property-rating'));
      await tester.ensureVisible(compact);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: compact, matching: find.text('1 verified viewing')),
        findsOneWidget,
      );
      final listed = find.byKey(const Key('details-landlord-rating'));
      await tester.ensureVisible(listed);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: listed, matching: find.text('3.0')),
        findsNothing,
      );
      expect(
        find.descendant(of: listed, matching: find.text('0 verified viewings')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final landlord in [false, true]) {
    for (final hasReviews in [false, true]) {
      testWidgets(
        '${landlord ? 'Landlord profile' : 'Property details'} shows only real reviews and safe labels ($hasReviews)',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 800);
          addTearDown(tester.view.reset);
          final backend = DiscoveryBackend();
          addTearDown(backend.close);
          final comment = List.filled(
            15,
            'A clear, helpful viewing.',
          ).join(' ');
          backend.intercept = (request) async {
            if (request.url.path.endsWith('/landlord-summary')) {
              return DiscoveryBackend.json({
                'displayName': 'Real landlord',
                'memberSinceYear': 2022,
                'hasProfileImage': false,
              });
            }
            if (request.url.path.endsWith('/landlord-summary/properties')) {
              return DiscoveryBackend.json([]);
            }
            if (request.url.path.endsWith('/viewing-reviews') ||
                request.url.path.endsWith('/landlord-viewing-reviews')) {
              final landlordRating = request.url.path.endsWith(
                '/landlord-viewing-reviews',
              );
              return DiscoveryBackend.json({
                'averageRating': hasReviews
                    ? (landlordRating ? 4.8 : 4.6)
                    : null,
                'reviewCount': hasReviews ? (landlordRating ? 18 : 12) : 0,
                'reviews': hasReviews
                    ? [
                        {
                          'rating': 5,
                          'comment': comment,
                          'reviewMonth': '2026-09',
                          'tenantId': 'secret-tenant',
                          'email': 'private@example.test',
                          'fullName': 'Secret reviewer',
                          'viewingId': 'secret-viewing',
                        },
                        {
                          'rating': 3,
                          'comment': '  ',
                          'reviewMonth': '2026-08',
                        },
                      ]
                    : [],
              });
            }
            return null;
          };
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: landlord
                  ? PublicLandlordProfileScreen(
                      propertyId: fixture.id,
                      propertyApiService: backend.service,
                    )
                  : PropertyDetailsScreen(
                      property: Property.fromJson(fixture.propertyJson()),
                      propertyApiService: backend.service,
                    ),
            ),
          );
          await tester.pumpAndSettle();
          if (landlord) {
            final identityRating = find.byKey(
              const Key('landlord-identity-rating'),
            );
            expect(
              find.descendant(of: identityRating, matching: find.text('4.8')),
              hasReviews ? findsOneWidget : findsNothing,
            );
            expect(
              find.descendant(
                of: identityRating,
                matching: find.text('18 verified viewings'),
              ),
              hasReviews ? findsOneWidget : findsNothing,
            );
          }
          if (hasReviews) {
            if (!landlord) {
              final compact = find.byKey(const Key('details-property-rating'));
              await tester.ensureVisible(compact);
              await tester.pumpAndSettle();
              expect(
                find.descendant(of: compact, matching: find.text('4.6')),
                findsOneWidget,
              );
              expect(
                find.bySemanticsLabel('4.6 out of 5 from 12 verified viewings'),
                findsOneWidget,
              );
              await tester.tap(compact);
              await tester.pumpAndSettle();
              expect(
                tester.getTopLeft(find.text('Viewing experience')).dy,
                lessThan(800),
              );
            }
            final heading = find.text(
              landlord ? 'Landlord experience' : 'Viewing experience',
            );
            await tester.scrollUntilVisible(
              heading,
              250,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(heading, findsOneWidget);
            expect(find.text(comment), findsOneWidget);
            expect(find.text(landlord ? '4.8 ★' : '4.6 ★'), findsOneWidget);
            expect(find.textContaining('Verified viewing ·'), findsOneWidget);
            expect(find.textContaining('Secret reviewer'), findsNothing);
            expect(find.textContaining('private@example'), findsNothing);
            expect(find.textContaining('secret-viewing'), findsNothing);
            expect(find.textContaining('secret-tenant'), findsNothing);
            expect(tester.takeException(), isNull);
            if (!landlord) {
              final listed = find.byKey(const Key('details-landlord-rating'));
              await tester.ensureVisible(listed);
              await tester.pumpAndSettle();
              expect(
                find.descendant(of: listed, matching: find.text('4.8')),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: listed,
                  matching: find.text('18 verified viewings'),
                ),
                findsOneWidget,
              );
              expect(
                backend.calls(
                  '/api/properties/${fixture.id}/landlord-viewing-reviews',
                ),
                1,
              );
              expect(tester.takeException(), isNull);
            }
          } else {
            expect(find.textContaining('0.0'), findsNothing);
            expect(
              find.text(
                landlord ? 'Landlord experience' : 'Viewing experience',
              ),
              findsNothing,
            );
          }
          final path =
              '/api/properties/${fixture.id}/${landlord ? 'landlord-viewing-reviews' : 'viewing-reviews'}';
          expect(backend.calls(path), 1);
          expect(
            backend.requests
                .firstWhere((r) => r.url.path == path)
                .headers
                .containsKey('Authorization'),
            isFalse,
          );
        },
      );
    }
  }
}
