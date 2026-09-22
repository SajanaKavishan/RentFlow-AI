import 'package:flutter/material.dart';

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
  });

  final Viewing viewing;
  final ViewingApiService viewingApiService;

  @override
  State<LandlordViewingRequestDetailsScreen> createState() =>
      _LandlordViewingRequestDetailsScreenState();
}

class _LandlordViewingRequestDetailsScreenState
    extends State<LandlordViewingRequestDetailsScreen> {
  late Viewing _viewing;
  late final TextEditingController _responseController;
  bool _isApproving = false;
  bool _isRejecting = false;
  String? _actionError;

  bool get _isBusy => _isApproving || _isRejecting;
  bool get _canRespond => _viewing.status == ViewingStatus.pending;

  @override
  void initState() {
    super.initState();
    _viewing = widget.viewing;
    _responseController = TextEditingController(
      text: widget.viewing.landlordResponse ?? '',
    );
  }

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  Future<void> _approve() => _respond(approve: true);

  Future<void> _reject() => _respond(approve: false);

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
      if (!mounted) return;
      setState(() {
        _viewing = updated;
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
    }
  }

  void _showError(String message) {
    setState(() => _actionError = message);
    AppSnackbars.show(context, message: message, tone: SnackTone.error);
  }

  @override
  Widget build(BuildContext context) {
    final local = _viewing.requestedDateTime.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(local);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        title: const Text('Viewing Request'),
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
              child: Row(
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
                  const SizedBox(width: AppSpacing.sm),
                  ViewingStatusChip(status: _viewing.status),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Request details'),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                children: [
                  _ReferenceRow(
                    label: 'Property reference',
                    value: _viewing.propertyId,
                  ),
                  const Divider(height: AppSpacing.lg),
                  _ReferenceRow(
                    label: 'Tenant reference',
                    value: _viewing.tenantId,
                  ),
                  const Divider(height: AppSpacing.lg),
                  _ReferenceRow(label: 'Requested date', value: date),
                  const Divider(height: AppSpacing.lg),
                  _ReferenceRow(label: 'Requested time', value: time),
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
}

class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({required this.label, required this.value});

  final String label;
  final String value;

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
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppPalette.text),
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
