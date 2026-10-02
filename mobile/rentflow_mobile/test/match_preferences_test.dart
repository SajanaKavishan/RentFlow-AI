import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/properties/screens/match_preferences_screen.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';

Future<void> scrollToVisible(
  WidgetTester tester,
  Finder finder,
  double delta,
) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .last,
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await scrollToVisible(tester, finder, 200);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openEditor(
  WidgetTester tester,
  DiscoveryBackend backend, {
  ValueChanged<PreferenceChange?>? result,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final change = await Navigator.push<PreferenceChange>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      MatchPreferencesScreen(service: backend.service),
                ),
              );
              result?.call(change);
            },
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

void main() {
  late DiscoveryBackend backend;
  setUp(() => backend = DiscoveryBackend());
  tearDown(() => backend.close());

  testWidgets(
    'fresh GET fills city rent bedrooms bathrooms and canonical/custom amenity chips',
    (tester) async {
      await openEditor(tester, backend);
      expect(backend.calls(preferencesPath), 1);
      for (final pair in {
        'preference-city': 'Kurunegala',
        'preference-rent': '100000',
        'preference-beds': '2',
        'preference-baths': '1',
      }.entries) {
        final field = tester.widget<TextFormField>(find.byKey(Key(pair.key)));
        expect(field.controller!.text, pair.value);
      }
      await scrollToVisible(
        tester,
        find.byKey(const Key('preference-amenity-wifi')),
        200,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('preference-amenity-wifi')),
            )
            .selected,
        true,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('preference-amenity-parking')),
            )
            .selected,
        true,
      );
      await scrollToVisible(
        tester,
        find.byKey(const Key('preference-amenity-Custom terrace')),
        200,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('preference-amenity-Custom terrace')),
            )
            .selected,
        true,
      );
    },
  );

  testWidgets(
    'Save sends exact shared values and keys, preserving custom web amenities',
    (tester) async {
      PreferenceChange? result;
      await openEditor(tester, backend, result: (value) => result = value);
      await tester.enterText(
        find.byKey(const Key('preference-city')),
        '  Colombo  ',
      );
      await tester.enterText(
        find.byKey(const Key('preference-rent')),
        '150000',
      );
      await tester.enterText(find.byKey(const Key('preference-beds')), '3');
      await tester.ensureVisible(find.byKey(const Key('preference-baths')));
      await tester.enterText(find.byKey(const Key('preference-baths')), '2');
      await tapVisible(
        tester,
        find.byKey(const Key('preference-amenity-parking')),
      );
      await tapVisible(tester, find.byKey(const Key('preference-amenity-gym')));
      await tapVisible(tester, find.text('Save preferences'));
      final put = backend.requests.singleWhere(
        (request) => request.method == 'PUT',
      );
      expect(jsonDecode(put.body), {
        'preferredCity': 'Colombo',
        'maximumMonthlyRent': 150000,
        'minimumBedrooms': 3,
        'minimumBathrooms': 2,
        'preferredAmenities': ['wifi', 'Custom terrace', 'gym'],
      });
      expect(result, PreferenceChange.saved);
      expect(find.byType(MatchPreferencesScreen), findsNothing);
    },
  );

  testWidgets('Cancel discards draft and reopening reads changed web values', (
    tester,
  ) async {
    await openEditor(tester, backend);
    await tester.enterText(
      find.byKey(const Key('preference-city')),
      'Unsaved city',
    );
    await tapVisible(tester, find.text('Cancel'));
    expect(backend.calls(preferencesPath, 'PUT'), 0);
    expect(backend.preferences['preferredCity'], 'Kurunegala');
    backend.preferences = {...savedPreferences, 'preferredCity': 'Galle'};
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('preference-city')))
          .controller!
          .text,
      'Galle',
    );
    expect(backend.calls(preferencesPath), 2);
  });

  testWidgets('room presets save minimums and Any preserves nullable values', (
    tester,
  ) async {
    await openEditor(tester, backend);
    await tapVisible(tester, find.byKey(const Key('preference-beds-choice-3')));
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('preference-beds')))
          .controller!
          .text,
      '3',
    );
    await tapVisible(
      tester,
      find.byKey(const Key('preference-baths-choice-any')),
    );
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    final put = backend.requests.singleWhere(
      (request) => request.method == 'PUT',
    );
    expect(jsonDecode(put.body), {
      'preferredCity': 'Kurunegala',
      'maximumMonthlyRent': 100000,
      'minimumBedrooms': 3,
      'minimumBathrooms': null,
      'preferredAmenities': ['wifi', 'parking', 'Custom terrace'],
    });
  });

  testWidgets('Save stays visible while browsing the amenity chips', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.reset);
    await openEditor(tester, backend);
    final save = find.widgetWithText(FilledButton, 'Save preferences');
    final before = tester.getRect(save);
    final cancel = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Cancel'),
    );
    final reset = tester.getRect(
      find.widgetWithText(TextButton, 'Reset saved preferences'),
    );
    expect(cancel.top, before.top);
    expect(cancel.bottom, before.bottom);
    expect(reset.left, cancel.left);
    expect(reset.bottom, lessThanOrEqualTo(cancel.top));
    await scrollToVisible(
      tester,
      find.byKey(const Key('preference-amenity-Custom terrace')),
      150,
    );
    expect(tester.getRect(save), before);
    expect(before.bottom, lessThanOrEqualTo(780));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Save tracks each field and amenities and mutes again on revert',
    (tester) async {
      await openEditor(tester, backend);
      FilledButton save() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save preferences'),
      );
      expect(save().onPressed, isNull);
      for (final field in {
        'preference-city': 'Colombo',
        'preference-rent': '120000',
        'preference-beds': '3',
        'preference-baths': '2',
      }.entries) {
        final finder = find.byKey(Key(field.key));
        await scrollToVisible(tester, finder, 150);
        final original = tester.widget<TextFormField>(finder).controller!.text;
        await tester.enterText(finder, field.value);
        await tester.pump();
        expect(save().onPressed, isNotNull);
        await tester.enterText(finder, original);
        await tester.pump();
        expect(save().onPressed, isNull);
      }
      await scrollToVisible(
        tester,
        find.byKey(const Key('preference-rent')),
        -150,
      );
      await tester.enterText(
        find.byKey(const Key('preference-rent')),
        '100000.0',
      );
      await tester.pump();
      expect(save().onPressed, isNull);
      await tapVisible(
        tester,
        find.byKey(const Key('preference-amenity-wifi')),
      );
      expect(save().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('preference-amenity-wifi')));
      await tester.pump();
      expect(save().onPressed, isNull);
      expect(backend.calls(preferencesPath, 'PUT'), 0);
    },
  );

  testWidgets('Reset requires confirmation and uses shared DELETE endpoint', (
    tester,
  ) async {
    PreferenceChange? result;
    await openEditor(tester, backend, result: (value) => result = value);
    await tapVisible(tester, find.text('Reset saved preferences'));
    expect(backend.calls(preferencesPath, 'DELETE'), 0);
    await tester.tap(find.text('Keep preferences'));
    await tester.pumpAndSettle();
    expect(backend.calls(preferencesPath, 'DELETE'), 0);
    await tester.tap(find.text('Reset saved preferences'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset preferences'));
    await tester.pumpAndSettle();
    expect(backend.calls(preferencesPath, 'DELETE'), 1);
    expect(result, PreferenceChange.reset);
    expect(backend.preferences['isConfigured'], false);
  });

  testWidgets('No preferences keeps Save disabled until the draft changes', (
    tester,
  ) async {
    backend.preferences = {'isConfigured': false};
    await openEditor(tester, backend);
    expect(find.text('Set match preferences'), findsOneWidget);
    expect(find.text('Reset saved preferences'), findsNothing);
    FilledButton save() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save preferences'),
    );
    expect(save().onPressed, isNull);
    await tester.enterText(find.byKey(const Key('preference-city')), 'Galle');
    await tester.pump();
    expect(save().onPressed, isNotNull);
    await tester.enterText(find.byKey(const Key('preference-city')), '');
    await tester.pump();
    expect(save().onPressed, isNull);
    expect(backend.calls(preferencesPath, 'PUT'), 0);
  });

  testWidgets('Invalid numbers cannot issue PUT', (tester) async {
    await openEditor(tester, backend);
    await tester.enterText(find.byKey(const Key('preference-rent')), '-5');
    await tester.enterText(find.byKey(const Key('preference-beds')), '2.5');
    await tester.ensureVisible(find.byKey(const Key('preference-baths')));
    await tester.enterText(find.byKey(const Key('preference-baths')), '21');
    await tapVisible(tester, find.text('Save preferences'));
    expect(backend.calls(preferencesPath, 'PUT'), 0);
    expect(find.byType(MatchPreferencesScreen), findsOneWidget);
  });

  testWidgets(
    'failed GET prevents overwriting existing preferences and offers retry',
    (tester) async {
      backend.intercept = (request) async =>
          request.url.path == preferencesPath ? http.Response('', 503) : null;
      await openEditor(tester, backend);
      expect(
        find.textContaining('Could not load your saved preferences'),
        findsOneWidget,
      );
      expect(find.text('Save preferences'), findsNothing);
      backend.intercept = null;
      await tester.tap(find.text('Retry preferences'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('preference-city')))
            .controller!
            .text,
        'Kurunegala',
      );
    },
  );

  testWidgets('failed PUT keeps draft open and does not report success', (
    tester,
  ) async {
    backend.intercept = (request) async =>
        request.method == 'PUT' ? http.Response('', 503) : null;
    await openEditor(tester, backend);
    await tester.enterText(find.byKey(const Key('preference-city')), 'Colombo');
    await tapVisible(tester, find.text('Save preferences'));
    expect(find.textContaining('Could not save preferences'), findsOneWidget);
    expect(find.byType(MatchPreferencesScreen), findsOneWidget);
    expect(backend.preferences['preferredCity'], 'Kurunegala');
  });

  testWidgets('failed DELETE keeps saved preferences and editor available', (
    tester,
  ) async {
    backend.intercept = (request) async =>
        request.method == 'DELETE' ? http.Response('', 503) : null;
    await openEditor(tester, backend);
    await tapVisible(tester, find.text('Reset saved preferences'));
    await tester.tap(find.text('Reset preferences'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not reset preferences'), findsOneWidget);
    expect(backend.preferences['isConfigured'], true);
  });

  testWidgets('Save remains pending until API confirms success', (
    tester,
  ) async {
    final gate = Completer<void>();
    backend.intercept = (request) async {
      if (request.method == 'PUT') await gate.future;
      return null;
    };
    PreferenceChange? result;
    await openEditor(tester, backend, result: (value) => result = value);
    await tester.enterText(find.byKey(const Key('preference-city')), 'Colombo');
    await scrollToVisible(tester, find.text('Save preferences'), 200);
    await tester.tap(find.text('Save preferences'));
    await tester.pump();
    expect(result, isNull);
    expect(find.text('Updating preferences…'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(result, PreferenceChange.saved);
  });

  testWidgets(
    'custom amenities remain selectable after removing them from a draft',
    (tester) async {
      await openEditor(tester, backend);
      final custom = find.byKey(const Key('preference-amenity-Custom terrace'));
      await tapVisible(tester, custom);
      expect(tester.widget<FilterChip>(custom).selected, false);
      await tester.tap(custom);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(custom).selected, true);
    },
  );

  testWidgets(
    'preferences remain usable at enlarged text on a narrow phone with keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openEditor(tester, backend);
      expect(tester.takeException(), isNull);
      await scrollToVisible(
        tester,
        find.byKey(const Key('preference-rent')),
        150,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.tap(find.byKey(const Key('preference-rent')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.byKey(const Key('preference-amenity-wifi')),
      );
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('Cancel'));
      expect(backend.calls(preferencesPath, 'PUT'), 0);
      expect(tester.takeException(), isNull);
    },
  );
}
