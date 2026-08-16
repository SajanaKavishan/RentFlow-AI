import 'package:flutter/material.dart';

import '../models/application_document.dart';

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
      decoration: const InputDecoration(
        labelText: 'Document type',
        prefixIcon: Icon(Icons.category_outlined),
        border: OutlineInputBorder(),
      ),
      items: ApplicationDocumentType.values
          .map((type) => DropdownMenuItem(value: type, child: Text(type.label)))
          .toList(growable: false),
      onChanged: enabled ? onChanged : null,
    );
  }
}
