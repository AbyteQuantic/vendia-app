// Spec: specs/040-capacidades-fotos-config-card/spec.md
//
// Scaffold reutilizable para una pantalla dedicada de capacidad. Cada
// capacidad opcional del negocio (mesas, recetas, promociones, etc.)
// tiene su propia pantalla pero todas comparten esta estructura:
//
//   foto hero  →  título  →  descripción
//                 ↓
//          (DESACTIVADO)              (ACTIVADO)
//          botón grande               botón principal al módulo
//          "Activar X"                + botón secundario opcional
//                                     + settings opcionales
//                                     + botón "Apagar" abajo
//
// Persistencia de la activación: `PATCH /store/profile` con
// `config.<flag>` — misma fuente de verdad que F023, no se duplica.
//
// `QuoteCapabilityScreen` es el caso especial porque expone settings
// funcionales (días de validez por defecto) que sí persisten en
// SharedPreferences; el resto usa este scaffold tal cual hasta que
// F040 final cierre los settings por capacidad en backend.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';

/// Acción opcional secundaria en estado activado (p. ej. "Nueva
/// cotización" en Cotizaciones, "Agregar mesa" en Mesas).
class CapabilitySecondaryAction {
  final String label;
  final IconData icon;
  final Widget Function() destination;

  const CapabilitySecondaryAction({
    required this.label,
    required this.icon,
    required this.destination,
  });
}

/// Metadata de una capacidad para pintar su pantalla dedicada.
class CapabilityMetadata {
  /// Título de la AppBar y del bloque de texto.
  final String title;

  /// Frase corta debajo del título — qué hace esta capacidad.
  final String tagline;

  /// Párrafo explicativo (1-3 líneas). Tono USTED, español neutro.
  final String description;

  /// Texto del CTA principal cuando está ACTIVADA. Si es null, se
  /// muestra "Ver mis [título]" por defecto.
  final String? primaryActionLabel;

  /// Ícono del CTA principal.
  final IconData primaryActionIcon;

  /// Texto del CTA cuando está DESACTIVADA. Default: "Activar [título]".
  final String? activateLabel;

  /// URL de la foto hero (Pexels/Unsplash). Si falla la carga, degrada
  /// a placeholder con [fallbackIcon].
  final String heroPhotoUrl;

  /// Ícono grande del placeholder (cuando la foto no carga / offline).
  final IconData fallbackIcon;

  /// Color de acento — usado para el placeholder, los bordes y los CTAs.
  final Color accentColor;

  /// Llave del flag en el bag `config` del backend (p. ej. `enable_tables`).
  /// Debe coincidir con el campo que `tenants.config` espera.
  final String configKey;

  /// Llave del flag en la respuesta de `GET /store/profile` (p. ej.
  /// `enable_tables`). Suele ser igual a [configKey].
  final String profileKey;

  /// Pantalla a la que lleva el CTA principal. Si es null, no se
  /// muestra el CTA principal (la capacidad modifica el comportamiento
  /// de otro flujo y no tiene un "módulo propio" — p. ej. servicios,
  /// venta a granel, precios multi-tier).
  final Widget Function()? primaryDestination;

  /// Acción secundaria opcional (p. ej. "Nueva mesa").
  final CapabilitySecondaryAction? secondary;

  /// Texto explicativo cuando NO hay módulo propio (capacidad que solo
  /// modifica otro flujo). Default: "Active esta capacidad y úsela en
  /// [dónde]". Solo se renderiza si [primaryDestination] es null.
  final String? noModuleHint;

  const CapabilityMetadata({
    required this.title,
    required this.tagline,
    required this.description,
    required this.heroPhotoUrl,
    required this.fallbackIcon,
    required this.accentColor,
    required this.configKey,
    required this.profileKey,
    this.primaryActionLabel,
    this.primaryActionIcon = Icons.arrow_forward_rounded,
    this.activateLabel,
    this.primaryDestination,
    this.secondary,
    this.noModuleHint,
  });
}

/// Pantalla genérica que renderea la metadata de una capacidad. La
/// activación pega contra el backend (`PATCH /store/profile`); los
/// settings extra van vía [extraSettingsBuilder] (opcional).
class CapabilityScaffold extends StatefulWidget {
  final CapabilityMetadata metadata;

  /// Inyección para tests. En producción se crea uno nuevo.
  final ApiService? apiOverride;

  /// Constructor opcional de una sección de settings adicional que solo
  /// se muestra en estado ACTIVADO (debajo del CTA principal). Permite
  /// añadir controles funcionales sin tocar el scaffold.
  final Widget Function(BuildContext)? extraSettingsBuilder;

  const CapabilityScaffold({
    super.key,
    required this.metadata,
    this.apiOverride,
    this.extraSettingsBuilder,
  });

  @override
  State<CapabilityScaffold> createState() => _CapabilityScaffoldState();
}

class _CapabilityScaffoldState extends State<CapabilityScaffold> {
  late final ApiService _api;
  bool _loading = true;
  bool _toggling = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _api.fetchBusinessProfile();
      if (!mounted) return;
      setState(() {
        _enabled = profile[widget.metadata.profileKey] == true;
        _loading = false;
      });
    } catch (_) {
      // Offline / error — quedamos en false; el dueño puede reintentar.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(bool next) async {
    if (_toggling) return;
    HapticFeedback.mediumImpact();
    setState(() => _toggling = true);
    try {
      await _api.updateBusinessProfile({
        'config': {widget.metadata.configKey: next},
      });
      // Refrescar el cache local de feature_flags — el Dashboard lee de disco
      // al volver y sin esto la capacidad recién activada no aparece en el
      // carrusel/grid hasta el siguiente login. OJO: el PATCH solo responde un
      // mensaje (no trae los flags), así que releemos el perfil (GET) —fuente
      // de verdad que SÍ incluye feature_flags.enable_events (no es columna
      // top-level)— y guardamos ESO.
      final profile = await _api.fetchBusinessProfile();
      await AuthService().saveFeatureFlagsFromProfile(profile);
      if (!mounted) return;
      setState(() => _enabled = next);
      _snack(next
          ? '${widget.metadata.title} activado'
          : '${widget.metadata.title} desactivado');
    } catch (e) {
      if (!mounted) return;
      _snack('No se pudo guardar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 17)),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _openPrimary() {
    final dest = widget.metadata.primaryDestination;
    if (dest == null) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => dest()));
  }

  void _openSecondary() {
    final sec = widget.metadata.secondary;
    if (sec == null) return;
    HapticFeedback.lightImpact();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => sec.destination()));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metadata;
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(m.title,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          )
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              children: [
                _CapabilityHero(
                  photoUrl: m.heroPhotoUrl,
                  fallbackIcon: m.fallbackIcon,
                  accent: m.accentColor,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.tagline,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                            height: 1.2,
                          )),
                      const SizedBox(height: 8),
                      Text(m.description,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          )),
                      const SizedBox(height: 20),
                      _enabled
                          ? _buildActivatedSection(context)
                          : _buildActivationCallout(context),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildActivationCallout(BuildContext context) {
    final m = widget.metadata;
    final label = m.activateLabel ?? 'Activar ${m.title.toLowerCase()}';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: m.accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: m.accentColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Aún no está activado',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          Text(
            'Active esta capacidad para empezar a usarla en su negocio.',
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              key: const Key('capability_activate_btn'),
              onPressed: _toggling ? null : () => _setEnabled(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: m.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _toggling
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded, size: 24),
              label: Text(_toggling ? 'Activando...' : label,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivatedSection(BuildContext context) {
    final m = widget.metadata;
    final hasPrimary = m.primaryDestination != null;
    final primaryLabel =
        m.primaryActionLabel ?? 'Ver ${m.title.toLowerCase()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPrimary)
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              key: const Key('capability_primary_btn'),
              onPressed: _openPrimary,
              style: ElevatedButton.styleFrom(
                backgroundColor: m.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: Icon(m.primaryActionIcon, size: 24),
              label: Text(primaryLabel,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800)),
            ),
          )
        else if (m.noModuleHint != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: m.accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: m.accentColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(m.noModuleHint!,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.textPrimary,
                        height: 1.35,
                      )),
                ),
              ],
            ),
          ),
        if (m.secondary != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              key: const Key('capability_secondary_btn'),
              onPressed: _openSecondary,
              style: OutlinedButton.styleFrom(
                foregroundColor: m.accentColor,
                side: BorderSide(color: m.accentColor, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: Icon(m.secondary!.icon, size: 24),
              label: Text(m.secondary!.label,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        if (widget.extraSettingsBuilder != null) ...[
          const SizedBox(height: 28),
          const Text('Configuración',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          widget.extraSettingsBuilder!(context),
        ],
        const SizedBox(height: 28),
        _DeactivateCard(
          title: m.title,
          loading: _toggling,
          onDeactivate: () => _setEnabled(false),
        ),
      ],
    );
  }
}

class _CapabilityHero extends StatelessWidget {
  final String photoUrl;
  final IconData fallbackIcon;
  final Color accent;

  const _CapabilityHero({
    required this.photoUrl,
    required this.fallbackIcon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tint = accent.withValues(alpha: 0.15);
    return SizedBox(
      width: double.infinity,
      height: 200,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: tint),
          Image.network(
            photoUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(tint),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return _placeholder(tint);
            },
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFFFFFBF7).withValues(alpha: 0.95),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(Color tint) {
    return Container(
      color: tint,
      child: Center(
        child: Icon(fallbackIcon, size: 72, color: accent),
      ),
    );
  }
}

class _DeactivateCard extends StatelessWidget {
  final String title;
  final bool loading;
  final VoidCallback onDeactivate;

  const _DeactivateCard({
    required this.title,
    required this.loading,
    required this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Desactivar ${title.toLowerCase()}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
                const Text(
                  'Sus datos no se borran; solo deja de aparecer en el menú.',
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('capability_deactivate_btn'),
            onPressed: loading ? null : onDeactivate,
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: Text(loading ? 'Guardando…' : 'Apagar',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
