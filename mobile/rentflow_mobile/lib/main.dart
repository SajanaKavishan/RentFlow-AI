import 'package:flutter/material.dart';
import 'features/properties/services/property_api_service.dart';
import 'core/auth/token_storage.dart';
import 'core/network/api_client.dart';
import 'features/auth/controllers/auth_controller.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/services/auth_service.dart';
import 'features/landing/screens/public_landing_screen.dart';
import 'features/lease_agreements/services/lease_agreement_api_service.dart';
import 'features/maintenance/services/maintenance_api_service.dart';
import 'features/notifications/services/notification_api_service.dart';
import 'features/payments/services/payment_api_service.dart';
import 'features/rental_applications/services/rental_application_api_service.dart';
import 'features/rental_offers/services/rental_offer_api_service.dart';
import 'features/rent_schedules/services/rent_schedule_api_service.dart';
import 'features/viewings/services/viewing_api_service.dart';
import 'features/auth/models/current_user.dart';
import 'features/viewing_follow_ups/services/viewing_follow_up_api_service.dart';
import 'features/viewing_follow_ups/widgets/tenant_follow_up_host.dart';
import 'shared/shell/shared_app_shell.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/shared_widgets.dart';

// Integration TODO: the owned Viewing/Application workflows still use a
// temporary property UUID. The shared shell does not introduce or use it.
void main() {
  runApp(const MyApp(showPublicLanding: true));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.authController, this.showPublicLanding = false});
  final AuthController? authController;
  final bool showPublicLanding;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthController _authController;
  ApiClient? _ownedApiClient;
  var _navigatorKey = GlobalKey<NavigatorState>();
  var _followUpNavigation = FollowUpNavigationObserver();
  String? _navigatorSession;

  @override
  void initState() {
    super.initState();
    if (widget.authController != null) {
      _authController = widget.authController!;
    } else {
      const storage = SecureTokenStorage();
      final apiClient = ApiClient(tokenStorage: storage);
      _ownedApiClient = apiClient;
      _authController = AuthController(
        authService: AuthService(apiClient),
        tokenStorage: storage,
      );
      apiClient.setUnauthorizedHandler(_authController.handleUnauthorized);
    }
    _authController.restoreSession();
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    if (widget.authController == null) _authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthScope(
    controller: _authController,
    child: AnimatedBuilder(
      animation: _authController,
      builder: (context, _) => _buildMaterialApp(),
    ),
  );

  Widget _buildMaterialApp() {
    final session =
        '${_authController.isLoading}-${_authController.currentUser?.id}';
    if (_navigatorSession != session) {
      _navigatorSession = session;
      _navigatorKey = GlobalKey<NavigatorState>();
      _followUpNavigation = FollowUpNavigationObserver();
    }
    return MaterialApp(
      key: ValueKey(session),
      title: 'RentFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      navigatorKey: _navigatorKey,
      navigatorObservers: [_followUpNavigation],
      builder: (context, child) {
        if (_authController.isLoading ||
            _authController.currentUser?.role != UserRole.tenant) {
          return child!;
        }
        final client = _authController.authService.apiClient;
        return TenantFollowUpHost(
          navigatorKey: _navigatorKey,
          navigation: _followUpNavigation,
          apiService: ViewingFollowUpApiService(client),
          applicationApiService: RentalApplicationApiService(client),
          propertyApiService: PropertyApiService(client),
          child: child!,
        );
      },
      home: _home(),
    );
  }

  Widget _home() {
    if (_authController.isLoading) return const SessionRestorationScreen();
    final user = _authController.currentUser;
    if (user == null) {
      return widget.showPublicLanding
          ? const PublicLandingScreen()
          : const LoginScreen();
    }
    final apiClient = _authController.authService.apiClient;
    return SharedAppShell(
      user: user,
      viewingApiService: ViewingApiService(apiClient),
      rentalApplicationApiService: RentalApplicationApiService(apiClient),
      rentalOfferApiService: RentalOfferApiService(apiClient),
      leaseAgreementApiService: LeaseAgreementApiService(apiClient),
      rentScheduleApiService: RentScheduleApiService(apiClient),
      paymentApiService: PaymentApiService(apiClient),
      notificationApiService: NotificationApiService(apiClient),
      propertyApiService: PropertyApiService(apiClient),
      maintenanceApiService: MaintenanceApiService(apiClient),
    );
  }
}

class SessionRestorationScreen extends StatelessWidget {
  const SessionRestorationScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(child: LoadingState(title: 'Restoring your session…')),
  );
}
