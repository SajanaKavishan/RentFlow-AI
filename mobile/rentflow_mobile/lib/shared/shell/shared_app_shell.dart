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
  int _selectedIndex = 0;

  List<RoleDestination> get _destinations =>
      destinationsFor(widget.user.role);

  RoleDestination get _selected => _destinations[_selectedIndex];

  void _select(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final ownsAppBar = selected.experience == DestinationExperience.feature;
    return Scaffold(
      appBar: ownsAppBar
          ? null
          : AppBar(
              title: selected.id == RoleDestinationId.home
                  ? Image.asset(
                      'assets/brand/wordmark.png',
                      width: 155,
                      fit: BoxFit.contain,
                      semanticLabel: 'RentFlow AI',
                    )
                  : Text(selected.label),
            ),
      body: _contentFor(selected),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        destinations: _destinations
            .map(
              (destination) => NavigationDestination(
                icon: Icon(destination.icon),
                label: destination.label,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _contentFor(RoleDestination destination) {
    return switch (destination.experience) {
      DestinationExperience.dashboard => _dashboard(),
      DestinationExperience.profile =>
        SafeArea(child: ProfileContent(user: widget.user)),
      DestinationExperience.feature => _featureFor(destination.id),
      DestinationExperience.unavailable => SafeArea(
        child: ModuleUnavailableState(
          title: destination.label,
          explanation: destination.explanation!,
          owner: destination.owner,
        ),
      ),
      DestinationExperience.webWorkspace => SafeArea(
        child: WebWorkspaceState(
          title: destination.label,
          explanation: destination.explanation!,
        ),
      ),
    };
  }

  Widget _featureFor(RoleDestinationId id) => switch (id) {
    RoleDestinationId.viewings =>
      widget.viewingsContent ?? const MyViewingsScreen(),
    RoleDestinationId.applications =>
      widget.applicationsContent ?? const MyRentalApplicationsScreen(),
    _ => const SizedBox.shrink(),
  };

  Widget _dashboard() {
    final quickLinks = _destinations
        .asMap()
        .entries
        .where((entry) => entry.value.id != RoleDestinationId.home)
        .toList(growable: false);
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
                  subtitle: _dashboardSubtitle(widget.user.role),
                ),
                const SizedBox(height: AppSpacing.lg),
                ...quickLinks.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _QuickLinkCard(
                      destination: entry.value,
                      onTap: () => _select(entry.key),
                    ),
                  ),
                ),
                if (widget.user.role == UserRole.tenant)
                  const AppCard(
                    child: Text(
                      'To book a viewing or apply for a rental, first select a real property. Property selection has not been integrated yet.',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _dashboardSubtitle(UserRole role) => switch (role) {
    UserRole.tenant =>
      'Your mobile home for viewings, applications, documents, and profile access.',
    UserRole.landlord =>
      'Review key activity here and use the RentFlow web workspace for full management tools.',
    UserRole.maintenanceTechnician =>
      'Your mobile workspace for assigned operational work.',
    UserRole.admin =>
      'A lightweight mobile overview with secure access to your profile.',
  };
}

class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({required this.destination, required this.onTap});

  final RoleDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (status, tone) = switch (destination.experience) {
      DestinationExperience.unavailable =>
        ('Integration pending', StatusTone.warning),
      DestinationExperience.webWorkspace =>
        ('Web workspace', StatusTone.progress),
      _ => ('Available', StatusTone.success),
    };
    return AppCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.small),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFECEFDF),
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: Icon(destination.icon, color: AppPalette.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    StatusChip(label: status, tone: tone),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppPalette.primary),
            ],
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
