import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/notifications/services/notification_api_service.dart';
import 'package:rentflow_mobile/shared/home/landlord_home.dart';
import 'package:rentflow_mobile/shared/home/home_greeting.dart';
import 'package:rentflow_mobile/shared/navigation/role_navigation.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'helpers/landlord_workspace_fixture.dart';

const user = CurrentUser(
  id: ownerId,
  fullName: 'Pansilu Perera',
  email: 'owner@example.com',
  phoneNumber: '',
  role: UserRole.landlord,
);
void main() {
  test('shared greeting uses the existing Colombo time bands', () {
    expect(homeGreeting(DateTime.utc(2030, 1, 2, 0)), 'Good morning');
    expect(homeGreeting(DateTime.utc(2030, 1, 2, 8)), 'Good afternoon');
    expect(homeGreeting(DateTime.utc(2030, 1, 2, 13)), 'Good evening');
    expect(homeGreeting(DateTime.utc(2030, 1, 2, 18)), 'Good night');
  });
  for (final viewport in [
    (320.0, 720.0, 1.0),
    (720.0, 1560.0, 2.0),
    (1080.0, 2340.0, 3.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'home fits ${viewport.$1}x${viewport.$2} at ${scale * 100}% text',
        (tester) async {
          tester.view.physicalSize = Size(viewport.$1, viewport.$2);
          tester.view.devicePixelRatio = viewport.$3;
          addTearDown(tester.view.reset);
          final selected = <RoleDestinationId>[];
          var bells = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: LandlordHome(
                  user: user,
                  now: () => DateTime.utc(2030, 1, 2, 13),
                  onDestinationSelected: selected.add,
                  onOpenNotifications: () => bells++,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('LANDLORD HOME'), findsOneWidget);
          expect(find.text('Good evening, Pansilu'), findsOneWidget);
          expect(
            find.text('Your rental work, wherever you are.'),
            findsOneWidget,
          );
          expect(find.byTooltip('Open profile'), findsNothing);
          expect(find.text('Recent activity'), findsNothing);
          await tester.tap(find.byTooltip('Notifications'));
          expect(bells, 1);
          for (final label in ['Viewing requests', 'Rental applications']) {
            await tester.ensureVisible(find.text(label));
            await tester.tap(find.text(label));
          }
          expect(selected, [
            RoleDestinationId.viewingRequests,
            RoleDestinationId.applications,
          ]);
          expect(
            find.text(
              'Full management tools are available on the RentFlow web workspace.',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('recent activity is real inbox data and opens the inbox', (
    tester,
  ) async {
    var opened = false;
    final client = workspaceClient(
      (_) async => jsonResponse({
        'items': [
          {
            'id': 'event',
            'eventType': 'ViewingCreated',
            'relatedResourceType': 'ViewingRequest',
            'relatedResourceId': 'viewing',
            'title': 'New viewing request',
            'message': 'A tenant requested a viewing at Garden House.',
            'createdAt': '2030-01-01T10:00:00Z',
            'isRead': false,
          },
          {
            'id': 'irrelevant',
            'eventType': 'Account',
            'relatedResourceType': 'UserAccount',
            'relatedResourceId': ownerId,
            'title': 'Password changed',
            'message': 'Account settings updated.',
            'createdAt': '2030-01-01T10:00:00Z',
            'isRead': true,
          },
        ],
        'pagination': {
          'page': 1,
          'pageSize': 10,
          'totalCount': 2,
          'totalPages': 1,
          'hasNextPage': false,
          'hasPreviousPage': false,
        },
      }),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: LandlordHome(
            user: user,
            onDestinationSelected: (_) {},
            onOpenNotifications: () => opened = true,
            notificationApiService: NotificationApiService(client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent activity'), findsOneWidget);
    expect(find.text('New viewing request'), findsOneWidget);
    expect(find.text('Password changed'), findsNothing);
    await tester.ensureVisible(find.text('New viewing request'));
    await tester.tap(find.text('New viewing request'));
    expect(opened, isTrue);
  });
  testWidgets('failed inbox omits activity', (tester) async {
    final client = workspaceClient((_) async => jsonResponse({}, 500));
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LandlordHome(
            user: user,
            onDestinationSelected: (_) {},
            notificationApiService: NotificationApiService(client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent activity'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
