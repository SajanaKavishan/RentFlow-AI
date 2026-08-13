import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../services/viewing_api_service.dart';

class BookViewingScreen extends StatefulWidget {
  const BookViewingScreen({
    super.key,
    required this.propertyId,
    required this.tenantId,
    this.viewingApiService,
  });

  final String propertyId;
  final String tenantId;
  final ViewingApiService? viewingApiService;

  @override
  State<BookViewingScreen> createState() => _BookViewingScreenState();
}

class _BookViewingScreenState extends State<BookViewingScreen> {
  static const _olive = Color(0xFF5D6842);
  static const _warmBackground = Color(0xFFF7F5EF);

  final _messageController = TextEditingController();
  ApiClient? _ownedApiClient;
  late final ViewingApiService _viewingApiService;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.viewingApiService case final service?) {
      _viewingApiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _viewingApiService = ViewingApiService(_ownedApiClient!);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Choose a viewing date',
    );

    if (selected == null || !mounted) return;

    setState(() {
      _selectedDate = selected;
      if (_selectedTime != null && !_combinedDateTime().isAfter(now)) {
        _selectedTime = null;
      }
    });
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime:
          _selectedTime ??
          TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))),
      helpText: 'Choose a viewing time',
    );

    if (selected == null || !mounted) return;
    if (_selectedDate != null) {
      final dateTime = _combine(_selectedDate!, selected);
      if (!dateTime.isAfter(DateTime.now())) {
        _showMessage('Please choose a time in the future.', isError: true);
        return;
      }
    }

    setState(() => _selectedTime = selected);
  }

  DateTime _combine(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime _combinedDateTime() => _combine(_selectedDate!, _selectedTime!);

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final date = _selectedDate;
    final time = _selectedTime;
    if (date == null || time == null) {
      _showMessage('Choose a date and time before booking.', isError: true);
      return;
    }

    final requestedDateTime = _combine(date, time);
    if (!requestedDateTime.isAfter(DateTime.now())) {
      _showMessage(
        'Please choose a viewing time in the future.',
        isError: true,
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      final message = _messageController.text.trim();
      await _viewingApiService.createViewing(
        tenantId: widget.tenantId,
        propertyId: widget.propertyId,
        requestedDateTime: requestedDateTime,
        tenantMessage: message.isEmpty ? null : message,
      );

      if (!mounted) return;
      setState(() {
        _selectedDate = null;
        _selectedTime = null;
        _messageController.clear();
      });
      _showMessage('Viewing request sent successfully.');
    } on ViewingApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to book the viewing right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
    final localizations = MaterialLocalizations.of(context);
    final dateLabel = _selectedDate == null
        ? 'Select a date'
        : localizations.formatMediumDate(_selectedDate!);
    final timeLabel = _selectedTime == null
        ? 'Select a time'
        : localizations.formatTimeOfDay(_selectedTime!);

    return Scaffold(
      backgroundColor: _warmBackground,
      appBar: AppBar(
        backgroundColor: _olive,
        foregroundColor: Colors.white,
        title: const Text('Book a Viewing'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose a time that works for you',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF313828),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The property owner will review your request and respond.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              Card(
                color: Colors.white,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _SelectionTile(
                        icon: Icons.calendar_today_outlined,
                        label: 'Date',
                        value: dateLabel,
                        onTap: _isSubmitting ? null : _pickDate,
                      ),
                      const Divider(height: 24),
                      _SelectionTile(
                        icon: Icons.schedule_outlined,
                        label: 'Time',
                        value: timeLabel,
                        onTap: _isSubmitting ? null : _pickTime,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _messageController,
                enabled: !_isSubmitting,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Message to the owner (optional)',
                  hintText: 'Add anything helpful about your visit.',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _olive,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Request viewing'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionTile extends StatelessWidget {
  const _SelectionTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: _BookViewingScreenState._olive),
      title: Text(label),
      subtitle: Text(value),
      trailing: const Icon(Icons.chevron_right),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}
