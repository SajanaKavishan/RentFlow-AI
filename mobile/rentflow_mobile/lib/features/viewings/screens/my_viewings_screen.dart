import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/viewing.dart';
import '../services/viewing_api_service.dart';
import '../widgets/viewing_status_chip.dart';

class MyViewingsScreen extends StatefulWidget {
  const MyViewingsScreen({super.key, this.viewingApiService});

  final ViewingApiService? viewingApiService;

  @override
  State<MyViewingsScreen> createState() => _MyViewingsScreenState();
}

class _MyViewingsScreenState extends State<MyViewingsScreen> {
  ApiClient? _ownedApiClient;
  late final ViewingApiService _viewingApiService;
  late Future<List<Viewing>> _viewings;
  final Set<String> _cancellingIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.viewingApiService case final service?) {
      _viewingApiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _viewingApiService = ViewingApiService(_ownedApiClient!);
    }
    _viewings = _viewingApiService.getMyViewings();
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = _viewingApiService.getMyViewings();
    setState(() {
      _viewings = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder presents the safe error state for this same request.
    }
  }

  bool _canCancel(Viewing viewing) {
    return viewing.status == ViewingStatus.pending ||
        viewing.status == ViewingStatus.approved;
  }

  Future<void> _confirmCancellation(Viewing viewing) async {
    if (_cancellingIds.contains(viewing.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.event_busy_outlined),
        title: const Text('Cancel this viewing?'),
        content: const Text(
          'The viewing request will be cancelled and cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep viewing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.danger),
            child: const Text('Cancel viewing'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancellingIds.add(viewing.id));
    late final Viewing cancelledViewing;
    try {
      cancelledViewing = await _viewingApiService.cancelViewing(id: viewing.id);
    } on ViewingApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
      return;
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to cancel the viewing right now. Please try again.',
          isError: true,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(viewing.id));
    }

    if (!mounted) return;
    final confirmedViewings = _viewings.then(
      (viewings) => viewings
          .map((item) => item.id == viewing.id ? cancelledViewing : item)
          .toList(growable: false),
    );
    setState(() {
      _viewings = confirmedViewings;
    });
    _showMessage('Viewing cancelled.');
    await _refreshAfterCancellation(confirmedViewings);
  }

  Future<void> _refreshAfterCancellation(
    Future<List<Viewing>> confirmedViewings,
  ) async {
    try {
      final refreshed = await _viewingApiService.getMyViewings();
      if (mounted) {
        setState(() {
          _viewings = Future.value(refreshed);
        });
      }
    } catch (_) {
      // Cancellation already succeeded. Keep the API-confirmed response instead
      // of reporting the refresh failure as a cancellation failure.
      if (mounted) {
        setState(() {
          _viewings = confirmedViewings;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    AppSnackbars.show(
      context,
      message: message,
      tone: isError ? SnackTone.error : SnackTone.success,
    );
  }

  String _safeErrorMessage(Object? error) {
    if (error is ViewingApiException) return error.message;
    return 'Unable to load your viewings. Please try again.';
  }

  List<Viewing> _pendingFirst(List<Viewing> viewings) {
    final indexed = viewings.asMap().entries.toList(growable: false);
    indexed.sort((left, right) {
      final leftRank = left.value.status == ViewingStatus.pending ? 0 : 1;
      final rightRank = right.value.status == ViewingStatus.pending ? 0 : 1;
      final statusOrder = leftRank.compareTo(rightRank);
      return statusOrder != 0 ? statusOrder : left.key.compareTo(right.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(
      title: const Text('My Viewings'),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    ),
    body: SafeArea(
      top: false,
      child: FutureBuilder<List<Viewing>>(
        future: _viewings,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingState(
              title: 'Loading your viewings',
              message: 'Getting your latest viewing schedule.',
            );
          }

          if (snapshot.hasError) {
            return _MessageState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load viewings',
              message: _safeErrorMessage(snapshot.error),
              actionLabel: 'Try again',
              onAction: _refresh,
              isError: true,
            );
          }

          final viewings = _pendingFirst(snapshot.data ?? const <Viewing>[]);
          if (viewings.isEmpty) {
            return _MessageState(
              icon: Icons.event_available_outlined,
              title: 'No viewings yet',
              message:
                  'When you request a property viewing, its schedule and status will appear here.',
              actionLabel: 'Refresh',
              onAction: _refresh,
            );
          }

          return RefreshIndicator(
            color: AppPalette.olive,
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                20,
                AppSpacing.lg,
                20,
                AppSpacing.xl,
              ),
              itemCount: viewings.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.base),
                    child: _ListHeader(count: viewings.length),
                  );
                }

                final viewing = viewings[index - 1];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == viewings.length ? 0 : AppSpacing.md,
                  ),
                  child: _ViewingCard(
                    viewing: viewing,
                    canCancel: _canCancel(viewing),
                    isCancelling: _cancellingIds.contains(viewing.id),
                    onCancel: () => _confirmCancellation(viewing),
                  ),
                );
              },
            ),
          );
        },
      ),
    ),
  );
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => SectionHeader(
    title: 'Viewing schedule',
    subtitle: 'Pending requests appear first. Pull down for updates.',
    trailing: StatusChip(
      label: '$count ${count == 1 ? 'viewing' : 'viewings'}',
      tone: StatusTone.neutral,
    ),
  );
}

class _ViewingCard extends StatelessWidget {
  const _ViewingCard({
    required this.viewing,
    required this.canCancel,
    required this.isCancelling,
    required this.onCancel,
  });

  final Viewing viewing;
  final bool canCancel;
  final bool isCancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final scheduled = viewing.requestedLocalDate == null
        ? viewing.requestedDateTime.toLocal()
        : DateTime.parse(viewing.requestedLocalDate!);
    final date = localizations.formatFullDate(scheduled);
    final time = viewing.requestedDisplayTime == null
        ? localizations.formatTimeOfDay(TimeOfDay.fromDateTime(scheduled))
        : '${viewing.requestedDisplayTime} (${viewing.timeZoneId})';

    return AppCard(
      key: ValueKey('viewing-card-${viewing.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppPalette.sage,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                child: const Icon(
                  Icons.home_work_outlined,
                  color: AppPalette.darkOlive,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROPERTY VIEWING',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.muted,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Property reference',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      viewing.propertyId,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ViewingStatusChip(status: viewing.status),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            children: [
              Expanded(
                child: _InformationPanel(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  value: date,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _InformationPanel(
                  icon: Icons.schedule_outlined,
                  label: 'Time',
                  value: time,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          _DetailBlock(
            label: 'Your message',
            value: _hasText(viewing.tenantMessage)
                ? viewing.tenantMessage!.trim()
                : 'No message provided.',
          ),
          const SizedBox(height: AppSpacing.md),
          _DetailBlock(
            label: 'Landlord response',
            value: _hasText(viewing.landlordResponse)
                ? viewing.landlordResponse!.trim()
                : 'No response yet.',
            highlighted: _hasText(viewing.landlordResponse),
          ),
          const SizedBox(height: AppSpacing.base),
          _ViewingTimeline(viewing: viewing),
          if (canCancel) ...[
            const SizedBox(height: AppSpacing.base),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: isCancelling ? null : onCancel,
                icon: isCancelling
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.danger,
                        ),
                      )
                    : const Icon(Icons.event_busy_outlined),
                label: Text(isCancelling ? 'Cancelling...' : 'Cancel viewing'),
                style: TextButton.styleFrom(foregroundColor: AppPalette.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}

class _InformationPanel extends StatelessWidget {
  const _InformationPanel({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 86),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppPalette.softCream,
      borderRadius: BorderRadius.circular(AppRadii.medium),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppPalette.olive),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppPalette.text,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: highlighted ? AppPalette.sage : AppPalette.softCream,
      borderRadius: BorderRadius.circular(AppRadii.medium),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: AppPalette.darkOlive),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _ViewingTimeline extends StatelessWidget {
  const _ViewingTimeline({required this.viewing});

  final Viewing viewing;

  @override
  Widget build(BuildContext context) {
    final created = _formatDateTime(context, viewing.createdAt);
    final updated = viewing.updatedAt == null
        ? null
        : _formatDateTime(context, viewing.updatedAt!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppPalette.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TimelineRow(label: 'Requested', value: created),
          if (updated != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _TimelineRow(label: 'Last updated', value: updated),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(local)} at '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.history, size: 17, color: AppPalette.olive),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: value),
            ],
          ),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
        ),
      ),
    ],
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AppCard(
          key: ValueKey(isError ? 'viewings-error' : 'viewings-empty'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SharedState(
            title: title,
            message: message,
            icon: icon,
            actionLabel: actionLabel,
            onAction: onAction,
            compact: true,
          ),
        ),
      ),
    ),
  );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      key: const ValueKey('viewings-loading'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LoadingState(title: title, message: message, compact: true),
    ),
  );
}
