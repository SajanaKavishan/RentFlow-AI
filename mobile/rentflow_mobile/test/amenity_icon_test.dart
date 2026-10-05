import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/properties/widgets/amenity_icon.dart';

void main() {
  test('Flutter uses the same icon names as the web amenity catalog', () {
    final catalog = File(
      '../../web/rentflow-web/src/features/properties/propertyListingCatalog.js',
    ).readAsStringSync();
    final entries = RegExp(
      r"\{ key: '([^']+)', label: '([^']+)', icon: '([^']+)' \}",
    ).allMatches(catalog).toList();
    expect(entries, hasLength(12));
    for (final entry in entries) {
      expect(amenityIconName(entry[2]!, canonicalKey: entry[1]), entry[3]);
      expect(amenityIconName(entry[2]!), entry[3]);
    }
    expect(amenityIconName('Car parking'), 'car');
    expect(
      amenityIconName('Private lift', canonicalKey: 'elevator'),
      'elevator',
    );
    expect(amenityIconName('Custom terrace'), 'amenity');
  });

  testWidgets('all amenity vectors render at chip size and large text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Wrap(
            children: [
              for (final name in [
                'wifi',
                'parking',
                'air-conditioning',
                'washer-dryer',
                'gym',
                'swimming-pool',
                'balcony',
                'elevator',
                'furnished',
                'garden',
                'security',
                'rooftop',
                'Custom terrace',
              ])
                AmenityIcon(name: name, size: 17),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(AmenityIcon), findsNWidgets(13));
    expect(tester.takeException(), isNull);
  });
}
