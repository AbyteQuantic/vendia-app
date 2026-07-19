// Spec: specs/106-onboarding-conversacional-agente/spec.md
//
// Camino de respaldo SIN IA (FR-10): una sola pantalla con selección
// MÚLTIPLE de tipos (los negocios mixtos son la norma) + toggles básicos.
// Nunca bloquea al tendero: es el plan B cuando Vendi no puede pensar.
import 'package:flutter/material.dart';

import '../../../config/business_types.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../theme/app_theme.dart';

typedef FallbackCall = Future<Map<String, dynamic>> Function({
  String? sessionId,
  String? businessName,
  required List<String> types,
  Map<String, bool> attrs,
});

class TypeFallbackScreen extends StatefulWidget {
  const TypeFallbackScreen({
    super.key,
    required this.onCompleted,
    this.sessionId,
    this.fallbackCallOverride,
  });

  final VoidCallback onCompleted;
  final String? sessionId;
  final FallbackCall? fallbackCallOverride;

  @override
  State<TypeFallbackScreen> createState() => _TypeFallbackScreenState();
}

class _TypeFallbackScreenState extends State<TypeFallbackScreen> {
  late final FallbackCall _call = widget.fallbackCallOverride ??
      (({sessionId, businessName, required types, attrs = const {}}) =>
          ApiService(AuthService()).agentFallback(
            sessionId: sessionId,
            businessName: businessName,
            types: types,
            attrs: attrs,
          ));

  final Set<String> _selected = {};
  final Map<String, bool> _attrs = {};
  bool _sending = false;
  String _error = '';

  static const _attrOptions = [
    ('mesas', 'Mis clientes consumen en mesas'),
    ('domicilios', 'Hago domicilios'),
    ('fiado', 'Le fío a clientes de confianza'),
    ('granel', 'Vendo a granel o por bultos'),
    ('equipo', 'Trabajo con más personas'),
  ];

  Future<void> _submit() async {
    if (_selected.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = '';
    });
    final res = await _call(
      sessionId: widget.sessionId,
      types: _selected.toList(),
      attrs: Map.of(_attrs),
    );
    if (!mounted) return;
    if (res['degraded'] == true) {
      setState(() {
        _sending = false;
        _error = 'Sin conexión. Verifique su internet e intente de nuevo.';
      });
      return;
    }
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
        title: const Text('Configure su negocio',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            const Text(
              '¿Qué tipo de negocio tiene? Puede escoger varios.',
              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in kBusinessTypes)
                  FilterChip(
                    key: Key('fallback_type_${t.value}'),
                    label: Text(t.label),
                    avatar: Icon(t.icon,
                        size: 18,
                        color: _selected.contains(t.value)
                            ? Colors.white
                            : AppTheme.primary),
                    selected: _selected.contains(t.value),
                    onSelected: (v) => setState(() {
                      v ? _selected.add(t.value) : _selected.remove(t.value);
                    }),
                    selectedColor: AppTheme.primary,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _selected.contains(t.value)
                          ? Colors.white
                          : AppTheme.textPrimary,
                    ),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFC9DAE6)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '¿Cómo trabaja? (opcional)',
              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            for (final (key, label) in _attrOptions)
              SwitchListTile(
                key: Key('fallback_attr_$key'),
                value: _attrs[key] ?? false,
                onChanged: (v) => setState(() => _attrs[key] = v),
                title: Text(label, style: const TextStyle(fontSize: 15)),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.primary,
              ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(_error,
                    style:
                        const TextStyle(color: AppTheme.error, fontSize: 14)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: FilledButton(
                key: const Key('fallback_submit'),
                onPressed: _selected.isEmpty || _sending ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : const Text('Crear mi tienda',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
