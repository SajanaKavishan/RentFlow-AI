import 'package:flutter/material.dart';
import '../../../shared/follow_up/follow_up_activity.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../application_documents/models/application_document.dart';
import '../../application_documents/screens/application_documents_screen.dart';
import '../../application_documents/services/application_document_api_service.dart';
import '../../application_documents/widgets/document_requirement_badge.dart';
import '../../auth/models/current_user.dart';
import '../../auth/services/auth_service.dart';
import '../../properties/services/property_api_service.dart';
import '../models/rental_application.dart';
import '../services/rental_application_api_service.dart';
import '../widgets/application_wizard_widgets.dart';
import '../widgets/tenant_application_journey.dart';
import 'rental_application_details_screen.dart';

class RentalApplicationFormScreen extends StatefulWidget {
  const RentalApplicationFormScreen({
    super.key,
    required this.propertyId,
    this.propertyTitle,
    this.application,
    this.rentalApplicationApiService,
    this.returnToApplicationDetails = false,
  });
  final String propertyId;
  final String? propertyTitle;
  final RentalApplication? application;
  final RentalApplicationApiService? rentalApplicationApiService;
  final bool returnToApplicationDetails;
  @override
  State<RentalApplicationFormScreen> createState() =>
      _RentalApplicationFormScreenState();
}

class _RentalApplicationFormScreenState
    extends State<RentalApplicationFormScreen> {
  static const _titles = [
    'Personal information',
    'Financial information',
    'Documents information',
    'Review information',
  ];
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _income = TextEditingController();
  final _occupation = TextEditingController();
  final _occupants = TextEditingController(text: '1');
  final _note = TextEditingController();
  ApiClient? _ownedApiClient;
  late final RentalApplicationApiService _api;
  late final ApplicationDocumentApiService _documentApi;
  RentalApplication? _application;
  CurrentUser? _profile;
  String? _propertyTitle;
  DateTime? _moveInDate;
  List<ApplicationDocument> _documents = const [];
  int _step = 0;
  bool _loading = true;
  bool _ready = false;
  bool _saving = false;
  bool _submitting = false;
  bool _documentsLoading = false;
  bool _openingDocuments = false;
  bool _allowExit = false;
  String? _loadError;
  String? _error;
  String? _dateError;
  String? _documentsError;

  bool get _busy => _loading || _saving || _submitting || _openingDocuments;
  bool get _canEdit =>
      _ready &&
      (_application == null ||
          _application!.status == RentalApplicationStatus.draft ||
          _application!.status == RentalApplicationStatus.changesRequested);

  @override
  void initState() {
    super.initState();
    _application = widget.application;
    _propertyTitle = widget.propertyTitle;
    if (widget.rentalApplicationApiService case final service?) {
      _api = service;
    } else {
      _ownedApiClient = ApiClient();
      _api = RentalApplicationApiService(_ownedApiClient!);
    }
    _documentApi = ApplicationDocumentApiService(_api.apiClient);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _income.dispose();
    _occupation.dispose();
    _occupants.dispose();
    _note.dispose();
    _ownedApiClient?.close();
    super.dispose();
  }

  void _checkIdentity(RentalApplication application) {
    final expected = _application ?? widget.application;
    if (application.propertyId != widget.propertyId ||
        (expected != null &&
            (application.id != expected.id ||
                application.tenantId != expected.tenantId))) {
      throw const RentalApplicationApiException(
        'The application service returned an invalid response.',
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _ready = false;
      _loadError = null;
    });
    try {
      if (widget.propertyId.trim().isEmpty) {
        throw const RentalApplicationApiException(
          'A real property reference is required to apply.',
        );
      }
      if (widget.application case final seed?) {
        final application = await _api.getApplicationById(seed.id);
        _checkIdentity(application);
        if (!mounted) return;
        _application = application;
        _prefill(application);
      } else {
        final eligibility = await _api.getEligibility(widget.propertyId);
        if (eligibility.hasExistingApplication) {
          final application = await _api.getApplicationById(
            eligibility.existingApplicationId!,
          );
          _checkIdentity(application);
          if (!mounted) return;
          _application = application;
          _prefill(application);
        } else if (!eligibility.canApply) {
          throw RentalApplicationApiException(
            eligibility.reason ??
                'Complete a viewing before applying for this property.',
          );
        }
      }
      await Future.wait([_loadProfile(), _loadPropertyTitle()]);
      if (_application != null) await _refreshDocuments();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _step = _resumeStep();
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _loadError = _message(
            error,
            'Unable to load your application. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await AuthService(_api.apiClient).getCurrentUser();
      if (mounted &&
          profile.role == UserRole.tenant &&
          (_application == null || profile.id == _application!.tenantId)) {
        _profile = profile;
      }
    } catch (_) {
      // Optional account data never substitutes for saved application fields.
    }
  }

  Future<void> _loadPropertyTitle() async {
    try {
      final property = await PropertyApiService(
        _api.apiClient,
      ).getPropertyById(widget.propertyId);
      if (mounted && property.id == widget.propertyId) {
        _propertyTitle = property.title;
      }
    } catch (_) {
      // A previously fetched real title can still provide property context.
    }
  }

  void _prefill(RentalApplication application) {
    _moveInDate = application.moveInDate;
    _income.text = application.monthlyIncome.toString();
    _occupation.text = application.occupation;
    _occupants.text = application.numberOfOccupants.toString();
    _note.text = application.tenantNote ?? '';
  }

  String? _incomeError(String? value) {
    final income = double.tryParse(value?.trim() ?? '');
    return income == null || !income.isFinite || income <= 0
        ? 'Enter a monthly income greater than 0.'
        : null;
  }

  String? _occupationError(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty
        ? 'Enter your occupation.'
        : text.length > 200
        ? 'Use 200 characters or fewer.'
        : null;
  }

  String? _occupantsError(String? value) {
    final count = int.tryParse(value?.trim() ?? '');
    return count == null || count < 1 ? 'Enter at least 1 occupant.' : null;
  }

  String? _noteError(String? value) => (value ?? '').trim().length > 1000
      ? 'Use 1000 characters or fewer.'
      : null;
  bool _futureDate(DateTime? date) {
    final now = DateTime.now();
    return date != null && date.isAfter(DateTime(now.year, now.month, now.day));
  }

  bool _personalComplete(RentalApplication? application) =>
      application != null &&
      _futureDate(application.moveInDate) &&
      application.numberOfOccupants >= 1 &&
      _noteError(application.tenantNote) == null;
  bool _financialComplete(RentalApplication? application) =>
      application != null &&
      _incomeError(application.monthlyIncome.toString()) == null &&
      _occupationError(application.occupation) == null;
  bool get _documentsComplete =>
      _application != null &&
      !_documentsLoading &&
      _documentsError == null &&
      ApplicationDocumentType.values
          .where((type) => type.requirement == DocumentRequirement.required)
          .every(
            (type) =>
                _documents.any((document) => document.documentType == type),
          );
  int _resumeStep() {
    final application = _application;
    if (application != null &&
        application.status != RentalApplicationStatus.draft &&
        application.status != RentalApplicationStatus.changesRequested) {
      return 3;
    }
    if (!_personalComplete(application)) return 0;
    if (!_financialComplete(application)) return 1;
    if (!_documentsComplete) return 2;
    // Only a generic landlord message is available; never infer a section from it.
    return application!.status == RentalApplicationStatus.changesRequested
        ? 0
        : 3;
  }

  bool get _personalMatchesSaved =>
      _application != null &&
      _moveInDate == _application!.moveInDate &&
      int.tryParse(_occupants.text.trim()) == _application!.numberOfOccupants &&
      _note.text.trim() == (_application!.tenantNote ?? '').trim();
  bool get _financialMatchesSaved =>
      _application != null &&
      double.tryParse(_income.text.trim()) == _application!.monthlyIncome &&
      _occupation.text.trim() == _application!.occupation.trim();
  bool get _dirty =>
      _ready &&
      (_application == null
          ? _moveInDate != null ||
                _occupants.text != '1' ||
                _note.text.isNotEmpty ||
                _income.text.isNotEmpty ||
                _occupation.text.isNotEmpty
          : _canEdit && (!_personalMatchesSaved || !_financialMatchesSaved));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _futureDate(_moveInDate) ? _moveInDate! : tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 5, now.month, now.day),
      helpText: 'Choose your move-in date',
    );
    if (picked != null && mounted) {
      setState(() {
        _moveInDate = picked;
        _dateError = null;
      });
    }
  }

  bool _validatePersonal() {
    final valid = _futureDate(_moveInDate);
    setState(() => _dateError = valid ? null : 'Choose a future move-in date.');
    return valid &&
        _occupantsError(_occupants.text) == null &&
        _noteError(_note.text) == null;
  }

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _next() async {
    if (_busy || !_canEdit) return;
    final fieldsValid = _formKey.currentState?.validate() ?? false;
    if (_step == 0) {
      final personalValid = _validatePersonal();
      if (!fieldsValid || !personalValid) return;
      if (_application == null || !_financialComplete(_application)) {
        // Every create/update requires both sections in the existing contract.
        // Keep Personal in memory until Financial can save the sections together.
        _goTo(1);
        return;
      }
      if (await _persist(0) && mounted) _goTo(1);
    } else if (_step == 1) {
      if (!fieldsValid) return;
      if (!_validatePersonal()) {
        _goTo(0);
        setState(
          () => _error = 'Check your personal information before saving.',
        );
        return;
      }
      if (await _persist(1) && mounted) {
        _goTo(2);
        await _refreshDocuments();
      }
    } else if (_step == 2) {
      if (!_documentsComplete) {
        setState(
          () => _error = _documentsError != null
              ? 'Reload your documents before continuing.'
              : 'Upload the required Identity Document and Income Proof before continuing.',
        );
        return;
      }
      _goTo(3);
    }
  }

  Future<bool> _persist(int step) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var existing = _application;
      if (existing != null) {
        final fresh = await _api.getApplicationById(existing.id);
        _checkIdentity(fresh);
        if (!mounted) return false;
        setState(() => _application = fresh);
        existing = fresh;
        if (!_canEdit) {
          setState(() => _step = 3);
          throw const RentalApplicationApiException(
            'This application can no longer be edited. View its details for the latest status.',
          );
        }
      }
      final income = step == 0 && existing != null
          ? existing.monthlyIncome
          : double.parse(_income.text.trim());
      final occupation = step == 0 && existing != null
          ? existing.occupation
          : _occupation.text.trim();
      final note = _note.text.trim();
      final saved = existing == null
          ? await _api.createApplication(
              propertyId: widget.propertyId,
              moveInDate: _moveInDate!,
              monthlyIncome: income,
              occupation: occupation,
              numberOfOccupants: int.parse(_occupants.text.trim()),
              tenantNote: note.isEmpty ? null : note,
            )
          : await _api.updateApplication(
              id: existing.id,
              moveInDate: _moveInDate!,
              monthlyIncome: income,
              occupation: occupation,
              numberOfOccupants: int.parse(_occupants.text.trim()),
              tenantNote: note.isEmpty ? null : note,
            );
      _checkIdentity(saved);
      if (!mounted) return false;
      setState(() => _application = saved);
      return true;
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _message(
            error,
            'Could not save your application. Your entered values are still here; please try again.',
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshDocuments() async {
    final application = _application;
    if (application == null || !mounted || _documentsLoading) return;
    setState(() {
      _documentsLoading = true;
      _documentsError = null;
    });
    try {
      final documents = await _documentApi.getDocumentsForApplication(
        applicationId: application.id,
      );
      if (documents.any(
        (document) => document.applicationId != application.id,
      )) {
        throw const ApplicationDocumentApiException(
          'The document service returned an invalid response.',
        );
      }
      if (mounted) setState(() => _documents = documents);
    } catch (error) {
      if (mounted) {
        setState(
          () => _documentsError = _message(
            error,
            'Unable to load documents. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _documentsLoading = false);
    }
  }

  Future<void> _openDocuments(ApplicationDocumentType type) async {
    final application = _application;
    if (application == null || _busy) return;
    setState(() => _openingDocuments = true);
    final hadEdits = _dirty;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ApplicationDocumentsScreen(
            applicationId: application.id,
            initialDocumentType: type,
            rentalApplicationApiService: _api,
            applicationDocumentApiService: _documentApi,
          ),
        ),
      );
      if (!mounted) return;
      final fresh = await _api.getApplicationById(application.id);
      _checkIdentity(fresh);
      if (!mounted) return;
      setState(() {
        _application = fresh;
        if (!hadEdits) _prefill(fresh);
        if (!_canEdit) _step = 3;
      });
      await _refreshDocuments();
    } catch (error) {
      if (mounted) {
        setState(
          () => _documentsError = _message(
            error,
            'Unable to refresh this application. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingDocuments = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_canEdit) return;
    if (!_validatePersonal()) {
      _goTo(0);
      return;
    }
    if (_incomeError(_income.text) != null ||
        _occupationError(_occupation.text) != null) {
      _goTo(1);
      return;
    }
    if (!_documentsComplete) {
      _goTo(2);
      return;
    }
    setState(() => _submitting = true);
    try {
      // Include edits made after navigating back from Review.
      if (!await _persist(1) || !mounted) return;
      await _refreshDocuments();
      if (!mounted) return;
      if (!_documentsComplete) {
        _goTo(2);
        setState(
          () => _error = 'Check your required documents before submitting.',
        );
        return;
      }
      final submitted = await _api.submitApplication(id: _application!.id);
      _checkIdentity(submitted);
      if (!mounted) return;
      setState(() => _application = submitted);
      await _showDetails();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _message(
            error,
            'Unable to submit your application. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showDetails() async {
    final application = _application;
    if (application == null) return;
    setState(() => _allowExit = true);
    if (widget.returnToApplicationDetails && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RentalApplicationDetailsScreen(
          application: application,
          rentalApplicationApiService: _api,
          applicationDocumentApiService: _documentApi,
        ),
      ),
    );
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _back() async {
    if (_busy) return;
    if (_step > 0 && _canEdit) {
      _goTo(_step - 1);
      return;
    }
    if (_dirty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Leave without saving?'),
          content: const Text(
            'Your saved application will be kept. Changes entered since your last save will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    setState(() => _allowExit = true);
    Navigator.of(context).pop();
  }

  String _message(Object error, String fallback) => switch (error) {
    RentalApplicationApiException(:final message) => message,
    ApplicationDocumentApiException(:final message) => message,
    _ => fallback,
  };

  @override
  Widget build(BuildContext context) => FollowUpPause(
    child: PopScope(
      canPop: _allowExit || (!_busy && (!_canEdit || (_step == 0 && !_dirty))),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppPalette.warmCream,
        body: SafeArea(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Form(
                  key: _formKey,
                  onChanged: () => setState(() {}),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TenantApplicationHeader(
                        eyebrow: 'RENTAL APPLICATION',
                        title: _titles[_step],
                        titleStyle: AppTypography.pageTitle.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.darkOlive,
                        ),
                        onBack: _back,
                      ),
                      const SizedBox(height: 16),
                      if (_loading)
                        const LoadingState(
                          title: 'Loading application',
                          compact: true,
                        ),
                      if (_loadError != null)
                        SharedState(
                          title: 'Could not load application',
                          message: _loadError!,
                          actionLabel: 'Try again',
                          onAction: _load,
                          compact: true,
                        ),
                      if (_ready) ...[
                        ApplicationWizardProgress(
                          currentStep: _step,
                          completed: [
                            _personalComplete(_application) &&
                                _personalMatchesSaved,
                            _financialComplete(_application) &&
                                _financialMatchesSaved,
                            _documentsComplete,
                            _application != null && !_canEdit,
                          ],
                          onSelect: _busy || !_canEdit ? null : _goTo,
                        ),
                        const SizedBox(height: 20),
                        if (_application?.status ==
                            RentalApplicationStatus.changesRequested) ...[
                          TenantApplicationCard(
                            actionRequired: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Changes requested', style: wizardLabel),
                                const SizedBox(height: 6),
                                Text(
                                  _application!.landlordResponse
                                              ?.trim()
                                              .isNotEmpty ==
                                          true
                                      ? _application!.landlordResponse!.trim()
                                      : 'The landlord requested updates but did not provide a message.',
                                  style: AppTypography.body,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (!_canEdit) ...[
                          Text(
                            'This application can no longer be edited.',
                            style: wizardHelper,
                          ),
                          const SizedBox(height: 12),
                          TenantApplicationStatusChip(
                            status: _application!.status,
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildStep(),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              key: const ValueKey('application-form-error'),
                              style: wizardHelper.copyWith(
                                color: AppPalette.danger,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (_saving || _submitting) ...[
                          const LinearProgressIndicator(
                            key: ValueKey('application-form-progress'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        FilledButton(
                          key: ValueKey(
                            !_canEdit
                                ? 'view-application-details'
                                : _step == 3
                                ? 'submit-application'
                                : 'application-next-step',
                          ),
                          onPressed: _busy
                              ? null
                              : !_canEdit
                              ? _showDetails
                              : _step == 3
                              ? _submit
                              : _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppPalette.darkOlive,
                            foregroundColor: AppPalette.white,
                            minimumSize: const Size.fromHeight(48),
                            padding: const EdgeInsets.all(14),
                            textStyle: AppTypography.button.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _submitting
                                ? 'Submitting…'
                                : _saving
                                ? 'Saving…'
                                : !_canEdit
                                ? 'View details'
                                : _step == 3
                                ? _application?.status ==
                                          RentalApplicationStatus
                                              .changesRequested
                                      ? 'Resubmit application'
                                      : 'Submit application'
                                : 'Continue',
                          ),
                        ),
                        if (_step < 2 && _application == null) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Your draft is saved after Personal and Financial information are complete.',
                            style: wizardHelper,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _buildStep() => switch (_step) {
    0 => _personal(),
    1 => _financial(),
    2 => _documentStep(),
    _ => _review(),
  };
  Widget _personal() => TenantApplicationCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_profile != null) ...[
          ApplicationWizardValue(label: 'Full name', value: _profile!.fullName),
          ApplicationWizardValue(
            label: 'Phone number',
            value: _profile!.phoneNumber,
          ),
          Text('Contact details from your account.', style: wizardHelper),
          const Divider(height: 24),
        ],
        Text('Move-in date', style: wizardLabel),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('application-move-in-date'),
          onPressed: _busy || !_canEdit ? null : _pickDate,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            alignment: Alignment.centerLeft,
          ),
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(
            _moveInDate == null
                ? 'Select a date'
                : MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(_moveInDate!),
          ),
        ),
        if (_dateError != null)
          Text(
            _dateError!,
            style: wizardHelper.copyWith(color: AppPalette.danger),
          ),
        const SizedBox(height: 16),
        ApplicationWizardField(
          key: const ValueKey('application-occupants'),
          label: 'Number of occupants',
          controller: _occupants,
          enabled: _canEdit && !_busy,
          keyboardType: TextInputType.number,
          validator: _occupantsError,
        ),
        const SizedBox(height: 16),
        ApplicationWizardField(
          key: const ValueKey('application-note'),
          label: 'Note to the landlord (optional)',
          controller: _note,
          enabled: _canEdit && !_busy,
          maxLength: 1000,
          maxLines: 3,
          validator: _noteError,
        ),
      ],
    ),
  );
  Widget _financial() => TenantApplicationCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ApplicationWizardField(
          key: const ValueKey('application-occupation'),
          label: 'Occupation',
          controller: _occupation,
          enabled: _canEdit && !_busy,
          maxLength: 200,
          validator: _occupationError,
        ),
        const SizedBox(height: 16),
        ApplicationWizardField(
          key: const ValueKey('application-income'),
          label: 'Monthly income',
          controller: _income,
          enabled: _canEdit && !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: _incomeError,
        ),
        const SizedBox(height: 8),
        Text(
          'Information used in the rental application.',
          style: wizardHelper,
        ),
      ],
    ),
  );
  Widget _documentStep() => TenantApplicationCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Add supporting documents', style: wizardLabel),
        const SizedBox(height: 12),
        if (_documentsLoading)
          const LoadingState(title: 'Loading documents', compact: true)
        else if (_documentsError != null) ...[
          Text(_documentsError!, style: wizardHelper),
          TextButton(
            onPressed: _busy ? null : _refreshDocuments,
            child: const Text('Reload documents'),
          ),
        ] else ...[
          for (final type in ApplicationDocumentType.values) ...[
            ApplicationWizardDocumentRow(
              type: type,
              documents: _documents,
              onOpen: _application == null || _busy
                  ? null
                  : () => _openDocuments(type),
            ),
            if (type != ApplicationDocumentType.values.last)
              const SizedBox(height: 10),
          ],
        ],
      ],
    ),
  );
  Widget _review() {
    final saved = !_canEdit ? _application : null;
    final date = saved?.moveInDate ?? _moveInDate;
    final note = saved == null
        ? _note.text.trim()
        : (saved.tenantNote ?? '').trim();
    return TenantApplicationCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            saved == null ? 'Review before submitting' : 'Saved application',
            style: wizardLabel,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppPalette.softCream,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _propertyTitle?.trim().isNotEmpty == true
                      ? _propertyTitle!
                      : 'Selected property',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your application details and uploaded documents will be shared with the landlord for review.',
                  style: wizardHelper,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_profile != null)
            ApplicationWizardValue(
              label: 'Applicant',
              value: _profile!.fullName,
            ),
          ApplicationWizardValue(
            label: 'Move-in date',
            value: date == null
                ? 'Not selected'
                : MaterialLocalizations.of(context).formatMediumDate(date),
          ),
          ApplicationWizardValue(
            label: 'Occupants',
            value: saved?.numberOfOccupants.toString() ?? _occupants.text,
          ),
          ApplicationWizardValue(
            label: 'Occupation',
            value: saved?.occupation ?? _occupation.text,
          ),
          ApplicationWizardValue(
            label: 'Monthly income',
            value: saved?.monthlyIncome.toString() ?? _income.text,
          ),
          if (note.isNotEmpty)
            ApplicationWizardValue(label: 'Your note', value: note),
          ApplicationWizardValue(
            label: 'Documents',
            value: _documentsLoading
                ? 'Loading documents'
                : _documentsError != null
                ? 'Document summary unavailable'
                : '${_documents.length} uploaded',
          ),
        ],
      ),
    );
  }
}
