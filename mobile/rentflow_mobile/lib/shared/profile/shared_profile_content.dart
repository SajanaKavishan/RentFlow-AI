import 'package:flutter/material.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/models/current_user.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'public_contact_editor.dart';

class SharedProfileContent extends StatelessWidget {
  const SharedProfileContent({
    super.key,
    required this.user,
    this.onOpenApplications,
  });

  final CurrentUser user;
  final VoidCallback? onOpenApplications;

  void _showDetails(
    BuildContext context, {
    required String title,
    required Map<String, String> values,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: AppSpacing.page,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'These details are read-only. Editing is unavailable.',
              ),
              for (final entry in values.entries) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(entry.key, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  _availableValue(entry.value),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AuthenticatedPage(
    maxWidth: 580,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: AppPalette.sage,
                foregroundColor: AppPalette.darkOlive,
                child: Text(
                  _initials(user.fullName),
                  style: AppTypography.pageTitle,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                _availableValue(user.fullName),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _availableValue(user.email),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ProfileSection(
          title: 'Account',
          children: [
            _ProfileTile(
              icon: Icons.person_outline,
              title: 'Personal information',
              subtitle: 'View your account details',
              onTap: () => _showDetails(
                context,
                title: 'Personal information',
                values: {'Full name': user.fullName},
              ),
            ),
            _ProfileTile(
              icon: Icons.alternate_email,
              title: 'Email & phone',
              subtitle: 'View your contact details',
              onTap: () => _showDetails(
                context,
                title: 'Email & phone',
                values: {'Email': user.email, 'Phone number': user.phoneNumber},
              ),
            ),
            const _ProfileTile(
              icon: Icons.lock_outline,
              title: 'Password & security',
              subtitle: 'Not available yet',
            ),
            if (user.role == UserRole.landlord)
              _ProfileTile(
                icon: Icons.phone_outlined,
                title: 'Public contact',
                subtitle: 'Manage contact for your property listings',
                onTap: () {
                  final auth = AuthScope.of(context);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    builder: (_) => PublicContactEditor(
                      loadUser: auth.authService.getCurrentUser,
                      save: auth.updatePublicContact,
                    ),
                  );
                },
              ),
            if (user.role == UserRole.tenant)
              _ProfileTile(
                icon: Icons.folder_outlined,
                title: 'My documents',
                subtitle: onOpenApplications == null
                    ? 'Not available yet'
                    : 'View documents in your applications',
                onTap: onOpenApplications,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ProfileSection(
          title: 'Preferences',
          children: [
            _ProfileTile(
              icon: Icons.notifications_none_outlined,
              title: 'Notifications',
              subtitle: 'Not available yet',
            ),
            _ProfileTile(
              icon: Icons.language_outlined,
              title: 'Language',
              subtitle: 'Not available yet',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ProfileSection(
          title: 'Support',
          children: [
            _ProfileTile(
              icon: Icons.help_outline,
              title: 'Help & support',
              subtitle: 'Not available yet',
            ),
            // The existing feedback service has no delivery transport.
            _ProfileTile(
              icon: Icons.chat_bubble_outline,
              title: 'Feedback',
              subtitle: 'Message delivery unavailable',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          key: const Key('profile-sign-out'),
          onPressed: () => AuthScope.of(context).logout(),
          icon: const Icon(Icons.logout, size: 20),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppPalette.danger,
            side: const BorderSide(color: AppPalette.outline),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'RentFlow AI v2.4.1 · © 2026',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppPalette.secondaryText.withValues(alpha: 0.55),
            fontSize: AppTypography.captionSize,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ),
  );
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index < children.length - 1)
                const Divider(
                  height: 1,
                  indent: 56,
                  endIndent: AppSpacing.base,
                ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppPalette.olive),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppPalette.secondaryText,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

String _availableValue(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Not provided' : trimmed;
}

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  if (words.isEmpty) return '?';
  return words
      .take(2)
      .map((word) => word.characters.first.toUpperCase())
      .join();
}
