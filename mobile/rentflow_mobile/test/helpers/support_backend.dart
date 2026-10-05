import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/features/support/models/support_ticket.dart';
import 'package:rentflow_mobile/features/support/services/support_ticket_api_service.dart';
import 'package:rentflow_mobile/shared/profile/help_support_screen.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import '../widget_test.dart' show MemoryTokenStorage, userJson;

const supportPath = '/api/support-tickets';
Map<String, dynamic> ticketJson({
  String id = 'server-ticket',
  String category = 'TechnicalIssue',
  String subject = 'Unable to upload a document',
  String message = 'The upload does not finish.',
  String status = 'Open',
  String created = '2026-10-02T10:00:00Z',
  String updated = '2026-10-03T10:00:00Z',
}) => {
  'id': id,
  'category': category,
  'subject': subject,
  'message': message,
  'status': status,
  'createdAt': created,
  'updatedAt': updated,
};

class SupportBackend {
  SupportBackend({
    this.role = UserRole.tenant,
    Duration timeout = const Duration(seconds: 20),
  }) {
    client = ApiClient(
      baseUrl: 'https://support.test',
      tokenStorage: storage,
      requestTimeout: timeout,
      httpClient: MockClient(_respond),
    );
    service = SupportTicketApiService(client);
    auth = AuthController(
      authService: AuthService(client),
      tokenStorage: storage,
    );
    client.setUnauthorizedHandler(auth.handleUnauthorized);
  }
  final UserRole role;
  final storage = MemoryTokenStorage('support-token');
  late final ApiClient client;
  late final SupportTicketApiService service;
  late final AuthController auth;
  final requests = <http.Request>[];
  List<Map<String, dynamic>> tickets = [ticketJson()];
  Map<String, dynamic>? createdOverride;
  String? getBody;
  String? postBody;
  int getStatus = 200;
  int postStatus = 201;
  bool networkFailure = false;
  Completer<http.Response>? pendingGet;
  Completer<http.Response>? pendingPost;

  List<http.Request> get loads => requests
      .where((r) => r.method == 'GET' && r.url.path == '$supportPath/mine')
      .toList();
  List<http.Request> get creates => requests
      .where((r) => r.method == 'POST' && r.url.path == supportPath)
      .toList();
  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    if (request.url.path.startsWith(supportPath)) {
      if (networkFailure) throw http.ClientException('private network detail');
      if (request.method == 'GET') {
        if (pendingGet != null) return pendingGet!.future;
        return http.Response(getBody ?? jsonEncode(tickets), getStatus);
      }
      if (pendingPost != null) return pendingPost!.future;
      if (postBody != null) return http.Response(postBody!, postStatus);
      if (postStatus != 201) {
        return http.Response('private server trace', postStatus);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final ticket =
          createdOverride ??
          ticketJson(
            id: 'created-by-server',
            category: body['category'] as String,
            subject: body['subject'] as String,
            message: body['message'] as String,
            created: '2030-02-03T10:00:00Z',
            updated: '2030-02-03T10:00:00Z',
          );
      tickets.insert(0, ticket);
      return http.Response(jsonEncode(ticket), 201);
    }
    if (request.url.path == '/api/auth/me') {
      return http.Response(jsonEncode(userJson(role)), 200);
    }
    if (request.url.path.endsWith('/unread-count')) {
      return http.Response('{"unreadCount":0}', 200);
    }
    return http.Response('[]', 200);
  }

  Future<void> pump(
    WidgetTester tester, {
    bool fromProfile = false,
    bool settle = true,
    double scale = 1,
  }) async {
    await auth.restoreSession();
    await tester.pumpWidget(
      AuthScope(
        controller: auth,
        child: MaterialApp(
          theme: AppTheme.build(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: fromProfile
              ? Scaffold(body: SharedProfileContent(user: auth.currentUser!))
              : HelpSupportScreen(service: service),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  void dispose() {
    client.close();
    auth.dispose();
  }
}

Future<void> tapSupport(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> openNewSupport(WidgetTester tester) =>
    tapSupport(tester, find.byKey(const Key('support-new-request')));
Future<void> pickSupportCategory(
  WidgetTester tester,
  SupportCategory category,
) async {
  await tapSupport(tester, find.byKey(const Key('support-category-picker')));
  await tapSupport(
    tester,
    find.byKey(ValueKey('support-category-${category.value}')),
  );
}

Future<void> fillSupport(
  WidgetTester tester, {
  SupportCategory? category = SupportCategory.other,
  String subject = 'Suggestion',
  String message = 'Please improve the property filters.',
}) async {
  if (category != null) await pickSupportCategory(tester, category);
  for (final entry in {
    'support-subject': subject,
    'support-message': message,
  }.entries) {
    final finder = find.byKey(Key(entry.key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, entry.value);
    await tester.pumpAndSettle();
  }
}

FilledButton supportSubmit(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('support-submit')));
