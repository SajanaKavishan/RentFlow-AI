import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/models/current_user.dart';
import '../theme/app_theme.dart';

String profileInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  if (words.isEmpty) return '?';
  return words
      .take(2)
      .map((word) => word.characters.first.toUpperCase())
      .join();
}

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.user,
    this.preview,
    this.radius = 34,
  });
  final CurrentUser user;
  final Uint8List? preview;
  final double radius;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  AuthController? _controller;
  String? _userId;
  int? _revision;
  bool? _hasImage;
  Future<Uint8List?>? _photo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final controller = AuthScope.maybeOf(context);
    if (_controller == controller &&
        _userId == widget.user.id &&
        _revision == controller?.profileImageRevision &&
        _hasImage == widget.user.hasProfileImage) {
      return;
    }
    _controller = controller;
    _userId = widget.user.id;
    _revision = controller?.profileImageRevision;
    _hasImage = widget.user.hasProfileImage;
    _photo = widget.user.hasProfileImage
        ? controller?.loadProfileImage()
        : null;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    // A changed revision discards FutureBuilder's previous image immediately.
    key: ValueKey('${widget.user.id}-$_revision'),
    future: _photo,
    builder: (context, snapshot) {
      final bytes =
          widget.preview ??
          (snapshot.connectionState == ConnectionState.done
              ? snapshot.data
              : null);
      final initials = Text(
        profileInitials(widget.user.fullName),
        style: AppTypography.identityName,
      );
      return Semantics(
        image: true,
        label:
            'Profile photo for ${widget.user.fullName.trim().isEmpty ? 'your account' : widget.user.fullName}',
        child: ExcludeSemantics(
          child: CircleAvatar(
            radius: widget.radius,
            backgroundColor: AppPalette.sage,
            foregroundColor: AppPalette.darkOlive,
            child: bytes == null
                ? initials
                : ClipOval(
                    child: Image.memory(
                      bytes,
                      width: widget.radius * 2,
                      height: widget.radius * 2,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          Center(child: initials),
                    ),
                  ),
          ),
        ),
      );
    },
  );
}
