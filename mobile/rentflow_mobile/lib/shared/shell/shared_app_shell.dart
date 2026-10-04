import 'package:flutter/material.dart';

import '../../features/auth/models/current_user.dart';
import '../../features/application_documents/screens/tenant_documents_screen.dart';
import '../../features/tenant_lease_payments/screens/tenant_lease_payments_screen.dart';
import '../../features/tenant_lease_payments/services/tenant_lease_payments_api_service.dart';
import '../../features/maintenance/screens/assigned_work_screen.dart';
import '../../features/maintenance/screens/landlord_maintenance_screen.dart';
import '../../features/maintenance/screens/my_maintenance_requests_screen.dart';
import '../../features/maintenance/services/maintenance_api_service.dart';
import '../../features/lease_agreements/screens/my_leases_screen.dart';
import '../../features/lease_agreements/services/lease_agreement_api_service.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/notifications/services/notification_api_service.dart';
import '../../features/payments/screens/pay_rent_screen.dart';
import '../../features/payments/services/payment_api_service.dart';
import '../../features/properties/screens/property_list_screen.dart';
import '../../features/properties/services/property_api_service.dart';
import '../../features/rental_applications/screens/landlord_rental_applications_screen.dart';
import '../../features/rental_applications/screens/my_rental_applications_screen.dart';
import '../../features/rental_applications/services/rental_application_api_service.dart';
import '../../features/rental_offers/services/rental_offer_api_service.dart';
import '../../features/rent_schedules/services/rent_schedule_api_service.dart';
import '../../features/viewings/screens/landlord_viewing_requests_screen.dart';
import '../../features/viewings/screens/my_viewings_screen.dart';
import '../../features/viewings/services/viewing_api_service.dart';
import '../home/landlord_home.dart';
import '../home/tenant_home.dart';
import '../navigation/role_navigation.dart';
import '../navigation/tenant_navigation_icon.dart';
import '../profile/shared_profile_content.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class SharedAppShell extends StatefulWidget {
  const SharedAppShell({
    super.key,
    required this.user,
    this.propertyApiService,
    this.viewingsContent,
    this.applicationsContent,
    this.viewingApiService,
    this.rentalApplicationApiService,
    this.rentalOfferApiService,
    this.leaseAgreementApiService,
    this.rentScheduleApiService,
    this.paymentApiService,
    this.notificationApiService,
    this.maintenanceApiService,
    this.landlordPropertyId,
  });

  final CurrentUser user;

  // Injectable content and services keep shell tests independent from network
  // access while production uses the same authenticated API contracts.
  final Widget? viewingsContent;
  final Widget? applicationsContent;
  final ViewingApiService? viewingApiService;
  final RentalApplicationApiService? rentalApplicationApiService;
  final RentalOfferApiService? rentalOfferApiService;
  final LeaseAgreementApiService? leaseAgreementApiService;
  final RentScheduleApiService? rentScheduleApiService;
  final PaymentApiService? paymentApiService;
  final NotificationApiService? notificationApiService;
  final MaintenanceApiService? maintenanceApiService;
  final String? landlordPropertyId;
  final PropertyApiService? propertyApiService;

  @override
  State<SharedAppShell> createState() => _SharedAppShellState();
}

class _SharedAppShellState extends State<SharedAppShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int? _unreadCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshUnreadCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshUnreadCount();
  }

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
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TenantDocumentsScreen(
          rentalApplicationApiService: widget.rentalApplicationApiService,
          propertyApiService: widget.propertyApiService,
        ),
      ),
    );
  }

  void _openApplicationDocuments() {
    AppSnackbars.show(
      context,
      message: 'Open an application to view or manage its documents.',
    );
    _selectDestination(RoleDestinationId.applications);
  }

  void _openViewings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            widget.viewingsContent ??
            MyViewingsScreen(viewingApiService: widget.viewingApiService),
      ),
    );
  }

  Future<void> _refreshUnreadCount() async {
    final service = widget.notificationApiService;

    if (service == null) return;

    try {
      final count = await service.getUnreadCount();

      if (mounted) {
        setState(() => _unreadCount = count > 0 ? count : null);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _unreadCount = null);
      }
    }
  }

  Future<void> _openNotifications() async {
    final service = widget.notificationApiService;

    if (service == null) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
          notificationApiService: service,
          userRole: widget.user.role,
          viewingApiService: widget.viewingApiService,
          rentalApplicationApiService: widget.rentalApplicationApiService,
        ),
      ),
    );

    await _refreshUnreadCount();
  }

  void _openLease() {
    final leaseService = widget.leaseAgreementApiService;
    final offerService = widget.rentalOfferApiService;
    if (leaseService == null || offerService == null) {
      _openTenantAccount(TenantAccountSection.lease);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyLeasesScreen(
          leaseAgreementApiService: leaseService,
          rentalOfferApiService: offerService,
          rentScheduleApiService: widget.rentScheduleApiService,
          paymentApiService: widget.paymentApiService,
        ),
      ),
    );
  }

  void _openPayRent() {
    final rentScheduleService = widget.rentScheduleApiService;
    final paymentService = widget.paymentApiService;
    if (rentScheduleService == null || paymentService == null) {
      _openTenantAccount(TenantAccountSection.rent);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PayRentScreen(
          rentScheduleApiService: rentScheduleService,
          paymentApiService: paymentService,
        ),
      ),
    );
  }

  void _openTenantAccount(TenantAccountSection section) {
    final client =
        widget.rentalApplicationApiService?.apiClient ??
        widget.propertyApiService?.apiClient ??
        widget.viewingApiService?.apiClient ??
        widget.notificationApiService?.apiClient ??
        widget.maintenanceApiService?.apiClient ??
        widget.leaseAgreementApiService?.apiClient ??
        widget.rentalOfferApiService?.apiClient ??
        widget.rentScheduleApiService?.apiClient ??
        widget.paymentApiService?.apiClient;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TenantLeasePaymentsScreen(
          section: section,
          apiService: client == null
              ? null
              : TenantLeasePaymentsApiService(client),
          propertyApiService: widget.propertyApiService,
        ),
      ),
    );
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
      bottomNavigationBar: widget.user.role == UserRole.tenant
          ? _tenantBottomNavigation()
          : _sharedBottomNavigation(),
    );
  }

  Widget _tenantBottomNavigation() => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppPalette.white,
      border: Border(top: BorderSide(color: AppPalette.outline)),
    ),
    child: SafeArea(
      top: false,
      child: NavigationBar(
        height: 64,
        elevation: 0,
        backgroundColor: AppPalette.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: _destinations
            .map(
              (destination) => NavigationDestination(
                icon: TenantNavigationIcon(destination: destination.id),
                selectedIcon: TenantNavigationIcon(
                  destination: destination.id,
                  selected: true,
                ),
                label: destination.label,
                tooltip: destination.label,
              ),
            )
            .toList(growable: false),
      ),
    ),
  );

  Widget _sharedBottomNavigation() => SafeArea(
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
  );

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
        IconButton(
          tooltip: 'Notifications',
          onPressed: _openNotifications,
          icon: _NotificationBell(unreadCount: _unreadCount),
        ),
        if (widget.user.role != UserRole.tenant)
          IconButton(
            tooltip: 'Open profile',
            onPressed: () => _selectDestination(RoleDestinationId.profile),
            icon: const Icon(Icons.account_circle_outlined),
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
            ? _openApplicationDocuments
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

  Widget _featureFor(RoleDestinationId id) => switch (id) {
    RoleDestinationId.properties =>
      widget.propertyApiService == null
          ? const ModuleUnavailableState(
              title: 'Properties',
              explanation: 'Property discovery is currently unavailable.',
              owner: 'Property management',
            )
          : PropertyListScreen(
              propertyApiService: widget.propertyApiService!,
              viewingApiService: widget.viewingApiService,
              rentalApplicationApiService: widget.rentalApplicationApiService,
            ),

    RoleDestinationId.viewings =>
      widget.viewingsContent ??
          MyViewingsScreen(viewingApiService: widget.viewingApiService),

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

    RoleDestinationId.maintenance => MyMaintenanceRequestsScreen(
      maintenanceApiService: widget.maintenanceApiService,
    ),

    RoleDestinationId.landlordMaintenance => LandlordMaintenanceScreen(
      landlordId: widget.user.id,
      propertyApiService: widget.propertyApiService,
      maintenanceApiService: widget.maintenanceApiService,
    ),

    RoleDestinationId.assignedWork => AssignedWorkScreen(
      maintenanceApiService: widget.maintenanceApiService,
      technicianId: widget.user.id,
    ),

    _ => const SizedBox.shrink(),
  };

  Widget _dashboard() {
    if (widget.user.role == UserRole.tenant) {
      return TenantHome(
        user: widget.user,
        viewingApiService: widget.viewingApiService,
        rentalApplicationApiService: widget.rentalApplicationApiService,
        propertyApiService: widget.propertyApiService,
        notificationApiService: widget.notificationApiService,
        maintenanceApiService: widget.maintenanceApiService,
        onDestinationSelected: _selectDestination,
        onOpenViewings: _openViewings,
        onOpenLease: _openLease,
        onPayRent: _openPayRent,
        onOpenDocuments: _openDocuments,
        unreadNotificationCount: _unreadCount,
        onOpenNotifications: _openNotifications,
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

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({this.unreadCount});

  final int? unreadCount;

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: unreadCount != null,
    label: Text(
      unreadCount != null && unreadCount! > 99 ? '99+' : '${unreadCount ?? ''}',
    ),
    child: const Icon(Icons.notifications_none_outlined),
  );
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
  RoleDestinationId.maintenance => Icons.build,
  RoleDestinationId.landlordMaintenance => Icons.build,
  RoleDestinationId.assignedWork => Icons.handyman,
  RoleDestinationId.profile => Icons.person,
};
