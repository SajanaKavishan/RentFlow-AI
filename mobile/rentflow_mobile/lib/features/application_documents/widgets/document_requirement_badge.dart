import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/application_document.dart';

enum DocumentRequirement { required, recommended, optional }

extension ApplicationDocumentTypeRequirement on ApplicationDocumentType {
  DocumentRequirement get requirement => switch (this) {
    ApplicationDocumentType.identityDocument ||
    ApplicationDocumentType.incomeProof => DocumentRequirement.required,
    ApplicationDocumentType.employmentLetter => DocumentRequirement.recommended,
    ApplicationDocumentType.other => DocumentRequirement.optional,
  };

  String get requirementLabel => switch (requirement) {
    DocumentRequirement.required => 'Required',
    DocumentRequirement.recommended => 'Recommended',
    DocumentRequirement.optional => 'Optional',
  };
}

class DocumentRequirementBadge extends StatelessWidget {
  const DocumentRequirementBadge({
    super.key,
    required this.documentType,
    this.compact = false,
  });

  final ApplicationDocumentType documentType;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final requirement = documentType.requirement;
    final (foreground, background) = switch (requirement) {
      DocumentRequirement.required => (
        AppPalette.danger,
        const Color(0xFFF5DDDC),
      ),
      DocumentRequirement.recommended => (
        AppPalette.warning,
        AppPalette.pending,
      ),
      DocumentRequirement.optional => (
        AppPalette.neutral,
        const Color(0xFFE9E7E2),
      ),
    };

    return Semantics(
      label:
          '${documentType.label}: ${documentType.requirementLabel.toLowerCase()}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: foreground.withValues(alpha: 0.18)),
        ),
        child: Text(
          documentType.requirementLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
