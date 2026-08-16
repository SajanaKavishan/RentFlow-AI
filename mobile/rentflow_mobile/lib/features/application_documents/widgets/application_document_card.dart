import 'package:flutter/material.dart';

import '../models/application_document.dart';

class ApplicationDocumentCard extends StatelessWidget {
  const ApplicationDocumentCard({
    super.key,
    required this.document,
    required this.onOpen,
    required this.isOpening,
    required this.isDeleting,
    this.onDelete,
  });

  final ApplicationDocument document;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final bool isOpening;
  final bool isDeleting;

  @override
  Widget build(BuildContext context) {
    final localUploadedAt = document.uploadedAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final uploadedDate = localizations.formatMediumDate(localUploadedAt);
    final uploadedTime = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localUploadedAt),
    );

    return Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECEFDF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_fileIcon, color: const Color(0xFF5D6842)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.documentType.label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        document.originalFileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${formatFileSize(document.fileSizeBytes)}  •  $uploadedDate at $uploadedTime',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: isOpening || isDeleting ? null : onOpen,
                  icon: isOpening
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new),
                  label: Text(isOpening ? 'Opening...' : 'Open'),
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: isDeleting || isOpening ? null : onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                    icon: isDeleting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(isDeleting ? 'Deleting...' : 'Delete'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData get _fileIcon {
    return switch (document.contentType) {
      'application/pdf' => Icons.picture_as_pdf_outlined,
      'image/jpeg' || 'image/png' => Icons.image_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
  return '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}
