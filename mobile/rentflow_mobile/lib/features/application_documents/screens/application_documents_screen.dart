import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../rental_applications/models/rental_application.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import '../models/application_document.dart';
import '../services/application_document_api_service.dart';
import '../widgets/application_document_card.dart';
import '../widgets/document_type_selector.dart';

class ApplicationDocumentsScreen extends StatefulWidget {
  const ApplicationDocumentsScreen({
    super.key,
    required this.applicationId,
    required this.tenantId,
    this.applicationDocumentApiService,
    this.rentalApplicationApiService,
  });

  final String applicationId;
  final String tenantId;
  final ApplicationDocumentApiService? applicationDocumentApiService;
  final RentalApplicationApiService? rentalApplicationApiService;

  @override
  State<ApplicationDocumentsScreen> createState() =>
      _ApplicationDocumentsScreenState();
}

class _ApplicationDocumentsScreenState
    extends State<ApplicationDocumentsScreen> {
  static const _olive = Color(0xFF5D6842);
  static const _warmBackground = Color(0xFFF7F5EF);
  static const _maximumFileSizeBytes = 5 * 1024 * 1024;

  ApiClient? _ownedApiClient;
  late final ApplicationDocumentApiService _documentApiService;
  late final RentalApplicationApiService _rentalApplicationApiService;
  late Future<_DocumentsData> _data;

  ApplicationDocumentType _selectedType =
      ApplicationDocumentType.identityDocument;
  _SelectedDocumentFile? _selectedFile;
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
    final documentsFuture = _documentApiService.getDocumentsForApplication(
      applicationId: widget.applicationId,
      tenantId: widget.tenantId,
    );
    final applicationFuture = _rentalApplicationApiService.getApplicationById(
      widget.applicationId,
    );
    final documents = await documentsFuture;
    final application = await applicationFuture;
    return _DocumentsData(
      documents: documents,
      canChangeDocuments:
          application.status == RentalApplicationStatus.draft ||
          application.status == RentalApplicationStatus.changesRequested,
    );
  }

  Future<void> _refresh() async {
    final request = _loadData();
    setState(() => _data = request);
    try {
      await request;
    } catch (_) {
      // FutureBuilder renders the safe error state.
    }
  }

  Future<void> _pickFile() async {
    if (_isPicking || _isUploading) return;
    setState(() => _isPicking = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (!mounted || file == null) return;
      final size = await file.length();
      if (!mounted) return;
      if (size <= 0) {
        _showMessage('The selected file could not be read.', isError: true);
        return;
      }
      if (size > _maximumFileSizeBytes) {
        _showMessage('Choose a file that is 5 MB or smaller.', isError: true);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(
        () => _selectedFile = _SelectedDocumentFile(
          name: file.name,
          extension: _extensionFor(file.name),
          size: size,
          bytes: bytes,
        ),
      );
    } on Exception {
      if (mounted) {
        _showMessage('Unable to select a file right now.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
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

    setState(() => _isUploading = true);
    try {
      await _documentApiService.uploadDocument(
        applicationId: widget.applicationId,
        tenantId: widget.tenantId,
        documentType: _selectedType,
        fileName: file.name,
        contentType: contentType,
        bytes: file.bytes,
      );
      if (!mounted) return;
      setState(() => _selectedFile = null);
      _showMessage('Document uploaded.');
      await _refresh();
    } on ApplicationDocumentApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to upload the document right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
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

    setState(() => _deletingIds.add(document.id));
    try {
      await _documentApiService.deleteDocument(
        documentId: document.id,
        tenantId: widget.tenantId,
      );
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
      if (mounted) setState(() => _deletingIds.remove(document.id));
    }
  }

  Future<void> _openDocument(ApplicationDocument document) async {
    if (_openingIds.contains(document.id)) return;
    setState(() => _openingIds.add(document.id));
    try {
      final downloadUrl = await _documentApiService.requestDownloadUrl(
        documentId: document.id,
        tenantId: widget.tenantId,
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
      if (mounted) setState(() => _openingIds.remove(document.id));
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
      backgroundColor: _warmBackground,
      appBar: AppBar(
        backgroundColor: _olive,
        foregroundColor: Colors.white,
        title: const Text('Application Documents'),
      ),
      body: SafeArea(
        child: FutureBuilder<_DocumentsData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _olive),
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
              color: _olive,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildUploadPanel(data.canChangeDocuments),
                  const SizedBox(height: 24),
                  Text(
                    'Uploaded documents',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (data.documents.isEmpty)
                    const _EmptyDocumentsState()
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
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add a document',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              canChangeDocuments
                  ? 'PDF, JPEG, or PNG • Maximum 5 MB'
                  : 'Documents can only be changed while the application is a draft or changes are requested.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            DocumentTypeSelector(
              value: _selectedType,
              enabled: canChangeDocuments && !_isUploading,
              onChanged: (value) {
                if (value != null) setState(() => _selectedType = value);
              },
            ),
            const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, color: _olive),
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
                            formatFileSize(file.size),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove selected file',
                      onPressed: _isUploading
                          ? null
                          : () => setState(() => _selectedFile = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
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
          ],
        ),
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

class _SelectedDocumentFile {
  const _SelectedDocumentFile({
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
  const _EmptyDocumentsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Icon(Icons.folder_open_outlined, size: 46, color: Color(0xFF5D6842)),
          SizedBox(height: 12),
          Text(
            'No documents uploaded',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Supporting documents for this application will appear here.',
            textAlign: TextAlign.center,
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: const Color(0xFF5D6842)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
