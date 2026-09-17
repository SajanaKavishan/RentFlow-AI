import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../models/rental_application.dart';
import '../services/rental_application_api_service.dart';
import '../widgets/rental_application_status_chip.dart';

class RentalApplicationFormScreen extends StatefulWidget {
  const RentalApplicationFormScreen({
    super.key,
    required this.propertyId,
    this.rentalApplicationApiService,
  });

  final String propertyId;
  final RentalApplicationApiService? rentalApplicationApiService;

  @override
  State<RentalApplicationFormScreen> createState() =>
      _RentalApplicationFormScreenState();
}

class _RentalApplicationFormScreenState
    extends State<RentalApplicationFormScreen> {
  static const _olive = Color(0xFF5D6842);
  static const _warmBackground = Color(0xFFF7F5EF);

  final _formKey = GlobalKey<FormState>();
  final _incomeController = TextEditingController();
  final _occupationController = TextEditingController();
  final _occupantsController = TextEditingController(text: '1');
  final _noteController = TextEditingController();

  ApiClient? _ownedApiClient;
  late final RentalApplicationApiService _apiService;
  DateTime? _moveInDate;
  RentalApplication? _application;
  bool _isSaving = false;
  bool _isSubmitting = false;

  bool get _isBusy => _isSaving || _isSubmitting;

  @override
  void initState() {
    super.initState();
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
      initialDate: _moveInDate ?? tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 5, now.month, now.day),
      helpText: 'Choose your move-in date',
    );
    if (selected != null && mounted) {
      setState(() {
        _moveInDate = selected;
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

  bool _validateMoveInDate() {
    final date = _moveInDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (date == null || !date.isAfter(today)) {
      _showMessage('Choose a future move-in date.', isError: true);
      return false;
    }
    return true;
  }

  Future<void> _createDraft() async {
    if (_isBusy || _application != null) return;
    if (!_formKey.currentState!.validate() || !_validateMoveInDate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });
    try {
      final note = _noteController.text.trim();
      final created = await _apiService.createApplication(
        propertyId: widget.propertyId,
        moveInDate: _moveInDate!,
        monthlyIncome: double.parse(_incomeController.text.trim()),
        occupation: _occupationController.text.trim(),
        numberOfOccupants: int.parse(_occupantsController.text.trim()),
        tenantNote: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      setState(() {
        _application = created;
      });
      _showMessage('Draft application created.');
    } on RentalApplicationApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to create your application right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _submitDraft() async {
    final application = _application;
    if (_isBusy || application?.status != RentalApplicationStatus.draft) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });
    try {
      final submitted = await _apiService.submitApplication(
        id: application!.id,
      );
      if (!mounted) return;
      setState(() {
        _application = submitted;
      });
      _showMessage('Application submitted successfully.');
    } on RentalApplicationApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to submit your application right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade700 : _olive,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final application = _application;
    final dateLabel = _moveInDate == null
        ? 'Select a date'
        : MaterialLocalizations.of(context).formatMediumDate(_moveInDate!);

    return Scaffold(
      backgroundColor: _warmBackground,
      appBar: AppBar(
        backgroundColor: _olive,
        foregroundColor: Colors.white,
        title: const Text('Rental Application'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Apply for this property',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF313828),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  application == null
                      ? 'Save your details as a draft, then submit when ready.'
                      : 'Your application has been saved.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                ),
                if (application != null) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: RentalApplicationStatusChip(
                      status: application.status,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Card(
                  color: Colors.white,
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(
                      Icons.calendar_today_outlined,
                      color: _olive,
                    ),
                    title: const Text('Move-in date'),
                    subtitle: Text(dateLabel),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: application == null && !_isBusy,
                    onTap: application == null && !_isBusy
                        ? _pickMoveInDate
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _incomeController,
                  enabled: application == null && !_isBusy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: _fieldDecoration(
                    'Monthly income',
                    Icons.payments_outlined,
                  ),
                  validator: _validateIncome,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _occupationController,
                  enabled: application == null && !_isBusy,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.words,
                  decoration: _fieldDecoration(
                    'Occupation',
                    Icons.work_outline,
                  ),
                  validator: _validateOccupation,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _occupantsController,
                  enabled: application == null && !_isBusy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _fieldDecoration(
                    'Number of occupants',
                    Icons.people_outline,
                  ),
                  validator: _validateOccupants,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _noteController,
                  enabled: application == null && !_isBusy,
                  maxLines: 4,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _fieldDecoration(
                    'Note to the landlord (optional)',
                    Icons.notes_outlined,
                  ).copyWith(alignLabelWithHint: true),
                  validator: _validateNote,
                ),
                const SizedBox(height: 24),
                if (application == null)
                  FilledButton(
                    onPressed: _isBusy ? null : _createDraft,
                    style: _primaryButtonStyle,
                    child: _isSaving
                        ? const _ButtonProgressIndicator()
                        : const Text('Save draft'),
                  )
                else if (application.status == RentalApplicationStatus.draft)
                  FilledButton(
                    onPressed: _isBusy ? null : _submitDraft,
                    style: _primaryButtonStyle,
                    child: _isSubmitting
                        ? const _ButtonProgressIndicator()
                        : const Text('Submit application'),
                  )
                else
                  const Card(
                    color: Color(0xFFECEFDF),
                    elevation: 0,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Your application has been submitted for review.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _olive),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  ButtonStyle get _primaryButtonStyle => FilledButton.styleFrom(
    backgroundColor: _olive,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(52),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

class _ButtonProgressIndicator extends StatelessWidget {
  const _ButtonProgressIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
    );
  }
}
