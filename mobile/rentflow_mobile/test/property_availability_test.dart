import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/properties/controllers/property_discovery_controller.dart';
import 'package:rentflow_mobile/features/properties/models/discovery_filters.dart';
import 'package:rentflow_mobile/features/properties/models/property.dart';
import 'package:rentflow_mobile/features/properties/models/property_availability.dart';
import 'package:rentflow_mobile/features/properties/screens/property_details_screen.dart';
import 'package:rentflow_mobile/features/properties/widgets/property_card.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_form_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/viewings/screens/book_viewing_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'package:rentflow_mobile/shared/widgets/shared_widgets.dart';

import 'helpers/discovery_backend.dart';
import 'property_details_test.dart' as fixture;

final today = DateTime(2026, 10, 2, 16, 30);
DateTime fixedToday() => today;

void main() {
  for (final scenario in [
    (available: false, date: null, status: PropertyAvailability.unavailable),
    (
      available: false,
      date: '2026-10-17',
      status: PropertyAvailability.unavailable,
    ),
    (available: true, date: null, status: PropertyAvailability.availableNow),
    (
      available: true,
      date: '2026-10-17',
      status: PropertyAvailability.availableSoon,
    ),
    (
      available: true,
      date: '2026-10-02',
      status: PropertyAvailability.availableNow,
    ),
    (
      available: true,
      date: '2026-10-01',
      status: PropertyAvailability.availableNow,
    ),
  ]) {
    final name = '${scenario.available}, ${scenario.date}';
    Map<String, dynamic> listing() => {
      ...fixture.propertyJson(available: scenario.available),
      'availableFrom': scenario.date,
    };

    test('display status for $name preserves the property fields', () {
      final property = Property.fromJson(listing());
      final date = property.availableFrom;
      expect(
        PropertyAvailability.fromProperty(property, today: today),
        scenario.status,
      );
      expect(property.isAvailable, scenario.available);
      expect(property.availableFrom, date);
      if (scenario.date == null) expect(property.availableFrom, isNull);
    });

    testWidgets('Details and PropertyCard agree for $name', (tester) async {
      final backend = DiscoveryBackend();
      addTearDown(backend.close);
      backend.properties = [listing()];
      final property = Property.fromJson(listing());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: PropertyDetailsScreen(
            property: property,
            propertyApiService: backend.service,
            todayProvider: fixedToday,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final availability = find.byKey(const Key('details-availability'));
      Finder inAvailability(String text) =>
          find.descendant(of: availability, matching: find.text(text));
      expect(
        inAvailability(scenario.status.label),
        scenario.available && scenario.date == null
            ? findsNWidgets(2)
            : findsOneWidget,
      );
      final expectedColor = switch (scenario.status) {
        PropertyAvailability.availableNow => AppPalette.success,
        PropertyAvailability.availableSoon => AppPalette.olive,
        PropertyAvailability.unavailable => AppPalette.secondaryText,
      };
      expect(
        tester
            .widget<Text>(inAvailability(scenario.status.label).last)
            .style!
            .color,
        expectedColor,
      );
      if (scenario.available && property.availableFrom != null) {
        expect(inAvailability('Available from'), findsOneWidget);
        final date = MaterialLocalizations.of(
          tester.element(availability),
        ).formatShortDate(property.availableFrom!);
        expect(inAvailability(date), findsOneWidget);
      } else {
        expect(inAvailability('Availability'), findsOneWidget);
        expect(inAvailability('Available from'), findsNothing);
        expect(
          find.descendant(
            of: availability,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text && (widget.data?.contains('2026') ?? false),
            ),
          ),
          findsNothing,
        );
        if (!scenario.available) {
          expect(inAvailability('Currently unavailable'), findsOneWidget);
        }
      }
      if (scenario.available) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('details-book-viewing')),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('details-apply-now')))
              .onPressed,
          isNotNull,
        );
      } else {
        expect(find.byKey(const Key('details-book-viewing')), findsNothing);
        expect(find.byKey(const Key('details-apply-now')), findsNothing);
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PropertyCard(
                property: property,
                onTap: () {},
                todayProvider: fixedToday,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(scenario.status.label), findsOneWidget);
      final chip = tester.widget<StatusChip>(find.byType(StatusChip));
      expect(chip.tone, switch (scenario.status) {
        PropertyAvailability.availableNow => StatusTone.success,
        PropertyAvailability.availableSoon => StatusTone.progress,
        PropertyAvailability.unavailable => StatusTone.neutral,
      });
      expect(tester.takeException(), isNull);
    });
  }

  test('same calendar day ignores time and local/UTC representation', () {
    for (final date in ['2026-10-02T23:59:59', '2026-10-02T23:59:59Z']) {
      final property = Property.fromJson({
        ...fixture.propertyJson(),
        'availableFrom': date,
      });
      expect(
        PropertyAvailability.fromProperty(
          property,
          today: DateTime(2026, 10, 2),
        ),
        PropertyAvailability.availableNow,
      );
    }
  });

  test('calendar comparison handles month and year boundaries', () {
    final property = Property.fromJson({
      ...fixture.propertyJson(),
      'availableFrom': '2027-01-01',
    });
    expect(
      PropertyAvailability.fromProperty(
        property,
        today: DateTime(2026, 12, 31, 23, 59),
      ),
      PropertyAvailability.availableSoon,
    );
    expect(
      PropertyAvailability.fromProperty(property, today: DateTime(2027, 2, 1)),
      PropertyAvailability.availableNow,
    );
  });

  testWidgets(
    'future listing keeps both CTA handoffs and boolean eligibility',
    (tester) async {
      final backend = DiscoveryBackend();
      addTearDown(backend.close);
      backend.properties = [
        {...fixture.propertyJson(), 'availableFrom': '2026-10-17'},
      ];
      final property = Property.fromJson(backend.properties.single);
      expect(
        const DiscoveryFilters(availableOnly: true).includes(property, ''),
        isTrue,
      );
      final discovery = PropertyDiscoveryController(backend.service);
      addTearDown(discovery.dispose);
      await discovery.refresh();
      expect(await discovery.toggleFavorite(property), isTrue);
      expect(backend.favorites, contains(property.id));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: PropertyDetailsScreen(
            property: property,
            propertyApiService: backend.service,
            viewingApiService: ViewingApiService(backend.client),
            rentalApplicationApiService: RentalApplicationApiService(
              backend.client,
            ),
            todayProvider: fixedToday,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('details-book-viewing')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BookViewingScreen>(find.byType(BookViewingScreen))
            .propertyId,
        property.id,
      );
      Navigator.of(tester.element(find.byType(BookViewingScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('details-apply-now')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RentalApplicationFormScreen>(
              find.byType(RentalApplicationFormScreen),
            )
            .propertyId,
        property.id,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
