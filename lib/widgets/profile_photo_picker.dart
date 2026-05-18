// Spec: specs/019-foto-perfil-tendero-empleado/spec.md
//
// "Cargar foto" surface for the owner (tendero) and each employee.
//
// Spec 019 / FR-03, AC-01, AC-02: the profile screen shows the photo as
// a circular avatar plus a button to load a new one — from the CAMERA
// or the GALLERY — cross-platform (web, including iOS Safari, and
// mobile). The upload reuses `ApiService.uploadEmployeePhoto`, which
// normalizes the image to PNG and sends it by BYTES (FR-04, AC-04 — no
// `dart:io` on the web path).
//
// This widget is self-contained: it owns the picked-image preview, the
// upload call, the loading spinner and the Spanish error/success
// messages. When the upload succeeds it reports the new `photo_url`
// back through [onUploaded] so the parent screen can refresh its state.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/app_error.dart';
import '../services/image_normalizer.dart' show ImageNormalizationException;
import 'profile_photo_avatar.dart';

/// Card with a circular profile avatar and a "Cargar foto" action that
/// lets the merchant take a photo or pick one from the gallery.
class ProfilePhotoPicker extends StatefulWidget {
  const ProfilePhotoPicker({
    super.key,
    required this.api,
    required this.employeeUuid,
    required this.name,
    this.photoUrl,
    this.onUploaded,
    this.isOwner = false,
  });

  /// API client used to upload the picked photo.
  final ApiService api;

  /// UUID of the employee (or owner) whose photo this is.
  final String employeeUuid;

  /// Full name — feeds the initials placeholder when there is no photo.
  final String name;

  /// Currently persisted photo URL, if any.
  final String? photoUrl;

  /// Called with the new `photo_url` after a successful upload, so the
  /// parent screen can update its own state / reload its list.
  final ValueChanged<String>? onUploaded;

  /// Whether this profile is the business owner — only changes the
  /// helper copy, not the behavior.
  final bool isOwner;

  @override
  State<ProfilePhotoPicker> createState() => _ProfilePhotoPickerState();
}

class _ProfilePhotoPickerState extends State<ProfilePhotoPicker> {
  /// The image the merchant just picked but has not uploaded yet.
  XFile? _picked;

  /// Latest persisted URL — starts from the widget, advances on upload.
  String? _photoUrl;

  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.photoUrl;
  }

  void _flash(String msg, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 15)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? const Color(0xFFDC2626) : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Picks an image from [source] and uploads it. Bounds the image at
  /// 1024px so the upload stays small on a low-end Android (Art. I).
  Future<void> _pickAndUpload(ImageSource source) async {
    HapticFeedback.selectionClick();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _picked = picked;
      _uploading = true;
    });
    try {
      final data = await widget.api.uploadEmployeePhoto(
        widget.employeeUuid,
        picked,
      );
      final newUrl = data['photo_url'] as String?;
      if (!mounted) return;
      if (newUrl != null && newUrl.isNotEmpty) {
        setState(() {
          _photoUrl = newUrl;
          _picked = null;
        });
        widget.onUploaded?.call(newUrl);
        _flash('Foto de perfil actualizada');
      } else {
        setState(() => _picked = null);
        _flash('No pudimos guardar la foto. Intenta de nuevo.',
            isError: true);
      }
    } on ImageNormalizationException catch (e) {
      // Spec 019 / FR-04: the picked image could not be decoded — show
      // the clear Spanish message, never a raw exception dump.
      if (mounted) {
        setState(() => _picked = null);
        _flash(e.message, isError: true);
      }
    } on AppError catch (e) {
      if (mounted) {
        setState(() => _picked = null);
        _flash(e.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showSourceSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Foto de perfil',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 16),
            _SourceTile(
              key: const Key('profile_photo_source_camera'),
              icon: Icons.camera_alt_rounded,
              label: 'Tomar foto',
              subtitle: 'Usa la cámara del teléfono',
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndUpload(ImageSource.camera);
              },
            ),
            const SizedBox(height: 12),
            _SourceTile(
              key: const Key('profile_photo_source_gallery'),
              icon: Icons.photo_library_rounded,
              label: 'Elegir de la galería',
              subtitle: 'Selecciona una imagen guardada',
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndUpload(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            ProfilePhotoAvatar(
              name: widget.name,
              photoUrl: _photoUrl,
              pickedPreview: _picked,
              diameter: 104,
            ),
            // Small camera badge over the avatar — a familiar
            // "edit photo" affordance.
            Material(
              color: const Color(0xFF1A2FA0),
              shape: const CircleBorder(),
              child: InkWell(
                key: const Key('profile_photo_edit_badge'),
                customBorder: const CircleBorder(),
                onTap: _uploading ? null : _showSourceSheet,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.camera_alt_rounded,
                      size: 20, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('profile_photo_load_button'),
            onPressed: _uploading ? null : _showSourceSheet,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.add_a_photo_rounded, size: 22),
            label: Text(
              _uploading
                  ? 'Subiendo foto...'
                  : (_photoUrl == null && _picked == null
                      ? 'Cargar foto'
                      : 'Cambiar foto'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1A2FA0),
              side: const BorderSide(color: Color(0xFF1A2FA0)),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One row in the camera/gallery picker bottom sheet.
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F5FB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1A2FA0).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF1A2FA0), size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
