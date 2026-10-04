import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/application_documents/screens/application_documents_screen.dart';
import 'package:rentflow_mobile/features/properties/screens/property_details_screen.dart';
import 'package:rentflow_mobile/features/properties/screens/property_list_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/models/rental_application.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/my_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/eligible_application_properties_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_details_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/rental_application_form_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'helpers/discovery_backend.dart';
import 'property_details_test.dart' as property;

const _id = '33333333-3333-4333-8333-333333333333';
const _root = '/api/rental-applications';
const _detail = '$_root/$_id';

Map<String, dynamic> _application(int status) => {
  'id': _id,
  'tenantId': '11111111-1111-4111-8111-111111111111',
  'propertyId': property.id,
  'moveInDate': '2030-02-03',
  'monthlyIncome': 2500,
  'occupation': 'Engineer',
  'numberOfOccupants': 2,
  'tenantNote': 'Please let me know about the parking space.',
  'status': status,
  'landlordResponse': status == 3
      ? 'Please upload an up-to-date employment letter.'
      : null,
  'createdAt': '2026-09-11T10:00:00Z',
  'submittedAt': status == 0 ? null : '2026-09-12T10:00:00Z',
  'updatedAt': status == 0 ? null : '2026-09-14T11:30:00Z',
};

Map<String, dynamic> _document(int number) => {
  'id': 'document-$number',
  'applicationId': _id,
  'documentType': number,
  'originalFileName': 'document-$number.pdf',
  'contentType': 'application/pdf',
  'fileSizeBytes': 128,
  'uploadedAt': '2026-09-12T10:00:00Z',
};

class _Backend {
  final DiscoveryBackend discovery = DiscoveryBackend();
  late Map<String, dynamic> application;
  late List<Map<String, dynamic>> applications;
  List<Map<String, dynamic>> documents = [_document(0), _document(1)];
  bool failList = false;
  bool failDetail = false;
  bool failProperty = false;
  bool failDocuments = false;
  bool wrongIdentity = false;
  Future<http.Response?> Function(http.Request)? intercept;

  _Backend({int status = 3}) {
    application = _application(status);
    applications = [application];
    discovery.properties = [
      {...property.propertyJson(), 'title': 'Maple Mews'},
    ];
    discovery.intercept = (request) async {
      final overridden = await intercept?.call(request);
      if (overridden != null) {
        return overridden;
      }
      final path = request.url.path;
      if (path.startsWith(_root)) {
        expect(request.headers['Authorization'], 'Bearer tenant-token');
        expect(request.url.queryParameters, isEmpty);
      }
      if (path == _root) {
        return failList
            ? http.Response('{}', 500)
            : DiscoveryBackend.json(applications);
      }
      if (path == _detail) {
        if (failDetail) return http.Response('{}', 404);
        return DiscoveryBackend.json({
          ...application,
          if (wrongIdentity) 'id': 'wrong-application',
        });
      }
      if (path == '$_detail/documents') {
        return failDocuments
            ? http.Response('{}', 500)
            : DiscoveryBackend.json(documents);
      }
      if (path == '$_detail/submit') {
        application = {
          ...application,
          'status': 1,
          'submittedAt': '2026-09-16T10:00:00Z',
          'updatedAt': '2026-09-16T10:00:00Z',
        };
        applications = [application];
        return DiscoveryBackend.json(application);
      }
      if (path == '$_detail/withdraw') {
        application = {
          ...application,
          'status': 6,
          'updatedAt': '2026-09-16T10:00:00Z',
        };
        applications = [application];
        return DiscoveryBackend.json(application);
      }
      if (path == '/api/properties/${property.id}' && failProperty) {
        return http.Response('{}', 404);
      }
      return null;
    };
  }
  RentalApplicationApiService get service =>
      RentalApplicationApiService(discovery.client);
  int calls(String path) => discovery.calls(path);
  void close() => discovery.close();
}

Future<void> _open(
  WidgetTester tester,
  _Backend backend, {
  bool details = false,
  double width = 390,
  double height = 844,
  double pixelRatio = 1,
  double scale = 1,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
  addTearDown(backend.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 30, bottom: 24),
        ),
        child: child!,
      ),
      home: details
          ? RentalApplicationDetailsScreen(
              application: RentalApplication.fromJson(_application(0)),
              rentalApplicationApiService: backend.service,
              propertyApiService: backend.discovery.service,
            )
          : MyRentalApplicationsScreen(
              rentalApplicationApiService: backend.service,
              propertyApiService: backend.discovery.service,
            ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final (status, label) in [
    (0, 'DRAFT'),
    (1, 'SUBMITTED'),
    (2, 'UNDER REVIEW'),
    (3, 'ACTION REQUIRED'),
    (4, 'APPROVED'),
    (5, 'REJECTED'),
    (6, 'WITHDRAWN'),
  ]) {
    testWidgets('detail renders authoritative $label and supported actions', (
      tester,
    ) async {
      final backend = _Backend(status: status);
      await _open(tester, backend, details: true);
      expect(find.text('APPLICATION'), findsOneWidget);
      expect(find.text('Maple Mews'), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(
        find.text('Continue application'),
        status == 0 || status == 3 ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Resubmit application'),
        status == 3 ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Withdraw application'),
        status < 4 ? findsOneWidget : findsNothing,
      );
      expect(find.text('Application created'), findsOneWidget);
      expect(
        find.text('Application submitted'),
        status == 0 ? findsNothing : findsNWidgets(status == 1 ? 2 : 1),
      );
      expect(
        find.text('Last updated'),
        status == 0 ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('Landlord review'),
        status == 1 || status == 2 ? findsOneWidget : findsNothing,
      );
      expect(find.textContaining('check completed'), findsNothing);
      expect(find.text('Documents reviewed'), findsNothing);
      expect(backend.calls(_detail), 1);
      expect(
        backend.discovery.requests.any(
          (r) => r.url.path.contains('validation'),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, height, ratio) in [
    (320.0, 780.0, 1.0),
    (720.0, 1560.0, 2.0),
    (1080.0, 2340.0, 3.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final details in [false, true]) {
        testWidgets(
          '${details ? 'details' : 'list'} fits ${width}x$height at ${scale}x with long content',
          (tester) async {
            final backend = _Backend();
            final name = List.filled(8, 'Maple Mews by the gardens').join(' ');
            backend.discovery.properties.single['title'] = name;
            backend.application['landlordResponse'] = List.filled(
              12,
              'Please upload a current employment letter and check your income details.',
            ).join(' ');
            backend.applications = [
              backend.application,
              {..._application(2), 'id': 'another-application'},
            ];
            await _open(
              tester,
              backend,
              details: details,
              width: width,
              height: height,
              pixelRatio: ratio,
              scale: scale,
            );
            expect(tester.takeException(), isNull);
            expect(find.text(name), findsWidgets);
            final header = find.text(
              details ? 'APPLICATION' : 'RENTAL JOURNEY',
            );
            expect(tester.getRect(header).top, greaterThanOrEqualTo(30));
            expect(
              MediaQuery.textScalerOf(tester.element(header)).scale(14),
              14 * scale,
            );
            if (details) {
              await _tap(
                tester,
                find.byKey(const ValueKey('manage-application-documents')),
              );
              expect(find.byType(ApplicationDocumentsScreen), findsOneWidget);
              await tester.pageBack();
              await tester.pumpAndSettle();
              await tester.drag(
                find.byType(SingleChildScrollView).first,
                const Offset(0, -8000),
              );
              await tester.pumpAndSettle();
              expect(
                tester
                    .getRect(
                      find.widgetWithText(TextButton, 'Withdraw application'),
                    )
                    .bottom,
                lessThanOrEqualTo(height / ratio - 24),
              );
            } else {
              await tester.scrollUntilVisible(
                find.byKey(
                  const ValueKey('application-details-another-application'),
                ),
                300,
              );
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'property reads are shared across cards; timestamps and CTA are real',
    (tester) async {
      final backend = _Backend();
      backend.applications.add({..._application(2), 'id': 'other-application'});
      await _open(tester, backend, height: 1400);
      expect(find.text('RENTAL JOURNEY'), findsOneWidget);
      expect(find.text('My applications'), findsOneWidget);
      expect(find.text('Maple Mews'), findsNWidgets(2));
      expect(find.text('Created Sep 11 · Submitted Sep 12'), findsNWidgets(2));
      expect(
        find.text('Please upload an up-to-date employment letter.'),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('View details'), findsOneWidget);
      expect(backend.calls('/api/properties/${property.id}'), 1);
      expect(find.text(property.id), findsNothing);
      expect(find.text('Your note'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final tapCard in [false, true]) {
    testWidgets(
      '${tapCard ? 'card opens details' : 'Continue opens wizard'} and Back refreshes list',
      (tester) async {
        final backend = _Backend();
        await _open(tester, backend);
        await _tap(
          tester,
          tapCard ? find.text('Maple Mews') : find.text('Continue'),
        );
        if (tapCard) {
          final screen = tester.widget<RentalApplicationDetailsScreen>(
            find.byType(RentalApplicationDetailsScreen),
          );
          expect(screen.application.id, _id);
          expect(
            screen.rentalApplicationApiService.apiClient,
            same(backend.discovery.client),
          );
          expect(find.text('Application progress'), findsOneWidget);
        } else {
          final screen = tester.widget<RentalApplicationFormScreen>(
            find.byType(RentalApplicationFormScreen),
          );
          expect(screen.application!.id, _id);
          expect(
            screen.rentalApplicationApiService!.apiClient,
            same(backend.discovery.client),
          );
          expect(find.text('Personal information'), findsOneWidget);
        }
        await _tap(tester, find.byTooltip('Back'));
        expect(find.byType(MyRentalApplicationsScreen), findsOneWidget);
        expect(backend.calls(_root), 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Continue opens the existing form; returning refreshes server status',
    (tester) async {
      final backend = _Backend();
      await _open(tester, backend, details: true);
      await _tap(tester, find.text('Continue application'));
      final form = tester.widget<RentalApplicationFormScreen>(
        find.byType(RentalApplicationFormScreen),
      );
      expect(form.application!.id, _id);
      expect(form.propertyId, property.id);
      backend.application = _application(1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('SUBMITTED'), findsOneWidget);
      expect(find.text('Continue application'), findsNothing);
      expect(find.text('Resubmit application'), findsNothing);
      expect(backend.calls(_detail), 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Manage opens selected documents and refreshes the real upload count on return',
    (tester) async {
      final backend = _Backend();
      await _open(tester, backend, details: true);
      expect(find.text('2 documents uploaded'), findsOneWidget);
      expect(find.textContaining('of 3 uploaded'), findsNothing);
      await _tap(tester, find.text('Manage'));
      final documents = tester.widget<ApplicationDocumentsScreen>(
        find.byType(ApplicationDocumentsScreen),
      );
      expect(documents.applicationId, _id);
      backend.documents = [_document(0)];
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1 document uploaded'), findsOneWidget);
      expect(find.text('2 documents uploaded'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in ['+ New', 'Browse properties']) {
    testWidgets(
      '$action follows its supported route to the new application form',
      (tester) async {
        final backend = _Backend();
        backend.applications = [];
        await _open(tester, backend);
        expect(find.text('No applications yet'), findsOneWidget);
        await _tap(tester, find.text(action));
        if (action == '+ New') {
          expect(
            find.byType(EligibleApplicationPropertiesScreen),
            findsOneWidget,
          );
          await _tap(tester, find.text('Start application'));
        } else {
          expect(find.byType(PropertyListScreen), findsOneWidget);
          await _tap(tester, find.text('Maple Mews'));
          expect(find.byType(PropertyDetailsScreen), findsOneWidget);
          await _tap(tester, find.byKey(const Key('details-apply-now')));
        }
        final form = tester.widget<RentalApplicationFormScreen>(
          find.byType(RentalApplicationFormScreen),
        );
        expect(form.propertyId, property.id);
        expect(form.application, isNull);
        expect(
          form.rentalApplicationApiService!.apiClient,
          same(backend.discovery.client),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final details in [false, true]) {
    testWidgets(
      '${details ? 'details' : 'list'} optional property failure keeps truthful application UI',
      (tester) async {
        final backend = _Backend()..failProperty = true;
        await _open(tester, backend, details: details);
        expect(
          find.text(
            details ? 'Application details' : 'Property details unavailable',
          ),
          findsOneWidget,
        );
        expect(find.text('ACTION REQUIRED'), findsOneWidget);
        expect(find.text(property.id), findsNothing);
        expect(find.text('Maple Mews'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'list loading, error and empty states keep the header and useful actions',
    (tester) async {
      final backend = _Backend();
      final response = Completer<http.Response>();
      backend.intercept = (request) =>
          request.url.path == _root ? response.future : Future.value(null);
      await _open(tester, backend, settle: false);
      await tester.pump();
      expect(find.text('Loading your applications'), findsOneWidget);
      expect(find.text('RENTAL JOURNEY'), findsOneWidget);
      response.complete(http.Response('{}', 500));
      await tester.pumpAndSettle();
      expect(find.text('Could not load applications'), findsOneWidget);
      backend.intercept = null;
      backend.applications = [];
      await _tap(tester, find.text('Try again'));
      expect(find.text('No applications yet'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Browse properties'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Refresh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing detail blocks stale actions and document reads, then retries',
    (tester) async {
      final backend = _Backend()..failDetail = true;
      await _open(tester, backend, details: true);
      expect(find.text('Could not load application'), findsOneWidget);
      expect(find.text('Continue application'), findsNothing);
      expect(find.text('Manage'), findsNothing);
      expect(backend.calls('$_detail/documents'), 0);
      backend.failDetail = false;
      await _tap(tester, find.text('Try again'));
      expect(find.text('Continue application'), findsOneWidget);
      expect(backend.calls('$_detail/documents'), 1);
    },
  );

  testWidgets('wrong detail identity is rejected before document reads', (
    tester,
  ) async {
    final backend = _Backend()..wrongIdentity = true;
    await _open(tester, backend, details: true);
    expect(find.text('Could not load application'), findsOneWidget);
    expect(find.text('Continue application'), findsNothing);
    expect(backend.calls('$_detail/documents'), 0);
  });

  testWidgets(
    'document failure shows no fabricated count and retries independently',
    (tester) async {
      final backend = _Backend()..failDocuments = true;
      await _open(tester, backend, details: true);
      expect(
        find.text('The document summary is currently unavailable.'),
        findsOneWidget,
      );
      expect(find.text('2 documents uploaded'), findsNothing);
      expect(find.text('Manage'), findsOneWidget);
      backend.failDocuments = false;
      await _tap(tester, find.text('Try again'));
      expect(find.text('2 documents uploaded'), findsOneWidget);
      expect(backend.calls(_detail), 1);
      expect(backend.calls('$_detail/documents'), 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'timeline deduplicates latest submission update and never assumes review history',
    (tester) async {
      final backend = _Backend(status: 1);
      backend.application['updatedAt'] = backend.application['submittedAt'];
      await _open(tester, backend, details: true);
      expect(find.text('Application created'), findsOneWidget);
      // One hero title and one timeline milestone, with no duplicate update.
      expect(find.text('Application submitted'), findsNWidgets(2));
      expect(find.text('Last updated'), findsNothing);
      expect(find.text('Documents reviewed'), findsNothing);
      expect(find.text('Changes requested'), findsNothing);
    },
  );

  testWidgets(
    'timeline sorts only known timestamps without inventing a decision date',
    (tester) async {
      final backend = _Backend(status: 4);
      backend.application['submittedAt'] = '2026-09-16T10:00:00Z';
      await _open(tester, backend, details: true);
      expect(
        tester.getRect(find.text('Application created')).top,
        lessThan(tester.getRect(find.text('Last updated')).top),
      );
      expect(
        tester.getRect(find.text('Last updated')).top,
        lessThan(tester.getRect(find.text('Application submitted')).top),
      );
      expect(find.text('Approved'), findsNothing);
      expect(find.text('Your application is approved'), findsOneWidget);
    },
  );

  testWidgets('detail refreshes authoritative status when the app resumes', (
    tester,
  ) async {
    final backend = _Backend(status: 1);
    await _open(tester, backend, details: true);
    expect(find.text('SUBMITTED'), findsOneWidget);
    backend.application = _application(4);
    await tester.runAsync(() async {
      final refreshed = Completer<void>();
      backend.intercept = (request) async {
        if (request.url.path == '$_detail/documents') refreshed.complete();
        return null;
      };
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await refreshed.future;
    });
    await tester.pumpAndSettle();
    expect(find.text('APPROVED'), findsOneWidget);
    expect(find.text('SUBMITTED'), findsNothing);
    expect(find.text('Withdraw application'), findsNothing);
    expect(backend.calls(_detail), 2);
  });

  testWidgets('detail resubmit uses confirmation and authoritative response', (
    tester,
  ) async {
    final backend = _Backend();
    await _open(tester, backend, details: true);
    await _tap(tester, find.text('Resubmit application'));
    await _tap(
      tester,
      find.widgetWithText(FilledButton, 'Resubmit application').last,
    );
    expect(find.text('SUBMITTED'), findsOneWidget);
    expect(find.text('ACTION REQUIRED'), findsNothing);
    expect(find.text('Continue application'), findsNothing);
    expect(
      backend.calls('$_detail/submit'),
      0,
    ); // Count helper defaults to GET.
    expect(backend.discovery.calls('$_detail/submit', 'PATCH'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail withdrawal preserves confirmation and removes editing actions',
    (tester) async {
      final backend = _Backend();
      await _open(tester, backend, details: true);
      await _tap(tester, find.text('Withdraw application'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Withdraw'));
      expect(find.text('WITHDRAWN'), findsOneWidget);
      expect(find.text('Continue application'), findsNothing);
      expect(find.text('Withdraw application'), findsNothing);
      expect(backend.discovery.calls('$_detail/withdraw', 'PATCH'), 1);
      expect(tester.takeException(), isNull);
    },
  );
}
