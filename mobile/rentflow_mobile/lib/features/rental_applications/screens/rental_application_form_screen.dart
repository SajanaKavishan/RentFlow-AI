import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../application_documents/screens/application_documents_screen.dart';
import '../../application_documents/services/application_document_api_service.dart';
import '../models/rental_application.dart';
import '../services/rental_application_api_service.dart';
import '../widgets/rental_application_status_chip.dart';

class RentalApplicationFormScreen extends StatefulWidget {
  const RentalApplicationFormScreen({
    super.key,
    required this.propertyId,
    this.propertyTitle,
    this.application,
    this.rentalApplicationApiService,
  });

  final String propertyId;
  final String? propertyTitle;
  final RentalApplication? application;
  final RentalApplicationApiService? rentalApplicationApiService;

  @override
  State<RentalApplicationFormScreen> createState() =>
      _RentalApplicationFormScreenState();
}

class _RentalApplicationFormScreenState
    extends State<RentalApplicationFormScreen> {
  static const _stepLabels = [
    'Personal',
    'Employment/Financial',
    'Documents',
    'Review & Submit',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _incomeController;
  late final TextEditingController _occupationController;
  late final TextEditingController _occupantsController;
  late final TextEditingController _noteController;

  ApiClient? _ownedApiClient;
  late final RentalApplicationApiService _apiService;
  DateTime? _moveInDate;
  RentalApplication? _application;
  String? _formError;
  int _currentStep = 0;
  bool _isSaving = false;
  bool _isSubmitting = false;

  bool get _isBusy => _isSaving || _isSubmitting;
  bool get _hasPropertyReference => widget.propertyId.trim().isNotEmpty;
  bool get _canEdit =>
      _application == null ||
      _application!.status == RentalApplicationStatus.draft ||
      _application!.status == RentalApplicationStatus.changesRequested;

  @override
  void initState() {
    super.initState();
    _application = widget.application;
    _moveInDate = widget.application?.moveInDate;
    _incomeController = TextEditingController(
      text: widget.application?.monthlyIncome.toString() ?? '',
    );
    _occupationController = TextEditingController(
      text: widget.application?.occupation ?? '',
    );
    _occupantsController = TextEditingController(
      text: widget.application?.numberOfOccupants.toString() ?? '1',
    );
    _noteController = TextEditingController(
      text: widget.application?.tenantNote ?? '',
    );
    if (widget.rentalApplicationApiService case final service?) {
      _apiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _apiService = RentalApplicationApiService(_ownedApiClient!);
    }
  }

  @override
  void dispose() {
    _incomeController.dispose();
    _occupationController.dispose();
    _occupantsController.dispose();
    _noteController.dispose();
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _pickMoveInDate() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final selected = await showDatePicker(
      context: context,
      initialDate: _moveInDate != null && _moveInDate!.isAfter(now)
          ? _moveInDate!
          : tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 5, now.month, now.day),
      helpText: 'Choose your move-in date',
    );
    if (selected != null && mounted) {
      setState(() {
        _moveInDate = selected;
        _formError = null;
      });
    }
  }

  String? _validateIncome(String? value) {
    final income = double.tryParse(value?.trim() ?? '');
    if (income == null || !income.isFinite || income <= 0) {
      return 'Enter a monthly income greater than 0.';
    }
    return null;
  }

  String? _validateOccupation(String? value) {
    final occupation = value?.trim() ?? '';
    if (occupation.isEmpty) return 'Enter your occupation.';
    if (occupation.length > 200) return 'Use 200 characters or fewer.';
    return null;
  }

  String? _validateOccupants(String? value) {
    final occupants = int.tryParse(value?.trim() ?? '');
    if (occupants == null || occupants < 1) {
      return 'Enter at least 1 occupant.';
    }
    return null;
  }

  String? _validateNote(String? value) {
    if ((value ?? '').trim().length > 1000) {
      return 'Use 1000 characters or fewer.';
    }
    return null;
  }

  bool _validateMoveInDate({bool showMessage = true}) {
    final date = _moveInDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (date == null || !date.isAfter(today)) {
      if (showMessage) _setError('Choose a future move-in date.');
      return false;
    }
    return true;
  }

  void _nextStep() {
    if (_currentStep == 0) {
      final validFields = _formKey.currentState?.validate() ?? false;
      if (!validFields || !_validateMoveInDate()) return;
    } else if (_currentStep == 1 &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _currentStep = (_currentStep + 1).clamp(0, _stepLabels.length - 1);
      _formError = null;
    });
  }

  void _previousStep() {
    FocusScope.of(context).unfocus();
    setState(() {
      _currentStep = (_currentStep - 1).clamp(0, _stepLabels.length - 1);
      _formError = null;
    });
  }

  bool _validateAllValues() {
    if (!_hasPropertyReference) {
      _setError('A real property reference is required to apply.');
      return false;
    }
    if (!_validateMoveInDate()) {
      setState(() => _currentStep = 0);
      return false;
    }
    final occupantError = _validateOccupants(_occupantsController.text);
    final noteError = _validateNote(_noteController.text);
    if (occupantError != null || noteError != null) {
      setState(() {
        _currentStep = 0;
        _formError = occupantError ?? noteError;
      });
      return false;
    }
    final incomeError = _validateIncome(_incomeController.text);
    final occupationError = _validateOccupation(_occupationController.text);
    if (incomeError != null || occupationError != null) {
      setState(() {
        _currentStep = 1;
        _formError = incomeError ?? occupationError;
      });
      return false;
    }
    return true;
  }

  Future<void> _saveApplication() async {
    if (_isBusy || !_canEdit || !_validateAllValues()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _formError = null;
    });
    try {
      final note = _noteController.text.trim();
      final existing = _application;
      final saved = existing == null
          ? await _apiService.createApplication(
              propertyId: widget.propertyId,
              moveInDate: _moveInDate!,
              monthlyIncome: double.parse(_incomeController.text.trim()),
              occupation: _occupationController.text.trim(),
              numberOfOccupants: int.parse(_occupantsController.text.trim()),
              tenantNote: note.isEmpty ? null : note,
            )
          : await _apiService.updateApplication(
              id: existing.id,
              moveInDate: _moveInDate!,
              monthlyIncome: double.parse(_incomeController.text.trim()),
              occupation: _occupationController.text.trim(),
              numberOfOccupants: int.parse(_occupantsController.text.trim()),
              tenantNote: note.isEmpty ? null : note,
            );
      if (!mounted) return;
      setState(() => _application = saved);
      _showMessage(
        existing == null
            ? 'Draft application created.'
            : 'Application changes saved.',
      );
    } on RentalApplicationApiException catch (error) {
      if (mounted) _setError(error.message);
    } catch (_) {
      if (mounted) {
        _setError(
          'Unable to save your application right now. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submitApplication() async {
    final application = _application;
    final canSubmit =
        application?.status == RentalApplicationStatus.draft ||
        application?.status == RentalApplicationStatus.changesRequested;
    if (_isBusy || !canSubmit) return;

    final isResubmission =
        application!.status == RentalApplicationStatus.changesRequested;
    setState(() {
      _isSubmitting = true;
      _formError = null;
    });
    try {
      final submitted = await _apiService.submitApplication(id: application.id);
      if (!mounted) return;
      setState(() => _application = submitted);
      _showMessage(
        isResubmission
            ? 'Application resubmitted successfully.'
            : 'Application submitted successfully.',
      );
    } on RentalApplicationApiException catch (error) {
      if (mounted) _setError(error.message);
    } catch (_) {
      if (mounted) {
        _setError(
          'Unable to submit your application right now. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _openDocuments() {
    final application = _application;
    if (application == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApplicationDocumentsScreen(
          applicationId: application.id,
          rentalApplicationApiService: _apiService,
          applicationDocumentApiService: ApplicationDocumentApiService(
            _apiService.apiClient,
          ),
        ),
      ),
    );
  }

  void _setError(String message) {
    setState(() => _formError = message);
    AppSnackbars.show(context, message: message, tone: SnackTone.error);
  }

  void _showMessage(String message) {
    AppSnackbars.show(context, message: message, tone: SnackTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final application = _application;
    final readOnly = !_canEdit;
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        title: const Text('Rental Application'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: AuthenticatedPage(
        maxWidth: 620,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                eyebrow: application == null
                    ? 'New application'
                    : 'Application ${application.id}',
                title:
                    application?.status ==
                        RentalApplicationStatus.changesRequested
                    ? 'Update your application'
                    : 'Apply for this property',
                subtitle: readOnly
                    ? 'This application can no longer be edited.'
                    : 'Complete each step, review your details, then save or submit.',
                trailing: application == null
                    ? null
                    : RentalApplicationStatusChip(status: application.status),
              ),
              if (widget.propertyTitle != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Selected home: ${widget.propertyTitle}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              if (application?.status ==
                  RentalApplicationStatus.changesRequested) ...[
                const SizedBox(height: AppSpacing.base),
                AppCard(
                  color: const Color(0xFFF5DDDC),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Changes requested',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: AppPalette.danger),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _hasText(application?.landlordResponse)
                            ? application!.landlordResponse!.trim()
                            : 'The landlord requested updates but did not provide a message.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              _StepIndicator(labels: _stepLabels, currentStep: _currentStep),
              const SizedBox(height: AppSpacing.lg),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey(_currentStep),
                  child: _buildStep(context, readOnly: readOnly),
                ),
              ),
              if (_formError case final error?) ...[
                const SizedBox(height: AppSpacing.base),
                _FormError(message: error),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (_isBusy) ...[
                const LinearProgressIndicator(
                  key: ValueKey('application-form-progress'),
                  color: AppPalette.olive,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _isSubmitting
                      ? 'Submitting your application...'
                      : 'Saving your application...',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _NavigationActions(
                currentStep: _currentStep,
                lastStep: _stepLabels.length - 1,
                isBusy: _isBusy,
                onBack: _previousStep,
                onNext: _nextStep,
              ),
              if (_currentStep == _stepLabels.length - 1 && !readOnly) ...[
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  key: const ValueKey('save-application'),
                  onPressed: _isBusy || !_hasPropertyReference
                      ? null
                      : _saveApplication,
                  icon: _isSaving
                      ? const _ButtonProgressIndicator()
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    application == null ? 'Save draft' : 'Save changes',
                  ),
                ),
                if (application?.status == RentalApplicationStatus.draft ||
                    application?.status ==
                        RentalApplicationStatus.changesRequested) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('submit-application'),
                    onPressed: _isBusy ? null : _submitApplication,
                    icon: _isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(
                      application?.status ==
                              RentalApplicationStatus.changesRequested
                          ? 'Resubmit application'
                          : 'Submit application',
                    ),
                  ),
                ],
              ],
              if (readOnly) ...[
                const SizedBox(height: AppSpacing.md),
                const AppCard(
                  color: AppPalette.sage,
                  child: Text(
                    'This application has been submitted and is read only.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, {required bool readOnly}) {
    return switch (_currentStep) {
      0 => _PersonalStep(
        propertyId: widget.propertyId,
        moveInDate: _moveInDate,
        occupantsController: _occupantsController,
        noteController: _noteController,
        enabled: !readOnly && !_isBusy,
        onPickDate: _pickMoveInDate,
        validateOccupants: _validateOccupants,
        validateNote: _validateNote,
      ),
      1 => _EmploymentStep(
        incomeController: _incomeController,
        occupationController: _occupationController,
        enabled: !readOnly && !_isBusy,
        validateIncome: _validateIncome,
        validateOccupation: _validateOccupation,
      ),
      2 => _DocumentsStep(
        hasDraft: _application != null,
        onOpenDocuments: _application == null ? null : _openDocuments,
      ),
      _ => _ReviewStep(
        propertyId: widget.propertyId,
        moveInDate: _moveInDate,
        occupation: _occupationController.text.trim(),
        income: _incomeController.text.trim(),
        occupants: _occupantsController.text.trim(),
        note: _noteController.text.trim(),
      ),
    };
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.labels, required this.currentStep});

  final List<String> labels;
  final int currentStep;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step ${currentStep + 1} of ${labels.length}',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppPalette.muted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          labels[currentStep],
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            for (var index = 0; index < labels.length; index++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 5,
                  decoration: BoxDecoration(
                    color: index <= currentStep
                        ? AppPalette.olive
                        : AppPalette.outline,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
              if (index < labels.length - 1)
                const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
      ],
    ),
  );
}

class _PersonalStep extends StatelessWidget {
  const _PersonalStep({
    required this.propertyId,
    required this.moveInDate,
    required this.occupantsController,
    required this.noteController,
    required this.enabled,
    required this.onPickDate,
    required this.validateOccupants,
    required this.validateNote,
  });

  final String propertyId;
  final DateTime? moveInDate;
  final TextEditingController occupantsController;
  final TextEditingController noteController;
  final bool enabled;
  final VoidCallback onPickDate;
  final FormFieldValidator<String> validateOccupants;
  final FormFieldValidator<String> validateNote;

  @override
  Widget build(BuildContext context) {
    final date = moveInDate == null
        ? 'Select a date'
        : MaterialLocalizations.of(context).formatMediumDate(moveInDate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Personal',
          subtitle: 'Your household and move-in details.',
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            children: [
              _ReferenceRow(
                label: 'Property reference',
                value: propertyId.trim().isEmpty ? 'Unavailable' : propertyId,
              ),
              const Divider(height: AppSpacing.lg),
              InkWell(
                key: const ValueKey('application-move-in-date'),
                onTap: enabled ? onPickDate : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: AppPalette.olive,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Move-in date'),
                            const SizedBox(height: AppSpacing.xs),
                            Text(date),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        TextFormField(
          key: const ValueKey('application-occupants'),
          controller: occupantsController,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Number of occupants',
            prefixIcon: Icon(Icons.people_outline),
          ),
          validator: validateOccupants,
        ),
        const SizedBox(height: AppSpacing.base),
        TextFormField(
          key: const ValueKey('application-note'),
          controller: noteController,
          enabled: enabled,
          maxLines: 4,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Note to the landlord (optional)',
            prefixIcon: Icon(Icons.notes_outlined),
            alignLabelWithHint: true,
          ),
          validator: validateNote,
        ),
      ],
    );
  }
}

class _EmploymentStep extends StatelessWidget {
  const _EmploymentStep({
    required this.incomeController,
    required this.occupationController,
    required this.enabled,
    required this.validateIncome,
    required this.validateOccupation,
  });

  final TextEditingController incomeController;
  final TextEditingController occupationController;
  final bool enabled;
  final FormFieldValidator<String> validateIncome;
  final FormFieldValidator<String> validateOccupation;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader(
        title: 'Employment/Financial',
        subtitle: 'Information used in the rental application.',
      ),
      const SizedBox(height: AppSpacing.md),
      TextFormField(
        key: const ValueKey('application-occupation'),
        controller: occupationController,
        enabled: enabled,
        maxLength: 200,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Occupation',
          prefixIcon: Icon(Icons.work_outline),
        ),
        validator: validateOccupation,
      ),
      const SizedBox(height: AppSpacing.base),
      TextFormField(
        key: const ValueKey('application-income'),
        controller: incomeController,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: const InputDecoration(
          labelText: 'Monthly income',
          prefixIcon: Icon(Icons.payments_outlined),
        ),
        validator: validateIncome,
      ),
    ],
  );
}

class _DocumentsStep extends StatelessWidget {
  const _DocumentsStep({required this.hasDraft, this.onOpenDocuments});

  final bool hasDraft;
  final VoidCallback? onOpenDocuments;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader(
        title: 'Documents',
        subtitle: 'Supporting files are managed per application.',
      ),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        child: Column(
          children: [
            const Icon(
              Icons.folder_outlined,
              size: 42,
              color: AppPalette.olive,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasDraft
                  ? 'Your draft is ready for document management.'
                  : 'Save a draft before adding documents.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No document is uploaded or validated from this form step.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onOpenDocuments != null) ...[
              const SizedBox(height: AppSpacing.base),
              OutlinedButton.icon(
                onPressed: onOpenDocuments,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Manage documents'),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.propertyId,
    required this.moveInDate,
    required this.occupation,
    required this.income,
    required this.occupants,
    required this.note,
  });

  final String propertyId;
  final DateTime? moveInDate;
  final String occupation;
  final String income;
  final String occupants;
  final String note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader(
        title: 'Review & Submit',
        subtitle: 'Confirm the real values that will be sent to RentFlow.',
      ),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        child: Column(
          children: [
            _ReferenceRow(label: 'Property', value: propertyId),
            const Divider(height: AppSpacing.lg),
            _ReferenceRow(
              label: 'Move-in date',
              value: moveInDate == null
                  ? 'Not selected'
                  : MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(moveInDate!),
            ),
            const Divider(height: AppSpacing.lg),
            _ReferenceRow(label: 'Occupation', value: occupation),
            const Divider(height: AppSpacing.lg),
            _ReferenceRow(label: 'Monthly income', value: income),
            const Divider(height: AppSpacing.lg),
            _ReferenceRow(label: 'Occupants', value: occupants),
            const Divider(height: AppSpacing.lg),
            _ReferenceRow(
              label: 'Landlord note',
              value: note.isEmpty ? 'No note added.' : note,
            ),
          ],
        ),
      ),
    ],
  );
}

class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 104,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppPalette.muted),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppPalette.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _NavigationActions extends StatelessWidget {
  const _NavigationActions({
    required this.currentStep,
    required this.lastStep,
    required this.isBusy,
    required this.onBack,
    required this.onNext,
  });

  final int currentStep;
  final int lastStep;
  final bool isBusy;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (currentStep > 0)
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isBusy ? null : onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        ),
      if (currentStep > 0 && currentStep < lastStep)
        const SizedBox(width: AppSpacing.md),
      if (currentStep < lastStep)
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('application-next-step'),
            onPressed: isBusy ? null : onNext,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ),
    ],
  );
}

class _FormError extends StatelessWidget {
  const _FormError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('application-form-error'),
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

class _ButtonProgressIndicator extends StatelessWidget {
  const _ButtonProgressIndicator();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2, color: AppPalette.white),
  );
}
