// Spec: specs/070-galeria-multimedia-producto/spec.md
//
// Editor de galería multimedia de un producto: agrega imágenes extra, un link
// de YouTube y un video corto (≤25s, grabado o de galería). El servidor es la
// autoridad del límite; aquí se limita la grabación a 25s y se muestran los
// errores del backend en USTED. Web-safe: solo bytes (XFile), nunca dart:io.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/app_error.dart';
import '../theme/app_theme.dart';
import '../theme/app_ui.dart';

class ProductMediaEditor extends StatefulWidget {
  final String productId;
  final ApiService api;
  const ProductMediaEditor({super.key, required this.productId, required this.api});

  @override
  State<ProductMediaEditor> createState() => _ProductMediaEditorState();
}

class _ProductMediaEditorState extends State<ProductMediaEditor> {
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _media = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await widget.api.fetchProductMedia(widget.productId);
      if (mounted) setState(() { _media = m; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final row = await action();
      if (mounted) setState(() => _media = [..._media, row]);
    } on AppError catch (e) {
      _snack(e.message, AppTheme.error);
    } catch (_) {
      _snack('No pudimos agregar el elemento. Intente de nuevo.', AppTheme.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addImage() async {
    final x = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (x == null) return;
    await _run(() => widget.api.addProductMediaImage(widget.productId, x));
  }

  Future<void> _addVideo(ImageSource source) async {
    // maxDuration limita la GRABACIÓN a 25s; para galería el server es la
    // autoridad (rechaza >25s / >8MB con mensaje en español).
    final x = await _picker.pickVideo(
        source: source, maxDuration: const Duration(seconds: 25));
    if (x == null) return;
    await _run(() => widget.api.addProductMediaVideo(widget.productId, x));
  }

  Future<void> _addYouTube() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar video de YouTube', style: AppUI.title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'Pegue el link de YouTube',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Agregar')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _run(() => widget.api.addProductMediaYouTube(widget.productId, url));
  }

  Future<void> _videoSourceSheet() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.videocam_rounded, color: AppTheme.primary),
            title: const Text('Grabar video (máx. 25 seg)'),
            onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_rounded, color: AppTheme.primary),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src != null) await _addVideo(src);
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final id = (m['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await widget.api.deleteProductMedia(widget.productId, id);
      if (mounted) setState(() => _media.removeWhere((e) => e['id'] == id));
    } catch (_) {
      _snack('No pudimos eliminar el elemento.', AppTheme.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fotos y videos', style: AppUI.bodyStrong),
        const SizedBox(height: 4),
        const Text(
          'Agregue más fotos, un video corto (máx. 25 seg) o un link de YouTube. '
          'Sus clientes los verán en un carrusel.',
          style: AppUI.bodySoft,
        ),
        const SizedBox(height: AppUI.s12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_media.isNotEmpty)
          Wrap(
            spacing: AppUI.s8,
            runSpacing: AppUI.s8,
            children: [for (final m in _media) _thumb(m)],
          ),
        const SizedBox(height: AppUI.s12),
        Wrap(
          spacing: AppUI.s8,
          runSpacing: AppUI.s8,
          children: [
            GhostButton(
              key: const Key('media_add_image'),
              icon: Icons.add_photo_alternate_rounded,
              label: 'Foto',
              color: AppTheme.primary,
              onPressed: _busy ? null : _addImage,
            ),
            GhostButton(
              key: const Key('media_add_video'),
              icon: Icons.videocam_rounded,
              label: 'Video',
              color: AppTheme.primary,
              onPressed: _busy ? null : _videoSourceSheet,
            ),
            GhostButton(
              key: const Key('media_add_youtube'),
              icon: Icons.smart_display_rounded,
              label: 'YouTube',
              color: const Color(0xFFEE3A3A),
              onPressed: _busy ? null : _addYouTube,
            ),
          ],
        ),
      ],
    );
  }

  Widget _thumb(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString();
    final thumb = (m['thumbnail'] ?? '').toString();
    final url = (m['url'] ?? '').toString();
    final isVideo = type == 'video';
    final isYouTube = type == 'youtube';
    final img = thumb.isNotEmpty ? thumb : (type == 'image' ? url : '');
    return SizedBox(
      key: Key('media_thumb_${m['id']}'),
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppUI.radiusSm),
            child: img.isNotEmpty
                ? Image.network(img, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(isVideo, isYouTube))
                : _placeholder(isVideo, isYouTube),
          ),
          if (isVideo || isYouTube)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white, size: 28),
            ),
          Positioned(
            top: -6,
            right: -6,
            child: IconButton(
              key: Key('media_delete_${m['id']}'),
              iconSize: 18,
              icon: const Icon(Icons.cancel, color: Colors.black54),
              onPressed: () => _delete(m),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(bool isVideo, bool isYouTube) => Container(
        color: AppUI.pageBg,
        child: Icon(
          isYouTube
              ? Icons.smart_display_rounded
              : isVideo
                  ? Icons.videocam_rounded
                  : Icons.image_rounded,
          color: AppUI.inkSoft,
        ),
      );
}
