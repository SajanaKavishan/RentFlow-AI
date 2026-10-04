import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/application_documents/models/application_document.dart';
import 'package:rentflow_mobile/features/application_documents/screens/application_documents_screen.dart';
import 'package:rentflow_mobile/features/application_documents/widgets/document_type_selector.dart';
import 'package:rentflow_mobile/features/rental_applications/models/rental_application.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/my_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_details_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_form_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/features/rental_applications/widgets/application_wizard_widgets.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';
import 'property_details_test.dart' as property;

const id = '33333333-3333-4333-8333-333333333333';
const tenantId = '11111111-1111-4111-8111-111111111111';
const root = '/api/rental-applications';
const detail = '$root/$id';

Map<String, dynamic> applicationJson({int status = 0}) => {
  'id': id,
  'tenantId': tenantId,
  'propertyId': property.id,
  'moveInDate': '2030-02-03',
  'monthlyIncome': 2500,
  'occupation': 'Engineer',
  'numberOfOccupants': 2,
  'tenantNote': 'Please let me know about parking.',
  'status': status,
  'landlordResponse': status == 3
      ? 'Please update your employment letter.'
      : null,
  'createdAt': '2026-09-11T10:00:00Z',
  'submittedAt': status == 0 ? null : '2026-09-12T10:00:00Z',
  'updatedAt': null,
};
Map<String, dynamic> documentJson(int type) => {
  'id': 'document-$type',
  'applicationId': id,
  'documentType': type,
  'originalFileName': type == 0 ? 'identity.pdf' : 'income.pdf',
  'contentType': 'application/pdf',
  'fileSizeBytes': 128,
  'uploadedAt': '2026-09-12T10:00:00Z',
};

class Backend {
  final discovery = DiscoveryBackend();
  Map<String, dynamic> application = applicationJson();
  List<Map<String, dynamic>> documents = [documentJson(0), documentJson(1)];
  Map<String, dynamic> profile = {
    'id': tenantId,
    'fullName': 'Alex Morgan',
    'email': 'alex@test.example',
    'phoneNumber': '+94771234567',
    'role': 'Tenant',
  };
  bool failRead = false;
  bool failSave = false;
  bool failDocuments = false;
  bool failSubmit = false;
  bool underReviewAfterSubmit = false;
  Completer<void>? submitGate;
  Completer<void>? saveGate;

  Backend({int status = 0, int step = 3}) {
    application = applicationJson(status: status);
    if (step == 0 && status == 0) application['numberOfOccupants'] = 0;
    if (step == 1) application['monthlyIncome'] = 0;
    if (step == 2) documents = [documentJson(0)];
    discovery.properties.single['title'] = 'Maple Mews';
    discovery.intercept = (request) async {
      final path = request.url.path;
      if (path.startsWith(root) || path == '/api/auth/me') {
        expect(request.headers['Authorization'], 'Bearer tenant-token');
        expect(request.url.queryParameters, isEmpty);
      }
      if (path == '/api/auth/me') return DiscoveryBackend.json(profile);
      if (path == root && request.method == 'GET') {
        return DiscoveryBackend.json([application]);
      }
      if (path == root && request.method == 'POST') {
        application = {
          ...applicationJson(),
          ...jsonDecode(request.body) as Map<String, dynamic>,
        };
        return DiscoveryBackend.json(application);
      }
      if (path == detail && request.method == 'GET') {
        return failRead
            ? http.Response('{}', 404)
            : DiscoveryBackend.json(application);
      }
      if (path == detail && request.method == 'PUT') {
        await saveGate?.future;
        if (failSave) {
          return http.Response(
            jsonEncode({'detail': 'Changes could not be saved.'}),
            500,
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {
          'moveInDate',
          'monthlyIncome',
          'occupation',
          'numberOfOccupants',
          'tenantNote',
        });
        application = {...application, ...body};
        return DiscoveryBackend.json(application);
      }
      if (path == '$detail/documents') {
        return failDocuments
            ? http.Response('{}', 500)
            : DiscoveryBackend.json(documents);
      }
      if (path == '$detail/submit') {
        await submitGate?.future;
        if (failSubmit) {
          return http.Response(
            jsonEncode({
              'detail': 'Please check the application before submitting.',
            }),
            409,
          );
        }
        final submitted = {
          ...application,
          'status': 1,
          'submittedAt': '2026-10-04T10:00:00Z',
        };
        application = {...submitted, if (underReviewAfterSubmit) 'status': 2};
        return DiscoveryBackend.json(submitted);
      }
      return null;
    };
  }
  RentalApplicationApiService get service =>
      RentalApplicationApiService(discovery.client);
  int calls(String path, [String method = 'GET']) =>
      discovery.calls(path, method);
  void close() => discovery.close();
}

Future<void> open(
  WidgetTester tester,
  Backend backend, {
  bool list = false,
  bool details = false,
  bool newApplication = false,
  double width = 390,
  double height = 844,
  double ratio = 1,
  double scale = 1,
  bool keyboard = false,
}) async {
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
  addTearDown(backend.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 24, bottom: 24),
          viewInsets: EdgeInsets.only(bottom: keyboard ? 260 : 0),
        ),
        child: child!,
      ),
      home: list
          ? MyRentalApplicationsScreen(
              rentalApplicationApiService: backend.service,
            )
          : details
          ? RentalApplicationDetailsScreen(
              application: RentalApplication.fromJson(applicationJson()),
              rentalApplicationApiService: backend.service,
            )
          : RentalApplicationFormScreen(
              propertyId: property.id,
              application: newApplication
                  ? null
                  : RentalApplication.fromJson(applicationJson()),
              rentalApplicationApiService: backend.service,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  // Let a focused field finish scrolling its caret before scrolling to a CTA.
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder field(String name) => find.descendant(
  of: find.byKey(ValueKey('application-$name')),
  matching: find.byType(TextFormField),
);
String value(WidgetTester tester, String name) =>
    tester.widget<TextFormField>(field(name)).controller!.text;
Future<void> next(WidgetTester tester) =>
    tap(tester, find.byKey(const ValueKey('application-next-step')));
Future<void> back(WidgetTester tester) =>
    tap(tester, find.byTooltip('Back').first);

void main() {
  for (final fromDetails in [false, true]) {
    testWidgets(
      '${fromDetails ? 'Details' : 'My applications'} Continue opens the same authoritative wizard',
      (tester) async {
        final backend = Backend(status: 3);
        await open(tester, backend, list: !fromDetails, details: fromDetails);
        await tap(
          tester,
          find.text(fromDetails ? 'Continue application' : 'Continue'),
        );
        final wizard = tester.widget<RentalApplicationFormScreen>(
          find.byType(RentalApplicationFormScreen),
        );
        expect(wizard.application!.id, id);
        expect(wizard.propertyId, property.id);
        expect(
          wizard.rentalApplicationApiService!.apiClient,
          same(backend.discovery.client),
        );
        expect(find.text('Personal information'), findsOneWidget);
        expect(
          find.text('Please update your employment letter.'),
          findsOneWidget,
        );
        expect(backend.calls(root, 'POST'), 0);
        expect(backend.calls(detail), fromDetails ? 2 : 1);
      },
    );
  }

  for (final (step, title) in [
    (0, 'Personal information'),
    (1, 'Financial information'),
    (2, 'Documents information'),
    (3, 'Review information'),
  ]) {
    testWidgets('resumes first incomplete section: $title', (tester) async {
      final backend = Backend(step: step);
      await open(tester, backend);
      expect(find.text(title), findsOneWidget);
      expect(backend.calls(detail), 1);
      expect(backend.calls(root, 'POST'), 0);
      expect(backend.calls(detail, 'PUT'), 0);
    });
  }

  testWidgets(
    'generic changes with complete documents opens earliest editable step without interpreting text',
    (tester) async {
      final backend = Backend(status: 3);
      await open(tester, backend);
      expect(find.text('Personal information'), findsOneWidget);
      expect(
        find.text('Please update your employment letter.'),
        findsOneWidget,
      );
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('+94771234567'), findsOneWidget);
      expect(value(tester, 'occupants'), '2');
      expect(value(tester, 'note'), 'Please let me know about parking.');
      await next(tester);
      expect(find.text('Financial information'), findsOneWidget);
      expect(value(tester, 'occupation'), 'Engineer');
      expect(value(tester, 'income'), '2500.0');
      expect(backend.calls(detail, 'PUT'), 1);
      expect(find.text('Annual income'), findsNothing);
      expect(find.text('Current address'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    },
  );

  testWidgets(
    'missing required uploads route Changes Requested to Documents using the same ID',
    (tester) async {
      final backend = Backend(status: 3, step: 2);
      await open(tester, backend);
      expect(find.text('Documents information'), findsOneWidget);
      expect(find.textContaining('Uploaded · identity.pdf'), findsOneWidget);
      expect(find.text('Missing · Required'), findsOneWidget);
      expect(find.text('Not uploaded · Recommended'), findsOneWidget);
      await next(tester);
      expect(find.text('Documents information'), findsOneWidget);
      expect(
        find.textContaining('Upload the required Identity Document'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('submit-application')), findsNothing);
      await tap(tester, find.byKey(const ValueKey('wizard-document-1')));
      final screen = tester.widget<ApplicationDocumentsScreen>(
        find.byType(ApplicationDocumentsScreen),
      );
      expect(screen.applicationId, id);
      expect(screen.initialDocumentType, ApplicationDocumentType.incomeProof);
      expect(
        screen.applicationDocumentApiService!.apiClient,
        same(backend.discovery.client),
      );
      backend.documents.add(documentJson(1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('Uploaded · income.pdf'), findsOneWidget);
      await next(tester);
      expect(find.text('Review information'), findsOneWidget);
      expect(find.text('Maple Mews'), findsOneWidget);
      expect(find.text('2 uploaded'), findsOneWidget);
    },
  );

  testWidgets(
    'Personal then Financial save the same draft; Back and reopening restore saved values',
    (tester) async {
      final backend = Backend(status: 3);
      await open(tester, backend, list: true);
      await tap(tester, find.text('Continue'));
      await tester.enterText(field('occupants'), '3');
      await tester.enterText(field('note'), 'Saved household update');
      await next(tester);
      expect(backend.application['numberOfOccupants'], 3);
      expect(backend.application['tenantNote'], 'Saved household update');
      expect(backend.application['monthlyIncome'], 2500);
      await tester.enterText(field('income'), '3200');
      await tester.enterText(field('occupation'), 'Designer');
      await next(tester);
      expect(find.text('Documents information'), findsOneWidget);
      expect(backend.application['monthlyIncome'], 3200);
      await next(tester);
      expect(find.text('Review information'), findsOneWidget);
      await back(tester);
      expect(find.text('Documents information'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Financial information'), findsOneWidget);
      expect(value(tester, 'income'), '3200');
      await back(tester);
      expect(value(tester, 'occupants'), '3');
      expect(value(tester, 'note'), 'Saved household update');
      await back(tester);
      expect(find.byType(MyRentalApplicationsScreen), findsOneWidget);
      await tap(tester, find.text('Continue'));
      expect(value(tester, 'note'), 'Saved household update');
      await next(tester);
      expect(value(tester, 'occupation'), 'Designer');
      expect(value(tester, 'income'), '3200.0');
      expect(backend.calls(root, 'POST'), 0);
    },
  );

  for (final financial in [false, true]) {
    testWidgets(
      '${financial ? 'Financial' : 'Personal'} save failure preserves values and does not advance',
      (tester) async {
        final backend = Backend(
          status: financial ? 0 : 3,
          step: financial ? 1 : 3,
        )..failSave = true;
        await open(tester, backend);
        await tester.enterText(
          field(financial ? 'income' : 'occupants'),
          financial ? '3100' : '3',
        );
        await next(tester);
        expect(
          find.text(
            financial ? 'Financial information' : 'Personal information',
          ),
          findsOneWidget,
        );
        expect(
          value(tester, financial ? 'income' : 'occupants'),
          financial ? '3100' : '3',
        );
        expect(
          find.text('The rental application request failed. Please try again.'),
          findsOneWidget,
        );
        expect(backend.calls(detail, 'PUT'), 1);
        expect(backend.calls(root, 'POST'), 0);
        backend.failSave = false;
        await next(tester);
        expect(
          find.text(
            financial ? 'Documents information' : 'Financial information',
          ),
          findsOneWidget,
        );
        expect(backend.calls(detail, 'PUT'), 2);
      },
    );
  }

  testWidgets(
    'inline validation blocks invalid Personal and Financial values',
    (tester) async {
      final backend = Backend(step: 0);
      await open(tester, backend);
      await next(tester);
      expect(find.text('Enter at least 1 occupant.'), findsOneWidget);
      expect(backend.calls(detail, 'PUT'), 0);
      await tester.enterText(field('occupants'), '2');
      await next(tester);
      await tester.enterText(field('income'), '0');
      await tester.enterText(field('occupation'), '');
      await next(tester);
      expect(
        find.text('Enter a monthly income greater than 0.'),
        findsOneWidget,
      );
      expect(find.text('Enter your occupation.'), findsOneWidget);
      expect(find.text('Financial information'), findsOneWidget);
      expect(backend.calls(detail, 'PUT'), 1);
    },
  );

  testWidgets(
    'new application creates one draft after complete financial information then only updates it',
    (tester) async {
      final backend = Backend()..documents = [];
      await open(tester, backend, newApplication: true);
      await next(tester);
      expect(find.text('Choose a future move-in date.'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('application-move-in-date')));
      await tap(tester, find.text('OK'));
      await next(tester);
      expect(backend.calls(root, 'POST'), 0);
      expect(find.text('Financial information'), findsOneWidget);
      await tester.enterText(field('occupation'), 'Engineer');
      await tester.enterText(field('income'), '2500');
      await next(tester);
      expect(find.text('Documents information'), findsOneWidget);
      expect(backend.calls(root, 'POST'), 1);
      await back(tester);
      expect(value(tester, 'occupation'), 'Engineer');
      await next(tester);
      expect(backend.calls(root, 'POST'), 1);
      expect(backend.calls(detail, 'PUT'), 1);
    },
  );

  testWidgets(
    'unsaved changes prompt on exit and Keep editing retains values',
    (tester) async {
      final backend = Backend(status: 3);
      await open(tester, backend, list: true);
      await tap(tester, find.text('Continue'));
      await tester.enterText(field('note'), 'Unsaved note');
      await back(tester);
      expect(find.text('Leave without saving?'), findsOneWidget);
      await tap(tester, find.text('Keep editing'));
      expect(value(tester, 'note'), 'Unsaved note');
      await back(tester);
      await tap(tester, find.text('Leave'));
      expect(find.byType(MyRentalApplicationsScreen), findsOneWidget);
      await tap(tester, find.text('Continue'));
      expect(value(tester, 'note'), 'Please let me know about parking.');
      expect(backend.calls(root, 'POST'), 0);
    },
  );

  testWidgets(
    'submission saves latest fields, prevents duplicate taps, and opens authoritative details',
    (tester) async {
      final backend = Backend()
        ..submitGate = Completer<void>()
        ..underReviewAfterSubmit = true;
      await open(tester, backend, list: true);
      await tap(tester, find.text('Continue'));
      final submit = find.byKey(const ValueKey('submit-application'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(submit);
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.calls('$detail/submit', 'PATCH'), 1);
      expect(backend.calls(detail, 'PUT'), 1);
      backend.submitGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(RentalApplicationDetailsScreen), findsOneWidget);
      expect(find.text('UNDER REVIEW'), findsOneWidget);
      expect(find.text('Continue application'), findsNothing);
      expect(backend.calls(detail), 3);
      expect(backend.calls(root, 'POST'), 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MyRentalApplicationsScreen), findsOneWidget);
      expect(find.text('UNDER REVIEW'), findsOneWidget);
      expect(backend.calls(root), 2);
    },
  );

  testWidgets(
    'resubmission returns to the originating Details and refetches status',
    (tester) async {
      final backend = Backend(status: 3);
      await open(tester, backend, details: true);
      await tap(tester, find.text('Continue application'));
      await next(tester);
      await next(tester);
      await next(tester);
      await tap(tester, find.byKey(const ValueKey('submit-application')));
      expect(find.byType(RentalApplicationFormScreen), findsNothing);
      expect(find.byType(RentalApplicationDetailsScreen), findsOneWidget);
      expect(find.text('SUBMITTED'), findsOneWidget);
      expect(find.text('Continue application'), findsNothing);
      expect(backend.calls('$detail/submit', 'PATCH'), 1);
      expect(backend.calls(root, 'POST'), 0);
    },
  );

  testWidgets(
    'submission failure remains on Review and preserves the existing draft',
    (tester) async {
      final backend = Backend()..failSubmit = true;
      await open(tester, backend);
      await tap(tester, find.byKey(const ValueKey('submit-application')));
      expect(find.text('Review information'), findsOneWidget);
      expect(
        find.text('Please check the application before submitting.'),
        findsOneWidget,
      );
      expect(find.byType(RentalApplicationDetailsScreen), findsNothing);
      expect(backend.application['status'], 0);
      expect(backend.calls(root, 'POST'), 0);
    },
  );

  testWidgets(
    'required document deletion after Review is refetched before submit',
    (tester) async {
      final backend = Backend();
      await open(tester, backend);
      backend.documents = [];
      await tap(tester, find.byKey(const ValueKey('submit-application')));
      expect(find.text('Documents information'), findsOneWidget);
      expect(
        find.text('Check your required documents before submitting.'),
        findsOneWidget,
      );
      expect(backend.calls('$detail/submit', 'PATCH'), 0);
      expect(find.text('Missing · Required'), findsNWidgets(2));
    },
  );

  testWidgets(
    'document row opens the supported type dropdown at narrow width and 2x text',
    (tester) async {
      final backend = Backend(step: 2);
      await open(tester, backend, width: 320, scale: 2);
      await tap(tester, find.byKey(const ValueKey('wizard-document-2')));
      expect(
        tester
            .widget<ApplicationDocumentsScreen>(
              find.byType(ApplicationDocumentsScreen),
            )
            .initialDocumentType,
        ApplicationDocumentType.employmentLetter,
      );
      // The existing documents page builds its lower upload panel lazily.
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<ApplicationDocumentType>),
        300,
      );
      await tap(
        tester,
        find.byType(DropdownButtonFormField<ApplicationDocumentType>),
      );
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Income Proof').last);
      expect(
        tester
            .widget<DocumentTypeSelector>(find.byType(DocumentTypeSelector))
            .value,
        ApplicationDocumentType.incomeProof,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('duplicate Continue taps produce one save before advancing', (
    tester,
  ) async {
    final backend = Backend(status: 3)..saveGate = Completer<void>();
    await open(tester, backend);
    final button = find.byKey(const ValueKey('application-next-step'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 100));
    expect(backend.calls(detail, 'PUT'), 1);
    expect(find.text('Personal information'), findsOneWidget);
    backend.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Financial information'), findsOneWidget);
    expect(backend.calls(detail, 'PUT'), 1);
  });

  testWidgets(
    'a different profile never supplies another tenant contact details',
    (tester) async {
      final backend = Backend(status: 3);
      backend.profile['id'] = 'another-tenant';
      await open(tester, backend);
      expect(find.text('Alex Morgan'), findsNothing);
      expect(find.text('+94771234567'), findsNothing);
      expect(find.text('Personal information'), findsOneWidget);
    },
  );

  for (final status in [1, 2, 4, 5, 6]) {
    testWidgets('authoritative status $status stops editing stale draft data', (
      tester,
    ) async {
      final backend = Backend(status: status);
      await open(tester, backend);
      expect(
        find.text('This application can no longer be edited.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('application-next-step')), findsNothing);
      expect(find.byKey(const ValueKey('submit-application')), findsNothing);
      expect(find.text('View details'), findsOneWidget);
      expect(backend.calls(root, 'POST'), 0);
      expect(backend.calls(detail, 'PUT'), 0);
    });
  }

  testWidgets(
    'status change before save blocks PUT and preserves server authority',
    (tester) async {
      final backend = Backend(status: 3);
      await open(tester, backend);
      await tester.enterText(field('occupants'), '3');
      backend.application['status'] = 1;
      await next(tester);
      expect(
        find.text('This application can no longer be edited.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('submit-application')), findsNothing);
      expect(backend.calls(detail, 'PUT'), 0);
      expect(backend.calls(root, 'POST'), 0);
    },
  );

  testWidgets('404 blocks editing and retry restores the same application', (
    tester,
  ) async {
    final backend = Backend()..failRead = true;
    await open(tester, backend);
    expect(find.text('Could not load application'), findsOneWidget);
    expect(find.byKey(const ValueKey('submit-application')), findsNothing);
    expect(backend.calls('$detail/documents'), 0);
    backend.failRead = false;
    await tap(tester, find.text('Try again'));
    expect(find.text('Review information'), findsOneWidget);
    expect(backend.calls(root, 'POST'), 0);
  });

  for (final identityField in ['id', 'tenantId', 'propertyId']) {
    testWidgets('mismatched $identityField cannot open an editable wizard', (
      tester,
    ) async {
      final backend = Backend();
      backend.application[identityField] = 'wrong-identity';
      await open(tester, backend);
      expect(find.text('Could not load application'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(backend.calls('$detail/documents'), 0);
      expect(backend.calls(root, 'POST'), 0);
    });
  }

  testWidgets(
    'failed document load keeps state unknown until successful retry',
    (tester) async {
      final backend = Backend()..failDocuments = true;
      await open(tester, backend);
      expect(find.text('Documents information'), findsOneWidget);
      expect(find.text('Missing · Required'), findsNothing);
      await next(tester);
      expect(
        find.text('Reload your documents before continuing.'),
        findsOneWidget,
      );
      backend.failDocuments = false;
      await tap(tester, find.text('Reload documents'));
      await next(tester);
      expect(find.text('Review information'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'document records from a different application do not satisfy requirements',
    (tester) async {
      final backend = Backend();
      backend.documents.first['applicationId'] = 'different-application';
      await open(tester, backend);
      expect(find.text('Documents information'), findsOneWidget);
      expect(
        find.text('The document service returned an invalid response.'),
        findsOneWidget,
      );
      expect(find.textContaining('Uploaded ·'), findsNothing);
    },
  );

  for (final (width, height, ratio) in [
    (320.0, 780.0, 1.0),
    (720.0, 1560.0, 2.0),
    (1080.0, 2340.0, 3.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (var step = 0; step < 4; step++) {
        testWidgets(
          'step $step fits ${width}x$height at ${scale}x with long content and keyboard',
          (tester) async {
            final backend = Backend(step: step);
            backend.discovery.properties.single['title'] = List.filled(
              8,
              'Maple Mews by the gardens',
            ).join(' ');
            backend.profile['fullName'] = List.filled(
              8,
              'Alex Morgan',
            ).join(' ');
            backend.application['tenantNote'] = List.filled(
              8,
              'A long note about the household and move-in arrangements.',
            ).join(' ');
            backend.documents.first['originalFileName'] =
                '${List.filled(12, 'long document name').join(' ')}.pdf';
            await open(
              tester,
              backend,
              width: width,
              height: height,
              ratio: ratio,
              scale: scale,
              keyboard: step < 2,
            );
            expect(tester.takeException(), isNull);
            final progress = tester.widget<ApplicationWizardProgress>(
              find.byType(ApplicationWizardProgress),
            );
            expect(progress.currentStep, step);
            if (step == 0) {
              await tester.enterText(field('occupants'), '0');
              await next(tester);
              expect(find.text('Enter at least 1 occupant.'), findsOneWidget);
            } else if (step == 1) {
              await tester.enterText(field('income'), '0');
              await next(tester);
              expect(
                find.text('Enter a monthly income greater than 0.'),
                findsOneWidget,
              );
            } else if (step == 2) {
              await next(tester);
              expect(
                find.textContaining('Upload the required Identity Document'),
                findsOneWidget,
              );
            } else {
              await tester.ensureVisible(
                find.byKey(const ValueKey('submit-application')),
              );
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
