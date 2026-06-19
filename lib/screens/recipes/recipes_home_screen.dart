// Spec: specs/067-planear-menu-ia-ux/spec.md
//
// Pantalla inicial del módulo "Mi menú" (F043 + F067). Caminos asistidos por IA
// para armar el menú (ver recetas, importar de la cámara, planear, dictar por
// voz) + un PREVIEW en vivo de "cómo se ve hoy su menú en línea": el catálogo
// público y el menú del día con los platos activos (misma resolución que el
// link público). Normalizada al kit AppUI (Spec 062/067).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/shimmer_box.dart';
import 'menu_import_screen.dart';
import 'menu_planner_screen.dart';
import 'recipe_list_screen.dart';
import 'recipe_voice_screen.dart';

class RecipesHomeScreen extends StatelessWidget {
  /// Inyectable para test (el preview usa este API). En producción se crea uno.
  final ApiService? api;
  const RecipesHomeScreen({super.key, this.api});

  void _go(BuildContext context, Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  // Fase 2 (F043): importar el menú desde una foto de la carta. Toma la foto,
  // la manda al endpoint de IA `/menu/scan-photo` y abre el editor de platos
  // (MenuImportScreen) para que el tendero revise/edite antes de publicar.
  // Web-safe: usa XFile.readAsBytes() + bytes (no dart:io File ni XFile.path).
  Future<void> _importFromCamera(BuildContext context) async {
    HapticFeedback.lightImpact();
    final source = await _pickSource(context);
    if (source == null || !context.mounted) return;

    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (photo == null || !context.mounted) return;

    final bytes = await photo.readAsBytes();
    const maxBytes = 8 * 1024 * 1024; // 8 MB (igual que el backend)
    if (bytes.lengthInBytes > maxBytes) {
      if (!context.mounted) return;
      _snack(context,
          'La foto es muy pesada. Tómela con buena luz y un poco más de lejos.',
          color: AppTheme.warning);
      return;
    }
    if (!context.mounted) return;

    // Loading bloqueante mientras la IA lee la carta.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ScanningDialog(),
    );

    try {
      final svc = api ?? ApiService(AuthService());
      final dishes = await svc.scanMenuPhoto(
        imageBytes: bytes,
        mimeType: photo.mimeType ?? 'image/jpeg',
        filename: photo.name.isNotEmpty ? photo.name : 'menu.jpg',
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // cierra el loading

      if (dishes.isEmpty) {
        _snack(context,
            'No encontramos platos en la foto. Asegúrese de que se vea la '
            'carta con buena luz, o arme su menú a mano.',
            color: AppTheme.warning);
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MenuImportScreen(scannedDishes: dishes),
      ));
    } on AppError catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _snack(context, e.message, color: AppTheme.error);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _snack(context, 'No pudimos leer su menú. Intente de nuevo.',
          color: AppTheme.error);
    }
  }

  Future<ImageSource?> _pickSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('menu_source_camera'),
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppTheme.primary),
              title: const Text('Tomar foto', style: TextStyle(fontSize: 16)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              key: const Key('menu_source_gallery'),
              leading:
                  const Icon(Icons.photo_library_rounded, color: AppTheme.primary),
              title: const Text('Elegir de la galería',
                  style: TextStyle(fontSize: 16)),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(BuildContext context, String msg, {required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 15)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Mi menú', style: AppUI.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s24),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: AppUI.s16, left: AppUI.s4),
            child: Text(
              'Arme su menú como le quede más fácil. La IA le ayuda con la foto, '
              'la descripción y las porciones — y todo lo puede editar.',
              style: AppUI.bodySoft,
            ),
          ),
          // Preview en vivo de cómo se ve hoy el menú en el link público.
          _MenuTodayPreview(api: api),
          const SizedBox(height: AppUI.s16),
          const Padding(
            padding: EdgeInsets.only(left: AppUI.s4, bottom: AppUI.s8),
            child: Text('Arme su menú', style: AppUI.sectionLabel),
          ),
          _OptionCard(
            key: const Key('recipes_option_list'),
            icon: Icons.menu_book_rounded,
            color: AppTheme.primary,
            title: 'Ver mis recetas',
            subtitle: 'Revise sus platos, costos y ganancias.',
            onTap: () => _go(context, const RecipeListScreen()),
          ),
          const SizedBox(height: AppUI.s12),
          _OptionCard(
            key: const Key('recipes_option_camera'),
            icon: Icons.photo_camera_rounded,
            color: const Color(0xFFEE5A24),
            title: 'Importar menú desde la cámara',
            subtitle: 'Tome una foto de su carta y la IA arma los platos.',
            onTap: () => _importFromCamera(context),
          ),
          const SizedBox(height: AppUI.s12),
          // Spec 066 — "Planear menú" arma el menú semanal que alimenta el link.
          _OptionCard(
            key: const Key('recipes_option_plan'),
            icon: Icons.calendar_month_rounded,
            color: AppTheme.primary,
            title: 'Planear menú',
            subtitle: 'Arme el menú de la semana; su link en línea muestra el del día.',
            onTap: () => _go(context, const MenuPlannerScreen()),
          ),
          const SizedBox(height: AppUI.s12),
          _OptionCard(
            key: const Key('recipes_option_voice'),
            icon: Icons.mic_rounded,
            color: const Color(0xFF7C3AED),
            title: 'Dictar receta desde el micrófono',
            subtitle: 'Diga su receta en voz alta y la IA la organiza.',
            onTap: () => _go(context, const RecipeVoiceScreen()),
          ),
        ],
      ),
    );
  }
}

/// Preview en vivo: el catálogo en línea + el menú del día con los platos
/// activos, resuelto igual que el link público (Spec 067).
class _MenuTodayPreview extends StatefulWidget {
  final ApiService? api;
  const _MenuTodayPreview({this.api});

  @override
  State<_MenuTodayPreview> createState() => _MenuTodayPreviewState();
}

class _MenuTodayPreviewState extends State<_MenuTodayPreview> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  bool _loading = true;
  String _slug = '';
  Map<String, dynamic>? _today;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([
        _api.fetchStoreConfig(),
        _api.fetchMenuToday(),
      ]);
      if (!mounted) return;
      setState(() {
        _slug = (res[0]['store_slug'] ?? '').toString();
        _today = res[1];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _url =>
      _slug.isEmpty ? '' : ApiConfig.publicCatalogUrlFor(_slug);

  Future<void> _open() async {
    if (_url.isEmpty) return;
    HapticFeedback.lightImpact();
    await launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication);
  }

  Future<void> _copy() async {
    if (_url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Link copiado', style: TextStyle(fontSize: 15)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.public_rounded, color: AppTheme.primary, size: 20),
              SizedBox(width: AppUI.s8),
              Expanded(
                child: Text('Así se ve hoy su menú en línea',
                    style: AppUI.bodyStrong),
              ),
            ],
          ),
          const SizedBox(height: AppUI.s12),
          if (_loading)
            const _PreviewSkeleton()
          else ...[
            _linkRow(),
            const SizedBox(height: AppUI.s12),
            const Divider(height: 1, color: AppUI.hairline),
            const SizedBox(height: AppUI.s12),
            _menuOfDay(),
          ],
        ],
      ),
    );
  }

  Widget _linkRow() {
    if (_url.isEmpty) {
      return const Text('Configure su tienda para tener un link en línea.',
          style: AppUI.bodySoft);
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Su catálogo en línea', style: AppUI.sectionLabel),
              Text(_url.replaceFirst('https://', ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppUI.bodyStrong),
            ],
          ),
        ),
        IconButton(
          key: const Key('menu_preview_copy'),
          icon: const Icon(Icons.copy_rounded, size: 20, color: AppUI.inkSoft),
          tooltip: 'Copiar link',
          onPressed: _copy,
        ),
        IconButton(
          key: const Key('menu_preview_open'),
          icon: const Icon(Icons.open_in_new_rounded,
              size: 20, color: AppTheme.primary),
          tooltip: 'Abrir',
          onPressed: _open,
        ),
      ],
    );
  }

  Widget _menuOfDay() {
    final t = _today;
    if (t == null) {
      return const Text('No pudimos cargar el menú de hoy.',
          style: AppUI.bodySoft);
    }
    final active = t['active'] == true;
    final found = t['found'] == true;
    if (!active) {
      return const _PreviewHint(
        icon: Icons.event_note_rounded,
        text: 'Aún no ha planeado su menú. Use "Planear menú" para que su link '
            'muestre el plato del día.',
      );
    }
    if (!found) {
      return const _PreviewHint(
        icon: Icons.coffee_rounded,
        text: 'Hoy no hay menú publicado en su link.',
      );
    }
    final items = (t['items'] as List?) ?? [];
    final dayLabel = (t['day_label'] ?? '').toString();
    final weekday = (t['weekday'] ?? '').toString();
    final header = dayLabel.isNotEmpty
        ? dayLabel
        : (weekday.isEmpty ? 'Menú de hoy' : 'Menú de hoy · $weekday');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(header, style: AppUI.bodyStrong)),
            MinimalBadge(
                label: '${items.length} plato${items.length == 1 ? '' : 's'}',
                color: AppTheme.success),
          ],
        ),
        const SizedBox(height: AppUI.s8),
        Wrap(
          spacing: AppUI.s8,
          runSpacing: AppUI.s8,
          children: [
            for (final it in items)
              _DishPill(name: ((it as Map)['name'] ?? 'Plato').toString()),
          ],
        ),
      ],
    );
  }
}

class _DishPill extends StatelessWidget {
  final String name;
  const _DishPill({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppUI.s12, vertical: 6),
      decoration: BoxDecoration(
        color: AppUI.pageBg,
        borderRadius: BorderRadius.circular(AppUI.radiusSm),
        border: Border.all(color: AppUI.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.restaurant_rounded, size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(name, style: AppUI.bodyStrong),
        ],
      ),
    );
  }
}

class _PreviewHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PreviewHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppUI.inkSoft),
        const SizedBox(width: AppUI.s8),
        Expanded(child: Text(text, style: AppUI.bodySoft)),
      ],
    );
  }
}

class _PreviewSkeleton extends StatelessWidget {
  const _PreviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShimmerBox(width: 220, height: 14),
        SizedBox(height: AppUI.s12),
        ShimmerBox(width: 140, height: 14),
        SizedBox(height: AppUI.s8),
        ShimmerBox(width: double.infinity, height: 28),
      ],
    );
  }
}

class _ScanningDialog extends StatelessWidget {
  const _ScanningDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 20),
            Text(
              'Leyendo su menú con IA…',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              'Esto puede tardar unos segundos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de opción del hub, normalizada al kit AppUI (tarjeta blanca con
/// sombra difusa + tile de ícono tintado, sin bordes pesados).
class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppUI.radius),
        child: Container(
          padding: const EdgeInsets.all(AppUI.s12),
          decoration: AppUI.card(),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUI.radius),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: AppUI.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppUI.bodyStrong),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppUI.bodySoft),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppUI.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
