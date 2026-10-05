import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../application_documents/models/application_document.dart';
import '../../application_documents/services/application_document_api_service.dart';
import '../../application_validation/models/application_validation.dart';
import '../../application_validation/services/application_validation_api_service.dart';
import '../models/rental_application.dart';
import '../services/rental_application_api_service.dart';
import '../widgets/rental_application_status_chip.dart';

class LandlordRentalApplicationDetailsScreen extends StatefulWidget {
  const LandlordRentalApplicationDetailsScreen({
    super.key,
    required this.application,
    required this.rentalApplicationApiService,
    this.applicationDocumentApiService,
    this.applicationValidationApiService,
  });

  final RentalApplication application;
  final RentalApplicationApiService rentalApplicationApiService;
  final ApplicationDocumentApiService? applicationDocumentApiService;
  final ApplicationValidationApiService? applicationValidationApiService;

  @override
  State<LandlordRentalApplicationDetailsScreen> createState() =>
      _LandlordRentalApplicationDetailsScreenState();
}

class _LandlordRentalApplicationDetailsScreenState
    extends State<LandlordRentalApplicationDetailsScreen> {
  late RentalApplication _application;
  late final ApplicationDocumentApiService _documentService;
  late final ApplicationValidationApiService _validationService;
  late Future<List<ApplicationDocument>> _documents;
  late Future<List<ApplicationValidationRun>> _validationRuns;
  bool _submitting = false;
  String? _actionError;

  bool get _canDecide =>
      _application.status == RentalApplicationStatus.submitted ||
      _application.status == RentalApplicationStatus.underReview;

  @override
  void initState() {
    super.initState();
    _application = widget.application;
    _documentService =
        widget.applicationDocumentApiService ??
        ApplicationDocumentApiService(
          widget.rentalApplicationApiService.apiClient,
        );
    _validationService =
        widget.applicationValidationApiService ??
        ApplicationValidationApiService(
          widget.rentalApplicationApiService.apiClient,
        );
    _documents = _loadDocuments();
    _validationRuns = _loadValidation();
  }

  Future<List<ApplicationDocument>> _loadDocuments() => _documentService
      .getDocumentsForApplication(applicationId: _application.id);

  Future<List<ApplicationValidationRun>> _loadValidation() =>
      _validationService.getRunsForApplication(_application.id);

  void _retryDocuments() {
    setState(() {
      _documents = _loadDocuments();
    });
  }

  Future<void> _retryValidation() async {
    final request = _loadValidation();
    setState(() {
      _validationRuns = request;
    });
    try {
      await request;
    } catch (_) {
      // The section renders the authoritative error state.
    }
  }

  Future<void> _approve() async {
    if (!_canDecide || _submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve application?'),
        content: const Text(
          'Confirm that you have reviewed the application and available findings. Your approval will be recorded as the human decision.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _submitDecision(
      successMessage: 'Application approved.',
      operation: () => widget.rentalApplicationApiService.approveApplication(
        id: _application.id,
      ),
    );
  }

  Future<void> _requestResponse({required bool requestingChanges}) async {
    if (!_canDecide || _submitting) return;
    final formKey = GlobalKey<FormState>();
    var responseText = '';
    final response = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          requestingChanges ? 'Request changes' : 'Reject application',
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            onChanged: (value) => responseText = value,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a response for the tenant.'
                : null,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Response to tenant',
              helperText: 'Required · up to 1,000 characters',
              hintText: requestingChanges
                  ? 'Explain what needs to be updated.'
                  : 'Explain why the application is rejected.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, responseText.trim());
              }
            },
            style: requestingChanges
                ? null
                : FilledButton.styleFrom(backgroundColor: AppPalette.danger),
            child: Text(requestingChanges ? 'Request changes' : 'Reject'),
          ),
        ],
      ),
    );
    if (response == null || !mounted) return;
    await _submitDecision(
      successMessage: requestingChanges
          ? 'Changes requested from the tenant.'
          : 'Application rejected.',
      operation: requestingChanges
          ? () => widget.rentalApplicationApiService.requestApplicationChanges(
              id: _application.id,
              landlordResponse: response,
            )
          : () => widget.rentalApplicationApiService.rejectApplication(
              id: _application.id,
              landlordResponse: response,
            ),
    );
  }

  Future<void> _submitDecision({
    required Future<RentalApplication> Function() operation,
    required String successMessage,
  }) async {
    setState(() {
      _submitting = true;
      _actionError = null;
    });
    try {
      final updated = await operation();
      if (!mounted) return;
      setState(() {
        _application = updated;
        _validationRuns = _loadValidation();
      });
      AppSnackbars.show(
        context,
        message: successMessage,
        tone: SnackTone.success,
      );
    } on RentalApplicationApiException catch (error) {
      if (mounted) setState(() => _actionError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _actionError =
              'Unable to record this decision right now. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(
      title: const Text('Application Details'),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: AppSpacing.page,
        children: [
          _StatusHeader(application: _application),
          const SizedBox(height: AppSpacing.base),
          _ApplicationOverview(application: _application),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(
            title: 'Documents',
            subtitle: 'Files attached to this application.',
          ),
          const SizedBox(height: AppSpacing.md),
          _DocumentSummary(future: _documents, onRetry: _retryDocuments),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            title: 'AI Findings',
            subtitle:
                'Validation assists the review. It does not make the human decision.',
            trailing: IconButton(
              tooltip: 'Refresh AI findings',
              onPressed: _retryValidation,
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ValidationReview(future: _validationRuns, onRetry: _retryValidation),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(
            title: 'Human Decision',
            subtitle: 'Only a landlord or administrator records the outcome.',
          ),
          const SizedBox(height: AppSpacing.md),
          _HumanDecision(
            canDecide: _canDecide,
            submitting: _submitting,
            error: _actionError,
            status: _application.status,
            landlordResponse: _application.landlordResponse,
            onApprove: _approve,
            onReject: () => _requestResponse(requestingChanges: false),
            onRequestChanges: () => _requestResponse(requestingChanges: true),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    ),
  );
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.application});
  final RentalApplication application;

  @override
  Widget build(BuildContext context) => AppCard(
    color: AppPalette.sage,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'APPLICATION STATUS',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        RentalApplicationStatusChip(status: application.status),
        const SizedBox(height: AppSpacing.md),
        Text('Property', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(
          application.propertyTitle ?? 'Property details unavailable',
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Applicant', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(
          application.applicantName ?? 'Applicant name unavailable',
        ),
      ],
    ),
  );
}

class _ApplicationOverview extends StatelessWidget {
  const _ApplicationOverview({required this.application});
  final RentalApplication application;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Application timeline'),
          const SizedBox(height: AppSpacing.base),
          _DetailRow(
            label: 'Created',
            value: _formatTimestamp(localizations, application.createdAt),
          ),
          _DetailRow(
            label: 'Submitted',
            value: application.submittedAt == null
                ? 'Not recorded'
                : _formatTimestamp(localizations, application.submittedAt!),
          ),
          _DetailRow(
            label: 'Updated',
            value: application.updatedAt == null
                ? 'Not recorded'
                : _formatTimestamp(localizations, application.updatedAt!),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _DocumentSummary extends StatelessWidget {
  const _DocumentSummary({required this.future, required this.onRetry});
  final Future<List<ApplicationDocument>> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
    child: FutureBuilder<List<ApplicationDocument>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState(
            title: 'Loading document summary',
            compact: true,
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          return ErrorState(
            message: error is ApplicationDocumentApiException
                ? error.message
                : 'Unable to load the document summary.',
            onRetry: onRetry,
            compact: true,
          );
        }
        final documents = snapshot.data ?? const <ApplicationDocument>[];
        if (documents.isEmpty) {
          return const EmptyState(
            title: 'No documents uploaded',
            message: 'No files are attached to this application yet.',
            compact: true,
          );
        }
        final localizations = MaterialLocalizations.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusChip(
              label:
                  '${documents.length} ${documents.length == 1 ? 'document' : 'documents'}',
              icon: Icons.attach_file,
            ),
            const SizedBox(height: AppSpacing.md),
            ...documents.map(
              (document) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 20,
                      color: AppPalette.olive,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            document.documentType.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${document.originalFileName} · ${_formatBytes(document.fileSizeBytes)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'Uploaded ${_formatTimestamp(localizations, document.uploadedAt)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ValidationReview extends StatelessWidget {
  const _ValidationReview({required this.future, required this.onRetry});
  final Future<List<ApplicationValidationRun>> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
    child: FutureBuilder<List<ApplicationValidationRun>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState(
            title: 'Loading validation findings',
            compact: true,
          );
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: 'Unable to load validation findings. Please try again.',
            onRetry: onRetry,
            compact: true,
          );
        }
        final runs = snapshot.data ?? const <ApplicationValidationRun>[];
        if (runs.isEmpty) {
          return const EmptyState(
            title: 'No validation review available',
            message:
                'No validation findings have been returned for this application yet.',
            compact: true,
          );
        }
        final run = runs.reduce(
          (latest, candidate) => candidate.createdAt.isAfter(latest.createdAt)
              ? candidate
              : latest,
        );
        return _ValidationFindings(run: run);
      },
    ),
  );
}

class _ValidationFindings extends StatelessWidget {
  const _ValidationFindings({required this.run});
  final ApplicationValidationRun run;

  @override
  Widget build(BuildContext context) {
    final summary = run.summary;
    final tone = switch (run.status) {
      ApplicationValidationStatus.awaitingHumanReview => StatusTone.warning,
      ApplicationValidationStatus.completed => StatusTone.success,
      ApplicationValidationStatus.failed => StatusTone.danger,
      _ => StatusTone.progress,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusChip(
          label: run.status.label,
          tone: tone,
          icon: run.status == ApplicationValidationStatus.awaitingHumanReview
              ? Icons.person_search_outlined
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Updated ${_formatTimestamp(MaterialLocalizations.of(context), run.updatedAt)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (run.status == ApplicationValidationStatus.failed) ...[
          const SizedBox(height: AppSpacing.md),
          const _Notice(
            icon: Icons.error_outline,
            text:
                'Validation failed. Available findings may be incomplete. Review the application and documents before deciding.',
          ),
        ] else if (run.status == ApplicationValidationStatus.completed) ...[
          const SizedBox(height: AppSpacing.md),
          const _Notice(
            icon: Icons.task_alt,
            text:
                'Validation is complete. The application status shows the recorded human decision.',
          ),
        ] else if (run.requiresHumanApproval ||
            run.status == ApplicationValidationStatus.awaitingHumanReview) ...[
          const SizedBox(height: AppSpacing.md),
          const _Notice(
            icon: Icons.verified_user_outlined,
            text: 'Human review is required before a decision is recorded.',
          ),
        ],
        if (summary == null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Detailed findings are not available yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.base),
          _FindingGroup(
            title: 'Missing required items',
            items: [
              ...summary.applicationData.missingFields.map(
                (item) => 'Application: ${_findingLabel(item)}',
              ),
              ...summary.documents.missingDocumentTypes.map(
                (item) => 'Document: ${_findingLabel(item)}',
              ),
            ],
            emptyText: 'No missing required items were returned.',
          ),
          const Divider(height: AppSpacing.lg),
          _FindingGroup(
            title: 'Deterministic checks',
            status: summary.deterministicChecks.passed
                ? 'Passed'
                : 'Needs attention',
            items: [
              '${summary.deterministicChecks.passedRules.length} passed · ${summary.deterministicChecks.failedRules.length} failed',
              ...summary.deterministicChecks.failedRules.map(_findingLabel),
            ],
            emptyText: 'No check details were returned.',
          ),
          const Divider(height: AppSpacing.lg),
          _FindingGroup(
            title: 'Important warnings',
            items: _unique([
              ...summary.applicationData.warnings,
              ...summary.documents.warnings,
              ...summary.deterministicChecks.warnings,
            ]),
            emptyText: 'No warnings were returned.',
          ),
          const Divider(height: AppSpacing.lg),
          _FindingGroup(
            title: 'Document findings',
            status: summary.documents.isValid
                ? 'Required types present'
                : 'Needs attention',
            items: [
              if (summary.documents.presentDocumentTypes.isNotEmpty)
                'Present: ${summary.documents.presentDocumentTypes.map(_findingLabel).join(', ')}'
              else
                'No document types reported as present.',
              if (summary.documents.missingDocumentTypes.isNotEmpty)
                '${summary.documents.missingDocumentTypes.length} document types missing',
            ],
            emptyText: 'No document findings were returned.',
          ),
        ],
      ],
    );
  }
}

class _FindingGroup extends StatelessWidget {
  const _FindingGroup({
    required this.title,
    required this.items,
    required this.emptyText,
    this.status,
  });
  final String title;
  final List<String> items;
  final String emptyText;
  final String? status;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (status != null)
            StatusChip(
              label: status!,
              tone: status == 'Passed' || status == 'Required types present'
                  ? StatusTone.success
                  : StatusTone.warning,
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      if (items.isEmpty)
        Text(emptyText, style: Theme.of(context).textTheme.bodyMedium)
      else
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: CircleAvatar(
                    radius: 2.5,
                    backgroundColor: AppPalette.olive,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(item)),
              ],
            ),
          ),
        ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppPalette.softCream,
      borderRadius: BorderRadius.circular(AppRadii.small),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppPalette.olive),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _HumanDecision extends StatelessWidget {
  const _HumanDecision({
    required this.canDecide,
    required this.submitting,
    required this.error,
    required this.status,
    required this.landlordResponse,
    required this.onApprove,
    required this.onReject,
    required this.onRequestChanges,
  });
  final bool canDecide;
  final bool submitting;
  final String? error;
  final RentalApplicationStatus status;
  final String? landlordResponse;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onRequestChanges;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Landlord response',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _hasText(landlordResponse)
              ? landlordResponse!.trim()
              : 'No response recorded.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const Divider(height: AppSpacing.lg),
        if (submitting) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Recording decision…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ] else if (canDecide) ...[
          FilledButton.icon(
            onPressed: onApprove,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Approve'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onRequestChanges,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Request Changes'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onReject,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Reject'),
            style: TextButton.styleFrom(foregroundColor: AppPalette.danger),
          ),
        ] else
          _Notice(
            icon: Icons.lock_outline,
            text:
                'No decision actions are available while this application is ${_statusLabel(status)}.',
          ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppPalette.danger),
          ),
        ],
      ],
    ),
  );
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

List<String> _unique(List<String> values) =>
    values.toSet().toList(growable: false);

String _findingLabel(String value) => switch (value) {
  'MoveInDate' => 'Move-in date',
  'MonthlyIncome' => 'Monthly income',
  'Occupation' => 'Occupation',
  'NumberOfOccupants' => 'Number of occupants',
  'IdentityDocument' => 'Identity document',
  'IncomeProof' => 'Income proof',
  'EmploymentLetter' => 'Employment letter',
  _ => value,
};

String _formatTimestamp(MaterialLocalizations localizations, DateTime value) {
  final local = value.toLocal();
  return '${localizations.formatMediumDate(local)}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _statusLabel(RentalApplicationStatus status) => switch (status) {
  RentalApplicationStatus.draft => 'Draft',
  RentalApplicationStatus.submitted => 'Submitted',
  RentalApplicationStatus.underReview => 'Under Review',
  RentalApplicationStatus.changesRequested => 'Changes Requested',
  RentalApplicationStatus.approved => 'Approved',
  RentalApplicationStatus.rejected => 'Rejected',
  RentalApplicationStatus.withdrawn => 'Withdrawn',
};
