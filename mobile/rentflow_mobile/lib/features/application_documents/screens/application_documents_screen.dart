import '../services/application_document_picker.dart';
export '../services/application_document_picker.dart' show SelectedDocumentFile;
import '../../../shared/follow_up/follow_up_activity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/profile/profile_page.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../rental_applications/models/rental_application.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import '../models/application_document.dart';
import '../services/application_document_api_service.dart';
import '../widgets/application_document_card.dart';
import '../widgets/document_requirement_badge.dart';
import '../widgets/document_type_selector.dart';

class ApplicationDocumentsScreen extends StatefulWidget {
  const ApplicationDocumentsScreen({
    super.key,
    required this.applicationId,
    this.applicationDocumentApiService,
    this.rentalApplicationApiService,
    this.documentPicker,
    this.initialDocumentType = ApplicationDocumentType.identityDocument,
  });

  final String applicationId;
  final ApplicationDocumentApiService? applicationDocumentApiService;
  final RentalApplicationApiService? rentalApplicationApiService;
  final Future<SelectedDocumentFile?> Function()? documentPicker;
  final ApplicationDocumentType initialDocumentType;

  @override
  State<ApplicationDocumentsScreen> createState() =>
      _ApplicationDocumentsScreenState();
}

class _ApplicationDocumentsScreenState
    extends State<ApplicationDocumentsScreen> {
  static const _maximumFileSizeBytes =
      ApplicationDocumentPicker.maximumFileSizeBytes;

  ApiClient? _ownedApiClient;
  late final ApplicationDocumentApiService _documentApiService;
  late final RentalApplicationApiService _rentalApplicationApiService;
  late Future<_DocumentsData> _data;

  ApplicationDocumentType _selectedType =
      ApplicationDocumentType.identityDocument;
  SelectedDocumentFile? _selectedFile;
  bool _isPicking = false;
  bool _isUploading = false;
  String? _uploadError;
  final Set<String> _deletingIds = {};
  final Set<String> _openingIds = {};

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialDocumentType;
    if (widget.applicationDocumentApiService case final documentService?) {
      _documentApiService = documentService;
    } else {
      _ownedApiClient = ApiClient();
      _documentApiService = ApplicationDocumentApiService(_ownedApiClient!);
    }

    if (widget.rentalApplicationApiService case final applicationService?) {
      _rentalApplicationApiService = applicationService;
    } else {
      _ownedApiClient ??= ApiClient();
      _rentalApplicationApiService = RentalApplicationApiService(
        _ownedApiClient!,
      );
    }
    _data = _loadData();
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<_DocumentsData> _loadData() async {
    if (kDebugMode) {
      debugPrint('[Documents] Load applicationId=${widget.applicationId}');
    }
    final application = await _rentalApplicationApiService.getApplicationById(
      widget.applicationId,
    );
    final documents = await _documentApiService.getDocumentsForApplication(
      applicationId: widget.applicationId,
    );
    return _DocumentsData(
      documents: documents,
      canChangeDocuments:
          application.status == RentalApplicationStatus.draft ||
          application.status == RentalApplicationStatus.changesRequested,
    );
  }

  Future<void> _refresh() async {
    final request = _loadData();
    setState(() {
      _data = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder renders the safe error state.
    }
  }

  Future<void> _pickFile() async {
    if (_isPicking || _isUploading) return;
    setState(() {
      _isPicking = true;
    });
    try {
      final selectedFile = widget.documentPicker == null
          ? await _pickDocumentFile()
          : await widget.documentPicker!();
      if (!mounted || selectedFile == null) return;
      if (selectedFile.size <= 0) {
        _showUploadError('The selected file could not be read.');
        return;
      }
      if (selectedFile.size > _maximumFileSizeBytes) {
        _showUploadError('Choose a file that is 5 MB or smaller.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _selectedFile = selectedFile;
        _uploadError = null;
      });
    } on DocumentSelectionException catch (error) {
      if (mounted) _showUploadError(error.message);
    } on Exception {
      if (mounted) {
        _showUploadError('Unable to select a file right now.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<SelectedDocumentFile?> _pickDocumentFile() =>
      ApplicationDocumentPicker.pick();

  Future<void> _upload() async {
    final file = _selectedFile;
    if (_isUploading || file == null) return;
    if (file.size > _maximumFileSizeBytes) {
      _showUploadError('Choose a file that is 5 MB or smaller.');
      return;
    }

    final contentType = _contentTypeFor(file.extension);
    if (contentType == null) {
      _showUploadError('Only PDF, JPEG, and PNG files are supported.');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadError = null;
    });
    late final ApplicationDocument uploadedDocument;
    try {
      uploadedDocument = await _documentApiService.uploadDocument(
        applicationId: widget.applicationId,
        documentType: _selectedType,
        fileName: file.name,
        contentType: contentType,
        bytes: file.bytes,
      );
    } on ApplicationDocumentApiException catch (error) {
      if (mounted) _showUploadError(error.message);
      return;
    } catch (_) {
      if (mounted) {
        _showUploadError(
          'Unable to upload the document right now. Please try again.',
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }

    if (!mounted) return;
    final previousData = _data;
    setState(() {
      _selectedFile = null;
      _uploadError = null;
      _data = _dataWithUploadedDocument(previousData, uploadedDocument);
    });
    _showMessage('Document uploaded.');

    try {
      final refreshedData = await _loadData();
      if (!mounted) return;
      setState(() {
        _data = Future.value(refreshedData);
      });
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Document uploaded, but the document list could not be refreshed.',
          isError: true,
        );
      }
    }
  }

  Future<_DocumentsData> _dataWithUploadedDocument(
    Future<_DocumentsData> previousData,
    ApplicationDocument uploadedDocument,
  ) async {
    try {
      final currentData = await previousData;
      final documents = [
        uploadedDocument,
        ...currentData.documents.where(
          (document) => document.id != uploadedDocument.id,
        ),
      ];
      return _DocumentsData(
        documents: documents,
        canChangeDocuments: currentData.canChangeDocuments,
      );
    } catch (_) {
      return _DocumentsData(
        documents: [uploadedDocument],
        canChangeDocuments: true,
      );
    }
  }

  Future<void> _confirmDelete(ApplicationDocument document) async {
    if (_deletingIds.contains(document.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this document?'),
        content: Text(
          '${document.originalFileName} will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deletingIds.add(document.id);
    });
    try {
      await _documentApiService.deleteDocument(documentId: document.id);
      if (!mounted) return;
      _showMessage('Document deleted.');
      await _refresh();
    } on ApplicationDocumentApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to delete the document right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _deletingIds.remove(document.id);
        });
      }
    }
  }

  Future<void> _openDocument(ApplicationDocument document) async {
    if (_openingIds.contains(document.id)) return;
    setState(() {
      _openingIds.add(document.id);
    });
    try {
      final downloadUrl = await _documentApiService.requestDownloadUrl(
        documentId: document.id,
      );
      final opened = await launchUrl(
        downloadUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        _showMessage(
          'No app was available to open this document.',
          isError: true,
        );
      }
    } on ApplicationDocumentApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage('Unable to open this document right now.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingIds.remove(document.id);
        });
      }
    }
  }

  String? _contentTypeFor(String? extension) =>
      ApplicationDocumentPicker.contentTypeFor(extension);

  void _showMessage(String message, {bool isError = false}) {
    AppSnackbars.show(
      context,
      message: message,
      tone: isError ? SnackTone.error : SnackTone.success,
    );
  }

  void _showUploadError(String message) {
    setState(() => _uploadError = message);
    _showMessage('Upload failed. Check the message below.', isError: true);
  }

  String _safeErrorMessage(Object? error) {
    if (error is ApplicationDocumentApiException) return error.message;
    if (error is RentalApplicationApiException) return error.message;
    return 'Unable to load application documents. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return FollowUpPause(child: _buildScaffold(context));
  }

  Widget _buildScaffold(BuildContext context) {
    return ProfileSurface(
      child: Scaffold(
        backgroundColor: AppPalette.background,
        appBar: profilePageAppBar(
          context,
          title: 'Application Documents',
          backLabel: 'Back',
        ),
        body: SafeArea(
          child: FutureBuilder<_DocumentsData>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _DocumentsLoadingState(
                  title: 'Loading documents',
                  message: 'Checking this application and its uploaded files.',
                );
              }
              if (snapshot.hasError) {
                return _MessageState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load documents',
                  message: _safeErrorMessage(snapshot.error),
                  onRetry: _refresh,
                );
              }

              final data = snapshot.requireData;
              return RefreshIndicator(
                color: AppPalette.primary,
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base,
                    AppSpacing.lg,
                    AppSpacing.base,
                    AppSpacing.xl,
                  ),
                  children: [
                    _DocumentsHeader(
                      applicationId: widget.applicationId,
                      count: data.documents.length,
                      canChangeDocuments: data.canChangeDocuments,
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _RequiredDocumentsCallout(documents: data.documents),
                    const SizedBox(height: AppSpacing.base),
                    _buildUploadPanel(data.canChangeDocuments),
                    const SizedBox(height: AppSpacing.lg),
                    SectionHeader(
                      title: 'Uploaded documents',
                      subtitle: 'Files supplied with this rental application.',
                      trailing: StatusChip(
                        label:
                            '${data.documents.length} ${data.documents.length == 1 ? 'file' : 'files'}',
                        tone: StatusTone.neutral,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (data.documents.isEmpty)
                      _EmptyDocumentsState(
                        canChangeDocuments: data.canChangeDocuments,
                      )
                    else
                      ...data.documents.map(
                        (document) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ApplicationDocumentCard(
                            document: document,
                            isOpening: _openingIds.contains(document.id),
                            isDeleting: _deletingIds.contains(document.id),
                            onOpen: () => _openDocument(document),
                            onDelete: data.canChangeDocuments
                                ? () => _confirmDelete(document)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUploadPanel(bool canChangeDocuments) {
    final uploadState = !canChangeDocuments
        ? const StatusChip(
            label: 'Read Only',
            tone: StatusTone.neutral,
            icon: Icons.lock_outline,
          )
        : _isUploading
        ? const StatusChip(
            label: 'Uploading',
            tone: StatusTone.progress,
            icon: Icons.cloud_upload_outlined,
          )
        : _uploadError != null
        ? const StatusChip(
            label: 'Failed',
            tone: StatusTone.danger,
            icon: Icons.error_outline,
          )
        : null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: canChangeDocuments
                        ? const Color(0xFFECEFDF)
                        : const Color(0xFFE9E7E2),
                    borderRadius: BorderRadius.circular(AppRadii.small),
                  ),
                  child: Icon(
                    canChangeDocuments
                        ? Icons.upload_file_outlined
                        : Icons.lock_outline,
                    color: canChangeDocuments
                        ? AppPalette.primary
                        : AppPalette.neutral,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add a document',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppPalette.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        canChangeDocuments
                            ? 'Choose a document type and file to upload.'
                            : 'Uploads and deletions are locked for this application status.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppPalette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (uploadState != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  uploadState,
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            const _DocumentRequirementGuide(),
            const SizedBox(height: AppSpacing.base),
            DocumentTypeSelector(
              value: _selectedType,
              enabled: canChangeDocuments && !_isUploading,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedType = value;
                    _uploadError = null;
                  });
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: canChangeDocuments && !_isPicking && !_isUploading
                  ? _pickFile
                  : null,
              icon: _isPicking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file),
              label: Text(_isPicking ? 'Opening files...' : 'Choose file'),
            ),
            if (_selectedFile case final file?) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppPalette.background,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  border: Border.all(color: AppPalette.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.insert_drive_file_outlined,
                      color: AppPalette.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${_selectedType.label} · ${formatFileSize(file.size)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove selected file',
                      onPressed: _isUploading
                          ? null
                          : () {
                              setState(() {
                                _selectedFile = null;
                                _uploadError = null;
                              });
                            },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ],
            if (_uploadError case final error?) ...[
              const SizedBox(height: AppSpacing.md),
              _UploadFailure(message: error),
            ],
            const SizedBox(height: AppSpacing.base),
            FilledButton.icon(
              onPressed:
                  canChangeDocuments && _selectedFile != null && !_isUploading
                  ? _upload
                  : null,
              icon: _isUploading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_isUploading ? 'Uploading...' : 'Upload document'),
            ),
            if (_isUploading) ...[
              const SizedBox(height: AppSpacing.md),
              const LinearProgressIndicator(color: AppPalette.primary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Uploading ${_selectedFile?.name ?? 'selected file'}...',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Accepted formats: PDF, JPEG, PNG · Maximum 5 MB',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DocumentsHeader extends StatelessWidget {
  const _DocumentsHeader({
    required this.applicationId,
    required this.count,
    required this.canChangeDocuments,
  });

  final String applicationId;
  final int count;
  final bool canChangeDocuments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Supporting documents',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppPalette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            StatusChip(
              label: canChangeDocuments ? 'Editable' : 'Read Only',
              tone: canChangeDocuments
                  ? StatusTone.success
                  : StatusTone.neutral,
              icon: canChangeDocuments
                  ? Icons.edit_outlined
                  : Icons.lock_outline,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$count ${count == 1 ? 'document' : 'documents'} uploaded',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            border: Border.all(color: AppPalette.border),
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Application reference',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                applicationId,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppPalette.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RequiredDocumentsCallout extends StatelessWidget {
  const _RequiredDocumentsCallout({required this.documents});

  static const _requiredTypes = [
    ApplicationDocumentType.identityDocument,
    ApplicationDocumentType.incomeProof,
  ];

  final List<ApplicationDocument> documents;

  @override
  Widget build(BuildContext context) {
    final uploadedTypes = documents
        .map((document) => document.documentType)
        .toSet();
    final missingCount = _requiredTypes
        .where((type) => !uploadedTypes.contains(type))
        .length;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      color: missingCount == 0 ? AppPalette.sage : AppPalette.softCream,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                missingCount == 0
                    ? Icons.task_alt_outlined
                    : Icons.rule_folder_outlined,
                color: missingCount == 0
                    ? AppPalette.success
                    : AppPalette.darkOlive,
              ),
              Text(
                'Required documents',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              StatusChip(
                label: missingCount == 0 ? 'Uploaded' : '$missingCount Missing',
                tone: missingCount == 0
                    ? StatusTone.success
                    : StatusTone.danger,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var index = 0; index < _requiredTypes.length; index++) ...[
            if (index > 0) const Divider(height: AppSpacing.md),
            _RequiredDocumentRow(
              type: _requiredTypes[index],
              isUploaded: uploadedTypes.contains(_requiredTypes[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _RequiredDocumentRow extends StatelessWidget {
  const _RequiredDocumentRow({required this.type, required this.isUploaded});

  final ApplicationDocumentType type;
  final bool isUploaded;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          type.label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppPalette.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      StatusChip(
        label: isUploaded ? 'Uploaded' : 'Missing',
        tone: isUploaded ? StatusTone.success : StatusTone.danger,
        icon: isUploaded ? Icons.check_circle_outline : Icons.error_outline,
      ),
    ],
  );
}

class _UploadFailure extends StatelessWidget {
  const _UploadFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('documents-upload-failed'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: const Color(0xFFF5DDDC),
      borderRadius: BorderRadius.circular(AppRadii.small),
      border: Border.all(color: AppPalette.danger.withValues(alpha: 0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: AppPalette.danger),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upload failed',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: AppPalette.danger),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DocumentRequirementGuide extends StatelessWidget {
  const _DocumentRequirementGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Document guide',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppPalette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Column(
            children: [
              _RequirementGuideItem(
                type: ApplicationDocumentType.identityDocument,
              ),
              SizedBox(height: AppSpacing.sm),
              _RequirementGuideItem(type: ApplicationDocumentType.incomeProof),
              SizedBox(height: AppSpacing.sm),
              _RequirementGuideItem(
                type: ApplicationDocumentType.employmentLetter,
              ),
              SizedBox(height: AppSpacing.sm),
              _RequirementGuideItem(type: ApplicationDocumentType.other),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequirementGuideItem extends StatelessWidget {
  const _RequirementGuideItem({required this.type});

  final ApplicationDocumentType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        border: Border.all(color: AppPalette.border),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(type.label),
          DocumentRequirementBadge(documentType: type, compact: true),
        ],
      ),
    );
  }
}

class _DocumentsData {
  const _DocumentsData({
    required this.documents,
    required this.canChangeDocuments,
  });

  final List<ApplicationDocument> documents;
  final bool canChangeDocuments;
}

class _EmptyDocumentsState extends StatelessWidget {
  const _EmptyDocumentsState({required this.canChangeDocuments});

  final bool canChangeDocuments;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('documents-empty'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        border: Border.all(color: AppPalette.border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 46,
            color: AppPalette.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'No documents uploaded',
            style: TextStyle(
              fontSize: AppTypography.sectionTitleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            canChangeDocuments
                ? 'Start with the required Identity Document and Income Proof.'
                : 'No supporting documents were uploaded before document changes were locked.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppPalette.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            key: const ValueKey('documents-error'),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF5DDDC),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 32, color: AppPalette.danger),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppPalette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppPalette.muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentsLoadingState extends StatelessWidget {
  const _DocumentsLoadingState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          key: const ValueKey('documents-loading'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 34,
              child: CircularProgressIndicator(
                color: AppPalette.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppPalette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
