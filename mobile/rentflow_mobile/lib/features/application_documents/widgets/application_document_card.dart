import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/application_document.dart';
import 'document_requirement_badge.dart';

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
      key: ValueKey('document-card-${document.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFECEFDF),
                    borderRadius: BorderRadius.circular(AppRadii.small),
                  ),
                  child: Icon(_fileIcon, color: AppPalette.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.documentType.label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppPalette.text,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        document.originalFileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          DocumentRequirementBadge(
                            documentType: document.documentType,
                            compact: true,
                          ),
                          const StatusChip(
                            label: 'Uploaded',
                            tone: StatusTone.success,
                            icon: Icons.check_circle_outline,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppPalette.background,
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DocumentMeta(
                    icon: Icons.data_usage_outlined,
                    label: formatFileSize(document.fileSizeBytes),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DocumentMeta(
                    icon: Icons.cloud_done_outlined,
                    label: 'Uploaded $uploadedDate at $uploadedTime',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: isOpening || isDeleting ? null : onOpen,
                  icon: isOpening
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new),
                  label: Text(isOpening ? 'Opening...' : 'View Document'),
                ),
                if (onDelete != null) ...[
                  TextButton.icon(
                    onPressed: isDeleting || isOpening ? null : onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: AppPalette.danger,
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

class _DocumentMeta extends StatelessWidget {
  const _DocumentMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppPalette.primary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
          ),
        ),
      ],
    );
  }
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
  return '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}
