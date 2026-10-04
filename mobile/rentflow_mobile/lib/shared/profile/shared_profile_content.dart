import 'package:flutter/material.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/models/current_user.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import 'public_contact_editor.dart';
import 'personal_information_screen.dart';
import 'profile_avatar.dart';

class SharedProfileContent extends StatelessWidget {
  const SharedProfileContent({
    super.key,
    required this.user,
    this.onOpenApplications,
    this.onOpenReviews,
  });

  final CurrentUser user;
  final VoidCallback? onOpenApplications;
  final VoidCallback? onOpenReviews;

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthScope.maybeOf(context)?.currentUser ?? user;
    return AuthenticatedPage(
      maxWidth: 580,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
            child: Column(
              children: [
                ProfileAvatar(user: currentUser),
                const SizedBox(height: AppSpacing.base),
                Text(
                  _availableValue(currentUser.fullName),
                  textAlign: TextAlign.center,
                  style: AppTypography.identityName,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _availableValue(currentUser.email),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall,
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
                subtitle: 'Update your photo, name, and phone number',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        PersonalInformationScreen(user: currentUser),
                  ),
                ),
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
                  title: 'Application documents',
                  subtitle: 'View documents in your applications',
                  onTap: onOpenApplications,
                ),
              if (user.role == UserRole.landlord)
                _ProfileTile(
                  icon: Icons.star_outline,
                  title: 'Reviews',
                  subtitle: 'Read verified viewing feedback',
                  onTap: onOpenReviews,
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
