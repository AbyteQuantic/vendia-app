// Spec: specs/019-foto-perfil-tendero-empleado/spec.md
//
// Circular profile avatar for the owner (tendero) and each employee.
//
// Spec 019 / D3 / FR-05: the profile photo is shown as a circular
// avatar. When there is no photo yet, the avatar falls back to the
// initials of the person's name over a solid background — never an
// empty hole, so the screen always reads cleanly (Constitution Art. I).
//
// The widget renders, in priority order:
//   1. [pickedPreview] — an image the merchant JUST picked but has not
//      uploaded yet (an `XFile`). Uses [PickedImagePreview], which is
//      cross-platform (no `dart:io` on the web path).
//   2. [photoUrl]       — a persisted photo from the backend, fetched
//      over the network.
//   3. initials of [name] — the placeholder when neither exists.
//
// This is display-only. The upload itself goes through
// `ApiService.uploadEmployeePhoto`, which normalizes the image to PNG.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'picked_image_preview.dart';

/// Shows a person's profile photo as a circular avatar, with an
/// initials placeholder when no photo is available.
class ProfilePhotoAvatar extends StatelessWidget {
  const ProfilePhotoAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.pickedPreview,
    this.diameter = 96,
    this.backgroundColor = const Color(0xFF1A2FA0),
  });

  /// Full name of the person — used to derive the initials placeholder.
  final String name;

  /// Persisted photo URL from the backend. Null / empty -> placeholder.
  final String? photoUrl;

  /// An image the merchant just picked but has not uploaded yet. When
  /// set it takes precedence over [photoUrl] so the preview is instant.
  final XFile? pickedPreview;

  /// Outer diameter of the circular avatar in logical pixels.
  final double diameter;

  /// Background color shown behind the initials placeholder.
  final Color backgroundColor;

  /// Initials derived from [name] — up to two letters (e.g. "María
  /// López" -> "ML"). Falls back to "?" for an empty name.
  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  bool get _hasPhotoUrl => photoUrl != null && photoUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (pickedPreview != null) {
      content = PickedImagePreview(
        file: pickedPreview!,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else if (_hasPhotoUrl) {
      content = Image.network(
        photoUrl!,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(),
      );
    } else {
      content = _placeholder();
    }

    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: content,
      ),
    );
  }

  /// Initials over a solid background — the no-photo fallback.
  Widget _placeholder() {
    return Container(
      width: diameter,
      height: diameter,
      color: backgroundColor,
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: diameter * 0.36,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
