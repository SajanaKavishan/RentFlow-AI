import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/properties/models/property.dart';
import 'package:rentflow_mobile/features/properties/models/property_matching.dart';
import 'package:rentflow_mobile/features/properties/screens/property_details_screen.dart';
import 'package:rentflow_mobile/features/properties/screens/property_list_screen.dart';
import 'package:rentflow_mobile/features/properties/services/property_api_service.dart';
import 'package:rentflow_mobile/features/properties/widgets/property_card.dart';
import 'package:rentflow_mobile/features/properties/widgets/property_photo.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_form_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/viewings/screens/book_viewing_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

const id = '22222222-2222-4222-8222-222222222222';

class MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}
  @override
  Future<String?> readToken() async => 'tenant-token';
  @override
  Future<void> saveToken(String value) async {}
}

Map<String, dynamic> propertyJson({bool available = true}) => {
  'id': id,
  'landlordId': '11111111-1111-4111-8111-111111111111',
  'title': 'A comfortable and very spacious home near the gardens',
  'description': 'Bright rooms with a quiet view.',
  'address': '42 Garden Road',
  'city': 'Colombo',
  'monthlyRent': 125000,
  'bedrooms': 3,
  'bathrooms': 2,
  'isAvailable': available,
  'createdAt': '2026-09-01T00:00:00Z',
  'updatedAt': null,
  'amenities': ['Wi-Fi', 'Custom terrace'],
};

PropertyApiService serviceWith({
  required http.Response Function(http.Request) respond,
  required void Function(ApiClient) register,
  bool canApply = true,
}) {
  final client = ApiClient(
    baseUrl: 'https://test.example',
    httpClient: MockClient(
      (request) async =>
          request.url.path.endsWith('/rental-application-eligibility')
          ? http.Response(
              jsonEncode({
                'canApply': canApply,
                'hasCompletedViewing': true,
                'reason': canApply
                    ? null
                    : 'This property is currently unavailable.',
              }),
              200,
            )
          : respond(request),
    ),
    tokenStorage: MemoryTokenStorage(),
  );
  register(client);
  return PropertyApiService(client);
}

void main() {
  test('property parses new nullable values and legacy JSON truthfully', () {
    final legacy = Property.fromJson(propertyJson());
    expect(legacy.area, isNull);
    expect(legacy.latitude, isNull);
    expect(legacy.advertisedSecurityDeposit, isNull);
    expect(legacy.preferredLeaseTermMonths, isNull);
    expect(legacy.amenityDetails, isNull);

    final complete = Property.fromJson({
      ...propertyJson(),
      'latitude': 6.93,
      'longitude': 79.84,
      'googlePlaceId': 'real-place-id',
      'area': 1500.5,
      'areaType': 'FloorArea',
      'areaUnit': 'sqft',
      'availableFrom': '2026-10-15',
      'advertisedSecurityDeposit': 250000,
      'preferredLeaseTermMonths': 12,
      'petPolicy': 'Conditional',
      'petPolicyNotes': 'Ask the owner',
      'includedUtilities': ['water'],
      'amenityDetails': [
        {'canonicalKey': 'wifi', 'name': 'Wi-Fi'},
        {'canonicalKey': null, 'name': 'Custom terrace'},
      ],
    });
    expect(complete.latitude, 6.93);
    expect(complete.longitude, 79.84);
    expect(complete.area, 1500.5);
    expect(complete.availableFrom, DateTime(2026, 10, 15));
    expect(complete.advertisedSecurityDeposit, 250000);
    expect(complete.preferredLeaseTermMonths, 12);
    expect(complete.amenityDetails?.last.name, 'Custom terrace');
  });

  test('image metadata orders primary first and resolves signed URL', () async {
    late ApiClient client;
    final service = serviceWith(
      register: (value) => client = value,
      respond: (request) {
        if (request.url.path.endsWith('/images')) {
          return http.Response(
            jsonEncode([
              {'id': 'b', 'isPrimary': false, 'sortOrder': 0},
              {'id': 'a', 'isPrimary': true, 'sortOrder': 9},
            ]),
            200,
          );
        }
        return http.Response(
          jsonEncode({'url': 'https://cdn.example/photo.jpg'}),
          200,
        );
      },
    );
    addTearDown(client.close);
    final images = await service.getImages(id);
    expect(images.map((item) => item.id), ['a', 'b']);
    expect(
      await service.getImageUrl(id, images.first.id),
      'https://cdn.example/photo.jpg',
    );
  });

  test('missing matching score is not represented as a real zero', () {
    final match = PropertyMatch.fromJson({
      'propertyId': id,
      'title': 'Home',
      'city': 'Colombo',
      'monthlyRent': 125000,
      'bedrooms': 3,
      'bathrooms': 2,
    });
    expect(match.matchScore, isNull);
  });

  testWidgets(
    'card fallback, long title and availability fit a narrow screen',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PropertyCard(
                property: Property.fromJson(propertyJson(available: false)),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('property-photo-fallback')),
        findsOneWidget,
      );
      expect(find.text('Unavailable'), findsOneWidget);
      expect(
        find.textContaining('A comfortable and very spacious'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('property photo uses the signed URL from image metadata', (
    tester,
  ) async {
    late ApiClient client;
    final service = serviceWith(
      register: (value) => client = value,
      respond: (request) {
        if (request.url.path.endsWith('/images')) {
          return http.Response(
            jsonEncode([
              {'id': 'image-one', 'isPrimary': true, 'sortOrder': 0},
            ]),
            200,
          );
        }
        return http.Response(
          jsonEncode({'url': 'https://cdn.example/real-property.jpg'}),
          200,
        );
      },
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: PropertyPhoto(propertyId: id, propertyApiService: service),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url ==
                'https://cdn.example/real-property.jpg',
      ),
      findsOneWidget,
    );
  });

  testWidgets('property photo falls back when the signed URL is missing', (
    tester,
  ) async {
    late ApiClient client;
    final service = serviceWith(
      register: (value) => client = value,
      respond: (request) {
        if (request.url.path.endsWith('/images')) {
          return http.Response(
            jsonEncode([
              {'id': 'image-one', 'isPrimary': true, 'sortOrder': 0},
            ]),
            200,
          );
        }
        return http.Response(jsonEncode({'url': null}), 200);
      },
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: PropertyPhoto(propertyId: id, propertyApiService: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('property-photo-fallback')),
      findsOneWidget,
    );
  });

  testWidgets(
    'details render real listing and public landlord, then hand off ID',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.reset);
      late ApiClient client;
      final full = {
        ...propertyJson(),
        'area': 1500,
        'areaType': 'FloorArea',
        'areaUnit': 'sqft',
        'advertisedSecurityDeposit': 250000,
        'preferredLeaseTermMonths': 12,
        'petPolicy': 'Conditional',
        'petPolicyNotes': 'Ask the owner',
        'includedUtilities': ['water'],
        'amenityDetails': [
          {'canonicalKey': 'wifi', 'name': 'Wi-Fi'},
          {'canonicalKey': null, 'name': 'Custom terrace'},
        ],
      };
      final service = serviceWith(
        register: (value) => client = value,
        respond: (request) {
          if (request.url.path.endsWith('/images')) {
            return http.Response('[]', 200);
          }
          if (request.url.path.endsWith('/landlord-summary')) {
            return http.Response(
              jsonEncode({
                'displayName': 'Maya Perera',
                'memberSinceYear': 2022,
                'hasProfileImage': false,
              }),
              200,
            );
          }
          return http.Response(jsonEncode(full), 200);
        },
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: PropertyDetailsScreen(
            property: Property.fromJson(full),
            propertyApiService: service,
            viewingApiService: ViewingApiService(client),
            rentalApplicationApiService: RentalApplicationApiService(client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('details-rent')))
            .textSpan!
            .toPlainText(),
        'Rs. 125,000 /mo',
      );
      expect(find.text('Landlord management'), findsNothing);
      await tester.scrollUntilVisible(find.text('Amenities'), 250);
      expect(
        find.byKey(const ValueKey('details-amenity-Wi-Fi')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('details-amenity-Custom terrace')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Listing preferences'), 250);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listing preferences'));
      await tester.pumpAndSettle();
      expect(find.text('LKR 250,000'), findsOneWidget);
      expect(find.text('12 months'), findsOneWidget);
      expect(find.text('Pets considered with conditions'), findsOneWidget);
      expect(find.text('water'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Maya Perera'), 250);
      expect(find.text('Maya Perera'), findsOneWidget);
      expect(find.text('Member since 2022'), findsOneWidget);
      await tester.tap(find.text('Book Viewing'));
      await tester.pumpAndSettle();
      expect(find.byType(BookViewingScreen), findsOneWidget);
      expect(
        tester
            .widget<BookViewingScreen>(find.byType(BookViewingScreen))
            .propertyId,
        id,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Now'));
      await tester.pumpAndSettle();
      expect(find.byType(RentalApplicationFormScreen), findsOneWidget);
      expect(
        tester
            .widget<RentalApplicationFormScreen>(
              find.byType(RentalApplicationFormScreen),
            )
            .propertyId,
        id,
      );
    },
  );

  testWidgets('unavailable details omit actions and absent preferences', (
    tester,
  ) async {
    late ApiClient client;
    final listing = propertyJson(available: false);
    final service = serviceWith(
      canApply: false,
      register: (value) => client = value,
      respond: (request) {
        if (request.url.path.endsWith('/images')) {
          return http.Response('[]', 200);
        }
        if (request.url.path.endsWith('/landlord-summary')) {
          return http.Response('', 404);
        }
        return http.Response(jsonEncode(listing), 200);
      },
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: PropertyDetailsScreen(
          property: Property.fromJson(listing),
          propertyApiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Book Viewing'), findsNothing);
    expect(find.text('Apply Now'), findsNothing);
    expect(find.textContaining('currently unavailable'), findsNWidgets(2));
    expect(find.text('Listing preferences'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Landlord details unavailable'),
      250,
    );
    expect(find.text('Landlord details unavailable'), findsOneWidget);
  });

  testWidgets('details remain scrollable at large text on a small phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.reset);
    late ApiClient client;
    final listing = {
      ...propertyJson(),
      'availableFrom': '2026-10-15',
      'area': 1750,
      'areaUnit': 'sqft',
      'areaType': 'FloorArea',
    };
    final service = serviceWith(
      register: (value) => client = value,
      respond: (request) {
        if (request.url.path.endsWith('/images')) {
          return http.Response('[]', 200);
        }
        if (request.url.path.endsWith('/landlord-summary')) {
          return http.Response('', 404);
        }
        return http.Response(jsonEncode(listing), 200);
      },
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: PropertyDetailsScreen(
          property: Property.fromJson(listing),
          propertyApiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Landlord details unavailable'),
      250,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Book Viewing'), findsOneWidget);
  });

  testWidgets('failed listing refresh prevents create handoffs', (
    tester,
  ) async {
    late ApiClient client;
    final listing = propertyJson();
    final service = serviceWith(
      register: (value) => client = value,
      respond: (request) {
        if (request.url.path.endsWith('/images')) {
          return http.Response('[]', 200);
        }
        return http.Response('', 404);
      },
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: PropertyDetailsScreen(
          property: Property.fromJson(listing),
          propertyApiService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Book Viewing'), findsNothing);
    expect(find.text('Apply Now'), findsNothing);
    expect(
      find.text('Current availability could not be verified.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('browse card opens details with a real property', (tester) async {
    late ApiClient client;
    final listing = propertyJson();
    final service = serviceWith(
      register: (value) => client = value,
      respond: (request) {
        if (request.url.path.endsWith('/images')) {
          return http.Response('[]', 200);
        }
        if (request.url.path.endsWith('/landlord-summary')) {
          return http.Response('', 404);
        }
        if (request.url.path.endsWith('/properties')) {
          return http.Response(jsonEncode([listing]), 200);
        }
        return http.Response(jsonEncode(listing), 200);
      },
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(body: PropertyListScreen(propertyApiService: service)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -550));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('A comfortable and very spacious'));
    await tester.pumpAndSettle();
    expect(find.byType(PropertyDetailsScreen), findsOneWidget);
    expect(find.textContaining('% match'), findsNothing);
  });
}
