import 'package:flutter/material.dart';

import '../../features/notifications/models/notification_preferences.dart';
import '../../features/notifications/services/notification_preferences_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key, required this.service});
  final NotificationPreferencesApiService service;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  NotificationPreferences? _confirmed;
  NotificationPreferences? _draft;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _saveError;
  String? _success;

  bool get _dirty =>
      _draft != null &&
      _confirmed != null &&
      (_draft!.viewingUpdatesEnabled != _confirmed!.viewingUpdatesEnabled ||
          _draft!.rentalApplicationUpdatesEnabled !=
              _confirmed!.rentalApplicationUpdatesEnabled);

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _message(Object error, String fallback) =>
      error is NotificationPreferencesApiException ? error.message : fallback;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final preferences = await widget.service.getNotificationPreferences();
      if (!mounted) return;
      setState(() {
        _confirmed = preferences;
        _draft = preferences;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _loadError = _message(
            error,
            'Notification preferences could not be loaded. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _edit(NotificationPreferences draft) {
    if (_saving) return;
    setState(() {
      _draft = draft;
      _saveError = null;
      _success = null;
    });
  }

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    final requested = _draft!;
    setState(() {
      _saving = true;
      _saveError = null;
      _success = null;
    });
    try {
      final confirmed = await widget.service.updateNotificationPreferences(
        viewingUpdatesEnabled: requested.viewingUpdatesEnabled,
        rentalApplicationUpdatesEnabled:
            requested.rentalApplicationUpdatesEnabled,
      );
      if (!mounted) return;
      setState(() {
        _confirmed = confirmed;
        _draft = confirmed;
        _success = 'Notification preferences saved.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _saveError = _message(
            error,
            'Notification preferences could not be saved. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to Profile',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('PROFILE', style: AppTypography.eyebrow),
      ),
      body: AuthenticatedPage(
        maxWidth: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Notifications', style: AppTypography.pageTitle),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Choose what updates you want to receive.',
              style: AppTypography.body,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_loading)
              Semantics(
                liveRegion: true,
                child: const LoadingState(
                  title: 'Loading notification preferences…',
                  compact: true,
                ),
              )
            else if (_loadError != null)
              Semantics(
                liveRegion: true,
                child: SharedState(
                  title: 'Notification preferences unavailable',
                  message: _loadError,
                  icon: Icons.cloud_off_outlined,
                  actionLabel: 'Retry',
                  onAction: _load,
                  compact: true,
                ),
              )
            else ...[
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _PreferenceRow(
                      id: 'preference-viewing',
                      title: 'Viewing updates',
                      description:
                          'Receive updates when viewing requests change.',
                      value: _draft!.viewingUpdatesEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => _edit(
                              _draft!.copyWith(viewingUpdatesEnabled: value),
                            ),
                    ),
                    const Divider(
                      height: 1,
                      indent: AppSpacing.base,
                      endIndent: AppSpacing.base,
                    ),
                    _PreferenceRow(
                      id: 'preference-applications',
                      title: 'Rental application updates',
                      description:
                          'Receive updates when rental applications change.',
                      value: _draft!.rentalApplicationUpdatesEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => _edit(
                              _draft!.copyWith(
                                rentalApplicationUpdatesEnabled: value,
                              ),
                            ),
                    ),
                    const Divider(
                      height: 1,
                      indent: AppSpacing.base,
                      endIndent: AppSpacing.base,
                    ),
                    _PreferenceRow(
                      id: 'preference-security',
                      title: 'Account security updates',
                      description:
                          'Required for important account and security activity. This setting cannot be turned off.',
                      value: _draft!.accountSecurityUpdatesEnabled,
                      requiredSetting: true,
                    ),
                  ],
                ),
              ),
              if (_saveError != null || _success != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.base),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _saveError ?? _success!,
                      key: const Key('preferences-feedback'),
                      style: AppTypography.body.copyWith(
                        color: _saveError != null
                            ? AppPalette.danger
                            : AppPalette.success,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Semantics(
                liveRegion: _saving,
                child: FilledButton(
                  key: const Key('preferences-save'),
                  onPressed: _dirty && !_saving ? _save : null,
                  child: Text(_saving ? 'Saving changes…' : 'Save changes'),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.id,
    required this.title,
    required this.description,
    required this.value,
    this.onChanged,
    this.requiredSetting = false,
  });
  final String id;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool requiredSetting;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.cardTitle)),
              const SizedBox(width: AppSpacing.sm),
              Switch(
                key: Key(id),
                value: value,
                onChanged: onChanged,
                activeTrackColor: AppPalette.olive,
                activeThumbColor: AppPalette.white,
              ),
            ],
          ),
          if (requiredSetting) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text('Always on', style: AppTypography.bodySmall),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(description, style: AppTypography.bodySmall),
        ],
      ),
    ),
  );
}
