// Spec: specs/083-mesas-catalogo-qr/spec.md
//
// "Mesas y código QR" — pantalla dedicada del hub de Catálogo Online: el tendero
// declara si su tienda atiende en mesas (activa la capacidad enable_tables) y, si
// es así, configura mesas/áreas y genera el QR por mesa. El QR lleva al catálogo
// con la mesa (tienda.vendia.store/<slug>?mesa=<id>) y el pedido entra a la cuenta
// de esa mesa (Centro de Tareas).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../dashboard/table_floor_plan_screen.dart';

class MesasConfigScreen extends StatefulWidget {
  final ApiService? api;
  const MesasConfigScreen({super.key, this.api});

  @override
  State<MesasConfigScreen> createState() => _MesasConfigScreenState();
}

class _MesasConfigScreenState extends State<MesasConfigScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  bool _loading = true;
  bool _saving = false;
  bool _hasTables = false;
  String _slug = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _api.fetchBusinessProfile();
      final d = (res['data'] as Map?)?.cast<String, dynamic>() ?? res;
      if (!mounted) return;
      final ff = (d['feature_flags'] as Map?)?.cast<String, dynamic>();
      setState(() {
        _slug = (d['store_slug'] as String?) ?? '';
        _hasTables = d['enable_tables'] == true || (ff?['enable_tables'] == true);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos cargar la configuración.';
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool v) async {
    setState(() {
      _hasTables = v;
      _saving = true;
    });
    HapticFeedback.mediumImpact();
    try {
      // config:{has_tables} parcial — el backend deriva el resto de toggles de
      // los flags actuales (no borra otras capacidades).
      final res = await _api.updateBusinessProfile({
        'config': {'has_tables': v},
      });
      await AuthService().saveFeatureFlagsFromProfile(res);
      if (!mounted) return;
      _snack(v ? 'Mesas activadas' : 'Mesas desactivadas', ok: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hasTables = !v);
      _snack('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(fontSize: 16)),
      backgroundColor: ok ? AppTheme.success : AppTheme.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight + AppUI.s8;
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(
        title: 'Mesas y código QR',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(AppUI.s24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center, style: AppUI.bodySoft),
                    const SizedBox(height: AppUI.s8),
                    TextButton(onPressed: _load, child: const Text('Reintentar')),
                  ]),
                ))
              : ListView(
                  padding: EdgeInsets.fromLTRB(AppUI.s16, topPad, AppUI.s16, AppUI.s24),
                  children: [
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ATENCIÓN EN MESA', style: AppUI.sectionLabel),
                          const SizedBox(height: AppUI.s8),
                          const Text(
                            'Active las mesas para generar un QR por mesa. Sus '
                            'clientes piden desde la mesa y el pedido llega al '
                            'Centro de Tareas con la mesa indicada; el mesero '
                            'también puede tomar el pedido escaneando el QR.',
                            style: AppUI.bodySoft,
                          ),
                          SwitchListTile(
                            key: const Key('mesas_toggle'),
                            contentPadding: EdgeInsets.zero,
                            value: _hasTables,
                            onChanged: _saving ? null : _toggle,
                            activeThumbColor: AppTheme.primary,
                            title: const Text('Mi tienda atiende en mesas',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    if (_hasTables) ...[
                      const SizedBox(height: AppUI.s16),
                      SoftCard(
                        child: InkWell(
                          key: const Key('mesas_configure'),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => TableFloorPlanScreen(slug: _slug),
                            ));
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: AppUI.s8),
                            child: Row(children: [
                              Icon(Icons.table_restaurant_rounded,
                                  color: AppTheme.primary),
                              SizedBox(width: AppUI.s12),
                              Expanded(
                                child: Text('Configurar mesas, áreas y QR',
                                    style: AppUI.bodyStrong),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: AppUI.inkSoft),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
