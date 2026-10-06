import 'package:flutter/material.dart';

import '../../features/auth/models/current_user.dart';
import '../../features/maintenance/models/maintenance_request.dart';
import '../../features/maintenance/services/maintenance_api_service.dart';
import '../../features/maintenance/widgets/tenant_maintenance_ui.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class TechnicianHome extends StatefulWidget {
  const TechnicianHome({
    super.key,
    required this.user,
    required this.onOpenJob,
    this.maintenanceApiService,
  });

  final CurrentUser user;
  final MaintenanceApiService? maintenanceApiService;
  final ValueChanged<MaintenanceRequest> onOpenJob;

  @override
  State<TechnicianHome> createState() => _TechnicianHomeState();
}

class _TechnicianHomeState extends State<TechnicianHome> {
  late Future<List<MaintenanceRequest>> _jobsFuture;

  @override
  void initState() {
    super.initState();
    _jobsFuture = _load();
  }

  Future<List<MaintenanceRequest>> _load() {
    final service = widget.maintenanceApiService;
    if (service == null) {
      return Future.error(
        const MaintenanceApiException('Assigned work is unavailable.'),
      );
    }
    return service.getAssignedWork(technicianId: widget.user.id);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _jobsFuture = next);
    await next;
  }

  void _retry() => setState(() => _jobsFuture = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MaintenanceRequest>>(
      future: _jobsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppPalette.olive),
          );
        }
        if (snapshot.hasError) {
          final message = snapshot.error is MaintenanceApiException
              ? (snapshot.error as MaintenanceApiException).message
              : 'Unable to load your technician workspace.';
          return AuthenticatedPage(
            child: SharedState(
              title: 'Could not load your jobs',
              message: message,
              icon: Icons.error_outline,
              actionLabel: 'Retry',
              onAction: _retry,
            ),
          );
        }

        final jobs = snapshot.data ?? const <MaintenanceRequest>[];
        final active = jobs.where(_isActiveTechnicianJob).toList()
          ..sort((a, b) => _jobTime(b).compareTo(_jobTime(a)));
        final inProgress = active
            .where((job) => job.status == MaintenanceRequestStatus.inProgress)
            .length;
        final now = DateTime.now();
        final startOfWeek = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - DateTime.monday));
        final completedThisWeek = jobs.where((job) {
          final completedAt = job.completedAt?.toLocal();
          return job.status == MaintenanceRequestStatus.completed &&
              completedAt != null &&
              !completedAt.isBefore(startOfWeek) &&
              !completedAt.isAfter(now);
        }).length;

        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppPalette.olive,
          child: ListView(
            key: const ValueKey('technician-home-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.page,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Welcome, ${widget.user.fullName.trim()}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'You have ${active.length} active ${active.length == 1 ? 'job' : 'jobs'}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppPalette.secondaryText,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              label: 'Active',
                              value: active.length,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _SummaryCard(
                              label: 'In progress',
                              value: inProgress,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _SummaryCard(
                              label: 'Completed this week',
                              value: completedThisWeek,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const SectionHeader(title: 'Active assigned jobs'),
                      const SizedBox(height: AppSpacing.md),
                      if (active.isEmpty)
                        const AppCard(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No active jobs right now. Pull down to refresh.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        ...active
                            .take(3)
                            .map(
                              (job) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: _ActiveJobCard(
                                  job: job,
                                  onOpen: () => widget.onOpenJob(job),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

bool _isActiveTechnicianJob(MaintenanceRequest job) =>
    job.status != MaintenanceRequestStatus.completed &&
    job.status != MaintenanceRequestStatus.rejected &&
    job.status != MaintenanceRequestStatus.cancelled;

DateTime _jobTime(MaintenanceRequest job) => job.updatedAt ?? job.createdAt;

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
    child: Column(
      children: [
        Text(
          '$value',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(color: AppPalette.darkOlive),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
  );
}

class _ActiveJobCard extends StatelessWidget {
  const _ActiveJobCard({required this.job, required this.onOpen});

  final MaintenanceRequest job;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          job.referenceCode ?? 'Reference unavailable',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.olive,
            fontWeight: FontWeight.w800,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 6),
        Text(job.title, style: Theme.of(context).textTheme.titleMedium),
        if (job.propertyTitle?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 5),
          Text(
            job.propertyTitle!.trim(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            MaintenanceBadge(label: maintenanceLabel(job.category)),
            MaintenanceBadge.priority(job.priority),
            MaintenanceBadge.status(job.status),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onOpen,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Open job'),
          ),
        ),
      ],
    ),
  );
}
