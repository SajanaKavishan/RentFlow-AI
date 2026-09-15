import 'package:flutter/material.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/models/current_user.dart';
import '../../features/rental_applications/screens/my_rental_applications_screen.dart';
import '../../features/viewings/screens/my_viewings_screen.dart';
import '../navigation/role_navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class SharedAppShell extends StatefulWidget {
  const SharedAppShell({
    super.key,
    required this.user,
    this.viewingsContent,
    this.applicationsContent,
  });
  final CurrentUser user;
  // Injectable content lets shell tests avoid feature API calls.
  final Widget? viewingsContent;
  final Widget? applicationsContent;

  @override
  State<SharedAppShell> createState() => _SharedAppShellState();
}

class _SharedAppShellState extends State<SharedAppShell> {
  int _tenantIndex = 0;
  String? _otherDestination;

  bool get _isTenant => widget.user.role == UserRole.tenant;
  bool get _featureTab => _isTenant && (_tenantIndex == 2 || _tenantIndex == 3);

  void _openFutureModule(String label) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(label)),
          body: SafeArea(child: UnavailableState(module: label)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isTenant
        ? const [
            'Home',
            'Properties',
            'Viewings',
            'Applications',
            'Profile',
          ][_tenantIndex]
        : _otherDestination ?? 'Dashboard';
    return Scaffold(
      appBar: _featureTab
          ? null
          : AppBar(
              title: title == 'Home' || title == 'Dashboard'
                  ? Image.asset(
                      'assets/brand/wordmark.png',
                      width: 155,
                      fit: BoxFit.contain,
                      semanticLabel: 'RentFlow AI',
                    )
                  : Text(title),
              actions: [
                IconButton(
                  tooltip: 'Profile',
                  onPressed: () => setState(() {
                    if (_isTenant) {
                      _tenantIndex = 4;
                    } else {
                      _otherDestination = 'Profile';
                    }
                  }),
                  icon: const Icon(Icons.account_circle_outlined),
                ),
              ],
            ),
      drawer: _isTenant
          ? null
          : Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    DrawerHeader(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Image.asset(
                            'assets/brand/wordmark.png',
                            width: 210,
                            fit: BoxFit.contain,
                            semanticLabel: 'RentFlow AI',
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text('${widget.user.role.value} workspace'),
                        ],
                      ),
                    ),
                    ListTile(
                      title: const Text('Dashboard'),
                      leading: const Icon(Icons.dashboard_outlined),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _otherDestination = null);
                      },
                    ),
                    ...destinationsFor(widget.user.role).map(
                      (item) => ListTile(
                        title: Text(item.label),
                        subtitle: const Text('Not integrated yet'),
                        leading: const Icon(Icons.construction_outlined),
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _otherDestination = item.label);
                        },
                      ),
                    ),
                    ListTile(
                      title: const Text('Profile'),
                      leading: const Icon(Icons.person_outline),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _otherDestination = 'Profile');
                      },
                    ),
                  ],
                ),
              ),
            ),
      body: _body(),
      bottomNavigationBar: _isTenant
          ? NavigationBar(
              selectedIndex: _tenantIndex,
              onDestinationSelected: (index) =>
                  setState(() => _tenantIndex = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.home_work_outlined),
                  label: 'Properties',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Viewings',
                ),
                NavigationDestination(
                  icon: Icon(Icons.description_outlined),
                  label: 'Applications',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Profile',
                ),
              ],
            )
          : null,
    );
  }

  Widget _body() {
    if (_isTenant) {
      return switch (_tenantIndex) {
        0 => _dashboard(),
        1 => const SafeArea(child: UnavailableState(module: 'Properties')),
        2 => widget.viewingsContent ?? const MyViewingsScreen(),
        3 => widget.applicationsContent ?? const MyRentalApplicationsScreen(),
        _ => SafeArea(child: ProfileContent(user: widget.user)),
      };
    }
    if (_otherDestination == 'Profile') {
      return SafeArea(child: ProfileContent(user: widget.user));
    }
    if (_otherDestination != null) {
      return SafeArea(child: UnavailableState(module: _otherDestination!));
    }
    return _dashboard();
  }

  Widget _dashboard() {
    final destinations = destinationsFor(widget.user.role);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  eyebrow: '${widget.user.role.value} workspace',
                  title: 'Welcome, ${widget.user.fullName}',
                  subtitle: widget.user.role == UserRole.landlord
                      ? 'Detailed viewing, application, and validation management is available in the RentFlow web dashboard.'
                      : 'Choose a destination. Modules still being integrated are clearly marked.',
                ),
                const SizedBox(height: AppSpacing.lg),
                ...destinations.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          StatusChip(
                            label: item.available
                                ? 'Available'
                                : 'Not available yet',
                            tone: item.available
                                ? StatusTone.success
                                : StatusTone.warning,
                          ),
                          if (item.note != null)
                            Text(
                              item.note!,
                              style: const TextStyle(color: AppPalette.muted),
                            ),
                          if (_isTenant && !item.available)
                            TextButton(
                              onPressed: () => _openFutureModule(item.label),
                              child: Text('About ${item.label}'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_isTenant)
                  const AppCard(
                    child: Text(
                      'To book a viewing or apply for rental, first select a real property. Property selection has not been integrated yet.',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileContent extends StatelessWidget {
  const ProfileContent({super.key, required this.user});
  final CurrentUser user;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpacing.base),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(
              title: 'Profile',
              subtitle:
                  'Your current account details. Editing is not available.',
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileField('Full name', user.fullName),
                  _ProfileField('Email', user.email),
                  _ProfileField('Phone number', user.phoneNumber),
                  _ProfileField('Role', user.role.value),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.danger,
                    ),
                    onPressed: () => AuthScope.of(context).logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.base),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppPalette.muted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          softWrap: true,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    ),
  );
}
