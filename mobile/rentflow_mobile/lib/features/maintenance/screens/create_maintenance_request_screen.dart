import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../properties/models/property.dart';
import '../models/maintenance_request.dart';
import '../services/maintenance_api_service.dart';
import '../services/maintenance_photo_picker.dart';
import '../widgets/maintenance_photo_source_sheet.dart';
import '../widgets/tenant_maintenance_ui.dart';

class CreateMaintenanceRequestScreen extends StatefulWidget {
  const CreateMaintenanceRequestScreen({
    super.key,
    required this.propertyId,
    this.properties = const [],
    this.maintenanceApiService,
    this.photoPicker,
  });

  final String propertyId;
  final List<Property> properties;
  final MaintenanceApiService? maintenanceApiService;
  final MaintenancePhotoPicker? photoPicker;

  @override
  State<CreateMaintenanceRequestScreen> createState() =>
      _CreateMaintenanceRequestScreenState();
}

class _CreateMaintenanceRequestScreenState
    extends State<CreateMaintenanceRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final List<MaintenancePhoto> _photos = [];
  ApiClient? _ownedClient;
  late final MaintenanceApiService _service;
  late final MaintenancePhotoPicker _picker;
  String? _propertyId;
  MaintenanceCategory _category = MaintenanceCategory.plumbing;
  MaintenancePriority _priority = MaintenancePriority.normal;
  PreferredAccessWindow? _access;
  bool _submitting = false;
  bool _picking = false;
  bool _uploading = false;
  String? _error;
  String? _submissionNote;
  int? _attachedCount;
  MaintenanceRequest? _created;

  Property? get _property {
    for (final property in widget.properties) {
      if (property.id == _propertyId) return property;
    }
    return null;
  }

  bool get _canSubmit =>
      !_submitting &&
      !_picking &&
      _propertyId != null &&
      _access != null &&
      _description.text.trim().isNotEmpty &&
      _description.text.characters.length <= 500;

  @override
  void initState() {
    super.initState();
    _propertyId = widget.properties.length > 1 ? null : widget.propertyId;
    if (widget.maintenanceApiService case final service?) {
      _service = service;
    } else {
      _ownedClient = ApiClient();
      _service = MaintenanceApiService(_ownedClient!);
    }
    _picker = widget.photoPicker ?? PlatformMaintenancePhotoPicker();
    _recoverPhotos();
  }

  @override
  void dispose() {
    _description.dispose();
    _ownedClient?.close();
    super.dispose();
  }

  Future<void> _recoverPhotos() async {
    try {
      final photos = await _picker.recoverLostPhotos();
      if (mounted && photos.isNotEmpty) _acceptPhotos(photos);
    } catch (error) {
      if (mounted) setState(() => _error = _photoError(error));
    }
  }

  String _photoError(Object error) => error is MaintenancePhotoPickerException
      ? error.message
      : 'Unable to choose a photo. Please try again.';

  Future<void> _openPhotoSettings() async {
    final opened = await _picker.openSettings();
    if (!opened && mounted) {
      setState(
        () => _error = 'Open your device Settings app to allow photo access.',
      );
    }
  }

  void _acceptPhotos(List<MaintenancePhoto> photos) {
    if (_photos.length + photos.length > MaintenancePhoto.maximumCount) {
      setState(
        () => _error = 'You can add up to 5 photos. Choose fewer photos.',
      );
      return;
    }
    for (final photo in photos) {
      if (photo.validate() case final error?) {
        setState(() => _error = error);
        return;
      }
    }
    setState(() {
      _photos.addAll(photos);
      _error = null;
    });
  }

  Future<void> _addPhotos() async {
    if (_picking ||
        _submitting ||
        _photos.length >= MaintenancePhoto.maximumCount) {
      return;
    }
    setState(() => _picking = true);
    try {
      final source = await showMaintenancePhotoSourceSheet(context);
      if (source == null || !mounted) return;
      final photos = await _picker.pick(source);
      if (mounted) _acceptPhotos(photos);
    } catch (error) {
      if (mounted) setState(() => _error = _photoError(error));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || !_formKey.currentState!.validate()) return;
    final tenant = AuthScope.of(context).currentUser;
    if (tenant == null) {
      setState(
        () => _error = 'Please sign in to submit a maintenance request.',
      );
      return;
    }
    for (final photo in _photos) {
      if (photo.validate() case final error?) {
        setState(() => _error = error);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // The server derives the title and confirms tenancy; Flutter sends neither
      // a display reference nor legacy access notes.
      final created = await _service.createMaintenanceRequest(
        tenantId: tenant.id,
        propertyId: _propertyId!,
        description: _description.text.trim(),
        category: _category,
        priority: _priority,
        preferredAccessWindow: _access!,
      );
      var failed = 0;
      var confirmed = 0;
      if (mounted && _photos.isNotEmpty) setState(() => _uploading = true);
      for (final photo in List<MaintenancePhoto>.of(_photos)) {
        try {
          final attachment = await _service.uploadMaintenanceAttachment(
            maintenanceRequestId: created.id,
            tenantId: tenant.id,
            fileName: photo.fileName,
            contentType: photo.contentType,
            bytes: photo.bytes,
          );
          if (attachment.maintenanceRequestId != created.id) {
            throw const MaintenanceApiException(
              'The photo upload could not be confirmed.',
            );
          }
          confirmed++;
        } catch (_) {
          failed++;
        }
      }
      var authoritative = created;
      try {
        final refreshed = await _service.getMaintenanceRequestById(created.id);
        if (refreshed.id == created.id) authoritative = refreshed;
      } catch (_) {
        // The successful POST response remains authoritative for this request.
      }
      var count = confirmed;
      try {
        final attachments = await _service.getMaintenanceRequestAttachments(
          maintenanceRequestId: created.id,
          tenantId: tenant.id,
        );
        count = attachments
            .where((a) => a.maintenanceRequestId == created.id)
            .length;
      } catch (_) {
        // Count only successful upload responses when the list cannot refresh.
      }
      if (!mounted) return;
      setState(() {
        _created = authoritative;
        _attachedCount = count;
        _submissionNote = failed == 0
            ? null
            : 'Your request was submitted, but $failed ${failed == 1 ? 'photo could' : 'photos could'} not be uploaded. '
                  'Track Request to add photos from the attachments section.';
      });
    } on MaintenanceApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.statusCode) {
            403 =>
              'You need a current active lease for this property to submit a maintenance request.',
            409 =>
              'This property is currently unavailable for a maintenance request. Refresh your properties and try again.',
            _ => error.message,
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to create your request. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploading = false;
        });
      }
    }
  }

  void _newRequest() {
    setState(() {
      _created = null;
      _description.clear();
      _photos.clear();
      _access = null;
      _category = MaintenanceCategory.plumbing;
      _priority = MaintenancePriority.normal;
      _propertyId = widget.properties.length > 1 ? null : widget.propertyId;
      _error = null;
      _submissionNote = null;
      _attachedCount = null;
    });
  }

  Widget _heading(String text, {double top = 18}) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: AppPalette.primaryText,
      ),
    ),
  );

  ButtonStyle get _primaryStyle => FilledButton.styleFrom(
    backgroundColor: AppPalette.darkOlive,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(48),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _categories() => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = scale > 1.45 || constraints.maxWidth < 260 ? 2 : 4;
      return Column(
        children: [
          for (
            var start = 0;
            start < tenantCreateCategories.length;
            start += columns
          )
            Padding(
              padding: EdgeInsets.only(
                bottom: start + columns < tenantCreateCategories.length ? 8 : 0,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = start;
                      index < start + columns &&
                          index < tenantCreateCategories.length;
                      index++
                    ) ...[
                      Expanded(
                        child: _categoryTile(tenantCreateCategories[index]),
                      ),
                      if (index + 1 < start + columns &&
                          index + 1 < tenantCreateCategories.length)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _categoryTile(MaintenanceCategory category) {
    final selected = _category == category;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('category-${category.name}'),
        onTap: _submitting ? null : () => setState(() => _category = category),
        borderRadius: BorderRadius.circular(12),
        child: MaintenanceSurface(
          radius: 12,
          selected: selected,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                maintenanceCategoryIcon(category),
                size: 22,
                color: AppPalette.darkOlive,
              ),
              const SizedBox(height: 7),
              Text(
                maintenanceLabel(category),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.primaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priorities() => Column(
    children: [
      for (final priority in tenantCreatePriorities)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            button: true,
            selected: _priority == priority,
            child: InkWell(
              key: ValueKey('priority-${priority.name}'),
              onTap: _submitting
                  ? null
                  : () => setState(() => _priority = priority),
              borderRadius: BorderRadius.circular(12),
              child: MaintenanceSurface(
                radius: 12,
                selected: _priority == priority,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      _priority == priority
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: switch (priority) {
                        MaintenancePriority.emergency => AppPalette.danger,
                        MaintenancePriority.high => AppPalette.warning,
                        _ => AppPalette.olive,
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            maintenanceCreatePriorityLabel(priority),
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: priority == MaintenancePriority.emergency
                                  ? AppPalette.danger
                                  : AppPalette.primaryText,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            switch (priority) {
                              MaintenancePriority.emergency =>
                                'Immediate safety risk',
                              MaintenancePriority.high => 'Affects daily life',
                              _ => 'Non-urgent repair',
                            },
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              color: AppPalette.secondaryText,
                            ),
                          ),
                        ],
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

  Widget _photoSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Add photos (optional)'),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var index = 0; index < _photos.length; index++)
            SizedBox(
              key: ValueKey('selected-photo-$index'),
              width: 86,
              height: 86,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _photos[index].bytes,
                        fit: BoxFit.cover,
                        semanticLabel: 'Selected photo ${index + 1}',
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: AppPalette.progress,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: 'Remove photo ${index + 1}',
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _photos.removeAt(index)),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          if (_photos.length < MaintenancePhoto.maximumCount)
            SizedBox(
              width: 86,
              child: OutlinedButton(
                key: const ValueKey('maintenance-add-photo'),
                onPressed: _submitting || _picking ? null : _addPhotos,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 12,
                  ),
                  backgroundColor: Colors.white,
                  foregroundColor: AppPalette.darkOlive,
                  side: const BorderSide(color: AppPalette.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _picking ? Icons.hourglass_empty : Icons.add,
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Add photo',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '${_photos.length}/5 photos added',
        style: const TextStyle(fontSize: 11, color: AppPalette.secondaryText),
      ),
    ],
  );

  Widget _accessSection() => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: MaintenanceSurface(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preferred access time',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppPalette.primaryText,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final window in PreferredAccessWindow.values)
                ChoiceChip(
                  key: ValueKey('access-${window.name}'),
                  label: Text(window.label),
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  selected: _access == window,
                  showCheckmark: false,
                  backgroundColor: Colors.white,
                  selectedColor: AppPalette.progress,
                  side: BorderSide(
                    color: _access == window
                        ? AppPalette.olive
                        : AppPalette.outline,
                  ),
                  labelStyle: const TextStyle(
                    fontSize: 11,
                    color: AppPalette.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: _submitting
                      ? null
                      : (_) => setState(() => _access = window),
                ),
            ],
          ),
          if (_access == null) ...[
            const SizedBox(height: 6),
            const Text(
              'Choose one access time to submit.',
              style: TextStyle(fontSize: 11, color: AppPalette.secondaryText),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _form() => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.properties.length > 1) ...[
          _heading('Property'),
          DropdownButtonFormField<String>(
            key: const ValueKey('maintenance-property-selector'),
            initialValue: _propertyId,
            isExpanded: true,
            decoration: const InputDecoration(hintText: 'Choose a property'),
            items: [
              for (final property in widget.properties)
                DropdownMenuItem(
                  value: property.id,
                  child: Text(property.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() => _propertyId = value),
          ),
        ],
        _heading('What needs attention?', top: 10),
        _categories(),
        _heading('Priority level'),
        _priorities(),
        _heading('Describe the issue'),
        TextFormField(
          key: const ValueKey('maintenance-description'),
          controller: _description,
          enabled: !_submitting,
          minLines: 4,
          maxLines: 7,
          maxLength: 500,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(
            fontSize: 14,
            height: 1.35,
            color: AppPalette.primaryText,
          ),
          decoration: InputDecoration(
            hintText:
                'The kitchen faucet has been dripping constantly for two days...',
            hintStyle: const TextStyle(
              fontSize: 14,
              color: AppPalette.secondaryText,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppPalette.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppPalette.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppPalette.olive),
            ),
          ),
          validator: (value) => (value?.trim() ?? '').isEmpty
              ? 'Please describe the issue.'
              : null,
          onChanged: (_) => setState(() => _error = null),
        ),
        _photoSection(),
        _accessSection(),
        if (_error case final error?) ...[
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: const TextStyle(fontSize: 13, color: AppPalette.danger),
            ),
          ),
          if (_picker.canOpenSettings && error.contains('device settings'))
            TextButton(
              onPressed: _openPhotoSettings,
              child: const Text('Open settings'),
            ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          key: const ValueKey('maintenance-submit'),
          onPressed: _canSubmit ? _submit : null,
          style: _primaryStyle,
          child: _submitting
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _uploading
                            ? 'Uploading photos...'
                            : 'Submitting request...',
                      ),
                    ),
                  ],
                )
              : const Text('Submit Request'),
        ),
      ],
    ),
  );

  String _submittedDate(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final format = MaterialLocalizations.of(context);
    return '${today ? 'Today' : format.formatMediumDate(local)}, ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Widget _success(MaintenanceRequest request) {
    final property = _property?.id == request.propertyId ? _property : null;
    final rows = <(String, String)>[
      ('Category', maintenanceLabel(request.category)),
      ('Priority', maintenanceCreatePriorityLabel(request.priority)),
      if (property != null) ('Property', property.title),
      if (request.preferredAccessWindow case final access?)
        ('Preferred access', access.label),
      if (_attachedCount case final count?) ('Photos', '$count attached'),
      ('Submitted', _submittedDate(request.createdAt)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        const Center(
          child: CircleAvatar(
            radius: 24,
            backgroundColor: AppPalette.progress,
            child: Icon(Icons.check, color: AppPalette.olive, size: 27),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Request Submitted',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppPalette.primaryText,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your maintenance request has been logged.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppPalette.secondaryText,
          ),
        ),
        const SizedBox(height: 22),
        MaintenanceSurface(
          radius: 15,
          selected: true,
          selectedBackground: const Color(0xFFF0F3E9),
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                request.referenceCode == null
                    ? 'REQUEST SUBMITTED'
                    : 'REQUEST #${request.referenceCode}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.darkOlive,
                ),
              ),
              const SizedBox(height: 12),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final large =
                          MediaQuery.textScalerOf(context).scale(1) > 1.45;
                      final labelWidget = Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppPalette.secondaryText,
                        ),
                      );
                      final valueWidget = Text(
                        value,
                        textAlign: large ? TextAlign.start : TextAlign.end,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.primaryText,
                        ),
                      );
                      return large
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                labelWidget,
                                const SizedBox(height: 3),
                                valueWidget,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: labelWidget),
                                const SizedBox(width: 12),
                                Expanded(child: valueWidget),
                              ],
                            );
                    },
                  ),
                ),
            ],
          ),
        ),
        if (_submissionNote case final note?) ...[
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              note,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppPalette.secondaryText,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(request),
          style: _primaryStyle,
          child: const Text('Track Request'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _newRequest,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: AppPalette.darkOlive,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('New Request'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Scaffold(
      backgroundColor: AppPalette.warmCream,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(_created),
                    icon: const Icon(Icons.arrow_back, size: 22),
                  ),
                  if (_created == null)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Maintenance request',
                              style: TextStyle(
                                fontSize: 20,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.primaryText,
                              ),
                            ),
                            if (_property case final property?) ...[
                              const SizedBox(height: 5),
                              Text(
                                property.title,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppPalette.secondaryText,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: _created != null ? _success(_created!) : _form(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
