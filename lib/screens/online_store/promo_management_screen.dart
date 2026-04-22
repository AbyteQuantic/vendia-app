import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Marketing Hub — lista de promociones reales del tenant + link
/// público del catálogo y acciones de compartir (WhatsApp / share
/// nativo).
///
/// Antes de este refactor la pantalla mostraba 3 ofertas quemadas
/// (Perro Caliente, Hamburguesa, Jugo). Ahora consume:
///   * `GET /api/v1/store/slug` — enlace público del catálogo
///     (se autogenera en el backend la primera vez).
///   * `GET /api/v1/promotions` — promociones del tenant (con items
///     preloaded, ya filtradas por `is_active=true`).
///
/// Exposed as a StatefulWidget con un [ApiService] opcional para que
/// los widget tests puedan inyectar un fake sin montar todo el grafo
/// de Auth/Dio.
class PromoManagementScreen extends StatefulWidget {
  /// Inyectable solo en tests. En runtime se construye un [ApiService]
  /// a partir del [AuthService] por defecto.
  final ApiService? apiService;

  const PromoManagementScreen({super.key, this.apiService});

  @override
  State<PromoManagementScreen> createState() => _PromoManagementScreenState();
}

/// View model de una promoción ya lista para pintar. Se construye a
/// partir del JSON del backend (que puede venir en dos shapes:
/// combo moderno con items[] o single-product legacy) — ambos casos
/// terminan en la misma representación plana.
class _PromoVM {
  final String id;
  final String title;
  final String subtitle; // items compactados o descripción
  final double totalPromo;
  final double totalRegular;
  final String emoji;

  const _PromoVM({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.totalPromo,
    required this.totalRegular,
    required this.emoji,
  });

  factory _PromoVM.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List?;
    final items = itemsRaw
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];

    // Combo → sumar items; legacy → usar orig_price/promo_price.
    double totalRegular = 0;
    double totalPromo = 0;
    final parts = <String>[];

    if (items.isNotEmpty) {
      for (final it in items) {
        final qty = (it['quantity'] as num?)?.toInt() ?? 1;
        final promoPrice = (it['promo_price'] as num?)?.toDouble() ?? 0;
        totalPromo += promoPrice * qty;
        final name = (it['name'] ?? it['product_name'] ?? 'Producto') as String;
        parts.add(qty > 1 ? '$qty× $name' : name);
      }
      totalRegular = (json['total_regular'] as num?)?.toDouble() ?? totalPromo;
    } else {
      totalRegular = (json['orig_price'] as num?)?.toDouble() ?? 0;
      totalPromo = (json['promo_price'] as num?)?.toDouble() ?? 0;
      final legacyName = (json['product_name'] as String?) ?? '';
      if (legacyName.isNotEmpty) parts.add(legacyName);
    }

    final title = (json['name'] as String?)?.trim().isNotEmpty == true
        ? json['name'] as String
        : (parts.isNotEmpty ? parts.first : 'Promoción');

    final subtitle = parts.isEmpty
        ? ((json['description'] as String?) ?? '')
        : parts.join(' + ');

    return _PromoVM(
      id: (json['id'] ?? json['uuid'] ?? '') as String,
      title: title,
      subtitle: subtitle,
      totalPromo: totalPromo,
      totalRegular: totalRegular,
      // Sin emoji real, mostramos un megáfono genérico consistente
      // con el icono del Marketing Hub.
      emoji: '📢',
    );
  }
}

class _PromoManagementScreenState extends State<PromoManagementScreen> {
  late final ApiService _api;
  bool _offersVisible = true;

  // Remote state — null significa "aún cargando", empty significa
  // "carga completa, sin resultados". Lo modelamos explícitamente
  // para evitar el flicker "no hay promos" antes del primer frame.
  List<_PromoVM>? _promos;
  Object? _promosError;

  String? _slug;
  String? _publicUrl;
  String? _slugError;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService(AuthService());
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadSlug(), _loadPromos()]);
  }

  Future<void> _loadSlug() async {
    try {
      final data = await _api.fetchStoreSlug();
      if (!mounted) return;
      setState(() {
        _slug = data['slug'] as String?;
        _publicUrl = data['public_url'] as String?;
        _slugError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _slugError = _errorMessage(e));
    }
  }

  Future<void> _loadPromos() async {
    try {
      final list = await _api.fetchPromotions();
      if (!mounted) return;
      setState(() {
        _promos = list.map(_PromoVM.fromJson).toList();
        _promosError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _promosError = e);
    }
  }

  String _errorMessage(Object e) =>
      e is AppError ? e.message : 'No se pudo conectar al servidor.';

  String _formatNumber(double value) {
    final intVal = value.toInt();
    return intVal.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  // ── Share helpers ───────────────────────────────────────────────────────────

  /// Comparte el link del catálogo (tarjeta superior). Texto
  /// estandarizado para que el mensaje se lea bien en WhatsApp aunque
  /// la URL quede lineada aparte.
  void _shareCatalog() {
    if (_publicUrl == null) return;
    HapticFeedback.lightImpact();
    final text =
        '¡Hola! Haz tus pedidos en mi nueva tienda online aquí: $_publicUrl';
    Share.share(text, subject: 'Catálogo Online');
  }

  /// Copia el link al portapapeles. Disponible aunque no haya
  /// aplicaciones de share instaladas (caso simulador/CI).
  void _copyCatalogLink() {
    if (_publicUrl == null) return;
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _publicUrl!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enlace copiado', style: TextStyle(fontSize: 16)),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// Comparte una promoción concreta. Si todavía no cargamos el link
  /// del catálogo, comparte solo el título + precio (degradación
  /// silenciosa en vez de bloquear la acción).
  void _sharePromo(_PromoVM p) {
    HapticFeedback.lightImpact();
    final price = '\$${_formatNumber(p.totalPromo)}';
    final tail =
        _publicUrl != null ? ' Pídela rápido aquí: $_publicUrl' : '';
    final text = '¡Tenemos una súper promo! ${p.title} a solo $price.$tail';
    Share.share(text, subject: p.title);
  }

  // ── Edit slug modal ─────────────────────────────────────────────────────────

  Future<void> _openEditSlugSheet() async {
    if (_slug == null) return;
    HapticFeedback.lightImpact();

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _EditSlugSheet(api: _api, initialSlug: _slug!),
    );

    if (result != null && mounted) {
      setState(() {
        _slug = result;
        _publicUrl = _publicUrl?.replaceFirst(
          RegExp(r'/[^/]+$'),
          '/$result',
        );
      });
      // Refresh to get the canonical base_url from the backend.
      _loadSlug();
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator.adaptive(
                onRefresh: _loadAll,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCatalogCard(),
                      const SizedBox(height: 20),
                      _buildVisibilityCard(),
                      const SizedBox(height: 24),
                      _buildPromosSection(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 24,
        right: 24,
        bottom: 28,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFFF6B6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 28),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Mis Promociones',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ofertas visibles en su catálogo web',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogCard() {
    return Container(
      key: const Key('catalog_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF7C3AED).withValues(alpha: 0.08),
            const Color(0xFF7C3AED).withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: Color(0xFF7C3AED), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Tu Catálogo Online',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // URL box — tap para copiar, long-press para editar. Se
          // muestra incluso en error para que el botón "Editar" siga
          // teniendo sentido visual.
          GestureDetector(
            key: const Key('catalog_url_box'),
            onTap: _publicUrl == null ? null : _copyCatalogLink,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded,
                      size: 20, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _publicUrl ??
                          (_slugError != null
                              ? 'Sin conexión'
                              : 'Cargando enlace...'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: _publicUrl != null
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_publicUrl != null)
                    const Icon(Icons.copy_rounded,
                        size: 18, color: AppTheme.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('btn_edit_slug'),
                  onPressed: _slug == null ? null : _openEditSlugSheet,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Editar Link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7C3AED),
                    side: const BorderSide(color: Color(0xFF7C3AED)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('btn_share_catalog'),
                  onPressed: _publicUrl == null ? null : _shareCatalog,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Compartir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisibilityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Sección de Ofertas visible',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Transform.scale(
            scale: 1.3,
            child: Switch(
              value: _offersVisible,
              onChanged: (val) {
                HapticFeedback.mediumImpact();
                setState(() => _offersVisible = val);
              },
              activeThumbColor: Colors.white,
              activeTrackColor: AppTheme.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromosSection() {
    if (_promos == null && _promosError == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_promosError != null) {
      return _ErrorStateCard(
        message: _errorMessage(_promosError!),
        onRetry: _loadPromos,
      );
    }
    final list = _promos!;
    if (list.isEmpty) {
      return const _EmptyPromosCard();
    }
    return Column(
      key: const Key('promos_list'),
      children: [
        for (final p in list) _buildOfferCard(p),
      ],
    );
  }

  Widget _buildOfferCard(_PromoVM p) {
    return Container(
      key: Key('promo_${p.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.surfaceGrey,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(p.emoji, style: const TextStyle(fontSize: 30)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (p.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (p.totalRegular > p.totalPromo) ...[
                      Text(
                        '\$${_formatNumber(p.totalRegular)}',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade500,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '\$${_formatNumber(p.totalPromo)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Compartir ${p.title}',
            child: GestureDetector(
              key: Key('share_${p.id}'),
              onTap: () => _sharePromo(p),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.ios_share_rounded,
                    color: Color(0xFF25D366), size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EDIT SLUG BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

/// Modal para editar el slug del catálogo. Hace debounce ligero en
/// el submit (no se valida mientras el usuario tipea — se valida al
/// presionar "Guardar" y se interpreta el 409 del backend como
/// mensaje inline).
class _EditSlugSheet extends StatefulWidget {
  final ApiService api;
  final String initialSlug;

  const _EditSlugSheet({required this.api, required this.initialSlug});

  @override
  State<_EditSlugSheet> createState() => _EditSlugSheetState();
}

class _EditSlugSheetState extends State<_EditSlugSheet> {
  late final TextEditingController _ctrl;
  String? _inlineError;
  bool _saving = false;

  // Mismo contrato que el backend (services.SlugPattern). Si lo
  // cambias allá, actualízalo acá también.
  static final RegExp _slugRe = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialSlug);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _localValidate(String value) {
    final v = value.trim();
    if (v.length < 3) return 'Debe tener al menos 3 caracteres.';
    if (v.length > 48) return 'No puede tener más de 48 caracteres.';
    if (!_slugRe.hasMatch(v)) {
      return 'Solo minúsculas, números y guiones (ej: mi-tienda-123).';
    }
    return null;
  }

  Future<void> _save() async {
    final value = _ctrl.text.trim().toLowerCase();
    final localErr = _localValidate(value);
    if (localErr != null) {
      setState(() => _inlineError = localErr);
      return;
    }
    if (value == widget.initialSlug) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _saving = true;
      _inlineError = null;
    });

    try {
      final data = await widget.api.updateStoreSlug(value);
      if (!mounted) return;
      Navigator.of(context).pop(data['slug'] as String? ?? value);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _inlineError = e.statusCode == 409
            ? 'Este nombre ya está en uso. Pruebe otro.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _inlineError = 'No se pudo guardar. Intente de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Editar enlace de tu tienda',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Solo minúsculas, números y guiones.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('slug_input'),
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
              LengthLimitingTextInputFormatter(48),
            ],
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.link_rounded),
              hintText: 'mi-tienda-123',
              errorText: _inlineError,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('btn_save_slug'),
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMPTY / ERROR STATES
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyPromosCard extends StatelessWidget {
  const _EmptyPromosCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('promos_empty'),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          const Icon(Icons.local_offer_rounded,
              size: 48, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          const Text(
            'Aún no tienes promociones',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Crea tu primer combo para verlo aquí.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorStateCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorStateCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('promos_error'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 40),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
