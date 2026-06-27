import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../../widgets/table_menu_qr_sheet.dart';

/// Campo de texto del kit (radius AppUI, sin relleno crema). Reusado por los
/// diálogos de crear/editar mesa para mantener la UI normalizada (AppUI).
InputDecoration _mesaField(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppUI.inkSoft),
      hintStyle: const TextStyle(color: AppUI.inkSoft),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppUI.radius),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppUI.radius),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.6),
      ),
    );

/// Floor Plan Editor — grid interactivo para gestionar mesas (UI normalizada
/// al kit AppUI). Todas las operaciones ocurren en memoria hasta "Guardar".
class TableFloorPlanScreen extends StatefulWidget {
  /// Spec 083 — slug de la tienda para generar el QR del menú por mesa
  /// (tienda.vendia.store/<slug>?mesa=<id>). Vacío → el botón de QR pide
  /// configurar primero el enlace del catálogo.
  final String? slug;

  const TableFloorPlanScreen({super.key, this.slug});

  @override
  State<TableFloorPlanScreen> createState() => _TableFloorPlanScreenState();
}

class _TableFloorPlanScreenState extends State<TableFloorPlanScreen> {
  static const _cols = 5;
  static const _rows = 8;

  late final ApiService _api;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  // In-memory table state: key = "x,y", value = table data
  final Map<String, _TableData> _tables = {};

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _fetchTables();
  }

  Future<void> _fetchTables() async {
    try {
      final list = await _api.fetchTables();
      if (!mounted) return;
      setState(() {
        _tables.clear();
        for (final t in list) {
          final x = (t['grid_x'] as num?)?.toInt() ?? 0;
          final y = (t['grid_y'] as num?)?.toInt() ?? 0;
          final key = '$x,$y';
          _tables[key] = _TableData(
            id: t['id'] as String? ?? '',
            label: t['label'] as String? ?? '',
            area: t['area'] as String? ?? '',
            gridX: x,
            gridY: y,
            capacity: (t['capacity'] as num?)?.toInt() ?? 4,
          );
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Error al cargar mesas: $e', isError: true);
    }
  }

  Future<void> _syncTables() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    try {
      final payload = _tables.values
          .map((t) => {
                'id': t.id,
                'label': t.label,
                'area': t.area,
                'grid_x': t.gridX,
                'grid_y': t.gridY,
                'capacity': t.capacity,
              })
          .toList();

      await _api.syncTables(payload);
      if (!mounted) return;
      setState(() => _dirty = false);
      _showSnack('Distribución guardada');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _showSnack('Error al guardar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onCellTap(int x, int y) {
    final key = '$x,$y';
    if (_tables.containsKey(key)) {
      _showTableOptions(key);
    } else {
      _showCreateDialog(x, y);
    }
  }

  void _showCreateDialog(int x, int y) {
    final ctrl = TextEditingController(text: 'Mesa ${_tables.length + 1}');
    final areaCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radius * 2)),
        title: const Text('Nueva mesa', style: AppUI.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(fontSize: 16, color: AppUI.ink),
              decoration: _mesaField('Nombre', hint: 'Mesa 1'),
            ),
            const SizedBox(height: AppUI.s12),
            TextField(
              controller: areaCtrl,
              style: const TextStyle(fontSize: 16, color: AppUI.ink),
              decoration: _mesaField('Área (opcional)', hint: 'Terraza, Salón, Barra…'),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(AppUI.s16, 0, AppUI.s16, AppUI.s12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppUI.inkSoft)),
          ),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              setState(() {
                _tables['$x,$y'] = _TableData(
                  id: '',
                  label: name,
                  area: areaCtrl.text.trim(),
                  gridX: x,
                  gridY: y,
                  capacity: 4,
                );
                _dirty = true;
              });
              HapticFeedback.lightImpact();
              Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radius)),
              padding: const EdgeInsets.symmetric(horizontal: AppUI.s24, vertical: AppUI.s12),
            ),
            child: const Text('Crear',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showTableOptions(String key) {
    final table = _tables[key]!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: AppUI.s24),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(table.label,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: AppUI.ink)),
            const SizedBox(height: AppUI.s4),
            Text(
                table.area.isNotEmpty
                    ? '${table.area} · ${table.capacity} sillas'
                    : 'Capacidad: ${table.capacity} sillas',
                style: AppUI.bodySoft),
            const SizedBox(height: AppUI.s16),
            // Spec 083 — QR del menú de la mesa (catálogo con ?mesa=<id>).
            SizedBox(
              width: double.infinity,
              child: _ActionButton(
                icon: Icons.qr_code_2_rounded,
                label: 'QR del menú de la mesa',
                color: AppTheme.primary,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openTableQr(table);
                },
              ),
            ),
            const SizedBox(height: AppUI.s12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.edit_rounded,
                    label: 'Editar',
                    color: AppTheme.primary,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showEditDialog(key);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.delete_rounded,
                    label: 'Eliminar',
                    color: AppTheme.error,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      setState(() {
                        _tables.remove(key);
                        _dirty = true;
                      });
                      HapticFeedback.mediumImpact();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(String key) {
    final table = _tables[key]!;
    final nameCtrl = TextEditingController(text: table.label);
    final areaCtrl = TextEditingController(text: table.area);
    final capCtrl = TextEditingController(text: table.capacity.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radius * 2)),
        title: const Text('Editar mesa', style: AppUI.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 16, color: AppUI.ink),
              decoration: _mesaField('Nombre'),
            ),
            const SizedBox(height: AppUI.s12),
            TextField(
              controller: areaCtrl,
              style: const TextStyle(fontSize: 16, color: AppUI.ink),
              decoration: _mesaField('Área (opcional)', hint: 'Terraza, Salón, Barra…'),
            ),
            const SizedBox(height: AppUI.s12),
            TextField(
              controller: capCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16, color: AppUI.ink),
              decoration: _mesaField('Sillas'),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(AppUI.s16, 0, AppUI.s16, AppUI.s12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppUI.inkSoft)),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              setState(() {
                _tables[key] = table.copyWith(
                  label: name,
                  area: areaCtrl.text.trim(),
                  capacity: int.tryParse(capCtrl.text) ?? table.capacity,
                );
                _dirty = true;
              });
              Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radius)),
              padding: const EdgeInsets.symmetric(horizontal: AppUI.s24, vertical: AppUI.s12),
            ),
            child: const Text('Guardar',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // Spec 083 — abre el QR del menú de una mesa. Requiere que la mesa esté
  // GUARDADA (tiene id) y un slug del catálogo configurado.
  void _openTableQr(_TableData table) {
    final slug = (widget.slug ?? '').trim();
    if (slug.isEmpty) {
      _showSnack('Primero configure el enlace de su tienda en el catálogo.',
          isError: true);
      return;
    }
    if (table.id.isEmpty || _dirty) {
      _showSnack('Guarde la distribución antes de generar el QR de la mesa.',
          isError: true);
      return;
    }
    showTableMenuQrSheet(
      context,
      slug: slug,
      tableId: table.id,
      tableLabel: table.label,
      area: table.area,
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 18)),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Plano de mesas', style: AppUI.title),
        actions: [
          const Padding(
              padding: EdgeInsets.only(right: AppUI.s8),
              child: Center(child: BranchSelectorChip())),
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(right: AppUI.s12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppUI.radiusSm),
                  ),
                  child: const Text('Sin guardar',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.warning)),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _buildGrid(),
      bottomNavigationBar: _loading ? null : _buildBottomBar(),
    );
  }

  Widget _buildGrid() {
    return Column(
      children: [
        // Legend
        const Padding(
          padding: EdgeInsets.fromLTRB(AppUI.s24, AppUI.s12, AppUI.s24, AppUI.s8),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppUI.inkSoft),
              SizedBox(width: AppUI.s8),
              Expanded(
                child: Text(
                  'Toque un espacio vacío para agregar mesa. Toque una mesa para editar, ver su QR o eliminar.',
                  style: AppUI.bodySoft,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Grid
        Expanded(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 2.0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellSize = constraints.maxWidth / _cols;
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _cols,
                    childAspectRatio: 1,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: _cols * _rows,
                  itemBuilder: (context, index) {
                    final x = index % _cols;
                    final y = index ~/ _cols;
                    final key = '$x,$y';
                    final table = _tables[key];

                    return GestureDetector(
                      onTap: () => _onCellTap(x, y),
                      child: table != null
                          ? _buildTableCell(table, cellSize)
                          : _buildEmptyCell(),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableCell(_TableData table, double cellSize) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.6), width: 1.5),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.table_restaurant_rounded,
                color: AppTheme.primary, size: 26),
            const SizedBox(height: 2),
            Text(
              table.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppUI.ink),
            ),
            Text(
              '${table.capacity} sillas',
              style: const TextStyle(fontSize: 10, color: AppUI.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCell() {
    return Container(
      decoration: BoxDecoration(
        color: AppUI.hairline,
        borderRadius: BorderRadius.circular(AppUI.radius),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Center(
        child: Icon(Icons.add_rounded, color: AppUI.inkSoft, size: 22),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          AppUI.s16, AppUI.s12, AppUI.s16, MediaQuery.paddingOf(context).bottom + AppUI.s12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          // Contador de mesas
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppUI.s16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppUI.radius),
            ),
            child: Text(
              '${_tables.length}',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.primary),
            ),
          ),
          const SizedBox(width: AppUI.s12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _syncTables,
                icon: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
                    : const Icon(Icons.save_rounded, size: 20),
                label: Text(
                  _saving ? 'Guardando…' : 'Guardar distribución',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppUI.radius)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableData {
  final String id;
  final String label;
  final String area; // Spec 083 — zona opcional (Terraza/Salón…)
  final int gridX;
  final int gridY;
  final int capacity;

  _TableData({
    required this.id,
    required this.label,
    this.area = '',
    required this.gridX,
    required this.gridY,
    required this.capacity,
  });

  _TableData copyWith({
    String? id,
    String? label,
    String? area,
    int? gridX,
    int? gridY,
    int? capacity,
  }) {
    return _TableData(
      id: id ?? this.id,
      label: label ?? this.label,
      area: area ?? this.area,
      gridX: gridX ?? this.gridX,
      gridY: gridY ?? this.gridY,
      capacity: capacity ?? this.capacity,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}
