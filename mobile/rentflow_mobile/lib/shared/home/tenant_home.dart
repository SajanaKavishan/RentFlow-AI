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
    required this.onOpenDocuments,
    this.viewingApiService,
    this.rentalApplicationApiService,
  });

  final CurrentUser user;
  final ValueChanged<RoleDestinationId> onDestinationSelected;
  final VoidCallback onOpenDocuments;
  final ViewingApiService? viewingApiService;
  final RentalApplicationApiService? rentalApplicationApiService;

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
  Widget build(BuildContext context) => AuthenticatedPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          eyebrow: 'Tenant home',
          title: 'Hello, ${_firstName(widget.user.fullName)}',
          subtitle: 'Your viewings, applications, and documents in one place.',
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(
          title: 'Your rental journey',
          subtitle: 'Live progress from your RentFlow activity.',
        ),
        const SizedBox(height: AppSpacing.md),
        _buildJourney(),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: 'Quick actions'),
        const SizedBox(height: AppSpacing.md),
        _QuickActionGrid(
          onSelected: widget.onDestinationSelected,
          onOpenDocuments: widget.onOpenDocuments,
        ),
        _buildRecentActivity(),
        const SizedBox(height: AppSpacing.lg),
        const _AiAssistanceCard(),
      ],
    ),
  );

  Widget _buildJourney() {
    if (!_hasActivityIntegration) {
      return const AppCard(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: IntegrationPendingState(
          title: 'Journey summary unavailable',
          message:
              'Property selection has not been integrated yet. Your authenticated session is active, but Home activity is not connected in this app context.',
          compact: true,
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: FutureBuilder<_TenantHomeSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState(
              title: 'Loading your journey',
              message: 'Checking your real viewing and application activity.',
              compact: true,
            );
          }
          if (snapshot.hasError) {
            return ErrorState(
              message:
                  'We could not load your journey. Nothing has been changed.',
              onRetry: _retry,
              compact: true,
            );
          }
          final data = snapshot.data!;
          return _JourneySummary(snapshot: data);
        },
      ),
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

class _JourneySummary extends StatelessWidget {
  const _JourneySummary({required this.snapshot});

  final _TenantHomeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final application = snapshot.currentApplication;
    if (application != null) {
      final status = _applicationStatus(application.status);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _JourneyIcon(icon: Icons.description_outlined),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rental application',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    StatusChip(label: status.$1, tone: status.$2),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Requested move-in: ${_formatDate(application.moveInDate)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }

    final viewing = snapshot.currentViewing;
    if (viewing != null) {
      final status = _viewingStatus(viewing.status);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _JourneyIcon(icon: Icons.calendar_month_outlined),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Property viewing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                StatusChip(label: status.$1, tone: status.$2),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _formatDateTime(viewing.requestedDateTime),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
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

class _JourneyIcon extends StatelessWidget {
  const _JourneyIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: AppPalette.sage,
      borderRadius: BorderRadius.circular(AppRadii.medium),
    ),
    child: Icon(icon, color: AppPalette.darkOlive),
  );
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({
    required this.onSelected,
    required this.onOpenDocuments,
  });

  final ValueChanged<RoleDestinationId> onSelected;
  final VoidCallback onOpenDocuments;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(
        label: 'Properties',
        icon: Icons.home_work_outlined,
        onTap: () => onSelected(RoleDestinationId.properties),
      ),
      _QuickAction(
        label: 'My Viewings',
        icon: Icons.calendar_month_outlined,
        onTap: () => onSelected(RoleDestinationId.viewings),
      ),
      _QuickAction(
        label: 'My Applications',
        icon: Icons.description_outlined,
        onTap: () => onSelected(RoleDestinationId.applications),
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
              SizedBox(
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

class _AiAssistanceCard extends StatelessWidget {
  const _AiAssistanceCard();

  @override
  Widget build(BuildContext context) => AppCard(
    color: AppPalette.darkOlive,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: AppPalette.sage,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.auto_awesome_outlined,
            color: AppPalette.darkOlive,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RentFlow AI',
                style: TextStyle(
                  color: AppPalette.sage,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'AI helps with the work. People stay in control.',
                style: TextStyle(
                  color: AppPalette.white,
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
