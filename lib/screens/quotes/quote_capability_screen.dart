// Spec: specs/040-capacidades-fotos-config-card/spec.md
//
// Pantalla dedicada de la capacidad "Cotizaciones" — primera muestra
// del rediseño F040: foto real grande, activación específica de la
// capacidad, settings propios del módulo y acceso directo a las
// pantallas funcionales. La card "Cotizaciones" del reel del Dashboard
// (F037) la abre cuando el tendero la toca; reemplaza la navegación
// previa a `BusinessCapabilitiesScreen` general (lista de 12 toggles
// uniformes), que era el bug reportado.
//
// Persistencia:
//   - Activación → backend (`PATCH /store/profile` con
//     `config.enable_quotes`). Misma fuente de verdad que F023, no se
//     duplica.
//   - Días de validez por defecto → SharedPreferences local. Es un
//     mockup funcional para F040; cuando el spec 040 cierre el
//     contrato de settings por capacidad en backend, este valor migra
//     a `tenants.config.quote_default_validity_days` o equivalente.
//
// Offline (Art. II): la foto cae a placeholder si no carga; el toggle
// y la navegación a QuotesListScreen siguen funcionando.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';
import 'quote_form_screen.dart';
import 'quotes_list_screen.dart';

/// Llave en SharedPreferences para los días de validez por defecto.
/// `QuoteFormScreen` debe leerla en una iteración siguiente para
/// reemplazar el `15` hardcoded actual (T-F040-Q1 del plan).
const String kQuoteDefaultValidityDaysKey = 'quote_default_validity_days';

/// Default histórico del módulo (lo que QuoteFormScreen usa hoy
/// hardcoded). Se mantiene como fallback.
const int kQuoteDefaultValidityDaysFallback = 15;

/// Foto representativa de la capacidad. Pexels — licencia libre para
/// uso comercial sin atribución obligatoria. Cacheada por el CDN de
/// Pexels; si no carga, el _CapabilityHero degrada a placeholder.
const String _kQuoteHeroPhotoUrl =
    'https://images.pexels.com/photos/95916/pexels-photo-95916.jpeg?auto=compress&cs=tinysrgb&w=1280&h=600&fit=crop';

class QuoteCapabilityScreen extends StatefulWidget {
  /// Inyección para tests. En producción se crea uno propio.
  final ApiService? apiOverride;

  const QuoteCapabilityScreen({super.key, this.apiOverride});

  @override
  State<QuoteCapabilityScreen> createState() => _QuoteCapabilityScreenState();
}

class _QuoteCapabilityScreenState extends State<QuoteCapabilityScreen> {
  late final ApiService _api;
  bool _loading = true;
  bool _toggling = false;
  bool _enabled = false;
  int _validityDays = kQuoteDefaultValidityDaysFallback;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localDays = prefs.getInt(kQuoteDefaultValidityDaysKey);

      final profile = await _api.fetchBusinessProfile();
      if (!mounted) return;
      setState(() {
        _enabled = profile['enable_quotes'] == true;
        _validityDays = localDays ?? kQuoteDefaultValidityDaysFallback;
        _loading = false;
      });
    } catch (_) {
      // Offline o error de red — dejamos lo último leído.
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _validityDays =
            prefs.getInt(kQuoteDefaultValidityDaysKey) ??
                kQuoteDefaultValidityDaysFallback;
        _loading = false;
      });
    }
  }

  Future<void> _setEnabled(bool next) async {
    if (_toggling) return;
    HapticFeedback.mediumImpact();
    setState(() => _toggling = true);
    try {
      await _api.updateBusinessProfile({
        'config': {'enable_quotes': next},
      });
      // Refrescar el cache local de feature_flags para que el
      // Dashboard vea la capacidad activada al volver (lee de disco,
      // no del backend). El PATCH solo responde {"message": ...} (sin
      // flags), así que releemos el perfil (GET) antes de persistir —
      // mismo patrón que capability_scaffold.dart.
      final updated = await _api.fetchBusinessProfile();
      await AuthService().saveFeatureFlagsFromProfile(updated);
      if (!mounted) return;
      setState(() => _enabled = next);
      _showSnack(next
          ? 'Cotizaciones activadas'
          : 'Cotizaciones desactivadas');
    } catch (e) {
      if (!mounted) return;
      _showSnack('No se pudo guardar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _setValidityDays(int days) async {
    setState(() => _validityDays = days);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kQuoteDefaultValidityDaysKey, days);
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 17)),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _openQuotesList() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuotesListScreen(apiOverride: widget.apiOverride),
      ),
    );
  }

  void _openNewQuoteForm() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuoteFormScreen(apiOverride: widget.apiOverride),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Cotizaciones',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              children: [
                const _CapabilityHero(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Arme propuestas de precio antes de la venta',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Envíe a sus clientes el detalle de lo que va a '
                        'cobrar, con folio y vigencia. Cuando aprueben, '
                        'lo convierte en venta de un toque.',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
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

  /// Estado DESACTIVADO — un solo CTA grande que activa la capacidad.
  Widget _buildActivationCallout(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2FA0).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: const Color(0xFF1A2FA0).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aún no está activado',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Active esta capacidad para empezar a crear cotizaciones y '
            'compartirlas con sus clientes por WhatsApp.',
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              key: const Key('quote_cap_activate_btn'),
              onPressed: _toggling ? null : () => _setEnabled(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A2FA0),
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
              label: Text(_toggling ? 'Activando...' : 'Activar cotizaciones',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  /// Estado ACTIVADO — accesos al módulo + settings + toggle de apagado.
  Widget _buildActivatedSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton.icon(
            key: const Key('quote_cap_open_list_btn'),
            onPressed: _openQuotesList,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A2FA0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.list_alt_rounded, size: 24),
            label: const Text('Ver mis cotizaciones',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            key: const Key('quote_cap_new_btn'),
            onPressed: _openNewQuoteForm,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1A2FA0),
              side: const BorderSide(color: Color(0xFF1A2FA0), width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.add_rounded, size: 24),
            label: const Text('Nueva cotización',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Configuración',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _ValidityDaysCard(
          days: _validityDays,
          onChanged: _setValidityDays,
        ),
        const SizedBox(height: 12),
        _DeactivateCard(
          loading: _toggling,
          onDeactivate: () => _setEnabled(false),
        ),
      ],
    );
  }
}

/// Foto representativa de la capacidad, con placeholder consistente
/// (Art. II — offline degrada limpio, no rompe layout).
class _CapabilityHero extends StatelessWidget {
  const _CapabilityHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 200,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFFE0E7FF)),
          Image.network(
            _kQuoteHeroPhotoUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFFE0E7FF),
              child: const Center(
                child: Icon(Icons.description_outlined,
                    size: 72, color: Color(0xFF1A2FA0)),
              ),
            ),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Container(
                color: const Color(0xFFE0E7FF),
                child: const Center(
                  child: Icon(Icons.description_outlined,
                      size: 72, color: Color(0xFF1A2FA0)),
                ),
              );
            },
          ),
          // Gradient para legibilidad del texto del cuerpo si el scroll
          // empuja el título sobre la foto en pantallas chicas.
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
}

/// Slider de días de validez por defecto. Persiste en SharedPreferences.
class _ValidityDaysCard extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChanged;

  const _ValidityDaysCard({required this.days, required this.onChanged});

  static const List<int> _options = [7, 15, 30, 60];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Días de validez por defecto',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          const Text(
            'Una cotización nueva nacerá vigente este número de días.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _options.map((d) {
              final active = d == days;
              return ChoiceChip(
                key: Key('quote_validity_$d'),
                label: Text('$d días',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : AppTheme.textPrimary,
                    )),
                selected: active,
                selectedColor: const Color(0xFF1A2FA0),
                backgroundColor: const Color(0xFFF1F2F8),
                onSelected: (_) => onChanged(d),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Tile para desactivar la capacidad. Separado del CTA principal a
/// propósito (Art. I — el botón grande es para usar, no para apagar).
class _DeactivateCard extends StatelessWidget {
  final bool loading;
  final VoidCallback onDeactivate;

  const _DeactivateCard({required this.loading, required this.onDeactivate});

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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Desactivar cotizaciones',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
                Text(
                  'Sus cotizaciones guardadas no se borran; solo deja '
                  'de aparecer en el menú.',
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('quote_cap_deactivate_btn'),
            onPressed: loading ? null : onDeactivate,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.error,
            ),
            child: Text(loading ? 'Guardando…' : 'Apagar',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
