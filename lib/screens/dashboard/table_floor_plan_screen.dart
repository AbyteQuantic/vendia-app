import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Floor Plan Editor — Gerontodiseño: grid interactivo para gestionar mesas.
/// Todas las operaciones ocurren en memoria hasta presionar "Guardar".
class TableFloorPlanScreen extends StatefulWidget {
  const TableFloorPlanScreen({super.key});

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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Nueva Mesa',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: Colors.black87)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 22, color: Colors.black87),
          decoration: const InputDecoration(
            hintText: 'Nombre de la mesa',
            hintStyle: TextStyle(color: Color(0xFFB0A99A)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar',
                style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              setState(() {
                _tables['$x,$y'] = _TableData(
                  id: '',
                  label: name,
                  gridX: x,
                  gridY: y,
                  capacity: 4,
                );
                _dirty = true;
              });
              HapticFeedback.lightImpact();
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Crear',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(table.label,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800,
                    color: Colors.black87)),
            const SizedBox(height: 4),
            Text('Capacidad: ${table.capacity} sillas',
                style: const TextStyle(
                    fontSize: 16, color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.edit_rounded,
                    label: 'Editar',
                    color: const Color(0xFF3B82F6),
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
    final capCtrl = TextEditingController(text: table.capacity.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Editar Mesa',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 20, color: Colors.black87),
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: capCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 20, color: Colors.black87),
              decoration: const InputDecoration(labelText: 'Sillas'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar',
                style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              setState(() {
                _tables[key] = table.copyWith(
                  label: name,
                  capacity: int.tryParse(capCtrl.text) ?? table.capacity,
                );
                _dirty = true;
              });
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Guardar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Plano de Mesas',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Sin guardar',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Toque un espacio vacío para agregar mesa. Toque una mesa para editar o eliminar.',
                  style: TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary),
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
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
        color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3B82F6), width: 2),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.table_restaurant_rounded,
                color: Color(0xFF3B82F6), size: 26),
            const SizedBox(height: 2),
            Text(
              table.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E3A5F),
              ),
            ),
            Text(
              '${table.capacity} sillas',
              style: TextStyle(
                fontSize: 10,
                color: const Color(0xFF3B82F6).withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCell() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD6D0C8),
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Icon(Icons.add_rounded,
            color: const Color(0xFFB0A99A).withValues(alpha: 0.5), size: 24),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Table counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${_tables.length}',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3B82F6)),
            ),
          ),
          const SizedBox(width: 12),
          // Save button
          Expanded(
            child: SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _syncTables,
                icon: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('\u{1F4BE}', style: TextStyle(fontSize: 22)),
                label: Text(
                  _saving ? 'Guardando...' : 'Guardar Distribución',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppTheme.success.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
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
  final int gridX;
  final int gridY;
  final int capacity;

  _TableData({
    required this.id,
    required this.label,
    required this.gridX,
    required this.gridY,
    required this.capacity,
  });

  _TableData copyWith({
    String? id,
    String? label,
    int? gridX,
    int? gridY,
    int? capacity,
  }) {
    return _TableData(
      id: id ?? this.id,
      label: label ?? this.label,
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
