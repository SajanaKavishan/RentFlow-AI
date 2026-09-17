import 'package:flutter/material.dart';

import 'core/auth/token_storage.dart';
import 'core/network/api_client.dart';
import 'features/auth/controllers/auth_controller.dart';
import 'features/auth/models/current_user.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/services/auth_service.dart';
import 'features/rental_applications/screens/my_rental_applications_screen.dart';
import 'features/rental_applications/screens/rental_application_form_screen.dart';
import 'features/viewings/screens/book_viewing_screen.dart';
import 'features/viewings/screens/my_viewings_screen.dart';

// TODO(dev-only): Replace with the property ID supplied by property navigation
// when property screens are implemented.
const _temporaryPropertyId = '22222222-2222-2222-2222-222222222222';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.authController});
  final AuthController? authController;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthController _authController;
  ApiClient? _ownedApiClient;

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
  Widget build(BuildContext context) {
    return AuthScope(
      controller: _authController,
      child: AnimatedBuilder(
        animation: _authController,
        builder: (context, _) => MaterialApp(
          key: ValueKey(
            '${_authController.isLoading}-${_authController.currentUser?.id}',
          ),
          title: 'RentFlow',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF5D6842),
            ),
            useMaterial3: true,
          ),
          home: _home(),
        ),
      ),
    );
  }

  Widget _home() {
    if (_authController.isLoading) return const SessionRestorationScreen();
    final user = _authController.currentUser;
    if (user == null) return const LoginScreen();
    if (user.role == UserRole.tenant) return TenantHome(user: user);
    return RoleLandingScreen(user: user);
  }
}

class SessionRestorationScreen extends StatelessWidget {
  const SessionRestorationScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Restoring your session…'),
          ],
        ),
      ),
    ),
  );
}

/// Tenant launcher for JWT-owned tenant workflows.
class TenantHome extends StatelessWidget {
  const TenantHome({super.key, required this.user});
  final CurrentUser user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RentFlow'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => AuthScope.of(context).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Viewing Booking',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text('Signed in as ${user.fullName}'),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BookViewingScreen(
                              propertyId: _temporaryPropertyId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_home_work_outlined),
                      label: const Text('Book a Viewing'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MyViewingsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('My Viewings'),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 24),
                    Text(
                      'Rental Applications',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manage your applications and documents in My Applications.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => RentalApplicationFormScreen(
                              propertyId: _temporaryPropertyId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Apply for Rental'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MyRentalApplicationsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('My Applications'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoleLandingScreen extends StatelessWidget {
  const RoleLandingScreen({super.key, required this.user});
  final CurrentUser user;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('RentFlow'),
      actions: [
        IconButton(
          tooltip: 'Logout',
          onPressed: () => AuthScope.of(context).logout(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user_outlined, size: 54),
                const SizedBox(height: 18),
                Text(
                  'Welcome, ${user.fullName}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  user.role == UserRole.landlord
                      ? 'Landlord management workflows are available in the RentFlow web dashboard.'
                      : 'You are signed in. No mobile workflows are assigned to the ${user.role.value} role yet.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
