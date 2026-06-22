import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Reusable widget that lets the cashier attach the photo of a
/// digital-payment receipt. Required for every non-cash payment;
/// the parent disables its primary button until [onImageReady]
/// fires with a non-null Supabase URL.
///
/// The widget owns the upload to Supabase Storage. Parents should
/// treat the URL as opaque audit evidence — the actual blob is
/// purged automatically after 8 days by a server-side cron.
class ReceiptImagePicker extends StatefulWidget {
  const ReceiptImagePicker({
    super.key,
    required this.onImageReady,
    this.label = 'Adjuntar comprobante',
  });

  /// Fires with the public Supabase URL once the image is uploaded,
  /// or with `null` when the cashier removes the attached image so
  /// the parent can re-disable its confirm button.
  final ValueChanged<String?> onImageReady;
  final String label;

  /// Literal warning the PO mandates so the cashier knows storage
  /// is ephemeral. Exposed as a const so the widget tests can
  /// assert the exact wording.
  static const String legalWarning =
      '⚠️ Estos comprobantes se eliminarán de la nube en 8 días. '
      'Guarde en su galería los que necesite.';

  @override
  State<ReceiptImagePicker> createState() => _ReceiptImagePickerState();
}

class _ReceiptImagePickerState extends State<ReceiptImagePicker> {
  /// Bytes de la imagen elegida (web-safe: NUNCA `dart:io File`/`XFile.path`).
  /// Se previsualizan con Image.memory mientras sube. null = nada elegido.
  Uint8List? _localBytes;
  String? _uploadedUrl;
  bool _uploading = false;

  Future<void> _pick(ImageSource source) async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;

    // Lee los BYTES (funciona en web e iOS); el path es un blob URL en web.
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _localBytes = bytes;
      _uploading = true;
      _uploadedUrl = null;
    });
    // Notify the parent NOW so the button stays disabled while we
    // upload — we never want a state where the cashier sees a
    // preview but the URL is still null and the parent thinks it's
    // green-lit.
    widget.onImageReady(null);

    try {
      final url = await ApiService(AuthService()).uploadReceipt(picked);
      if (!mounted) return;
      setState(() {
        _uploadedUrl = url;
        _uploading = false;
      });
      widget.onImageReady(url);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localBytes = null;
        _uploadedUrl = null;
        _uploading = false;
      });
      widget.onImageReady(null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFDC2626),
          content: Text('No se pudo subir el comprobante. Intenta de nuevo.',
              style: TextStyle(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _remove() {
    setState(() {
      _localBytes = null;
      _uploadedUrl = null;
    });
    widget.onImageReady(null);
  }

  Future<void> _showSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: Color(0xFF1D4ED8), size: 28),
              title: const Text('Tomar foto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFF1D4ED8), size: 28),
              title: const Text('Elegir de la galería',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_localBytes == null)
          ElevatedButton.icon(
            onPressed: _uploading ? null : _showSourceSheet,
            icon: const Icon(Icons.attach_file_rounded, size: 22),
            label: Text(widget.label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD6D0C8)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_localBytes!,
                      width: 64, height: 64, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _uploading
                            ? 'Subiendo comprobante…'
                            : '✅ Comprobante adjunto',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      if (_uploadedUrl != null)
                        const Text('Listo para registrar',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
                if (_uploading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFF6B7280)),
                    onPressed: _remove,
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            border: Border.all(color: const Color(0xFFFCD34D)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            ReceiptImagePicker.legalWarning,
            style: TextStyle(
                fontSize: 13, color: Color(0xFF92400E), height: 1.35),
          ),
        ),
      ],
    );
  }
}
