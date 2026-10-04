import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_form_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_details_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/viewing_follow_ups/services/viewing_follow_up_api_service.dart';
import 'package:rentflow_mobile/features/viewing_follow_ups/widgets/tenant_follow_up_host.dart';
import 'package:rentflow_mobile/features/viewing_follow_ups/widgets/viewing_follow_up_dialog.dart';
import 'package:rentflow_mobile/features/viewing_follow_ups/models/viewing_follow_up.dart';
import 'package:rentflow_mobile/shared/follow_up/follow_up_activity.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'package:rentflow_mobile/main.dart';
import 'helpers/discovery_backend.dart';
import 'property_details_test.dart' as property;
import 'rental_application_wizard_test.dart' as wizard;
import 'widget_test.dart' as auth_fixture;

const claimPath = '/api/viewing-follow-ups/next/claim';
const respondPath = '/api/viewing-follow-ups/follow-up-1/respond';
const eligibilityPath =
    '/api/properties/${property.id}/rental-application-eligibility';
final notNow = find.byKey(const Key('follow-up-not-now'));
final applyNow = find.byKey(const Key('follow-up-apply-now'));
Map<String, dynamic> prompt({
  String title = 'Real harbour home',
  String address = 'Kureepoththa, Pothuhera',
}) => {
  'followUpId': 'follow-up-1',
  'viewingId': 'viewing-1',
  'claimedAt': '2030-01-02T10:00:00Z',
  'property': {
    'id': property.id,
    'title': title,
    'address': address,
    'city': 'Kurunegala',
  },
  'application': {
    'canApply': true,
    'hasCompletedViewing': true,
    'reason': null,
  },
};

class Backend {
  final fixture = wizard.Backend(step: 0);
  DiscoveryBackend get discovery => fixture.discovery;
  List<Map<String, dynamic>> prompts = [prompt()];
  bool failClaim = false, failResponse = false, canApply = true;
  int? applicationStatus;
  Completer<void>? claimGate, responseGate;
  String role = 'Tenant';
  Backend() {
    final previous = discovery.intercept;
    discovery.intercept = (request) async {
      if (request.url.path == '/api/auth/me') {
        return DiscoveryBackend.json({...fixture.profile, 'role': role});
      }
      if (request.url.path == claimPath) {
        await claimGate?.future;
        if (failClaim) return http.Response('{}', 503);
        return prompts.isEmpty
            ? http.Response('', 204)
            : DiscoveryBackend.json(prompts.removeAt(0));
      }
      if (request.url.path.endsWith('/respond')) {
        await responseGate?.future;
        if (failResponse) return http.Response('{}', 503);
        final decision =
            (jsonDecode(request.body) as Map<String, dynamic>)['decision'];
        return DiscoveryBackend.json({
          'followUpId': request.url.path.split('/')[3],
          'decision': decision,
          'respondedAt': '2030-01-02T10:01:00Z',
        });
      }
      if (request.url.path == eligibilityPath) {
        return DiscoveryBackend.json({
          'canApply': canApply && applicationStatus == null,
          'hasCompletedViewing': true,
          'reason': canApply ? null : 'This property is currently unavailable.',
          'existingApplicationId': applicationStatus == null ? null : wizard.id,
          'existingApplicationStatus': applicationStatus,
        });
      }
      return await previous?.call(request);
    };
  }
}

Future<void> resume(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

Future<GlobalKey<NavigatorState>> pump(
  WidgetTester tester,
  Backend backend, {
  Widget? home,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 850);
  addTearDown(tester.view.reset);
  final navigator = GlobalKey<NavigatorState>();
  final observer = FollowUpNavigationObserver();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      navigatorKey: navigator,
      navigatorObservers: [observer],
      builder: (_, child) => TenantFollowUpHost(
        navigatorKey: navigator,
        navigation: observer,
        apiService: ViewingFollowUpApiService(backend.discovery.client),
        applicationApiService: RentalApplicationApiService(
          backend.discovery.client,
        ),
        propertyApiService: backend.discovery.service,
        child: child!,
      ),
      home: home ?? const Scaffold(body: Text('Tenant workspace')),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    backend.discovery.close();
  });
  await tester.pumpAndSettle();
  return navigator;
}

void main() {
  testWidgets(
    'login and unresolved restoration never claim until tenant shell is ready',
    (tester) async {
      final backend = Backend();
      final previous = backend.discovery.intercept;
      final profileGate = Completer<void>();
      backend.discovery.intercept = (request) async {
        if (request.url.path == '/api/auth/login') {
          return DiscoveryBackend.json({
            'accessToken': 'tenant-token',
            'user': backend.fixture.profile,
          });
        }
        if (request.url.path == '/api/auth/me') await profileGate.future;
        return await previous?.call(request);
      };
      final auth = AuthController(
        authService: AuthService(backend.discovery.client),
        tokenStorage: auth_fixture.MemoryTokenStorage(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        backend.discovery.close();
      });
      await tester.pumpWidget(MyApp(authController: auth));
      await tester.pumpAndSettle();
      expect(backend.discovery.calls(claimPath, 'POST'), 0);
      final login = auth.login(
        email: 'alex@test.example',
        password: 'test-password',
      );
      await tester.pumpAndSettle();
      expect(backend.discovery.calls(claimPath, 'POST'), 0);
      profileGate.complete();
      await login;
      await tester.pumpAndSettle();
      expect(backend.discovery.calls(claimPath, 'POST'), 1);
      expect(find.byType(Dialog), findsOneWidget);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.byType(ViewingFollowUpDialog), findsNothing);
    },
  );
  testWidgets(
    'resume on another page claims only after its navigation transition',
    (tester) async {
      final backend = Backend()..prompts.clear();
      final navigator = await pump(tester, backend);
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Another tenant page')),
        ),
      );
      await tester.pumpAndSettle();
      backend.prompts.add(prompt());
      await resume(tester);
      expect(find.text('Another tenant page'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
    },
  );
  testWidgets(
    'busy scope changing during claim prevents the dialog until work finishes',
    (tester) async {
      final backend = Backend()..claimGate = Completer<void>();
      final busy = ValueNotifier<bool>(false);
      addTearDown(busy.dispose);
      await pump(
        tester,
        backend,
        home: ValueListenableBuilder<bool>(
          valueListenable: busy,
          builder: (_, active, child) => FollowUpPause(
            active: active,
            child: const Scaffold(body: Text('Submitting application')),
          ),
        ),
      );
      busy.value = true;
      await tester.pump();
      backend.claimGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(backend.discovery.calls(claimPath, 'POST'), 1);
      busy.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    },
  );
  test('malformed claim and response acknowledgements fail safely', () async {
    final backend = Backend();
    addTearDown(backend.discovery.close);
    backend.discovery.intercept = (_) async =>
        DiscoveryBackend.json({'private': 'invalid'});
    final api = ViewingFollowUpApiService(backend.discovery.client);
    await expectLater(api.claimNext(), throwsA(isA<FollowUpApiException>()));
    await expectLater(
      api.respond('follow-up-1', FollowUpDecision.notNow),
      throwsA(isA<FollowUpApiException>()),
    );
  });
  test(
    'service uses JWT and only a decision, with no client identity/time',
    () async {
      final backend = Backend();
      addTearDown(backend.discovery.close);
      final api = ViewingFollowUpApiService(backend.discovery.client);
      final followUp = (await api.claimNext())!;
      await api.respond(followUp.id, FollowUpDecision.notNow);
      final requests = backend.discovery.requests;
      expect(requests.first.url.path, claimPath);
      expect(jsonDecode(requests.last.body), {'decision': 'NotNow'});
      for (final request in requests) {
        expect(request.headers['Authorization'], 'Bearer tenant-token');
        expect(request.url.queryParameters, isEmpty);
      }
    },
  );
  testWidgets(
    'authenticated open shows real context, fallback image, and explicit Not now',
    (tester) async {
      final backend = Backend();
      await pump(tester, backend);
      expect(find.text('How did your viewing go?'), findsOneWidget);
      expect(find.text('Real harbour home'), findsOneWidget);
      expect(find.text('Kureepoththa, Pothuhera, Kurunegala'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('property-photo-fallback')),
        findsOneWidget,
      );
      await tester.tap(notNow);
      await tester.pumpAndSettle();
      expect(find.byType(ViewingFollowUpDialog), findsNothing);
      expect(backend.discovery.calls(respondPath, 'POST'), 1);
      expect(
        jsonDecode(
          backend.discovery.requests
              .firstWhere((r) => r.url.path == respondPath)
              .body,
        ),
        {'decision': 'NotNow'},
      );
      await resume(tester);
      expect(find.byType(ViewingFollowUpDialog), findsNothing);
    },
  );
  testWidgets(
    'no follow-up and failed claim do not block usage; later resume retries',
    (tester) async {
      final backend = Backend()..failClaim = true;
      await pump(tester, backend);
      expect(find.text('Tenant workspace'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      backend.failClaim = false;
      backend.prompts.clear();
      await resume(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(backend.discovery.calls(claimPath, 'POST'), 2);
      backend.prompts.add(prompt());
      await resume(tester);
      expect(find.byType(ViewingFollowUpDialog), findsOneWidget);
    },
  );
  testWidgets(
    'only one prompt per interaction; next viewing waits for later resume',
    (tester) async {
      final backend = Backend()
        ..prompts.add({
          ...prompt(),
          'followUpId': 'follow-up-2',
          'viewingId': 'viewing-2',
        });
      await pump(tester, backend);
      await tester.tap(notNow);
      await tester.pumpAndSettle();
      expect(backend.discovery.calls(claimPath, 'POST'), 1);
      expect(find.byType(Dialog), findsNothing);
      await resume(tester);
      expect(backend.discovery.calls(claimPath, 'POST'), 2);
      expect(find.byType(ViewingFollowUpDialog), findsOneWidget);
      await resume(tester);
      expect(backend.discovery.calls(claimPath, 'POST'), 2);
      expect(find.byType(Dialog), findsOneWidget);
    },
  );
  testWidgets('claim in flight is not duplicated by repeated resumes', (
    tester,
  ) async {
    final backend = Backend()..claimGate = Completer<void>();
    await pump(tester, backend);
    await resume(tester);
    await resume(tester);
    expect(backend.discovery.calls(claimPath, 'POST'), 1);
    backend.claimGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });
  testWidgets(
    'response failure stays open; retry persists before closing and blocks double taps',
    (tester) async {
      final backend = Backend()..failResponse = true;
      await pump(tester, backend);
      await tester.tap(notNow);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save your choice. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsOneWidget);
      backend.failResponse = false;
      backend.responseGate = Completer<void>();
      await tester.tap(notNow);
      await tester.pump();
      expect(tester.widget<OutlinedButton>(notNow).onPressed, isNull);
      expect(tester.widget<FilledButton>(applyNow).onPressed, isNull);
      backend.responseGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(backend.discovery.calls(respondPath, 'POST'), 2);
    },
  );
  testWidgets('Apply failure never navigates before persistence', (
    tester,
  ) async {
    final backend = Backend()..failResponse = true;
    await pump(tester, backend);
    await tester.tap(applyNow);
    await tester.pumpAndSettle();
    expect(find.byType(RentalApplicationFormScreen), findsNothing);
    expect(backend.discovery.calls(eligibilityPath), 0);
    backend.failResponse = false;
    await tester.tap(applyNow);
    await tester.pumpAndSettle();
    expect(find.byType(RentalApplicationFormScreen), findsOneWidget);
    final requests = backend.discovery.requests;
    expect(
      requests.indexWhere((r) => r.url.path == respondPath),
      lessThan(requests.indexWhere((r) => r.url.path == eligibilityPath)),
    );
    expect(backend.discovery.calls('/api/rental-applications', 'POST'), 0);
  });
  for (final status in <int?>[null, 0, 3, 1, 2]) {
    testWidgets(
      'Apply now refreshes state $status and routes without creating duplicates',
      (tester) async {
        final backend = Backend();
        await pump(tester, backend);
        backend.applicationStatus = status;
        if (status != null) backend.fixture.application['status'] = status;
        await tester.tap(applyNow);
        await tester.pumpAndSettle();
        if (status == null || status == 0 || status == 3) {
          final form = tester.widget<RentalApplicationFormScreen>(
            find.byType(RentalApplicationFormScreen),
          );
          expect(form.propertyId, property.id);
          expect(form.application?.id, status == null ? isNull : wizard.id);
        } else {
          expect(
            tester
                .widget<RentalApplicationDetailsScreen>(
                  find.byType(RentalApplicationDetailsScreen),
                )
                .application
                .id,
            wizard.id,
          );
        }
        expect(backend.discovery.calls(respondPath, 'POST'), 1);
        expect(
          backend.discovery.calls(eligibilityPath),
          greaterThanOrEqualTo(1),
        );
        expect(backend.discovery.calls('/api/rental-applications', 'POST'), 0);
      },
    );
  }
  testWidgets(
    'eligibility changed to unavailable displays truth after saved choice and can close',
    (tester) async {
      final backend = Backend();
      await pump(tester, backend);
      backend.canApply = false;
      await tester.tap(applyNow);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This property is currently unavailable. Your choice was saved.',
        ),
        findsOneWidget,
      );
      expect(find.byType(RentalApplicationFormScreen), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(backend.discovery.calls(respondPath, 'POST'), 1);
    },
  );
  testWidgets('back and barrier cannot silently dismiss the prompt', (
    tester,
  ) async {
    final backend = Backend();
    final navigator = await pump(tester, backend);
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(3, 3));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(backend.discovery.calls(respondPath, 'POST'), 0);
  });
  testWidgets(
    'protected workflow defers claim until returning, including resumes',
    (tester) async {
      final backend = Backend();
      final show = ValueNotifier<bool>(true);
      addTearDown(show.dispose);
      await pump(
        tester,
        backend,
        home: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, protected, child) => protected
              ? const FollowUpPause(
                  child: Scaffold(
                    body: Text('Protected application/document work'),
                  ),
                )
              : const Scaffold(body: Text('Tenant workspace')),
        ),
      );
      expect(backend.discovery.calls(claimPath, 'POST'), 0);
      await resume(tester);
      expect(backend.discovery.calls(claimPath, 'POST'), 0);
      show.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    },
  );
  testWidgets(
    'an existing cancellation modal defers a resume check until it closes',
    (tester) async {
      final backend = Backend()..prompts.clear();
      final navigator = await pump(tester, backend);
      final modal = showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Cancel viewing?')),
      );
      await tester.pumpAndSettle();
      backend.prompts.add(prompt());
      await resume(tester);
      expect(backend.discovery.calls(claimPath, 'POST'), 1);
      expect(find.byType(ViewingFollowUpDialog), findsNothing);
      navigator.currentState!.pop();
      await modal;
      await tester.pumpAndSettle();
      expect(find.byType(ViewingFollowUpDialog), findsOneWidget);
    },
  );
  testWidgets('claim completing in background waits for a safe foreground', (
    tester,
  ) async {
    final backend = Backend()..claimGate = Completer<void>();
    await pump(tester, backend);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    backend.claimGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(backend.discovery.calls(claimPath, 'POST'), 1);
  });
  testWidgets(
    'small phone, long real title/location, and 2x text remain scrollable',
    (tester) async {
      final backend = Backend()
        ..prompts = [
          prompt(
            title: List.filled(6, 'Long real property title').join(' '),
            address: List.filled(8, 'Long real address').join(' '),
          ),
        ];
      await pump(tester, backend);
      tester.view.physicalSize = const Size(320, 650);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.ensureVisible(notNow);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(notNow);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );
  for (final role in ['Tenant', 'Landlord', 'Admin', 'MaintenanceTechnician']) {
    testWidgets('authenticated root role $role only checks for Tenant', (
      tester,
    ) async {
      final backend = Backend()..role = role;
      final auth = AuthController(
        authService: AuthService(backend.discovery.client),
        tokenStorage: property.MemoryTokenStorage(),
      );
      await tester.pumpWidget(MyApp(authController: auth));
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        backend.discovery.close();
      });
      expect(
        backend.discovery.calls(claimPath, 'POST'),
        role == 'Tenant' ? 1 : 0,
      );
      expect(
        find.byType(ViewingFollowUpDialog),
        role == 'Tenant' ? findsOneWidget : findsNothing,
      );
    });
  }
}
