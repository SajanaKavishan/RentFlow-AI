import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../widgets/tenant_maintenance_ui.dart';
import '../../auth/controllers/auth_controller.dart';
import '../models/maintenance_request.dart';
import '../services/maintenance_api_service.dart';

class CreateMaintenanceRequestScreen extends StatefulWidget {
  const CreateMaintenanceRequestScreen({
    super.key,
    required this.propertyId,
    this.maintenanceApiService,
  });

  final String propertyId;
  final MaintenanceApiService? maintenanceApiService;

  @override
  State<CreateMaintenanceRequestScreen> createState() =>
      _CreateMaintenanceRequestScreenState();
}

class _CreateMaintenanceRequestScreenState
    extends State<CreateMaintenanceRequestScreen> {
  static const _olive = AppPalette.darkOlive;
  static const _warmBackground = AppPalette.warmCream;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tenantAccessNotesController = TextEditingController();

  ApiClient? _ownedApiClient;
  late final MaintenanceApiService _maintenanceApiService;

  MaintenanceCategory _selectedCategory = MaintenanceCategory.plumbing;
  MaintenancePriority _selectedPriority = MaintenancePriority.normal;
  bool _isSubmitting = false;
  String? _errorMessage;
  MaintenanceRequest? _created;

  @override
  void initState() {
    super.initState();
    if (widget.maintenanceApiService case final service?) {
      _maintenanceApiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _maintenanceApiService = MaintenanceApiService(_ownedApiClient!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tenantAccessNotesController.dispose();
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) {
      return;
    }

    final currentUser = AuthScope.of(context).currentUser;
    if (currentUser == null) {
      setState(
        () => _errorMessage =
            'You must be signed in to create a maintenance request.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final created = await _maintenanceApiService.createMaintenanceRequest(
        tenantId: currentUser.id,
        propertyId: widget.propertyId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        priority: _selectedPriority,
        tenantAccessNotes: _tenantAccessNotesController.text.trim().isEmpty
            ? null
            : _tenantAccessNotesController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _created = created);
    } on MaintenanceApiException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(error.message),
              backgroundColor: Colors.red.shade700,
            ),
          );
      }
    } catch (_) {
      if (mounted) {
        const message = 'Unable to create the maintenance request right now.';
        setState(() => _errorMessage = message);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _newRequest() {
    setState(() {
      _created = null;
      _errorMessage = null;
      _titleController.clear();
      _descriptionController.clear();
      _tenantAccessNotesController.clear();
      _selectedCategory = MaintenanceCategory.plumbing;
      _selectedPriority = MaintenancePriority.normal;
    });
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(
      text,
      style: AppTypography.sectionTitle.copyWith(color: AppPalette.primaryText),
    ),
  );

  Color _priorityBackground(MaintenancePriority priority) => switch (priority) {
    MaintenancePriority.emergency => const Color(0xFFF8EAE7),
    MaintenancePriority.high => const Color(0xFFFFF4D8),
    MaintenancePriority.normal ||
    MaintenancePriority.low => AppPalette.progress,
  };

  Color _priorityColor(MaintenancePriority priority) => switch (priority) {
    MaintenancePriority.emergency => AppPalette.danger,
    MaintenancePriority.high => AppPalette.warning,
    MaintenancePriority.normal || MaintenancePriority.low => AppPalette.olive,
  };

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    alignLabelWithHint: true,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppPalette.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppPalette.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _olive),
    ),
  );

  Widget _success(MaintenanceRequest request) {
    final localDate = request.createdAt.toLocal();
    final rows = <(String, String)>[
      ('Request ID', request.id),
      ('Category', maintenanceLabel(request.category)),
      ('Priority', maintenanceLabel(request.priority)),
      ('Status', maintenanceLabel(request.status)),
      (
        'Submitted',
        '${MaterialLocalizations.of(context).formatMediumDate(localDate)} \u00b7 ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(localDate))}',
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Center(
            child: CircleAvatar(
              radius: 26,
              backgroundColor: Color(0xFFEAF2E5),
              child: Icon(Icons.check, color: AppPalette.success, size: 28),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Request submitted',
            textAlign: TextAlign.center,
            style: AppTypography.pageTitle.copyWith(
              color: AppPalette.primaryText,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your maintenance request has been logged.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppPalette.secondaryText),
          ),
          const SizedBox(height: 20),
          MaintenanceSurface(
            selected: true,
            radius: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  request.title,
                  style: AppTypography.cardTitle.copyWith(
                    color: AppPalette.primaryText,
                  ),
                ),
                const SizedBox(height: 12),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.$1,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppPalette.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          row.$2,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            style: _buttonStyle,
            onPressed: () => Navigator.of(context).pop(request),
            child: const Text('Track Request'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _olive,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _newRequest,
            child: const Text('New Request'),
          ),
        ],
      ),
    );
  }

  ButtonStyle get _buttonStyle => FilledButton.styleFrom(
    backgroundColor: _olive,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    minimumSize: const Size.fromHeight(52),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(_created),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppPalette.primaryText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _created == null
                            ? 'Maintenance request'
                            : 'Maintenance',
                        style: AppTypography.pageTitle.copyWith(
                          color: AppPalette.primaryText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _created != null
                  ? _success(_created!)
                  : SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _heading('What needs attention?'),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final columns =
                                    MediaQuery.textScalerOf(context).scale(1) >
                                        1.3
                                    ? 2
                                    : 4;
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final category
                                        in MaintenanceCategory.values)
                                      SizedBox(
                                        width:
                                            (constraints.maxWidth -
                                                8 * (columns - 1)) /
                                            columns,
                                        child: Semantics(
                                          label: maintenanceLabel(category),
                                          selected:
                                              category == _selectedCategory,
                                          button: true,
                                          child: InkWell(
                                            key: ValueKey(
                                              'category-${category.name}',
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              13,
                                            ),
                                            onTap: _isSubmitting
                                                ? null
                                                : () => setState(
                                                    () => _selectedCategory =
                                                        category,
                                                  ),
                                            child: MaintenanceSurface(
                                              selected:
                                                  category == _selectedCategory,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 12,
                                                  ),
                                              radius: 13,
                                              child: Column(
                                                children: [
                                                  Icon(
                                                    maintenanceCategoryIcon(
                                                      category,
                                                    ),
                                                    color: _olive,
                                                    size: 22,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    maintenanceLabel(category),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppPalette
                                                          .primaryText,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                            _heading('Priority level'),
                            for (final priority
                                in MaintenancePriority.values.reversed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Semantics(
                                  checked: priority == _selectedPriority,
                                  inMutuallyExclusiveGroup: true,
                                  label: maintenanceLabel(priority),
                                  child: InkWell(
                                    key: ValueKey('priority-${priority.name}'),
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: _isSubmitting
                                        ? null
                                        : () => setState(
                                            () => _selectedPriority = priority,
                                          ),
                                    child: MaintenanceSurface(
                                      selected: priority == _selectedPriority,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      selectedBackground: _priorityBackground(
                                        priority,
                                      ),
                                      selectedBorder: _priorityColor(priority),
                                      child: Row(
                                        children: [
                                          Icon(
                                            priority == _selectedPriority
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_off,
                                            color: _priorityColor(priority),
                                            size: 22,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              maintenanceLabel(priority),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    priority ==
                                                        MaintenancePriority
                                                            .emergency
                                                    ? AppPalette.danger
                                                    : AppPalette.primaryText,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            _heading('Describe the issue'),
                            TextFormField(
                              controller: _titleController,
                              enabled: !_isSubmitting,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: _decoration(
                                'Title',
                                hint: 'A short summary of the issue',
                              ),
                              validator: (value) =>
                                  (value?.trim() ?? '').isEmpty
                                  ? 'Please enter a title.'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _descriptionController,
                              enabled: !_isSubmitting,
                              minLines: 4,
                              maxLines: 8,
                              maxLength: 2000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: _decoration(
                                'Description',
                                hint:
                                    'Describe what is happening and where the issue is.',
                              ),
                              validator: (value) =>
                                  (value?.trim() ?? '').isEmpty
                                  ? 'Please describe the issue.'
                                  : null,
                            ),
                            _heading('Access notes (optional)'),
                            TextFormField(
                              controller: _tenantAccessNotesController,
                              enabled: !_isSubmitting,
                              minLines: 2,
                              maxLines: 5,
                              maxLength: 1000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: _decoration(
                                'Tenant access notes (optional)',
                                hint:
                                    'Share any access instructions for this property.',
                              ),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 14),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: AppPalette.danger,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _isSubmitting ? null : _submit,
                              style: _buttonStyle,
                              child: _isSubmitting
                                  ? const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Flexible(
                                          child: Text('Submitting request...'),
                                        ),
                                      ],
                                    )
                                  : const Text('Submit Request'),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
