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
    this.unreadNotificationCount,
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
  final int? unreadNotificationCount;
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TenantHomeHeader(
              date: _formatHeaderDate(now),
              greeting: _greetingForHour(now.hour),
              firstName: _firstName(widget.user.fullName),
              unreadNotificationCount: widget.unreadNotificationCount,
              onOpenNotifications: widget.onOpenNotifications,
            ),
            const SizedBox(height: 18),
            _buildJourney(),
            const SizedBox(height: 22),
            const _TenantSectionHeader(title: 'What would you like to do?'),
            const SizedBox(height: 10),
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
      _DarkJourneyCard(onTap: onTap, child: child);

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
        child: const _JourneyMessage(
          status: 'Integration pending',
          title: 'Journey summary unavailable',
          message:
              'Property selection has not been integrated yet. Home activity is not connected.',
        ),
      );
    }

    return FutureBuilder<_TenantHomeSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _journeyCard(
            child: const _JourneyMessage(
              status: 'Checking activity',
              title: 'Loading your journey',
              message: 'Checking your real viewing and application activity.',
              isLoading: true,
            ),
          );
        }
        if (snapshot.hasError) {
          return _journeyCard(
            child: _JourneyMessage(
              status: 'Unable to load',
              title: 'Journey unavailable',
              message: 'Nothing has been changed. Please try again.',
              onRetry: _retry,
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
        final activities = snapshot.data!.activity;
        final visibleActivities = activities.take(3).toList(growable: false);
        return Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TenantSectionHeader(
                title: 'Recent activity',
                trailing: activities.length > 3
                    ? TextButton(
                        onPressed: () => _showAllActivities(activities),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          foregroundColor: AppPalette.olive,
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('See all'),
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              Column(
                key: const Key('tenant-home-activity-list'),
                children: [
                  for (var index = 0; index < visibleActivities.length; index++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: index < visibleActivities.length - 1 ? 8 : 0,
                      ),
                      child: AppCard(
                        key: ValueKey('tenant-home-activity-$index'),
                        padding: EdgeInsets.zero,
                        child: _ActivityTile(
                          activity: visibleActivities[index],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAllActivities(List<_TenantActivity> activities) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.warmCream,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              key: const Key('tenant-all-activity-sheet'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _TenantSectionHeader(title: 'All recent activity'),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: activities.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => AppCard(
                      key: ValueKey('tenant-all-activity-$index'),
                      padding: EdgeInsets.zero,
                      child: _ActivityTile(activity: activities[index]),
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

class _DarkJourneyCard extends StatelessWidget {
  const _DarkJourneyCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: const EdgeInsets.all(16), child: child);
    return Container(
      key: const Key('tenant-journey-card'),
      decoration: BoxDecoration(
        color: AppPalette.darkOlive,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppPalette.darkOlive.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class _JourneyMessage extends StatelessWidget {
  const _JourneyMessage({
    required this.status,
    required this.title,
    required this.message,
    this.isLoading = false,
    this.onRetry,
  });

  final String status;
  final String title;
  final String message;
  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _JourneyStatusPill(
                label: status,
                tone: StatusTone.neutral,
              ),
            ),
          ),
          if (isLoading)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppPalette.sage,
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppPalette.white,
          fontSize: 16,
          height: 1.18,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppPalette.sage, height: 1.35),
      ),
      if (onRetry != null) ...[
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            foregroundColor: AppPalette.sage,
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Try again'),
        ),
      ],
    ],
  );
}

class _TenantSectionHeader extends StatelessWidget {
  const _TenantSectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppPalette.primaryText,
            fontSize: 16,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (trailing != null) ...[
        const SizedBox(width: AppSpacing.sm),
        trailing!,
      ],
    ],
  );
}

class _TenantHomeHeader extends StatelessWidget {
  const _TenantHomeHeader({
    required this.date,
    required this.greeting,
    required this.firstName,
    required this.onOpenNotifications,
    this.unreadNotificationCount,
  });

  final String date;
  final String greeting;
  final String firstName;
  final VoidCallback onOpenNotifications;
  final int? unreadNotificationCount;

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
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$greeting, $firstName',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppPalette.darkOlive,
                fontSize: 26,
                height: 1.04,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
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
        child: Badge(
          isLabelVisible: unreadNotificationCount != null,
          label: Text(
            unreadNotificationCount != null && unreadNotificationCount! > 99
                ? '99+'
                : '${unreadNotificationCount ?? ''}',
          ),
          child: IconButton(
            tooltip: 'Notifications',
            onPressed: onOpenNotifications,
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: AppPalette.darkOlive,
            ),
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
        title: switch (application.status) {
          RentalApplicationStatus.draft => 'Your application is in draft',
          RentalApplicationStatus.submitted => 'Your application is submitted',
          RentalApplicationStatus.underReview =>
            'Your application is being reviewed',
          RentalApplicationStatus.changesRequested =>
            'Your application needs changes',
          RentalApplicationStatus.approved => 'Your application is approved',
          _ => 'Rental application',
        },
        reference: 'Property reference: ${application.propertyId}',
        progress:
            'Move-in requested for ${_formatDate(application.moveInDate)}',
      );
    }

    final viewing = snapshot.currentViewing;
    if (viewing != null) {
      final status = _viewingStatus(viewing.status);
      return _ActiveJourney(
        statusLabel: status.$1,
        tone: status.$2,
        title: viewing.status == ViewingStatus.approved
            ? 'Your viewing is approved'
            : 'Your viewing is awaiting approval',
        reference: 'Property reference: ${viewing.propertyId}',
        progress: 'Requested for ${_formatDateTime(viewing.requestedDateTime)}',
      );
    }

    return const _JourneyMessage(
      status: 'No activity yet',
      title: 'No rental journey yet',
      message:
          'Real viewing or application progress will appear here once available.',
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
  });

  final String statusLabel;
  final StatusTone tone;
  final String title;
  final String reference;
  final String progress;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _JourneyStatusPill(label: statusLabel, tone: tone),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppPalette.sage.withValues(alpha: 0.72),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppPalette.white,
          fontSize: 16,
          height: 1.18,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        reference,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppPalette.sage, height: 1.3),
      ),
      const SizedBox(height: 14),
      // A status accent, not a percentage: the API does not report progress.
      ExcludeSemantics(
        child: Container(
          height: 3,
          decoration: BoxDecoration(
            color: AppPalette.sage.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
        ),
      ),
      const SizedBox(height: 9),
      Text(
        progress,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppPalette.sage,
          fontSize: 11,
          height: 1.3,
        ),
      ),
    ],
  );
}

class _JourneyStatusPill extends StatelessWidget {
  const _JourneyStatusPill({required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final background = switch (tone) {
      StatusTone.progress || StatusTone.success => AppPalette.sage,
      _ => AppPalette.softCream,
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
          color: AppPalette.darkOlive,
          fontSize: 9,
          height: 1.2,
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
                onTap: action.onTap,
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: width,
                    child: AppCard(
                      padding: const EdgeInsets.all(13),
                      onTap: action.onTap,
                      child: SizedBox(
                        height:
                            44 +
                            (MediaQuery.textScalerOf(context).scale(13) * 1.25)
                                    .ceilToDouble() *
                                2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppPalette.softCream,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                action.icon,
                                size: 19,
                                color: AppPalette.olive,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    action.label,
                                    maxLines: 2,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: AppPalette.primaryText,
                                          fontSize: 13,
                                          height: 1.25,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: AppPalette.secondaryText,
                                ),
                              ],
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
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppPalette.sage,
            shape: BoxShape.circle,
          ),
          child: Icon(activity.icon, size: 17, color: AppPalette.olive),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activity.title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppPalette.primaryText,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                activity.statusLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppPalette.secondaryText,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          fit: FlexFit.tight,
          child: Text(
            _formatDate(activity.occurredAt),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.secondaryText,
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ),
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
    return items;
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
