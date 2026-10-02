import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
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
  static const _olive = Color(0xFF5D6842);
  static const _warmBackground = Color(0xFFF7F5EF);

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
      Navigator.of(context).pop(created);
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

  String _categoryLabel(MaintenanceCategory category) {
    return category.name
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (part) =>
              part.isEmpty ? part : part[0].toUpperCase() + part.substring(1),
        )
        .join(' ');
  }

  String _priorityLabel(MaintenancePriority priority) {
    return priority.name
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (part) =>
              part.isEmpty ? part : part[0].toUpperCase() + part.substring(1),
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _warmBackground,
      appBar: AppBar(
        backgroundColor: _olive,
        foregroundColor: Colors.white,
        title: const Text('Create Maintenance Request'),
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
                  'Report a maintenance issue for this property',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Provide the details so the request can be triaged properly.',
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
                        TextFormField(
                          controller: _titleController,
                          enabled: !_isSubmitting,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Title',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';
                            return trimmed.isEmpty
                                ? 'Please enter a title.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          enabled: !_isSubmitting,
                          maxLines: 5,
                          maxLength: 2000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';
                            return trimmed.isEmpty
                                ? 'Please describe the issue.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<MaintenanceCategory>(
                          isExpanded: true,
                          itemHeight: null,
                          initialValue: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            border: OutlineInputBorder(),
                          ),
                          items: MaintenanceCategory.values
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(_categoryLabel(category)),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _isSubmitting
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _selectedCategory = value);
                                  }
                                },
                          validator: (value) =>
                              value == null ? 'Select a category.' : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<MaintenancePriority>(
                          isExpanded: true,
                          itemHeight: null,
                          initialValue: _selectedPriority,
                          decoration: const InputDecoration(
                            labelText: 'Priority',
                            border: OutlineInputBorder(),
                          ),
                          items: MaintenancePriority.values
                              .map(
                                (priority) => DropdownMenuItem(
                                  value: priority,
                                  child: Text(_priorityLabel(priority)),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _isSubmitting
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _selectedPriority = value);
                                  }
                                },
                          validator: (value) =>
                              value == null ? 'Select a priority.' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _tenantAccessNotesController,
                          enabled: !_isSubmitting,
                          maxLines: 3,
                          maxLength: 1000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Tenant access notes (optional)',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit request'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
