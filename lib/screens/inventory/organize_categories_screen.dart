// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';

/// Organizar categorías con IA: para los productos SIN categoría, la IA sugiere
/// una (desde el nombre); el tenant la revisa, EDITA y guarda. No aplica nada sin
/// confirmación. Resuelve catálogos cargados solo con nombre+precio. Spec 078.
class OrganizeCategoriesScreen extends StatefulWidget {
  const OrganizeCategoriesScreen({super.key, this.api});
  final ApiService? api;

  @override
  State<OrganizeCategoriesScreen> createState() => _OrganizeCategoriesScreenState();
}

class _OrganizeCategoriesScreenState extends State<OrganizeCategoriesScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  List<Map<String, dynamic>> _items = [];
  final List<TextEditingController> _ctrls = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.suggestProductCategories();
      if (!mounted) return;
      for (final c in _ctrls) {
        c.dispose();
      }
      _ctrls.clear();
      for (final it in res) {
        _ctrls.add(TextEditingController(text: (it['suggested'] ?? '').toString()));
      }
      setState(() {
        _items = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AppError ? e.message : 'No se pudieron sugerir categorías.';
      });
    }
  }

  Future<void> _save() async {
    final payload = <Map<String, dynamic>>[];
    for (var i = 0; i < _items.length; i++) {
      final cat = _ctrls[i].text.trim();
      if (cat.isEmpty) continue; // sin categoría → no se toca
      payload.add({'id': (_items[i]['id'] ?? '').toString(), 'category': cat});
    }
    if (payload.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    try {
      final n = await _api.bulkUpdateCategories(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$n producto(s) categorizados.'), backgroundColor: AppTheme.success));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppError ? e.message : 'No se pudo guardar.'), backgroundColor: AppTheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Organizar categorías', style: AppUI.title),
      ),
      body: _body(),
      bottomNavigationBar: (_items.isEmpty || _loading)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppUI.s16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const Key('save_categories'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Guardar categorías'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: AppUI.s16),
          Text('Analizando sus productos con IA…', style: AppUI.bodySoft),
        ]),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppUI.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: AppUI.bodySoft),
            const SizedBox(height: AppUI.s12),
            OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
          ]),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppUI.s24),
          child: Text('Todos sus productos ya tienen categoría 🎉',
              textAlign: TextAlign.center, style: AppUI.bodySoft),
        ),
      );
    }
    return ListView.separated(
      key: const Key('categories_list'),
      padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s12, AppUI.s16, AppUI.s16),
      itemCount: _items.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: AppUI.s8),
      itemBuilder: (_, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppUI.s8),
            child: Text('La IA sugirió una categoría para cada producto. Edítela si quiere y guarde.',
                style: AppUI.bodySoft),
          );
        }
        final idx = i - 1;
        return Container(
          padding: const EdgeInsets.all(AppUI.s12),
          decoration: AppUI.borderedCard(r: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((_items[idx]['name'] ?? '').toString(),
                style: AppUI.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppUI.s8),
            TextField(
              key: Key('cat_${_items[idx]['id']}'),
              controller: _ctrls[idx],
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.sell_outlined, size: 18),
                hintText: 'Categoría',
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]),
        );
      },
    );
  }
}
