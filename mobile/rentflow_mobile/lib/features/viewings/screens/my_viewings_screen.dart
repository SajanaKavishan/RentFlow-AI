import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Cancel viewing'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancellingIds.add(viewing.id));
    try {
      await _viewingApiService.cancelViewing(id: viewing.id);
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
    final optimisticViewings = _viewings.then(
      (viewings) => viewings
          .map((item) => item.id == viewing.id ? _asCancelled(item) : item)
          .toList(growable: false),
    );
    setState(() {
      _viewings = optimisticViewings;
    });
    _showMessage('Viewing cancelled.');
    await _refreshAfterCancellation(optimisticViewings);
  }

  Future<void> _refreshAfterCancellation(
    Future<List<Viewing>> optimisticViewings,
  ) async {
    try {
      final refreshed = await _viewingApiService.getMyViewings();
      if (mounted) {
        setState(() {
          _viewings = Future.value(refreshed);
        });
      }
    } catch (_) {
      // Cancellation already succeeded. Keep the optimistic cancelled state
      // instead of reporting the refresh failure as a cancellation failure.
      if (mounted) {
        setState(() {
          _viewings = optimisticViewings;
        });
      }
    }
  }

  Viewing _asCancelled(Viewing viewing) {
    return Viewing(
      id: viewing.id,
      tenantId: viewing.tenantId,
      propertyId: viewing.propertyId,
      requestedDateTime: viewing.requestedDateTime,
      status: ViewingStatus.cancelled,
      tenantMessage: viewing.tenantMessage,
      landlordResponse: viewing.landlordResponse,
      createdAt: viewing.createdAt,
      updatedAt: viewing.updatedAt,
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppPalette.danger : AppPalette.primary,
        ),
      );
  }

  String _safeErrorMessage(Object? error) {
    if (error is ViewingApiException) return error.message;
    return 'Unable to load your viewings. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'My Viewings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
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

            final viewings = snapshot.data ?? const <Viewing>[];
            if (viewings.isEmpty) {
              return _MessageState(
                icon: Icons.event_available_outlined,
                title: 'No viewings yet',
                message:
                    'When you request a property viewing, its date, time, and status will appear here.',
                actionLabel: 'Refresh',
                onAction: _refresh,
              );
            }

            return RefreshIndicator(
              color: AppPalette.primary,
              onRefresh: _refresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  AppSpacing.lg,
                  AppSpacing.base,
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
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Viewing schedule',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppPalette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Pull down to check for updates.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          '$count ${count == 1 ? 'viewing' : 'viewings'}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppPalette.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
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
    final localDateTime = viewing.requestedDateTime.toLocal();
    final date = localizations.formatFullDate(localDateTime);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localDateTime),
    );

    return Card(
      key: ValueKey('viewing-card-${viewing.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFECEFDF),
                    borderRadius: BorderRadius.circular(AppRadii.small),
                  ),
                  child: const Icon(
                    Icons.calendar_month_outlined,
                    color: AppPalette.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VIEWING APPOINTMENT',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppPalette.muted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        date,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppPalette.text,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ViewingStatusChip(status: viewing.status),
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            _InformationRow(
              icon: Icons.schedule_outlined,
              label: 'Time',
              value: time,
              emphasized: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            _InformationRow(
              icon: Icons.home_work_outlined,
              label: 'Property reference',
              value: viewing.propertyId,
            ),
            if (_hasText(viewing.tenantMessage)) ...[
              const SizedBox(height: AppSpacing.base),
              _DetailBlock(
                label: 'Your message',
                value: viewing.tenantMessage!.trim(),
              ),
            ],
            if (_hasText(viewing.landlordResponse)) ...[
              const SizedBox(height: AppSpacing.md),
              _DetailBlock(
                label: 'Landlord response',
                value: viewing.landlordResponse!.trim(),
                highlighted: true,
              ),
            ],
            if (canCancel) ...[
              const SizedBox(height: AppSpacing.base),
              const Divider(height: 1, color: AppPalette.border),
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
                  label: Text(isCancelling ? 'Cancelling…' : 'Cancel viewing'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppPalette.danger,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppPalette.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.text,
                    fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFECEFDF) : const Color(0xFFF5F3ED),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppPalette.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            key: ValueKey(isError ? 'viewings-error' : 'viewings-empty'),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: isError
                          ? const Color(0xFFF5DDDC)
                          : const Color(0xFFECEFDF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 32,
                      color: isError ? AppPalette.danger : AppPalette.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppPalette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppPalette.muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh_outlined),
                    label: Text(actionLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          key: const ValueKey('viewings-loading'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 34,
              child: CircularProgressIndicator(
                color: AppPalette.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppPalette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
