import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/viewing.dart';
import '../services/viewing_api_service.dart';
import '../widgets/viewing_status_chip.dart';

class LandlordViewingRequestDetailsScreen extends StatefulWidget {
  const LandlordViewingRequestDetailsScreen({
    super.key,
    required this.viewing,
    required this.viewingApiService,
    this.nowProvider,
  });

  final Viewing viewing;
  final ViewingApiService viewingApiService;
  final DateTime Function()? nowProvider;

  @override
  State<LandlordViewingRequestDetailsScreen> createState() =>
      _LandlordViewingRequestDetailsScreenState();
}

class _LandlordViewingRequestDetailsScreenState
    extends State<LandlordViewingRequestDetailsScreen>
    with WidgetsBindingObserver {
  late Viewing _viewing;
  late final TextEditingController _responseController;
  bool _isApproving = false;
  bool _isRejecting = false;
  String? _actionError;
  bool _contactLoaded = false;
  bool _isRefreshing = false;
  bool _isCompleting = false;
  bool _confirmingCompletion = false;
  bool _completionLoaded = false;
  bool _inForeground = true;
  bool _refreshPending = false;
  Timer? _completionTimer;
  DateTime? _completionRefreshedAt;

  bool get _isBusy =>
      _isApproving ||
      _isRejecting ||
      _isRefreshing ||
      _isCompleting ||
      _confirmingCompletion;
  bool get _canComplete =>
      _completionLoaded &&
      _viewing.status == ViewingStatus.approved &&
      _viewing.canMarkCompleted;
  bool get _canRespond => _viewing.status == ViewingStatus.pending;
  bool get _canCall =>
      _contactLoaded &&
      _viewing.status == ViewingStatus.approved &&
      _viewing.tenant.dialerUri != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewing = widget.viewing;
    _responseController = TextEditingController(
      text: widget.viewing.landlordResponse ?? '',
    );
    if (_viewing.status == ViewingStatus.approved) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _inForeground = true;
      if ((ModalRoute.of(context)?.isCurrent ?? false) ||
          _confirmingCompletion) {
        _refresh();
      }
    } else {
      _inForeground = false;
      _completionTimer?.cancel();
      setState(() {
        _contactLoaded = false;
        _completionLoaded = false;
      });
    }
  }

  void _checkIdentity(Viewing updated) {
    if (updated.id != _viewing.id ||
        updated.propertyId != _viewing.propertyId ||
        updated.tenantId != _viewing.tenantId) {
      throw const ViewingApiException(
        'The viewing service returned an invalid response.',
      );
    }
  }

  void _setViewing(Viewing updated) {
    _viewing = updated;
    _contactLoaded = _inForeground;
    _completionLoaded = _inForeground;
    _scheduleCompletionRefresh();
  }

  void _scheduleCompletionRefresh() {
    _completionTimer?.cancel();
    final eligibleAt = _viewing.completionEligibleAt;
    if (!_inForeground ||
        _viewing.status != ViewingStatus.approved ||
        _viewing.canMarkCompleted ||
        eligibleAt == null ||
        eligibleAt == _completionRefreshedAt) {
      return;
    }
    // Device time schedules a GET only. A repeated false response for the same
    // end does not restart a polling loop, even if the device clock is ahead.
    final delay =
        eligibleAt.difference(widget.nowProvider?.call() ?? DateTime.now()) +
        const Duration(seconds: 1);
    _completionTimer = Timer(
      delay > Duration.zero ? delay : const Duration(seconds: 1),
      () {
        _completionRefreshedAt = eligibleAt;
        if (mounted && _inForeground) _refresh();
      },
    );
  }

  void _refreshWhenIdle() {
    if (_refreshPending && mounted && _inForeground && !_isBusy) {
      _refreshPending = false;
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (_isBusy) {
      _refreshPending = true;
      return;
    }
    setState(() {
      _isRefreshing = true;
      _contactLoaded = false;
      _completionLoaded = false;
      _actionError = null;
    });
    try {
      final updated = await widget.viewingApiService.getViewingById(
        _viewing.id,
      );
      _checkIdentity(updated);
      if (!mounted) return;
      setState(() {
        _setViewing(updated);
      });
    } catch (_) {
      if (mounted) {
        _showError('Unable to refresh this viewing request. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
      _refreshWhenIdle();
    }
  }

  Future<void> _callTenant() async {
    if (!_canCall || _isBusy) return;
    final uri = _viewing.tenant.dialerUri!;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Unsupported devices and platform failures use the same concise feedback.
    }
    if (mounted) {
      AppSnackbars.show(
        context,
        message: 'Calling is not available on this device.',
        tone: SnackTone.error,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _completionTimer?.cancel();
    _responseController.dispose();
    super.dispose();
  }

  Future<void> _approve() => _respond(approve: true);

  Future<void> _reject() => _respond(approve: false);

  Future<void> _complete() async {
    if (!_canComplete || _isBusy) return;
    setState(() => _confirmingCompletion = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark viewing completed?'),
        content: const Text(
          'Confirm that the tenant attended this viewing and the viewing has finished.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm completed'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirmingCompletion = false);
    if (confirmed != true || !_canComplete) {
      _refreshWhenIdle();
      return;
    }
    setState(() {
      _isCompleting = true;
      _actionError = null;
    });
    try {
      final updated = await widget.viewingApiService.completeViewing(
        id: _viewing.id,
      );
      _checkIdentity(updated);
      if (!mounted) return;
      setState(() => _setViewing(updated));
      AppSnackbars.show(
        context,
        message: 'Viewing marked as completed.',
        tone: SnackTone.success,
      );
    } on ViewingApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 409) {
        // A different device may have completed it, or server eligibility changed.
        setState(() {
          _completionLoaded = false;
          _contactLoaded = false;
        });
        try {
          final updated = await widget.viewingApiService.getViewingById(
            _viewing.id,
          );
          _checkIdentity(updated);
          if (!mounted) return;
          setState(() => _setViewing(updated));
          if (updated.status == ViewingStatus.approved &&
              updated.canMarkCompleted) {
            _showError('Could not update the viewing. Please try again.');
          }
        } catch (_) {
          if (mounted) {
            _showError('Could not update the viewing. Please try again.');
          }
        }
      } else {
        _showError('Could not update the viewing. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        _showError('Could not update the viewing. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isCompleting = false);
      _refreshWhenIdle();
    }
  }

  Future<void> _respond({required bool approve}) async {
    if (!_canRespond || _isBusy) return;
    final response = _responseController.text.trim();
    if (!approve && response.isEmpty) {
      setState(() {
        _actionError = 'Add a landlord response before rejecting this request.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isApproving = approve;
      _isRejecting = !approve;
      _actionError = null;
    });
    try {
      final updated = approve
          ? await widget.viewingApiService.approveViewing(
              id: _viewing.id,
              landlordResponse: response,
            )
          : await widget.viewingApiService.rejectViewing(
              id: _viewing.id,
              landlordResponse: response,
            );
      _checkIdentity(updated);
      if (!mounted) return;
      setState(() {
        _setViewing(updated);
        _responseController.text = updated.landlordResponse ?? response;
      });
      AppSnackbars.show(
        context,
        message: approve ? 'Viewing approved.' : 'Viewing rejected.',
        tone: SnackTone.success,
      );
    } on ViewingApiException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) {
        _showError(
          'Unable to update this viewing request right now. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isApproving = false;
          _isRejecting = false;
        });
      }
      _refreshWhenIdle();
    }
  }

  void _showError(String message) {
    setState(() => _actionError = message);
    AppSnackbars.show(context, message: message, tone: SnackTone.error);
  }

  @override
  Widget build(BuildContext context) {
    final local = _viewing.requestedLocalDate == null
        ? _viewing.requestedDateTime.toLocal()
        : DateTime.parse(_viewing.requestedLocalDate!);
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(local);
    final time = _viewing.requestedDisplayTime == null
        ? localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))
        : '${_viewing.requestedDisplayTime} (${_viewing.timeZoneId})';
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        title: const Text('Viewing Request'),
        titleTextStyle: AppTypography.pageTitle.copyWith(
          color: AppPalette.darkOlive,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh viewing request',
            onPressed: _isBusy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: AuthenticatedPage(
        maxWidth: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ViewingStatusChip(status: _viewing.status),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        color: AppPalette.olive,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Requested $date',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              time,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_viewing.status == ViewingStatus.completed) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                key: const ValueKey('viewing-completed-state'),
                color: AppPalette.progress,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Viewing completed',
                      style: AppTypography.sectionTitle.copyWith(
                        color: AppPalette.darkOlive,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('This viewing has been marked as completed.'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Request details'),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                children: [
                  _ReferenceRow(
                    label: 'Property',
                    value:
                        _viewing.propertyTitle ??
                        'Property details unavailable',
                  ),
                  const Divider(height: AppSpacing.lg),
                  _ReferenceRow(
                    label: 'Tenant',
                    value: _viewing.tenant.displayName,
                    emphasize: true,
                  ),
                  if (_canCall) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        _viewing.tenant.phoneNumber!.trim(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppPalette.muted,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _isBusy ? null : _callTenant,
                        icon: const Icon(Icons.phone_outlined),
                        label: const Text('Call tenant'),
                      ),
                    ),
                  ],
                  const Divider(height: AppSpacing.lg),
                  _ReferenceRow(label: 'Requested date', value: date),
                  const Divider(height: AppSpacing.lg),
                  _ReferenceRow(label: 'Requested time', value: time),
                  const SizedBox(height: AppSpacing.md),
                  _ReferenceRow(
                    label: 'Duration',
                    value: _viewing.durationMinutes == null
                        ? 'Not recorded'
                        : '${_viewing.durationMinutes} minutes',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Tenant message'),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Text(
                _hasText(_viewing.tenantMessage)
                    ? _viewing.tenantMessage!.trim()
                    : 'No tenant message was provided.',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Landlord response'),
            const SizedBox(height: AppSpacing.md),
            if (_canRespond)
              TextField(
                key: const ValueKey('landlord-viewing-response'),
                controller: _responseController,
                enabled: !_isBusy,
                maxLines: 4,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Response to tenant',
                  helperText:
                      'Required when rejecting; optional when approving.',
                  alignLabelWithHint: true,
                ),
              )
            else
              AppCard(
                color: AppPalette.softCream,
                child: Text(
                  _hasText(_viewing.landlordResponse)
                      ? _viewing.landlordResponse!.trim()
                      : 'No landlord response was provided.',
                ),
              ),
            if (_actionError case final error?) ...[
              const SizedBox(height: AppSpacing.md),
              _ActionError(message: error),
            ],
            if (_canRespond || _viewing.status == ViewingStatus.approved) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Landlord actions',
                style: AppTypography.cardTitle.copyWith(
                  color: AppPalette.darkOlive,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_viewing.status == ViewingStatus.approved)
              if (_canComplete)
                FilledButton.icon(
                  key: const ValueKey('complete-viewing-request'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.olive,
                  ),
                  onPressed: _isBusy ? null : _complete,
                  icon: _isCompleting
                      ? const _ButtonProgress()
                      : const Icon(Icons.task_alt_outlined),
                  label: Text(
                    _isCompleting ? 'Completing...' : 'Mark viewing completed',
                  ),
                )
              else
                AppCard(
                  key: const ValueKey('viewing-completion-info'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Viewing completion',
                        style: AppTypography.cardTitle.copyWith(
                          color: AppPalette.darkOlive,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'You can mark this viewing as completed after the scheduled viewing ends.',
                      ),
                      if (_completionTimeLabel(context) case final label?) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(label, style: AppTypography.bodySmall),
                      ],
                    ],
                  ),
                ),
            if (_canRespond) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                key: const ValueKey('approve-viewing-request'),
                onPressed: _isBusy ? null : _approve,
                icon: _isApproving
                    ? const _ButtonProgress()
                    : const Icon(Icons.check_circle_outline),
                label: Text(_isApproving ? 'Approving...' : 'Approve'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                key: const ValueKey('reject-viewing-request'),
                onPressed: _isBusy ? null : _reject,
                icon: _isRejecting
                    ? const _ButtonProgress(color: AppPalette.danger)
                    : const Icon(Icons.cancel_outlined),
                label: Text(_isRejecting ? 'Rejecting...' : 'Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.danger,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  String? _completionTimeLabel(BuildContext context) {
    final instant = _viewing.completionEligibleAt;
    if (instant == null || _viewing.timeZoneId != 'Asia/Colombo') return null;
    // Display follows the property's existing Colombo convention, independent
    // of the device zone. This formatted time never controls action permission.
    final local = instant.toUtc().add(const Duration(hours: 5, minutes: 30));
    final labels = MaterialLocalizations.of(context);
    return 'Available after ${labels.formatMediumDate(local)}, ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))} (Asia/Colombo)';
  }
}

class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppPalette.muted),
      ),
      const SizedBox(height: AppSpacing.xs),
      SelectableText(
        value,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppPalette.text,
          fontWeight: emphasize ? FontWeight.w600 : null,
        ),
      ),
    ],
  );
}

class _ActionError extends StatelessWidget {
  const _ActionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('viewing-action-error'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: const Color(0xFFF5DDDC),
      borderRadius: BorderRadius.circular(AppRadii.medium),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: AppPalette.danger),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppPalette.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress({this.color = AppPalette.white});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}
