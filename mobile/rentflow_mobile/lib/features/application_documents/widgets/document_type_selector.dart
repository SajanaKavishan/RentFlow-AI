import 'package:flutter/material.dart';

import '../models/application_document.dart';
import 'document_requirement_badge.dart';

class DocumentTypeSelector extends StatelessWidget {
  const DocumentTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final ApplicationDocumentType value;
  final ValueChanged<ApplicationDocumentType?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ApplicationDocumentType>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Document type',
        prefixIcon: const Icon(Icons.category_outlined),
        helperText: '${value.requirementLabel} document',
      ),
      items: ApplicationDocumentType.values
          .map(
            (type) => DropdownMenuItem(
              value: type,
              child: Row(
                children: [
                  Expanded(
                    child: Text(type.label, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  DocumentRequirementBadge(documentType: type, compact: true),
                ],
              ),
            ),
          )
          .toList(growable: false),
      onChanged: enabled ? onChanged : null,
    );
  }
}
