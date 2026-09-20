import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../application_documents/models/application_document.dart';
import '../../application_documents/screens/application_documents_screen.dart';
import '../../application_documents/services/application_document_api_service.dart';
import '../models/rental_application.dart';
import '../services/rental_application_api_service.dart';
import '../widgets/rental_application_status_chip.dart';
import 'rental_application_form_screen.dart';

class RentalApplicationDetailsScreen extends StatefulWidget {
  const RentalApplicationDetailsScreen({
    super.key,
    required this.application,
    required this.rentalApplicationApiService,
    this.applicationDocumentApiService,
  });

  final RentalApplication application;
  final RentalApplicationApiService rentalApplicationApiService;
  final ApplicationDocumentApiService? applicationDocumentApiService;

  @override
  State<RentalApplicationDetailsScreen> createState() =>
      _RentalApplicationDetailsScreenState();
}

class _RentalApplicationDetailsScreenState
    extends State<RentalApplicationDetailsScreen> {
  late RentalApplication _application;
  late final ApplicationDocumentApiService _documentApiService;
  late Future<List<ApplicationDocument>> _documents;
  bool _isSubmitting = false;
  bool _isWithdrawing = false;

  bool get _isBusy => _isSubmitting || _isWithdrawing;

  bool get _canWithdraw => switch (_application.status) {
    RentalApplicationStatus.draft ||
    RentalApplicationStatus.submitted ||
    RentalApplicationStatus.underReview ||
    RentalApplicationStatus.changesRequested => true,
    RentalApplicationStatus.approved ||
    RentalApplicationStatus.rejected ||
    RentalApplicationStatus.withdrawn => false,
  };

  bool get _canResubmit =>
      _application.status == RentalApplicationStatus.changesRequested;

  bool get _canContinue => _application.status == RentalApplicationStatus.draft;

  bool get _canEdit =>
      _application.status == RentalApplicationStatus.changesRequested;

  @override
  void initState() {
    super.initState();
    _application = widget.application;
    _documentApiService =
        widget.applicationDocumentApiService ??
        ApplicationDocumentApiService(
          widget.rentalApplicationApiService.apiClient,
        );
    _documents = _loadDocuments();
  }

  Future<List<ApplicationDocument>> _loadDocuments() {
    return _documentApiService.getDocumentsForApplication(
      applicationId: _application.id,
    );
  }

  void _retryDocuments() => setState(() => _documents = _loadDocuments());

  Future<void> _openForm() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RentalApplicationFormScreen(
          propertyId: _application.propertyId,
          application: _application,
          rentalApplicationApiService: widget.rentalApplicationApiService,
        ),
      ),
    );
    if (!mounted) return;
    try {
      final refreshed = await widget.rentalApplicationApiService
          .getApplicationById(_application.id);
      if (mounted) setState(() => _application = refreshed);
    } on RentalApplicationApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    }
  }

  void _openDocuments() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApplicationDocumentsScreen(
          applicationId: _application.id,
          rentalApplicationApiService: widget.rentalApplicationApiService,
          applicationDocumentApiService: _documentApiService,
        ),
      ),
    );
  }

  Future<void> _resubmit() async {
    if (!_canResubmit || _isBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.send_outlined),
        title: const Text('Resubmit application?'),
        content: const Text(
          'Resubmit this updated rental application for landlord review?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resubmit application'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final submitted = await widget.rentalApplicationApiService
          .submitApplication(id: _application.id);
      if (!mounted) return;
      setState(() => _application = submitted);
      _showMessage('Application resubmitted successfully.');
    } on RentalApplicationApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to resubmit your application right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _withdraw() async {
    if (!_canWithdraw || _isBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.undo_outlined),
        title: const Text('Withdraw this application?'),
        content: const Text(
          'The application will be withdrawn and cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep application'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.danger),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWithdrawing = true);
    try {
      final withdrawn = await widget.rentalApplicationApiService
          .withdrawApplication(id: _application.id);
      if (!mounted) return;
      setState(() => _application = withdrawn);
      _showMessage('Application withdrawn.');
    } on RentalApplicationApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to withdraw the application right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    AppSnackbars.show(
      context,
      message: message,
      tone: isError ? SnackTone.error : SnackTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final actionRequired =
        _application.status == RentalApplicationStatus.changesRequested;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Details'),
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
              color: actionRequired
                  ? const Color(0xFFF5DDDC)
                  : AppPalette.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          actionRequired
                              ? 'Action required'
                              : 'Rental application',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      RentalApplicationStatusChip(status: _application.status),
                    ],
                  ),
                  if (actionRequired) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Review the landlord response, edit the requested details, then resubmit.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppPalette.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Application overview'),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                children: [
                  _DetailRow(
                    icon: Icons.home_work_outlined,
                    label: 'Property reference',
                    value: _application.propertyId,
                  ),
                  const Divider(height: AppSpacing.lg),
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Requested move-in',
                    value: MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(_application.moveInDate),
                  ),
                  const Divider(height: AppSpacing.lg),
                  _DetailRow(
                    icon: Icons.work_outline,
                    label: 'Occupation',
                    value: _application.occupation,
                  ),
                  const Divider(height: AppSpacing.lg),
                  _DetailRow(
                    icon: Icons.people_outline,
                    label: 'Occupants',
                    value: _application.numberOfOccupants.toString(),
                  ),
                  const Divider(height: AppSpacing.lg),
                  _DetailRow(
                    icon: Icons.payments_outlined,
                    label: 'Monthly income',
                    value: _application.monthlyIncome.toStringAsFixed(2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Progress'),
            const SizedBox(height: AppSpacing.md),
            _ApplicationTimeline(application: _application),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Landlord response'),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: _hasText(_application.landlordResponse)
                  ? AppPalette.sage
                  : AppPalette.white,
              child: Text(
                _hasText(_application.landlordResponse)
                    ? _application.landlordResponse!.trim()
                    : 'No landlord response is available yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Documents'),
            const SizedBox(height: AppSpacing.md),
            _DocumentSummary(
              documents: _documents,
              onRetry: _retryDocuments,
              onOpen: _openDocuments,
            ),
            if (_canContinue || _canEdit || _canResubmit || _canWithdraw) ...[
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'Available actions'),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_canContinue)
                      FilledButton.icon(
                        onPressed: _isBusy ? null : _openForm,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continue application'),
                      ),
                    if (_canEdit)
                      OutlinedButton.icon(
                        onPressed: _isBusy ? null : _openForm,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit application'),
                      ),
                    if (_canResubmit) ...[
                      if (_canEdit) const SizedBox(height: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed: _isBusy ? null : _resubmit,
                        icon: _isSubmitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppPalette.white,
                                ),
                              )
                            : const Icon(Icons.send_outlined),
                        label: Text(
                          _isSubmitting
                              ? 'Resubmitting...'
                              : 'Resubmit application',
                        ),
                      ),
                    ],
                    if (_canWithdraw) ...[
                      if (_canContinue || _canEdit || _canResubmit)
                        const SizedBox(height: AppSpacing.sm),
                      TextButton.icon(
                        onPressed: _isBusy ? null : _withdraw,
                        icon: _isWithdrawing
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.undo_outlined),
                        label: Text(
                          _isWithdrawing
                              ? 'Withdrawing...'
                              : 'Withdraw application',
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppPalette.danger,
                        ),
                      ),
                    ],
                  ],
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: AppPalette.olive),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppPalette.muted),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(value, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    ],
  );
}

class _ApplicationTimeline extends StatelessWidget {
  const _ApplicationTimeline({required this.application});

  final RentalApplication application;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      children: [
        _TimelineItem(
          label: 'Created',
          timestamp: application.createdAt,
          isLast:
              application.submittedAt == null && application.updatedAt == null,
        ),
        if (application.submittedAt case final timestamp?)
          _TimelineItem(
            label: 'Submitted',
            timestamp: timestamp,
            isLast: application.updatedAt == null,
          ),
        if (application.updatedAt case final timestamp?)
          _TimelineItem(
            label: 'Last updated',
            timestamp: timestamp,
            isLast: true,
          ),
      ],
    ),
  );
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.label,
    required this.timestamp,
    required this.isLast,
  });

  final String label;
  final DateTime timestamp;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final local = timestamp.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final value =
        '${localizations.formatMediumDate(local)} at '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppPalette.olive,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  const Expanded(
                    child: VerticalDivider(width: 1, thickness: 1),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(value, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentSummary extends StatelessWidget {
  const _DocumentSummary({
    required this.documents,
    required this.onRetry,
    required this.onOpen,
  });

  final Future<List<ApplicationDocument>> documents;
  final VoidCallback onRetry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AppCard(
    child: FutureBuilder<List<ApplicationDocument>>(
      future: documents,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState(
            title: 'Loading document summary',
            compact: true,
          );
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: 'The document summary is currently unavailable.',
            onRetry: onRetry,
            compact: true,
          );
        }
        final count = snapshot.data?.length ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_outlined, color: AppPalette.olive),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    count == 0
                        ? 'No documents uploaded'
                        : '$count ${count == 1 ? 'document' : 'documents'} uploaded',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Open documents'),
            ),
          ],
        );
      },
    ),
  );
}
