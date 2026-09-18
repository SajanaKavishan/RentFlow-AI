import 'package:flutter/material.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/models/current_user.dart';
import '../../features/rental_applications/screens/my_rental_applications_screen.dart';
import '../../features/rental_applications/screens/landlord_rental_applications_screen.dart';
import '../../features/rental_applications/services/rental_application_api_service.dart';
import '../../features/viewings/screens/landlord_viewing_requests_screen.dart';
import '../../features/viewings/screens/my_viewings_screen.dart';
import '../../features/viewings/services/viewing_api_service.dart';
import '../home/landlord_home.dart';
import '../home/tenant_home.dart';
import '../navigation/role_navigation.dart';
import '../profile/shared_profile_content.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class SharedAppShell extends StatefulWidget {
  const SharedAppShell({
    super.key,
    required this.user,
    this.viewingsContent,
    this.applicationsContent,
    this.viewingApiService,
    this.rentalApplicationApiService,
    this.landlordPropertyId,
  });

  final CurrentUser user;

  // Injectable content and services keep shell tests independent from network
  // access while production uses the same authenticated API contracts.
  final Widget? viewingsContent;
  final Widget? applicationsContent;
  final ViewingApiService? viewingApiService;
  final RentalApplicationApiService? rentalApplicationApiService;
  final String? landlordPropertyId;

  @override
  State<SharedAppShell> createState() => _SharedAppShellState();
}

class _SharedAppShellState extends State<SharedAppShell> {
  int _selectedIndex = 0;

  List<RoleDestination> get _destinations => destinationsFor(widget.user.role);

  RoleDestination get _selected => _destinations[_selectedIndex];

  void _select(int index) => setState(() => _selectedIndex = index);

  void _selectDestination(RoleDestinationId id) {
    final index = _destinations.indexWhere(
      (destination) => destination.id == id,
    );
    if (index >= 0) _select(index);
  }

  void _openDocuments() {
    AppSnackbars.show(
      context,
      message: 'Open an application to view or manage its documents.',
    );
    _selectDestination(RoleDestinationId.applications);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final contentOwnsAppBar =
        selected.experience == DestinationExperience.feature ||
        (selected.id == RoleDestinationId.home &&
            widget.user.role == UserRole.tenant);
    return Scaffold(
      appBar: contentOwnsAppBar ? null : _appBar(selected),
      body: _contentFor(selected),
      bottomNavigationBar: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppPalette.outline)),
          ),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _select,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            destinations: _destinations
                .map(
                  (destination) => NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(_selectedIcon(destination.id)),
                    label: destination.label,
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(RoleDestination selected) => AppBar(
    titleSpacing: AppSpacing.base,
    title: selected.id == RoleDestinationId.home
        ? Image.asset(
            'assets/brand/wordmark.png',
            width: 148,
            height: 40,
            fit: BoxFit.contain,
            semanticLabel: 'RentFlow AI',
          )
        : Text(selected.label),
    actions: switch (selected.id) {
      RoleDestinationId.home => [
        if (widget.user.role == UserRole.landlord)
          IconButton(
            tooltip: 'Notifications',
            onPressed: _showNotificationsPending,
            icon: const Icon(Icons.notifications_none_outlined),
          ),
        if (widget.user.role != UserRole.tenant)
          IconButton(
            tooltip: 'Open profile',
            onPressed: () => _selectDestination(RoleDestinationId.profile),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        const SizedBox(width: AppSpacing.sm),
      ],
      RoleDestinationId.profile => [
        TextButton.icon(
          onPressed: () => AuthScope.of(context).logout(),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Logout'),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
      _ => null,
    },
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(1),
      child: Divider(height: 1),
    ),
  );

  Widget _contentFor(RoleDestination destination) {
    return switch (destination.experience) {
      DestinationExperience.dashboard => _dashboard(),
      DestinationExperience.profile => SharedProfileContent(
        user: widget.user,
        onOpenApplications: widget.user.role == UserRole.tenant
            ? () => _selectDestination(RoleDestinationId.applications)
            : null,
      ),
      DestinationExperience.feature => _featureFor(destination.id),
      DestinationExperience.unavailable => ModuleUnavailableState(
        title: destination.label,
        explanation: destination.explanation!,
        owner: destination.owner,
      ),
      DestinationExperience.webWorkspace => WebWorkspaceState(
        title: destination.label,
        explanation: destination.explanation!,
      ),
    };
  }

  void _showNotificationsPending() => AppSnackbars.show(
    context,
    message: 'Notifications are not connected yet.',
  );

  Widget _featureFor(RoleDestinationId id) => switch (id) {
    RoleDestinationId.viewings =>
      widget.viewingsContent ?? const MyViewingsScreen(),
    RoleDestinationId.viewingRequests =>
      widget.viewingsContent ??
          LandlordViewingRequestsScreen(
            propertyId: widget.landlordPropertyId,
            viewingApiService: widget.viewingApiService,
          ),
    RoleDestinationId.applications =>
      widget.applicationsContent ??
          (widget.user.role == UserRole.landlord
              ? LandlordRentalApplicationsScreen(
                  propertyId: widget.landlordPropertyId,
                  rentalApplicationApiService:
                      widget.rentalApplicationApiService,
                )
              : MyRentalApplicationsScreen(
                  rentalApplicationApiService:
                      widget.rentalApplicationApiService,
                )),
    _ => const SizedBox.shrink(),
  };

  Widget _dashboard() {
    if (widget.user.role == UserRole.tenant) {
      return TenantHome(
        user: widget.user,
        viewingApiService: widget.viewingApiService,
        rentalApplicationApiService: widget.rentalApplicationApiService,
        onDestinationSelected: _selectDestination,
        onOpenDocuments: _openDocuments,
        onOpenNotifications: _showNotificationsPending,
      );
    }
    if (widget.user.role == UserRole.landlord) {
      return LandlordHome(
        user: widget.user,
        onDestinationSelected: _selectDestination,
      );
    }
    return _RoleHome(
      user: widget.user,
      destinations: _destinations,
      onSelected: _select,
    );
  }
}

class _RoleHome extends StatelessWidget {
  const _RoleHome({
    required this.user,
    required this.destinations,
    required this.onSelected,
  });

  final CurrentUser user;
  final List<RoleDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final quickLinks = destinations
        .asMap()
        .entries
        .where((entry) => entry.value.id != RoleDestinationId.home)
        .toList(growable: false);
    return AuthenticatedPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            eyebrow: '${user.role.value} workspace',
            title: 'Welcome, ${user.fullName}',
            subtitle: _dashboardSubtitle(user.role),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Workspace'),
          const SizedBox(height: AppSpacing.md),
          ...quickLinks.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _QuickLinkCard(
                destination: entry.value,
                onTap: () => onSelected(entry.key),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dashboardSubtitle(UserRole role) => switch (role) {
    UserRole.tenant => '',
    UserRole.landlord =>
      'Use the RentFlow web workspace for full property and application management.',
    UserRole.maintenanceTechnician =>
      'Mobile operational tools will appear as their integrations become available.',
    UserRole.admin =>
      'A lightweight mobile overview with secure profile access.',
  };
}

class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({required this.destination, required this.onTap});

  final RoleDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (status, tone) = switch (destination.experience) {
      DestinationExperience.unavailable => (
        'Integration pending',
        StatusTone.warning,
      ),
      DestinationExperience.webWorkspace => (
        'Web workspace',
        StatusTone.progress,
      ),
      _ => ('Available', StatusTone.success),
    };
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppPalette.sage,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Icon(destination.icon, color: AppPalette.darkOlive),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                StatusChip(label: status, tone: tone),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppPalette.olive),
        ],
      ),
    );
  }
}

IconData _selectedIcon(RoleDestinationId id) => switch (id) {
  RoleDestinationId.home => Icons.home,
  RoleDestinationId.properties => Icons.home_work,
  RoleDestinationId.viewings ||
  RoleDestinationId.viewingRequests => Icons.calendar_month,
  RoleDestinationId.applications => Icons.description,
  RoleDestinationId.assignedWork => Icons.handyman,
  RoleDestinationId.profile => Icons.person,
};
