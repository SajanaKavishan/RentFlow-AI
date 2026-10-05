import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/properties/services/property_api_service.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/landlord_rental_application_details_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/landlord_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/viewings/screens/landlord_viewing_requests_screen.dart';
import 'package:rentflow_mobile/features/viewings/screens/landlord_viewing_request_details_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/home/landlord_workspace_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'helpers/landlord_workspace_fixture.dart';

void main() {
  for (final viewing in [true, false]) {
    testWidgets(
      '${viewing ? 'viewing' : 'application'} lists load owned properties and open correct details',
      (tester) async {
        final paths = <String>[];
        final client = workspaceClient((request) async {
          expect(request.headers['Authorization'], 'Bearer owner-token');
          paths.add(request.url.path);
          if (request.url.path == '/api/properties/mine') {
            return jsonResponse([
              propertyJson(),
              propertyJson(id: 'second-property'),
            ]);
          }
          if (request.url.path.endsWith('/second-property')) {
            return jsonResponse([]);
          }
          if (request.url.path == '/api/viewings/property/property') {
            return jsonResponse([viewingJson(status: 0)]);
          }
          if (request.url.path ==
              '/api/rental-applications/property/property') {
            return jsonResponse([applicationJson()]);
          }
          if (request.url.path.endsWith('/documents') ||
              request.url.path.endsWith('/validation-runs')) {
            return jsonResponse([]);
          }
          return jsonResponse({}, 404);
        });
        addTearDown(client.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: viewing
                ? LandlordViewingRequestsScreen(
                    viewingApiService: ViewingApiService(client),
                    propertyApiService: PropertyApiService(client),
                  )
                : LandlordRentalApplicationsScreen(
                    rentalApplicationApiService: RentalApplicationApiService(
                      client,
                    ),
                    propertyApiService: PropertyApiService(client),
                  ),
          ),
        );
        await tester.pumpAndSettle();
        expect(paths, contains('/api/properties/mine'));
        expect(
          paths,
          contains(
            viewing
                ? '/api/viewings/property/second-property'
                : '/api/rental-applications/property/second-property',
          ),
        );
        expect(find.text('Garden House'), findsWidgets);
        expect(find.text('Nimal Perera'), findsOneWidget);
        expect(find.text('tenant'), findsNothing);
        await tester.tap(
          find.byKey(
            ValueKey(
              viewing
                  ? 'landlord-viewing-card-viewing'
                  : 'landlord-application-card-application',
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (viewing) {
          final details = tester.widget<LandlordViewingRequestDetailsScreen>(
            find.byType(LandlordViewingRequestDetailsScreen),
          );
          expect(details.viewing.id, 'viewing');
          expect(find.text('60 minutes'), findsOneWidget);
        } else {
          final details = tester.widget<LandlordRentalApplicationDetailsScreen>(
            find.byType(LandlordRentalApplicationDetailsScreen),
          );
          expect(details.application.id, 'application');
          expect(find.text('Nimal Perera'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '${viewing ? 'viewing' : 'application'} empty owned property list renders truthful empty state',
      (tester) async {
        final client = workspaceClient((request) async => jsonResponse([]));
        addTearDown(client.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: viewing
                ? LandlordViewingRequestsScreen(
                    viewingApiService: ViewingApiService(client),
                    propertyApiService: PropertyApiService(client),
                  )
                : LandlordRentalApplicationsScreen(
                    rentalApplicationApiService: RentalApplicationApiService(
                      client,
                    ),
                    propertyApiService: PropertyApiService(client),
                  ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(viewing ? 'No viewing requests' : 'No rental applications'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${viewing ? 'viewing' : 'application'} owner API failure shows retry and recovers',
      (tester) async {
        var fail = true;
        final client = workspaceClient(
          (_) async => fail ? jsonResponse({}, 403) : jsonResponse([]),
        );
        addTearDown(client.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(),
            home: viewing
                ? LandlordViewingRequestsScreen(
                    viewingApiService: ViewingApiService(client),
                    propertyApiService: PropertyApiService(client),
                  )
                : LandlordRentalApplicationsScreen(
                    rentalApplicationApiService: RentalApplicationApiService(
                      client,
                    ),
                    propertyApiService: PropertyApiService(client),
                  ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Try again'), findsOneWidget);
        fail = false;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(
          find.text(viewing ? 'No viewing requests' : 'No rental applications'),
          findsOneWidget,
        );
      },
    );
  }
  test(
    'partial property fetch fails as a whole, preventing destructive reminder reconciliation',
    () async {
      final client = workspaceClient((request) async {
        if (request.url.path == '/api/properties/mine') {
          return jsonResponse([
            propertyJson(),
            propertyJson(id: 'second-property'),
          ]);
        }
        if (request.url.path.endsWith('/second-property')) {
          return jsonResponse({}, 500);
        }
        return jsonResponse([viewingJson()]);
      });
      addTearDown(client.close);
      await expectLater(
        LandlordWorkspaceService(
          PropertyApiService(client),
        ).viewings(ViewingApiService(client)),
        throwsA(isA<ViewingApiException>()),
      );
    },
  );
}
