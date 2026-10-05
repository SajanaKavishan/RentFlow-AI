import 'package:flutter/material.dart';
import '../../features/auth/models/current_user.dart';
import '../../features/notifications/models/notification.dart';
import '../../features/notifications/services/notification_api_service.dart';
import '../navigation/role_navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'home_greeting.dart';

class LandlordHome extends StatefulWidget {
  const LandlordHome({
    super.key,
    required this.user,
    required this.onDestinationSelected,
    this.onOpenNotifications,
    this.notificationApiService,
    this.unreadNotificationCount,
    this.now,
  });
  final CurrentUser user;
  final ValueChanged<RoleDestinationId> onDestinationSelected;
  final VoidCallback? onOpenNotifications;
  final NotificationApiService? notificationApiService;
  final int? unreadNotificationCount;
  final DateTime Function()? now;
  @override
  State<LandlordHome> createState() => _LandlordHomeState();
}

class _LandlordHomeState extends State<LandlordHome>
    with WidgetsBindingObserver {
  List<AppNotification> _activity = const [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final page = await widget.notificationApiService?.getNotifications(
        pageSize: 10,
      );
      final items =
          page?.items
              .where(
                (item) =>
                    item.relatedResourceType == 'ViewingRequest' ||
                    item.relatedResourceType == 'RentalApplication',
              )
              .toList() ??
          <AppNotification>[];
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (mounted) setState(() => _activity = items.take(3).toList());
    } catch (_) {
      // Never replace unavailable events with sample activity.
      if (mounted) setState(() => _activity = const []);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: RefreshIndicator(
      onRefresh: _refresh,
      child: AuthenticatedPage(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LANDLORD HOME',
                        style: AppTypography.label.copyWith(
                          color: AppPalette.olive,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${homeGreeting(widget.now?.call() ?? DateTime.now())}, ${homeFirstName(widget.user.fullName)}',
                        style: AppTypography.pageTitle.copyWith(
                          color: AppPalette.darkOlive,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Badge(
                  isLabelVisible: (widget.unreadNotificationCount ?? 0) > 0,
                  label: Text(
                    (widget.unreadNotificationCount ?? 0) > 99
                        ? '99+'
                        : '${widget.unreadNotificationCount ?? 0}',
                  ),
                  child: IconButton(
                    tooltip: 'Notifications',
                    onPressed: widget.onOpenNotifications,
                    icon: const Icon(
                      Icons.notifications_none_outlined,
                      color: AppPalette.darkOlive,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Review tenant requests from your authenticated workspace.',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: 22),
            AppCard(
              color: AppPalette.darkOlive,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.apartment_outlined,
                      size: 20,
                      color: AppPalette.sage,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your rental work, wherever you are.',
                    style: AppTypography.cardTitle.copyWith(
                      color: AppPalette.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Review the essentials on mobile, then move to the web workspace for more.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppPalette.warmCream,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Quick actions'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = MediaQuery.textScalerOf(context).scale(14) > 21;
                final width = stacked
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final action in [
                      (
                        label: 'Viewing requests',
                        icon: Icons.calendar_month_outlined,
                        destination: RoleDestinationId.viewingRequests,
                      ),
                      (
                        label: 'Rental applications',
                        icon: Icons.description_outlined,
                        destination: RoleDestinationId.applications,
                      ),
                    ])
                      SizedBox(
                        width: width,
                        child: AppCard(
                          onTap: () =>
                              widget.onDestinationSelected(action.destination),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(action.icon, color: AppPalette.olive),
                              const SizedBox(height: 22),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      action.label,
                                      style: AppTypography.bodySmall,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: AppPalette.olive,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (_activity.isNotEmpty) ...[
              const SizedBox(height: 24),
              const SectionHeader(title: 'Recent activity'),
              const SizedBox(height: 12),
              for (final item in _activity)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: widget.onOpenNotifications,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.notifications_none_outlined,
                          color: AppPalette.olive,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title, style: AppTypography.body),
                              Text(
                                item.message,
                                style: AppTypography.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                MaterialLocalizations.of(
                                  context,
                                ).formatMediumDate(item.createdAt.toLocal()),
                                style: AppTypography.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            AppCard(
              color: AppPalette.softCream,
              child: Text(
                'Full management tools are available on the RentFlow web workspace.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppPalette.secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
