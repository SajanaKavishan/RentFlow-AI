import 'package:flutter/material.dart';

import '../../features/auth/models/current_user.dart';
import '../../features/maintenance/services/maintenance_api_service.dart';
import '../../features/notifications/services/notification_api_service.dart';
import '../../features/properties/screens/property_details_screen.dart';
import '../../features/properties/screens/property_matching_screen.dart';
import '../../features/properties/services/property_api_service.dart';
import '../../features/properties/widgets/property_photo.dart';
import '../../features/rental_applications/services/rental_application_api_service.dart';
import '../../features/viewings/services/viewing_api_service.dart';
import '../navigation/role_navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'tenant_dashboard_data.dart';

class TenantHome extends StatefulWidget {
  const TenantHome({
    super.key,
    required this.user,
    required this.onDestinationSelected,
    required this.onOpenViewings,
    required this.onOpenDocuments,
    required this.onOpenNotifications,
    this.onOpenLease,
    this.onPayRent,
    this.unreadNotificationCount,
    this.viewingApiService,
    this.rentalApplicationApiService,
    this.propertyApiService,
    this.notificationApiService,
    this.maintenanceApiService,
    this.dashboardService,
    this.now,
  });
  final CurrentUser user;
  final ValueChanged<RoleDestinationId> onDestinationSelected;
  final VoidCallback onOpenViewings;
  final VoidCallback onOpenDocuments;
  final VoidCallback onOpenNotifications;
  final VoidCallback? onOpenLease;
  final VoidCallback? onPayRent;
  final int? unreadNotificationCount;
  final ViewingApiService? viewingApiService;
  final RentalApplicationApiService? rentalApplicationApiService;
  final PropertyApiService? propertyApiService;
  final NotificationApiService? notificationApiService;
  final MaintenanceApiService? maintenanceApiService;
  final TenantDashboardService? dashboardService;
  final DateTime Function()? now;
  @override
  State<TenantHome> createState() => _TenantHomeState();
}

class _TenantHomeState extends State<TenantHome> {
  Future<TenantDashboardSnapshot>? _snapshot;
  Future<TenantRecommendations>? _recommendations;
  DateTime get _now => widget.now?.call() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TenantHome old) {
    super.didUpdateWidget(old);
    if (old.user.id != widget.user.id ||
        old.viewingApiService != widget.viewingApiService ||
        old.rentalApplicationApiService != widget.rentalApplicationApiService ||
        old.propertyApiService != widget.propertyApiService ||
        old.notificationApiService != widget.notificationApiService ||
        old.maintenanceApiService != widget.maintenanceApiService ||
        old.dashboardService != widget.dashboardService) {
      _load();
    }
  }

  void _load() {
    final client =
        widget.propertyApiService?.apiClient ??
        widget.viewingApiService?.apiClient ??
        widget.rentalApplicationApiService?.apiClient ??
        widget.notificationApiService?.apiClient ??
        widget.maintenanceApiService?.apiClient;
    final service =
        widget.dashboardService ??
        (client == null ? null : TenantDashboardService(client));
    _snapshot = service?.load(
      tenantId: widget.user.id,
      now: _now,
      viewings: widget.viewingApiService,
      applications: widget.rentalApplicationApiService,
      notifications: widget.notificationApiService,
      maintenance: widget.maintenanceApiService,
      properties: widget.propertyApiService,
    );
    _loadRecommendations();
  }

  void _loadRecommendations() {
    final service = widget.propertyApiService;
    _recommendations = service == null
        ? null
        : TenantDashboardService.recommendations(service);
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait<Object?>([
      ?_snapshot,
      if (_recommendations != null)
        _recommendations!.then<Object?>((value) => value, onError: (_) => null),
    ]);
  }

  Future<void> _openMatching() async {
    final service = widget.propertyApiService;
    if (service == null) return;
    TenantRecommendations? recommendations;
    try {
      recommendations = await _recommendations;
    } catch (_) {
      /* Matching can still be opened when recommendations fail. */
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PropertyMatchingScreen(
          propertyApiService: service,
          viewingApiService: widget.viewingApiService,
          rentalApplicationApiService: widget.rentalApplicationApiService,
          initialResult: recommendations?.matches,
        ),
      ),
    );
    if (mounted) setState(_loadRecommendations);
  }

  void _openActivity(TenantActivity item) {
    if (item.isNotification) {
      widget.onOpenNotifications();
    } else if (item.destination == RoleDestinationId.viewings) {
      widget.onOpenViewings();
    } else if (item.destination != null) {
      widget.onDestinationSelected(item.destination!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = _now.toUtc().add(const Duration(hours: 5, minutes: 30));
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: AuthenticatedPage(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                          _formatHeaderDate(local).toUpperCase(),
                          style: _style(
                            12,
                            FontWeight.w700,
                            color: AppPalette.olive,
                            spacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_greetingForHour(local.hour)}, ${_firstName(widget.user.fullName)}',
                          style: _style(
                            28,
                            FontWeight.w700,
                            height: 1.1,
                            color: AppPalette.darkOlive,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
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
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: AppPalette.white,
                        side: const BorderSide(color: AppPalette.outline),
                      ),
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        color: AppPalette.darkOlive,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FutureBuilder<TenantDashboardSnapshot>(
                future: _snapshot,
                builder: (context, result) {
                  final loading =
                      _snapshot != null &&
                      result.connectionState != ConnectionState.done;
                  final unavailable =
                      _snapshot == null ||
                      result.hasError ||
                      result.data?.journeyUnavailable == true;
                  final journey = loading ? null : result.data?.journey;
                  return _JourneyCard(
                    status: loading
                        ? 'Checking activity'
                        : unavailable
                        ? 'Unable to load'
                        : journey?.status ?? 'No activity yet',
                    title: loading
                        ? 'Loading your journey'
                        : unavailable
                        ? 'Journey unavailable'
                        : journey?.title ?? 'No rental journey yet',
                    subtitle: loading
                        ? 'Checking your rental activity.'
                        : unavailable
                        ? 'Your journey could not be loaded. Please try again.'
                        : journey?.subtitle ??
                              'Real viewing or application progress will appear here once available.',
                    helper: journey?.helper,
                    loading: loading,
                    onRetry: unavailable && _snapshot != null
                        ? () => setState(_load)
                        : null,
                    onTap: journey?.destination == null
                        ? null
                        : () {
                            if (journey!.destination ==
                                RoleDestinationId.viewings) {
                              widget.onOpenViewings();
                            } else {
                              widget.onDestinationSelected(
                                journey.destination!,
                              );
                            }
                          },
                  );
                },
              ),
              const SizedBox(height: 28),
              _SectionHeading(
                title: 'Recommended for You',
                subtitle: 'Based on your preferences',
                action: widget.propertyApiService == null
                    ? null
                    : _openMatching,
              ),
              const SizedBox(height: 12),
              _buildRecommendations(),
              const SizedBox(height: 28),
              const _SectionHeading(title: 'What would you like to do?'),
              const SizedBox(height: 8),
              _QuickActionsRow(
                actions: [
                  _QuickAction(
                    'My Viewings',
                    Icons.calendar_month_outlined,
                    widget.onOpenViewings,
                  ),
                  _QuickAction(
                    'My Lease',
                    Icons.article_outlined,
                    widget.onOpenLease,
                  ),
                  _QuickAction(
                    'Pay Rent',
                    Icons.credit_card_outlined,
                    widget.onPayRent,
                  ),
                  _QuickAction(
                    'Documents',
                    Icons.folder_outlined,
                    widget.onOpenDocuments,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildActivity(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendations() => FutureBuilder<TenantRecommendations>(
    future: _recommendations,
    builder: (context, result) {
      if (_recommendations == null) {
        return const _PanelMessage(
          'Recommendations unavailable',
          'Property recommendations are currently unavailable.',
        );
      }
      if (result.connectionState != ConnectionState.done) {
        return Semantics(
          label: 'Loading recommendations',
          child: SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 2,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => Container(
                width: 220,
                decoration: BoxDecoration(
                  color: AppPalette.softCream,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: ColoredBox(color: AppPalette.sage)),
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      if (result.hasError) {
        return _PanelMessage(
          'Recommendations unavailable',
          'We could not load your matches. Please try again.',
          action: () => setState(_loadRecommendations),
          actionLabel: 'Retry recommendations',
        );
      }
      final data = result.data!;
      if (!data.configured) {
        return _PanelMessage(
          'Make yourself at home',
          'Set your preferences to get smarter recommendations.',
          action: _openMatching,
          actionLabel: 'Find my matches',
        );
      }
      if (data.items.isEmpty) {
        return _PanelMessage(
          data.partialFailure
              ? 'Recommendations unavailable'
              : 'No available matches yet',
          data.partialFailure
              ? 'Some property details could not be loaded. Please try again.'
              : 'No available properties match your saved preferences right now.',
          action: data.partialFailure
              ? () => setState(_loadRecommendations)
              : _openMatching,
          actionLabel: data.partialFailure
              ? 'Retry recommendations'
              : 'Explore matches',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth * 0.73).clamp(220.0, 300.0);
              final height = data.items
                  .map(
                    (item) =>
                        _RecommendationCard.heightFor(context, item, width),
                  )
                  .reduce((a, b) => a > b ? a : b);
              return SizedBox(
                height: height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: data.items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, index) => SizedBox(
                    width: width,
                    child: _RecommendationCard(
                      item: data.items[index],
                      service: widget.propertyApiService!,
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => PropertyDetailsScreen(
                            property: data.items[index].property,
                            propertyApiService: widget.propertyApiService!,
                            viewingApiService: widget.viewingApiService,
                            rentalApplicationApiService:
                                widget.rentalApplicationApiService,
                            matchScore: data.items[index].match.matchScore,
                            matchReasons: data.items[index].match.matchReasons,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (data.partialFailure)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Some property details could not be loaded.',
                style: _style(
                  13,
                  FontWeight.w400,
                  color: AppPalette.secondaryText,
                ),
              ),
            ),
        ],
      );
    },
  );
  Widget _buildActivity() => FutureBuilder<TenantDashboardSnapshot>(
    future: _snapshot,
    builder: (context, result) {
      final data = result.data;
      final items = data?.activities ?? <TenantActivity>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            title: 'Recent activity',
            action: items.length > 3 ? () => _showAllActivities(items) : null,
          ),
          const SizedBox(height: 12),
          if (_snapshot != null &&
              result.connectionState != ConnectionState.done)
            const _PanelMessage(
              'Loading recent activity',
              'Checking your account updates.',
              loading: true,
            )
          else if (_snapshot == null ||
              result.hasError ||
              data?.successfulSources == 0)
            _PanelMessage(
              'Activity unavailable',
              'We could not load your recent activity.',
              action: _snapshot == null ? null : () => setState(_load),
              actionLabel: 'Retry activity',
            )
          else ...[
            if (data!.failedSources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Some activity could not be loaded (${data.failedSources.toSet().join(', ')}).',
                      style: _style(
                        13,
                        FontWeight.w400,
                        color: AppPalette.secondaryText,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(_load),
                      child: const Text('Retry activity'),
                    ),
                  ],
                ),
              ),
            if (items.isEmpty)
              const _PanelMessage(
                'No recent activity',
                'Viewing, application, lease, payment and maintenance updates will appear here.',
              )
            else
              Column(
                key: const Key('tenant-home-activity-list'),
                children: [
                  for (var index = 0; index < items.take(3).length; index++)
                    Padding(
                      padding: EdgeInsets.only(bottom: index < 2 ? 8 : 0),
                      child: AppCard(
                        key: ValueKey('tenant-home-activity-$index'),
                        padding: EdgeInsets.zero,
                        child: _ActivityTile(
                          activity: items[index],
                          now: _now,
                          onTap:
                              items[index].destination != null ||
                                  items[index].isNotification
                              ? () => _openActivity(items[index])
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ],
      );
    },
  );
  void _showAllActivities(List<TenantActivity> items) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.warmCream,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              key: const Key('tenant-all-activity-sheet'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeading(title: 'All recent activity'),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => AppCard(
                      padding: EdgeInsets.zero,
                      child: _ActivityTile(
                        activity: items[index],
                        now: _now,
                        onTap:
                            items[index].destination != null ||
                                items[index].isNotification
                            ? () {
                                Navigator.of(context).pop();
                                _openActivity(items[index]);
                              }
                            : null,
                      ),
                    ),
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

TextStyle _style(
  double size,
  FontWeight weight, {
  double height = 1.4,
  Color color = AppPalette.primaryText,
  double? spacing,
}) => TextStyle(
  fontSize: size,
  fontWeight: weight,
  height: height,
  color: color,
  letterSpacing: spacing,
);

double _measuredHeight(
  BuildContext context,
  TextSpan span,
  double width, {
  int? maxLines,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: span.text,
      children: span.children,
      style: DefaultTextStyle.of(context).style.merge(span.style),
    ),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
    maxLines: maxLines,
  )..layout(maxWidth: width);
  final height = painter.height.ceilToDouble();
  painter.dispose();
  return height;
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _style(22, FontWeight.w700, height: 1.2)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: _style(
                  13,
                  FontWeight.w400,
                  color: AppPalette.secondaryText,
                ),
              ),
            ],
          ],
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: action,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('See all'),
        ),
    ],
  );
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.status,
    required this.title,
    required this.subtitle,
    this.helper,
    this.loading = false,
    this.onTap,
    this.onRetry,
  });
  final String status, title, subtitle;
  final String? helper;
  final bool loading;
  final VoidCallback? onTap, onRetry;
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('tenant-journey-card'),
    decoration: BoxDecoration(
      color: AppPalette.darkOlive,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: AppPalette.darkOlive.withValues(alpha: 0.12),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.softCream,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: _style(
                            11,
                            FontWeight.w700,
                            spacing: 0.8,
                            color: AppPalette.darkOlive,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppPalette.sage,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: _style(
                  24,
                  FontWeight.w700,
                  height: 1.15,
                  color: AppPalette.white,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: _style(
                    14,
                    FontWeight.w500,
                    height: 1.35,
                    color: AppPalette.sage,
                  ),
                ),
              ],
              if (helper != null) ...[
                const SizedBox(height: 18),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppPalette.sage.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  helper!,
                  style: _style(12, FontWeight.w500, color: AppPalette.sage),
                ),
              ],
              if (loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: AppPalette.sage),
              ],
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: AppPalette.white,
                  ),
                  child: const Text('Try again'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage(
    this.title,
    this.subtitle, {
    this.action,
    this.actionLabel,
    this.loading = false,
  });
  final String title, subtitle;
  final VoidCallback? action;
  final String? actionLabel;
  final bool loading;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _style(16, FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: _style(13, FontWeight.w400, color: AppPalette.secondaryText),
        ),
        if (loading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (action != null)
          TextButton(
            onPressed: action,
            child: Text(actionLabel ?? 'Try again'),
          ),
      ],
    ),
  );
}

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.actions});
  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 7.0;
      const visibleCards = 3;
      const labelStyle = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: AppPalette.primaryText,
      );
      final scaler = MediaQuery.textScalerOf(context);
      var minimumWidth = 88.0;
      // At larger text sizes, allow each word to remain legible in two lines.
      // The row scrolls when these cards no longer fit the available width.
      if (scaler.scale(12) > 12) {
        for (final action in actions) {
          for (final word in action.label.split(' ')) {
            final painter = TextPainter(
              text: TextSpan(
                text: word,
                style: DefaultTextStyle.of(context).style.merge(labelStyle),
              ),
              textScaler: scaler,
              textDirection: Directionality.of(context),
            )..layout();
            final wordWidth = painter.width.ceilToDouble() + 20;
            if (wordWidth > minimumWidth) {
              minimumWidth = wordWidth;
            }
            painter.dispose();
          }
        }
      }
      final fittedWidth =
          (constraints.maxWidth - gap * (visibleCards - 1)) / visibleCards;
      final width = fittedWidth < minimumWidth ? minimumWidth : fittedWidth;
      final labelHeight = scaler.scale(12) * 1.25 * 2;
      final height = labelHeight + 58;
      return SingleChildScrollView(
        key: const Key('tenant-quick-actions-row'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              if (index > 0) const SizedBox(width: gap),
              Semantics(
                button: true,
                enabled: actions[index].onTap != null,
                label: actions[index].label,
                onTap: actions[index].onTap,
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Card(
                      key: ValueKey('tenant-quick-action-$index'),
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      color: AppPalette.white,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppPalette.outline),
                      ),
                      child: InkWell(
                        onTap: actions[index].onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: AppPalette.softCream,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  actions[index].icon,
                                  color: AppPalette.olive,
                                  size: 19,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: labelHeight,
                                child: Center(
                                  child: Text(
                                    actions[index].label,
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    style: labelStyle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.item,
    required this.service,
    required this.onTap,
  });
  final TenantRecommendation item;
  final PropertyApiService service;
  final VoidCallback onTap;

  static TextSpan rentSpan(TenantRecommendation item) => TextSpan(
    text: 'Rs. ${dashboardMoney(item.property.monthlyRent)}',
    style: _style(16, FontWeight.w700, color: AppPalette.olive),
    children: [
      TextSpan(
        text: '/mo',
        style: _style(13, FontWeight.w500, color: AppPalette.secondaryText),
      ),
    ],
  );

  static String facts(TenantRecommendation item) =>
      '${item.property.bedrooms == 0 ? 'Studio' : '${item.property.bedrooms} BD'} \u00b7 ${item.property.bathrooms} BA';

  static double heightFor(
    BuildContext context,
    TenantRecommendation item,
    double width,
  ) {
    final contentWidth = width - 28;
    return 142 +
        28 +
        24 +
        _measuredHeight(
          context,
          TextSpan(
            text: item.property.title,
            style: _style(16, FontWeight.w700, height: 1.2),
          ),
          contentWidth,
          maxLines: 2,
        ) +
        _measuredHeight(
          context,
          TextSpan(
            text: item.property.city,
            style: _style(13, FontWeight.w400),
          ),
          contentWidth,
          maxLines: 1,
        ) +
        _measuredHeight(context, rentSpan(item), contentWidth) +
        _measuredHeight(
          context,
          TextSpan(text: facts(item), style: _style(12, FontWeight.w500)),
          contentWidth,
        );
  }

  @override
  Widget build(BuildContext context) {
    final property = item.property;
    final score = item.match.matchScore;
    return Semantics(
      button: true,
      label: 'View ${property.title}',
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              child: SizedBox(
                height: 142,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PropertyPhoto(
                      propertyId: property.id,
                      propertyApiService: service,
                    ),
                    if (score != null && score >= 0 && score <= 100)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.sage,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '$score% match',
                            style: _style(
                              11,
                              FontWeight.w700,
                              color: AppPalette.darkOlive,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _style(16, FontWeight.w700, height: 1.2),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      property.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style(
                        13,
                        FontWeight.w400,
                        color: AppPalette.secondaryText,
                      ),
                    ),
                    const Spacer(),
                    Text.rich(rentSpan(item)),
                    const SizedBox(height: 5),
                    Text(
                      facts(item),
                      style: _style(
                        12,
                        FontWeight.w500,
                        color: AppPalette.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, required this.now, this.onTap});
  final TenantActivity activity;
  final DateTime now;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final local = activity.timestamp.toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    final today = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final timestamp =
        local.year == today.year &&
            local.month == today.month &&
            local.day == today.day
        ? 'Today'
        : dashboardDate(local);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppPalette.sage,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(activity.icon, size: 20, color: AppPalette.olive),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(activity.title, style: _style(15, FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    activity.subtitle,
                    style: _style(
                      13,
                      FontWeight.w400,
                      color: AppPalette.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    timestamp,
                    style: _style(
                      12,
                      FontWeight.w500,
                      color: AppPalette.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppPalette.secondaryText,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _firstName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'there';
  return trimmed.split(RegExp(r'\s+')).first;
}

String _greetingForHour(int hour) {
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  if (hour >= 17 && hour < 21) return 'Good evening';
  return 'Good night';
}

String _formatHeaderDate(DateTime value) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[value.weekday - 1]}, ${value.day} ${months[value.month - 1]}';
}
