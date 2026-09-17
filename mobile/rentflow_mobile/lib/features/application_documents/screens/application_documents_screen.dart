import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
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
  });

  final String applicationId;
  final ApplicationDocumentApiService? applicationDocumentApiService;
  final RentalApplicationApiService? rentalApplicationApiService;
  final Future<SelectedDocumentFile?> Function()? documentPicker;

  @override
  State<ApplicationDocumentsScreen> createState() =>
      _ApplicationDocumentsScreenState();
}

class _ApplicationDocumentsScreenState
    extends State<ApplicationDocumentsScreen> {
  static const _olive = AppPalette.primary;
  static const _maximumFileSizeBytes = 5 * 1024 * 1024;

  ApiClient? _ownedApiClient;
  late final ApplicationDocumentApiService _documentApiService;
  late final RentalApplicationApiService _rentalApplicationApiService;
  late Future<_DocumentsData> _data;

  ApplicationDocumentType _selectedType =
      ApplicationDocumentType.identityDocument;
  SelectedDocumentFile? _selectedFile;
  bool _isPicking = false;
  bool _isUploading = false;
  final Set<String> _deletingIds = {};
  final Set<String> _openingIds = {};

  @override
  void initState() {
    super.initState();
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
        _showMessage('The selected file could not be read.', isError: true);
        return;
      }
      if (selectedFile.size > _maximumFileSizeBytes) {
        _showMessage('Choose a file that is 5 MB or smaller.', isError: true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _selectedFile = selectedFile;
      });
    } on Exception {
      if (mounted) {
        _showMessage('Unable to select a file right now.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<SelectedDocumentFile?> _pickDocumentFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null) return null;
    final size = await file.length();
    final bytes = await file.readAsBytes();
    return SelectedDocumentFile(
      name: file.name,
      extension: _extensionFor(file.name),
      size: size,
      bytes: bytes,
    );
  }

  Future<void> _upload() async {
    final file = _selectedFile;
    if (_isUploading || file == null) return;
    if (file.size > _maximumFileSizeBytes) {
      _showMessage('Choose a file that is 5 MB or smaller.', isError: true);
      return;
    }

    final contentType = _contentTypeFor(file.extension);
    if (contentType == null) {
      _showMessage(
        'Only PDF, JPEG, and PNG files are supported.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isUploading = true;
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
      if (mounted) _showMessage(error.message, isError: true);
      return;
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to upload the document right now. Please try again.',
          isError: true,
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

  String? _contentTypeFor(String? extension) {
    return switch (extension?.toLowerCase()) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => null,
    };
  }

  String? _extensionFor(String fileName) {
    final separator = fileName.lastIndexOf('.');
    if (separator < 0 || separator == fileName.length - 1) return null;
    return fileName.substring(separator + 1).toLowerCase();
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

  String _safeErrorMessage(Object? error) {
    if (error is ApplicationDocumentApiException) return error.message;
    if (error is RentalApplicationApiException) return error.message;
    return 'Unable to load application documents. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Application Documents',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
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
                  _buildUploadPanel(data.canChangeDocuments),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Uploaded documents',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: AppPalette.text,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Text(
                        '${data.documents.length} ${data.documents.length == 1 ? 'file' : 'files'}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppPalette.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Files supplied with this rental application.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
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
    );
  }

  Widget _buildUploadPanel(bool canChangeDocuments) {
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
                              });
                            },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: canChangeDocuments
                    ? const Color(0xFFECEFDF)
                    : const Color(0xFFE9E7E2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                canChangeDocuments ? 'Editable' : 'Read only',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: canChangeDocuments
                      ? AppPalette.success
                      : AppPalette.neutral,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
          const Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _RequirementGuideItem(
                type: ApplicationDocumentType.identityDocument,
              ),
              _RequirementGuideItem(type: ApplicationDocumentType.incomeProof),
              _RequirementGuideItem(
                type: ApplicationDocumentType.employmentLetter,
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        border: Border.all(color: AppPalette.border),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(type.label),
          const SizedBox(width: AppSpacing.sm),
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

class SelectedDocumentFile {
  const SelectedDocumentFile({
    required this.name,
    required this.extension,
    required this.size,
    required this.bytes,
  });

  final String name;
  final String? extension;
  final int size;
  final Uint8List bytes;
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
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
