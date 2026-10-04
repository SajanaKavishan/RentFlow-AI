import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/application_documents/screens/application_documents_screen.dart';
import 'package:rentflow_mobile/features/application_documents/screens/tenant_documents_screen.dart';
import 'package:rentflow_mobile/features/application_documents/services/application_document_api_service.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/features/notifications/services/notification_preferences_api_service.dart';
import 'package:rentflow_mobile/features/properties/screens/match_preferences_screen.dart';
import 'package:rentflow_mobile/features/properties/services/property_api_service.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/support/services/support_ticket_api_service.dart';
import 'package:rentflow_mobile/features/viewing_reviews/screens/landlord_reviews_screen.dart';
import 'package:rentflow_mobile/features/viewing_reviews/services/viewing_review_api_service.dart';
import 'package:rentflow_mobile/shared/profile/create_support_request_screen.dart';
import 'package:rentflow_mobile/shared/profile/help_support_screen.dart';
import 'package:rentflow_mobile/shared/profile/notification_preferences_screen.dart';
import 'package:rentflow_mobile/shared/profile/password_security_screen.dart';
import 'package:rentflow_mobile/shared/profile/personal_information_screen.dart';
import 'package:rentflow_mobile/shared/profile/public_contact_editor.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart' show savedPreferences;
import 'helpers/notification_preferences_backend.dart' show preferencesJson;
import 'helpers/profile_backend.dart' show ProfileBackend;
import 'helpers/support_backend.dart' show ticketJson;
import 'tenant_quick_action_destinations_test.dart' show application;
import 'widget_test.dart' show MemoryTokenStorage, userJson;

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance(), b = background.computeLuminance();
  return ((a > b ? a : b) + 0.05) / ((a < b ? a : b) + 0.05);
}

void main() {
  late ApiClient client;
  late AuthController auth;
  setUp(() {
    final storage = MemoryTokenStorage('polish-token');
    client = ApiClient(
      baseUrl: 'https://polish.test',
      tokenStorage: storage,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        final Object body;
        if (path == '/api/auth/me') {
          body = {
            ...userJson(UserRole.tenant),
            'fullName': 'Amara Wijesinghe ${'LongFamilyName ' * 5}',
            'email': '${'longemail' * 7}@example.com',
          };
        } else if (path == '/api/notification-preferences') {
          body = preferencesJson();
        } else if (path == '/api/tenant/property-preferences') {
          body = savedPreferences;
        } else if (path == '/api/support-tickets/mine') {
          body = [ticketJson()];
        } else if (path == '/api/landlord/viewing-reviews/summary') {
          body = {
            'landlord': {
              'reviewCount': 0,
              'averageRating': null,
              'reviews': [],
            },
            'properties': [],
          };
        } else if (path == '/api/rental-applications') {
          body = [application];
        } else if (path == '/api/rental-applications/${application['id']}') {
          body = application;
        } else if (path.endsWith('/documents')) {
          body = [];
        } else {
          return http.Response('', 404);
        }
        return http.Response(jsonEncode(body), 200);
      }),
    );
    auth = AuthController(
      authService: AuthService(client),
      tokenStorage: storage,
    );
    client.setUnauthorizedHandler(auth.handleUnauthorized);
  });
  tearDown(() {
    auth.dispose();
    client.close();
  });

  final screens = <String, Widget Function(ApiClient, CurrentUser)>{
    'Personal information': (api, user) =>
        PersonalInformationScreen(user: user),
    'Password & security': (api, user) => const PasswordSecurityScreen(),
    'Notifications': (api, user) => NotificationPreferencesScreen(
      service: NotificationPreferencesApiService(api),
    ),
    'Help & support': (api, user) =>
        HelpSupportScreen(service: SupportTicketApiService(api)),
    'New request': (api, user) =>
        CreateSupportRequestScreen(service: SupportTicketApiService(api)),
    'Match Preferences': (api, user) =>
        MatchPreferencesScreen(service: PropertyApiService(api)),
    'Reviews': (api, user) =>
        LandlordReviewsScreen(apiService: ViewingReviewApiService(api)),
    'Your documents': (api, user) => TenantDocumentsScreen(
      rentalApplicationApiService: RentalApplicationApiService(api),
    ),
    'Application Documents': (api, user) => ApplicationDocumentsScreen(
      applicationId: application['id'] as String,
      rentalApplicationApiService: RentalApplicationApiService(api),
      applicationDocumentApiService: ApplicationDocumentApiService(api),
    ),
  };

  for (final device in [
    (320.0, 780.0, 1.0),
    (720.0, 1560.0, 2.0),
    (1080.0, 2340.0, 3.0),
  ]) {
    for (final entry in screens.entries) {
      testWidgets(
        '${entry.key} has one readable wrapping header at ${device.$1}×${device.$2} and 200%',
        (tester) async {
          tester.view.physicalSize = Size(device.$1, device.$2);
          tester.view.devicePixelRatio = device.$3;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          try {
            await auth.restoreSession();
            await tester.pumpWidget(
              AuthScope(
                controller: auth,
                child: MaterialApp(
                  theme: AppTheme.build(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => TextButton(
                        child: const Text('Open Profile page'),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) =>
                                entry.value(client, auth.currentUser!),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Open Profile page'));
            await tester.pumpAndSettle();
            expect(find.text('PROFILE'), findsNothing);
            expect(find.text('SUPPORT'), findsNothing);
            expect(find.text(entry.key), findsOneWidget);
            final title = find.descendant(
              of: find.byType(AppBar),
              matching: find.text(entry.key),
            );
            expect(title, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(title);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.text.style!.color, AppPalette.primaryText);
            expect(paragraph.textScaler.scale(24), 48);
            expect(
              tester.getBottomRight(title).dy,
              lessThanOrEqualTo(tester.getBottomRight(find.byType(AppBar)).dy),
            );
            expect(tester.takeException(), isNull);
            final fields = find.byType(TextFormField);
            if (fields.evaluate().isNotEmpty) {
              final field = fields.first;
              await tester.ensureVisible(field);
              await tester.pumpAndSettle();
              await tester.tap(field);
              tester.view.viewInsets = FakeViewPadding(bottom: 220 * device.$3);
              await tester.pumpAndSettle();
              await tester.ensureVisible(field);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              tester.view.resetViewInsets();
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
            }
            final back = find.descendant(
              of: find.byType(AppBar),
              matching: find.byType(IconButton),
            );
            final label = tester.widget<IconButton>(back).tooltip!;
            expect(label, startsWith('Back'));
            final backSemantics = tester.getSemantics(back).getSemanticsData();
            expect(backSemantics.tooltip, label);
            expect(backSemantics.hasAction(SemanticsAction.tap), isTrue);
            await tester.tap(back);
            await tester.pumpAndSettle();
            expect(find.text('Open Profile page'), findsOneWidget);
            expect(auth.isAuthenticated, isTrue);
          } finally {
            tester.view.resetViewInsets();
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      'Public contact keeps one readable title and Back at ${device.$1}×${device.$2} and 200%',
      (tester) async {
        tester.view.physicalSize = Size(device.$1, device.$2);
        tester.view.devicePixelRatio = device.$3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = ProfileBackend(role: UserRole.landlord);
        addTearDown(backend.dispose);
        await backend.pump(
          tester,
          (user) => Scaffold(body: SharedProfileContent(user: user)),
          scale: 2,
        );
        await tester.ensureVisible(find.text('Public contact'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Public contact'));
        await tester.pumpAndSettle();
        expect(find.byType(PublicContactEditor), findsOneWidget);
        expect(find.text('PROFILE'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(PublicContactEditor),
            matching: find.text('Public contact'),
          ),
          findsOneWidget,
        );
        expect(find.byTooltip('Back to Profile'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Back to Profile'));
        await tester.pumpAndSettle();
        expect(find.byType(PublicContactEditor), findsNothing);
      },
    );
  }

  for (final role in UserRole.values) {
    testWidgets(
      'Profile normal titles and descriptions have accessible contrast for ${role.name}',
      (tester) async {
        final backend = ProfileBackend(role: role);
        addTearDown(backend.dispose);
        await backend.pump(
          tester,
          (user) => Scaffold(
            body: SharedProfileContent(user: user, onOpenReviews: () {}),
          ),
        );
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          if (text.data == null || text.data!.isEmpty) continue;
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byWidget(text),
          );
          final color = paragraph.text.style!.color!;
          expect(
            contrast(color, AppPalette.white),
            greaterThanOrEqualTo(4.5),
            reason: text.data,
          );
          expect(
            contrast(color, AppPalette.warmCream),
            greaterThanOrEqualTo(4.5),
            reason: text.data,
          );
        }
        final title = tester.renderObject<RenderParagraph>(
          find.text('Personal information'),
        );
        expect(title.text.style!.color, AppPalette.primaryText);
        final description = tester.renderObject<RenderParagraph>(
          find.text('Update your photo, name, and phone number'),
        );
        expect(description.text.style!.color, AppPalette.neutral);
      },
    );
  }
}
