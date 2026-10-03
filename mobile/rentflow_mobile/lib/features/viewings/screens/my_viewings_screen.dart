import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../properties/models/property.dart';
import '../../properties/services/property_api_service.dart';
import '../models/viewing.dart';
import '../services/viewing_api_service.dart';
import 'tenant_viewing_details_screen.dart';

class MyViewingsScreen extends StatefulWidget {
  const MyViewingsScreen({super.key, this.viewingApiService});

  final ViewingApiService? viewingApiService;

  @override
  State<MyViewingsScreen> createState() => _MyViewingsScreenState();
}

class _MyViewingsScreenState extends State<MyViewingsScreen> {
  ApiClient? _ownedApiClient;
  late final ViewingApiService _viewingApiService;
  late final PropertyApiService _propertyApiService;
  final Map<String, Property?> _properties = {};
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
    _propertyApiService = PropertyApiService(_viewingApiService.apiClient);
    _viewings = _loadViewings();
  }

  Future<List<Viewing>> _loadViewings() async {
    final viewings = await _viewingApiService.getMyViewings();
    final propertyIds = viewings.map((viewing) => viewing.propertyId).toSet();
    await Future.wait(
      propertyIds.map((id) async {
        try {
          final property = await _propertyApiService.getPropertyById(id);
          _properties[id] = property.id == id ? property : null;
        } catch (_) {
          // A removed or unavailable property must not hide the viewing itself.
          _properties[id] = null;
        }
      }),
    );
    return viewings;
  }

  Future<void> _openViewing(Viewing viewing) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TenantViewingDetailsScreen(
          viewingId: viewing.id,
          propertyApiService: _propertyApiService,
          viewingApiService: _viewingApiService,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = _loadViewings();
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
    return viewing.canCancel;
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
      final refreshed = await _loadViewings();
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
    appBar: AppBar(),
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
                AppSpacing.xs,
                20,
                AppSpacing.xl,
              ),
              itemCount: viewings.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.base),
                    child: const _ListHeader(),
                  );
                }

                final viewing = viewings[index - 1];
                final property = _properties[viewing.propertyId];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == viewings.length ? 0 : AppSpacing.md,
                  ),
                  child: _ViewingCard(
                    viewing: viewing,
                    property: property,
                    onOpenViewing: () => _openViewing(viewing),
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
  const _ListHeader();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'YOUR SCHEDULE',
        style: AppTypography.eyebrow.copyWith(
          color: AppPalette.darkOlive,
          fontSize: AppTypography.labelSize,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text('My viewings', style: AppTypography.pageTitle),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Pending requests appear first.',
        style: AppTypography.body.copyWith(color: AppPalette.secondaryText),
      ),
    ],
  );
}

class _ViewingCard extends StatelessWidget {
  const _ViewingCard({
    required this.viewing,
    required this.property,
    required this.onOpenViewing,
    required this.canCancel,
    required this.isCancelling,
    required this.onCancel,
  });

  final Viewing viewing;
  final Property? property;
  final VoidCallback onOpenViewing;
  final bool canCancel;
  final bool isCancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final scheduled = viewing.requestedLocalDate == null
        ? viewing.requestedDateTime.toLocal()
        : DateTime.parse(viewing.requestedLocalDate!);
    final date = localizations.formatMediumDate(scheduled);
    final time =
        viewing.requestedDisplayTime ??
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(scheduled));
    final location = [property?.address, property?.city]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim())
        .join(', ');
    final note = viewing.tenantMessage?.trim();
    final response = viewing.landlordResponse?.trim();
    final updated = viewing.updatedAt ?? viewing.createdAt;
    final updatedLocal = updated.toLocal();
    final updatedLabel =
        '${localizations.formatMediumDate(updatedLocal)} at '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(updatedLocal))}';

    return AppCard(
      key: ValueKey('viewing-card-${viewing.id}'),
      onTap: onOpenViewing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CompactViewingStatus(status: viewing.status),
              const Spacer(),
              SizedBox.square(
                dimension: 32,
                child: IconButton(
                  tooltip: 'View viewing details',
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: onOpenViewing,
                  style: IconButton.styleFrom(
                    foregroundColor: AppPalette.darkOlive,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            property?.title.trim().isNotEmpty == true
                ? property!.title.trim()
                : 'Property details unavailable',
            style: AppTypography.cardTitle.copyWith(
              color: AppPalette.darkOlive,
            ),
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(location, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: AppSpacing.base),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dateRow = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 15,
                      color: AppPalette.muted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        date,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppPalette.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                );
                final timeText = Text(
                  time,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppPalette.text,
                    fontWeight: FontWeight.w500,
                  ),
                );
                final schedule =
                    constraints.maxWidth <
                        MediaQuery.textScalerOf(
                              context,
                            ).scale(AppTypography.bodySmallSize) *
                            24
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          dateRow,
                          const SizedBox(height: AppSpacing.sm),
                          timeText,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: dateRow),
                          const SizedBox(width: AppSpacing.md),
                          timeText,
                        ],
                      );
                return viewing.timeZoneId == null
                    ? schedule
                    : Tooltip(
                        message: 'Time zone: ${viewing.timeZoneId}',
                        child: schedule,
                      );
              },
            ),
          ),
          const Divider(height: 1),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            _DetailBlock(label: 'Your note', value: note),
          ],
          if (response != null && response.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            _DetailBlock(label: 'Landlord response', value: response),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Last updated $updatedLabel',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppPalette.muted,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (canCancel) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: isCancelling ? null : onCancel,
              style: TextButton.styleFrom(
                foregroundColor: AppPalette.danger,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                alignment: Alignment.centerLeft,
                textStyle: AppTypography.button,
              ),
              child: isCancelling
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text('Cancelling...'),
                      ],
                    )
                  : const Text('Cancel request'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactViewingStatus extends StatelessWidget {
  const _CompactViewingStatus({required this.status});
  final ViewingStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, foreground, background) = switch (status) {
      ViewingStatus.pending => (
        'Pending',
        AppPalette.warning,
        AppPalette.pending,
      ),
      ViewingStatus.approved => (
        'Approved',
        AppPalette.success,
        AppPalette.sage,
      ),
      ViewingStatus.rejected => (
        'Rejected',
        AppPalette.danger,
        const Color(0xFFF5DDDC),
      ),
      ViewingStatus.cancelled => (
        'Cancelled',
        AppPalette.neutral,
        AppPalette.softCream,
      ),
      ViewingStatus.completed => (
        'Completed',
        AppPalette.darkOlive,
        AppPalette.progress,
      ),
    };
    return Semantics(
      label: 'Viewing status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: AppTypography.labelSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.only(left: AppSpacing.sm),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: AppPalette.sage, width: 2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.darkOlive,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: AppTypography.body),
      ],
    ),
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
