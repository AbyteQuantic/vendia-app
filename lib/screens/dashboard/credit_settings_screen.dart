// Spec: specs/028-copy-fiar-credito-configurable/spec.md (F035 — refactor UX)
//
// Pantalla unificada con TODO lo relacionado al cuaderno de créditos:
// - Habilitar / deshabilitar el cuaderno (movido desde la tile rápida de
//   Mi Negocio para tener un contexto explicativo).
// - Vocabulario "Fiar" vs "Venta a crédito" (movido desde Perfil del
//   Negocio donde estaba escondido al fondo).
//
// Sigue el patrón Gerontodiseño: tarjetas grandes, textos descriptivos,
// objetivo táctil ≥48dp. Lee desde el endpoint /store/profile el modo
// actual + el toggle enable_fiados.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_labels.dart';

class CreditSettingsScreen extends StatefulWidget {
  const CreditSettingsScreen({super.key});

  @override
  State<CreditSettingsScreen> createState() => _CreditSettingsScreenState();
}

class _CreditSettingsScreenState extends State<CreditSettingsScreen> {
  late final ApiService _api;
  bool _loading = true;
  bool _saving = false;
  bool _enableFiados = true;
  String _creditLabelMode = 'fiar';

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchStoreConfig();
      final profile = await _api.fetchBusinessProfile();
      if (!mounted) return;
      setState(() {
        _enableFiados = data['enable_fiados'] as bool? ?? true;
        final rawMode = profile['credit_label_mode'] as String?;
        _creditLabelMode = (rawMode == 'credit') ? 'credit' : 'fiar';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('No se pudo cargar la configuración: $e', isError: true);
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    final previous = _enableFiados;
    setState(() => _enableFiados = value);
    HapticFeedback.lightImpact();
    try {
      await _api.updateStoreConfig({'enable_fiados': value});
    } catch (e) {
      if (!mounted) return;
      setState(() => _enableFiados = previous);
      _snack('No se pudo guardar el cambio: $e', isError: true);
    }
  }

  Future<void> _saveVocabulary(String newMode) async {
    if (newMode == _creditLabelMode) return;
    final previous = _creditLabelMode;
    setState(() {
      _creditLabelMode = newMode;
      _saving = true;
    });
    HapticFeedback.lightImpact();
    try {
      await _api.updateBusinessProfile({'credit_label_mode': newMode});
      if (mounted) {
        await context.read<AuthService>().updateCreditLabelMode(newMode);
      }
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Vocabulario actualizado');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creditLabelMode = previous;
        _saving = false;
      });
      _snack('No se pudo guardar el vocabulario: $e', isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AppTheme.error : AppTheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = CreditLabels.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(labels.configTitle,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700)),
        backgroundColor: AppTheme.background,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _buildEnableCard(labels),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _enableFiados
                      ? _buildVocabularyCard(key: const ValueKey('vocab-on'))
                      : const SizedBox.shrink(key: ValueKey('vocab-off')),
                ),
              ],
            ),
    );
  }

  // ── Card 1: habilitar/deshabilitar el cuaderno ──────────────────────────
  Widget _buildEnableCard(CreditLabels labels) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD6D0C8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded,
                  size: 28, color: Color(0xFF6D28D9)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Cuaderno habilitado',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ),
              Switch.adaptive(
                value: _enableFiados,
                activeTrackColor: const Color(0xFF6D28D9),
                onChanged: _toggleEnabled,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _enableFiados
                ? 'Tus clientes pueden ${labels.verbInfinitive}. El botón aparece en el POS al cobrar.'
                : 'El cuaderno está apagado. No aparecerá la opción de ${labels.verbInfinitive} al cobrar.',
            style: const TextStyle(
                fontSize: 15, color: AppTheme.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ── Card 2: vocabulario (solo si el cuaderno está habilitado) ───────────
  Widget _buildVocabularyCard({Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD6D0C8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.translate_rounded,
                  size: 24, color: AppTheme.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Vocabulario del cuaderno',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Elige cómo se llama el registro en su negocio. El cambio se ve en todas las pantallas, mensajes de WhatsApp y recibos.',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          _VocabOption(
            value: 'fiar',
            groupValue: _creditLabelMode,
            title: CreditLabels.optionFiarLabel,
            subtitle: 'Vocabulario de barrio colombiano (por defecto)',
            onChanged: _saving ? null : (v) => _saveVocabulary(v),
          ),
          const SizedBox(height: 8),
          _VocabOption(
            value: 'credit',
            groupValue: _creditLabelMode,
            title: CreditLabels.optionCreditLabel,
            subtitle: 'Vocabulario formal para ferreterías y distribuidoras',
            onChanged: _saving ? null : (v) => _saveVocabulary(v),
          ),
          if (_saving) ...[
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Guardando…',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VocabOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final String title;
  final String subtitle;
  final ValueChanged<String>? onChanged;

  const _VocabOption({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF3EEFE) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                selected ? const Color(0xFF6D28D9) : const Color(0xFFE5E5EA),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color:
                  selected ? const Color(0xFF6D28D9) : AppTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
