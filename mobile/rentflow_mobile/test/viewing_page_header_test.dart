import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/viewings/widgets/viewing_page_header.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

void main() {
  testWidgets(
    'long title wraps at narrow width and 2x without shrinking the Back target',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      const title =
          'Viewing details for your upcoming property viewing appointment';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(2),
              padding: const EdgeInsets.only(top: 32),
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: ViewingPageHeader(
                    eyebrow: 'my viewings',
                    title: title,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('MY VIEWINGS'), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      final back = find.byTooltip('Back');
      expect(tester.getSemantics(back).getSemanticsData().tooltip, 'Back');
      expect(tester.getSize(back), const Size(48, 48));
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
      );
      expect(button.icon, isA<Icon>().having((icon) => icon.size, 'size', 24));
      expect(button.style?.backgroundColor?.resolve({}), Colors.transparent);
      expect(button.style?.side?.resolve({}), BorderSide.none);
      expect(button.style?.elevation?.resolve({}), 0);
      final titleStyle = tester.widget<Text>(find.text(title)).style!;
      expect(titleStyle.fontSize, 24);
      expect(titleStyle.fontWeight, FontWeight.w600);
      expect(titleStyle.color, AppPalette.darkOlive);
      final eyebrowStyle = tester.widget<Text>(find.text('MY VIEWINGS')).style!;
      expect(eyebrowStyle.fontSize, 12);
      expect(eyebrowStyle.fontWeight, FontWeight.w600);
      expect(eyebrowStyle.color, AppPalette.olive);
      expect(
        tester.getRect(back).right,
        lessThan(tester.getRect(find.text(title)).left),
      );
      expect(
        tester.getRect(find.byType(ViewingPageHeader)).top,
        greaterThanOrEqualTo(32),
      );
      expect(
        MediaQuery.textScalerOf(tester.element(find.text(title))).scale(24),
        48,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
