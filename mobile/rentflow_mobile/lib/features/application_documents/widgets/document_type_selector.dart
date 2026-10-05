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
      itemHeight: null,
      selectedItemBuilder: (context) => ApplicationDocumentType.values
          .map((type) => Text(type.label, overflow: TextOverflow.ellipsis))
          .toList(growable: false),
      decoration: InputDecoration(
        labelText: 'Document type',
        prefixIcon: const Icon(Icons.category_outlined),
        helperText: '${value.requirementLabel} document',
      ),
      items: ApplicationDocumentType.values
          .map(
            (type) => DropdownMenuItem(
              value: type,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.label),
                    const SizedBox(height: 4),
                    DocumentRequirementBadge(documentType: type, compact: true),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
      onChanged: enabled ? onChanged : null,
    );
  }
}
