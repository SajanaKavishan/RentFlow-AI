import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../application_documents/models/application_document.dart';
import '../../application_documents/widgets/document_requirement_badge.dart';

final wizardLabel = AppTypography.label.copyWith(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: AppPalette.darkOlive,
);
final wizardHelper = AppTypography.bodySmall.copyWith(fontSize: 12);

class ApplicationWizardProgress extends StatelessWidget {
  const ApplicationWizardProgress({
    super.key,
    required this.currentStep,
    required this.completed,
    required this.onSelect,
  });
  final int currentStep;
  final List<bool> completed;
  final ValueChanged<int>? onSelect;
  static const labels = ['Personal', 'Financial', 'Documents', 'Review'];

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < labels.length; index++)
        Expanded(
          child: Semantics(
            label:
                '${labels[index]}, step ${index + 1} of 4${currentStep == index ? ', current step' : ''}${completed[index] ? ', saved and complete' : ''}',
            selected: currentStep == index,
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('application-step-$index'),
              borderRadius: BorderRadius.circular(12),
              onTap: onSelect != null && index < currentStep
                  ? () => onSelect!(index)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                child: Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: currentStep == index || completed[index]
                            ? AppPalette.darkOlive
                            : AppPalette.outline,
                        shape: BoxShape.circle,
                        border: currentStep == index
                            ? Border.all(color: AppPalette.olive, width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: AppTypography.caption.copyWith(
                          fontSize: 10,
                          color: currentStep == index || completed[index]
                              ? AppPalette.white
                              : AppPalette.secondaryText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[index],
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(
                        fontSize: 10,
                        fontWeight: currentStep == index
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: currentStep == index || completed[index]
                            ? AppPalette.darkOlive
                            : AppPalette.secondaryText,
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
}

class ApplicationWizardField extends StatelessWidget {
  const ApplicationWizardField({
    super.key,
    required this.label,
    required this.controller,
    required this.enabled,
    this.validator,
    this.keyboardType,
    this.maxLength,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: wizardLabel),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        enabled: enabled,
        validator: validator,
        keyboardType: keyboardType,
        maxLength: maxLength,
        maxLines: maxLines,
        style: AppTypography.body,
        textCapitalization: keyboardType == null
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        decoration: InputDecoration(
          hintText: label,
          filled: true,
          fillColor: AppPalette.softCream,
          isDense: true,
          contentPadding: const EdgeInsets.all(14),
          errorMaxLines: 4,
          errorStyle: wizardHelper.copyWith(color: AppPalette.danger),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppPalette.outline),
          ),
        ),
      ),
    ],
  );
}

class ApplicationWizardValue extends StatelessWidget {
  const ApplicationWizardValue({
    super.key,
    required this.label,
    required this.value,
  });
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: wizardHelper),
        const SizedBox(height: 4),
        Text(value, style: AppTypography.body),
      ],
    ),
  );
}

class ApplicationWizardDocumentRow extends StatelessWidget {
  const ApplicationWizardDocumentRow({
    super.key,
    required this.type,
    required this.documents,
    required this.onOpen,
    this.picking = false,
    this.uploading = false,
    this.uploadError,
  });
  final ApplicationDocumentType type;
  final List<ApplicationDocument> documents;
  final VoidCallback? onOpen;
  final bool picking, uploading;
  final String? uploadError;
  @override
  Widget build(BuildContext context) {
    final uploaded = documents
        .where((doc) => doc.documentType == type)
        .toList();
    final summary = uploading
        ? 'Uploading...'
        : picking
        ? 'Choosing file...'
        : uploaded.isEmpty
        ? '${type.requirement == DocumentRequirement.required ? 'Missing' : 'Not uploaded'} · ${type.requirementLabel}'
        : 'Uploaded · ${uploaded.map((doc) => doc.originalFileName).join(', ')}';
    return Material(
      color: AppPalette.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppPalette.outline),
      ),
      child: InkWell(
        key: ValueKey('wizard-document-${type.value}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: AppTypography.body.copyWith(
                        color: AppPalette.primaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        summary,
                        style: wizardHelper.copyWith(
                          color: AppPalette.primaryText,
                        ),
                      ),
                    ),
                    if (uploadError != null) ...[
                      const SizedBox(height: 6),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          onOpen == null
                              ? 'Upload failed'
                              : 'Upload failed · Tap to retry',
                          style: wizardHelper.copyWith(
                            color: AppPalette.danger,
                          ),
                        ),
                      ),
                      Text(
                        uploadError!,
                        style: wizardHelper.copyWith(
                          color: AppPalette.primaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (uploading)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  uploaded.isEmpty
                      ? Icons.upload_file_outlined
                      : Icons.check_circle_outline,
                  size: 24,
                  color: AppPalette.olive,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
