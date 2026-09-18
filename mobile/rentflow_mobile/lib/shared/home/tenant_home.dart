import 'package:flutter/material.dart';

import '../../features/auth/models/current_user.dart';
import '../../features/rental_applications/models/rental_application.dart';
import '../../features/rental_applications/services/rental_application_api_service.dart';
import '../../features/viewings/models/viewing.dart';
import '../../features/viewings/services/viewing_api_service.dart';
import '../navigation/role_navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class TenantHome extends StatefulWidget {
  const TenantHome({
    super.key,
    required this.user,
    required this.onDestinationSelected,
    required this.onOpenViewings,
    required this.onOpenLease,
    required this.onPayRent,
    required this.onOpenDocuments,
    required this.onOpenNotifications,
    this.viewingApiService,
    this.rentalApplicationApiService,
    this.now,
  });

  final CurrentUser user;
  final ValueChanged<RoleDestinationId> onDestinationSelected;
  final VoidCallback onOpenViewings;
  final VoidCallback onOpenLease;
  final VoidCallback onPayRent;
  final VoidCallback onOpenDocuments;
  final VoidCallback onOpenNotifications;
  final ViewingApiService? viewingApiService;
  final RentalApplicationApiService? rentalApplicationApiService;
  final DateTime Function()? now;

  @override
  State<TenantHome> createState() => _TenantHomeState();
}

class _TenantHomeState extends State<TenantHome> {
  Future<_TenantHomeSnapshot>? _snapshot;

  bool get _hasActivityIntegration =>
      widget.viewingApiService != null &&
      widget.rentalApplicationApiService != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TenantHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewingApiService != widget.viewingApiService ||
        oldWidget.rentalApplicationApiService !=
            widget.rentalApplicationApiService) {
      _load();
    }
  }

  void _load() {
    if (!_hasActivityIntegration) {
      _snapshot = null;
      return;
    }
    _snapshot = _fetchSnapshot();
  }

  Future<_TenantHomeSnapshot> _fetchSnapshot() async {
    final results = await Future.wait<Object>([
      widget.viewingApiService!.getMyViewings(),
      widget.rentalApplicationApiService!.getMyApplications(),
    ]);
    return _TenantHomeSnapshot(
      viewings: results[0] as List<Viewing>,
      applications: results[1] as List<RentalApplication>,
    );
  }

  void _retry() => setState(_load);

  @override
  Widget build(BuildContext context) {
    final now = (widget.now?.call() ?? DateTime.now()).toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    return SafeArea(
      bottom: false,
      child: AuthenticatedPage(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TenantHomeHeader(
              date: _formatHeaderDate(now),
              greeting: _greetingForHour(now.hour),
              firstName: _firstName(widget.user.fullName),
              onOpenNotifications: widget.onOpenNotifications,
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Your rental journey'),
            const SizedBox(height: AppSpacing.md),
            _buildJourney(),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Quick actions'),
            const SizedBox(height: AppSpacing.md),
            _QuickActionGrid(
              onOpenViewings: widget.onOpenViewings,
              onOpenLease: widget.onOpenLease,
              onPayRent: widget.onPayRent,
              onOpenDocuments: widget.onOpenDocuments,
            ),
            _buildRecentActivity(),
          ],
        ),
      ),
    );
  }

  Widget _journeyCard({required Widget child, VoidCallback? onTap}) =>
      AppCard(padding: const EdgeInsets.all(18), onTap: onTap, child: child);

  VoidCallback? _journeyAction(_TenantHomeSnapshot snapshot) {
    if (snapshot.currentApplication != null) {
      return () => widget.onDestinationSelected(RoleDestinationId.applications);
    }
    if (snapshot.currentViewing != null) {
      return () => widget.onDestinationSelected(RoleDestinationId.viewings);
    }
    return null;
  }

  Widget _buildJourney() {
    if (!_hasActivityIntegration) {
      return _journeyCard(
        child: const IntegrationPendingState(
          title: 'Journey summary unavailable',
          message:
              'Property selection has not been integrated yet. Your authenticated session is active, but Home activity is not connected in this app context.',
          compact: true,
        ),
      );
    }

    return FutureBuilder<_TenantHomeSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _journeyCard(
            child: const LoadingState(
              title: 'Loading your journey',
              message: 'Checking your real viewing and application activity.',
              compact: true,
            ),
          );
        }
        if (snapshot.hasError) {
          return _journeyCard(
            child: ErrorState(
              message:
                  'We could not load your journey. Nothing has been changed.',
              onRetry: _retry,
              compact: true,
            ),
          );
        }
        final data = snapshot.data!;
        return _journeyCard(
          onTap: _journeyAction(data),
          child: _JourneySummary(snapshot: data),
        );
      },
    );
  }

  Widget _buildRecentActivity() {
    if (!_hasActivityIntegration) return const SizedBox.shrink();
    return FutureBuilder<_TenantHomeSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.activity.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Recent activity'),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < snapshot.data!.activity.length;
                      index++
                    ) ...[
                      _ActivityTile(activity: snapshot.data!.activity[index]),
                      if (index < snapshot.data!.activity.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TenantHomeHeader extends StatelessWidget {
  const _TenantHomeHeader({
    required this.date,
    required this.greeting,
    required this.firstName,
    required this.onOpenNotifications,
  });

  final String date;
  final String greeting;
  final String firstName;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              date.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.olive,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.35,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$greeting,\n$firstName',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppPalette.darkOlive,
                fontSize: 32,
                height: 1.08,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.7,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      Material(
        color: AppPalette.white,
        shape: const CircleBorder(side: BorderSide(color: AppPalette.outline)),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: 'Notifications',
          onPressed: onOpenNotifications,
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: AppPalette.darkOlive,
          ),
        ),
      ),
    ],
  );
}

class _JourneySummary extends StatelessWidget {
  const _JourneySummary({required this.snapshot});

  final _TenantHomeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final application = snapshot.currentApplication;
    if (application != null) {
      final status = _applicationStatus(application.status);
      return _ActiveJourney(
        statusLabel: status.$1,
        tone: status.$2,
        title: 'Rental application',
        reference: 'Property reference: ${application.propertyId}',
        progress:
            'Move-in requested for ${_formatDate(application.moveInDate)}',
        progressIcon: Icons.event_available_outlined,
      );
    }

    final viewing = snapshot.currentViewing;
    if (viewing != null) {
      final status = _viewingStatus(viewing.status);
      return _ActiveJourney(
        statusLabel: status.$1,
        tone: status.$2,
        title: 'Property viewing',
        reference: 'Property reference: ${viewing.propertyId}',
        progress: 'Requested for ${_formatDateTime(viewing.requestedDateTime)}',
        progressIcon: Icons.schedule_outlined,
      );
    }

    return const EmptyState(
      title: 'No rental journey yet',
      message:
          'Real viewing or application progress will appear here once available.',
      compact: true,
    );
  }
}

class _ActiveJourney extends StatelessWidget {
  const _ActiveJourney({
    required this.statusLabel,
    required this.tone,
    required this.title,
    required this.reference,
    required this.progress,
    required this.progressIcon,
  });

  final String statusLabel;
  final StatusTone tone;
  final String title;
  final String reference;
  final String progress;
  final IconData progressIcon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _JourneyStatusPill(label: statusLabel, tone: tone),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              reference,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(progressIcon, size: 16, color: AppPalette.olive),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    progress,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.primaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      const Icon(Icons.chevron_right_rounded, color: AppPalette.olive),
    ],
  );
}

class _JourneyStatusPill extends StatelessWidget {
  const _JourneyStatusPill({required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = switch (tone) {
      StatusTone.neutral => (AppPalette.neutral, AppPalette.softCream),
      StatusTone.pending ||
      StatusTone.warning => (AppPalette.warning, AppPalette.pending),
      StatusTone.progress => (const Color(0xFF43556A), AppPalette.progress),
      StatusTone.success => (AppPalette.success, AppPalette.sage),
      StatusTone.danger => (AppPalette.danger, const Color(0xFFF5DDDC)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({
    required this.onOpenViewings,
    required this.onOpenLease,
    required this.onPayRent,
    required this.onOpenDocuments,
  });

  final VoidCallback onOpenViewings;
  final VoidCallback onOpenLease;
  final VoidCallback onPayRent;
  final VoidCallback onOpenDocuments;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(
        label: 'My Viewings',
        icon: Icons.calendar_month_outlined,
        onTap: onOpenViewings,
      ),
      _QuickAction(
        label: 'My Lease',
        icon: Icons.article_outlined,
        onTap: onOpenLease,
      ),
      _QuickAction(
        label: 'Pay Rent',
        icon: Icons.credit_card_outlined,
        onTap: onPayRent,
      ),
      _QuickAction(
        label: 'Documents',
        icon: Icons.folder_outlined,
        onTap: onOpenDocuments,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              Semantics(
                button: true,
                label: action.label,
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: width,
                    child: AppCard(
                      onTap: action.onTap,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 92),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(action.icon, color: AppPalette.olive),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              action.label,
                              maxLines: 2,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: AppPalette.primaryText),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final _TenantActivity activity;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.base),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: AppPalette.softCream,
            shape: BoxShape.circle,
          ),
          child: Icon(activity.icon, size: 20, color: AppPalette.olive),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activity.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _formatDate(activity.occurredAt),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        StatusChip(label: activity.statusLabel, tone: activity.tone),
      ],
    ),
  );
}

class _TenantHomeSnapshot {
  _TenantHomeSnapshot({
    required List<Viewing> viewings,
    required List<RentalApplication> applications,
  }) : viewings = List.unmodifiable(viewings),
       applications = List.unmodifiable(applications);

  final List<Viewing> viewings;
  final List<RentalApplication> applications;

  RentalApplication? get currentApplication {
    final active = applications.where(
      (application) =>
          application.status != RentalApplicationStatus.rejected &&
          application.status != RentalApplicationStatus.withdrawn,
    );
    return _latestApplication(active);
  }

  Viewing? get currentViewing {
    final active = viewings.where(
      (viewing) =>
          viewing.status == ViewingStatus.pending ||
          viewing.status == ViewingStatus.approved,
    );
    return _latestViewing(active);
  }

  List<_TenantActivity> get activity {
    final items = <_TenantActivity>[
      ...applications.map((application) {
        final status = _applicationStatus(application.status);
        return _TenantActivity(
          title: 'Application updated',
          occurredAt: application.updatedAt ?? application.createdAt,
          statusLabel: status.$1,
          tone: status.$2,
          icon: Icons.description_outlined,
        );
      }),
      ...viewings.map((viewing) {
        final status = _viewingStatus(viewing.status);
        return _TenantActivity(
          title: 'Viewing updated',
          occurredAt: viewing.updatedAt ?? viewing.createdAt,
          statusLabel: status.$1,
          tone: status.$2,
          icon: Icons.calendar_month_outlined,
        );
      }),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items.take(3).toList(growable: false);
  }

  RentalApplication? _latestApplication(Iterable<RentalApplication> values) {
    RentalApplication? latest;
    for (final value in values) {
      if (latest == null ||
          (value.updatedAt ?? value.createdAt).isAfter(
            latest.updatedAt ?? latest.createdAt,
          )) {
        latest = value;
      }
    }
    return latest;
  }

  Viewing? _latestViewing(Iterable<Viewing> values) {
    Viewing? latest;
    for (final value in values) {
      if (latest == null ||
          (value.updatedAt ?? value.createdAt).isAfter(
            latest.updatedAt ?? latest.createdAt,
          )) {
        latest = value;
      }
    }
    return latest;
  }
}

class _TenantActivity {
  const _TenantActivity({
    required this.title,
    required this.occurredAt,
    required this.statusLabel,
    required this.tone,
    required this.icon,
  });

  final String title;
  final DateTime occurredAt;
  final String statusLabel;
  final StatusTone tone;
  final IconData icon;
}

(String, StatusTone) _applicationStatus(RentalApplicationStatus status) =>
    switch (status) {
      RentalApplicationStatus.draft => ('Draft', StatusTone.neutral),
      RentalApplicationStatus.submitted => ('Submitted', StatusTone.pending),
      RentalApplicationStatus.underReview => (
        'Under review',
        StatusTone.progress,
      ),
      RentalApplicationStatus.changesRequested => (
        'Changes requested',
        StatusTone.warning,
      ),
      RentalApplicationStatus.approved => ('Approved', StatusTone.success),
      RentalApplicationStatus.rejected => ('Rejected', StatusTone.danger),
      RentalApplicationStatus.withdrawn => ('Withdrawn', StatusTone.neutral),
    };

(String, StatusTone) _viewingStatus(ViewingStatus status) => switch (status) {
  ViewingStatus.pending => ('Pending', StatusTone.pending),
  ViewingStatus.approved => ('Approved', StatusTone.success),
  ViewingStatus.rejected => ('Rejected', StatusTone.danger),
  ViewingStatus.cancelled => ('Cancelled', StatusTone.neutral),
  ViewingStatus.completed => ('Completed', StatusTone.success),
};

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

String _formatDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = value.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0
      ? 12
      : (local.hour > 12 ? local.hour - 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${_formatDate(local)} at $hour:$minute $period';
}
