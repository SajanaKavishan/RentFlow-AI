import 'package:flutter/material.dart';

import '../../features/support/models/support_ticket.dart';
import '../../features/support/services/support_ticket_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'profile_page.dart';

class CreateSupportRequestScreen extends StatefulWidget {
  const CreateSupportRequestScreen({super.key, required this.service});
  final SupportTicketApiService service;
  @override
  State<CreateSupportRequestScreen> createState() =>
      _CreateSupportRequestScreenState();
}

class _CreateSupportRequestScreenState
    extends State<CreateSupportRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _categoryField = GlobalKey<FormFieldState<SupportCategory>>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  SupportCategory? _category;
  bool _submitting = false;
  String? _error;

  bool get _valid =>
      _category != null &&
      CreateSupportTicketRequest.validateSubject(_subject.text) == null &&
      CreateSupportTicketRequest.validateMessage(_message.text) == null;

  @override
  void initState() {
    super.initState();
    _subject.addListener(_edited);
    _message.addListener(_edited);
  }

  void _edited() => setState(() => _error = null);
  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    final category = await showModalBottomSheet<SupportCategory>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        child: Padding(
          padding: AppSpacing.card,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose a category',
                style: AppTypography.sectionTitle,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final category in SupportCategory.values)
                ListTile(
                  key: ValueKey('support-category-${category.value}'),
                  title: Text(category.label, style: AppTypography.body),
                  onTap: () => Navigator.of(sheetContext).pop(category),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || category == null) return;
    setState(() {
      _category = category;
      _error = null;
    });
    _categoryField.currentState!.didChange(category);
  }

  Future<void> _submit() async {
    if (_submitting || !_valid || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ticket = await widget.service.createSupportTicket(
        CreateSupportTicketRequest(
          category: _category!,
          subject: _subject.text,
          message: _message.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(ticket);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is SupportTicketApiException
              ? error.message
              : 'Your support request could not be submitted. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ProfileSurface(
    child: PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: profilePageAppBar(
          context,
          title: 'New request',
          backLabel: 'Back to support',
          canGoBack: !_submitting,
        ),
        body: AuthenticatedPage(
          maxWidth: 580,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Category', style: AppTypography.body),
                      const SizedBox(height: AppSpacing.sm),
                      FormField<SupportCategory>(
                        key: _categoryField,
                        validator: (value) =>
                            value == null ? 'Choose a category.' : null,
                        builder: (field) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton(
                              key: const Key('support-category-picker'),
                              onPressed: _submitting ? null : _pickCategory,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      field.value?.label ?? 'Choose a category',
                                      style: AppTypography.body,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  const Icon(Icons.expand_more, size: 20),
                                ],
                              ),
                            ),
                            if (field.errorText != null)
                              Text(
                                field.errorText!,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppPalette.danger,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      TextFormField(
                        key: const Key('support-subject'),
                        controller: _subject,
                        enabled: !_submitting,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        textInputAction: TextInputAction.next,
                        validator: CreateSupportTicketRequest.validateSubject,
                        decoration: const InputDecoration(
                          labelText: 'Subject',
                          helperText: 'Up to 200 characters.',
                          helperMaxLines: 3,
                          errorMaxLines: 3,
                          fillColor: AppPalette.white,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      TextFormField(
                        key: const Key('support-message'),
                        controller: _message,
                        enabled: !_submitting,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        minLines: 4,
                        maxLines: 8,
                        validator: CreateSupportTicketRequest.validateMessage,
                        decoration: const InputDecoration(
                          labelText: 'Message',
                          helperText: 'Up to 4,000 characters.',
                          helperMaxLines: 3,
                          errorMaxLines: 3,
                          fillColor: AppPalette.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.base),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        key: const Key('support-create-error'),
                        style: AppTypography.body.copyWith(
                          color: AppPalette.danger,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  liveRegion: _submitting,
                  child: FilledButton(
                    key: const Key('support-submit'),
                    onPressed: _valid && !_submitting ? _submit : null,
                    child: Text(
                      _submitting ? 'Submitting request…' : 'Submit request',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
