// Spec: specs/095-variantes-producto/spec.md (AC-03)
//
// "Vincular a un grupo de variantes" — adopta un producto YA EXISTENTE a un
// grupo sin recrearlo (UPDATE in-place en el backend), así que su historial
// de ventas/kardex/órdenes de compra queda intacto. Si ya está vinculado,
// muestra "Parte de: <grupo>" en vez del botón.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class VariantGroupLinkTile extends StatefulWidget {
  const VariantGroupLinkTile({
    super.key,
    required this.productId,
    required this.currentGroupId,
    required this.onAdopted,
    this.apiOverride,
  });

  final String productId;
  final String? currentGroupId;
  final VoidCallback onAdopted;
  final ApiService? apiOverride;

  @override
  State<VariantGroupLinkTile> createState() => _VariantGroupLinkTileState();
}

class _VariantGroupLinkTileState extends State<VariantGroupLinkTile> {
  late final ApiService _api = widget.apiOverride ?? ApiService(AuthService());
  List<Map<String, dynamic>> _groups = [];
  String? _currentGroupName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final groups = await _api.listVariantGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        if (widget.currentGroupId != null) {
          final match = groups.where((g) => g['id'] == widget.currentGroupId);
          _currentGroupName =
              match.isNotEmpty ? match.first['name'] as String? : null;
        }
      });
    } catch (_) {
      // Sin conexión: el tile simplemente no ofrece la acción esta vez.
    }
  }

  Future<void> _pickGroup() async {
    HapticFeedback.lightImpact();
    final group = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Elige el grupo de variantes',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            for (final g in _groups)
              ListTile(
                title: Text(g['name'] as String? ?? ''),
                onTap: () => Navigator.of(ctx).pop(g),
              ),
          ],
        ),
      ),
    );
    if (group == null) return;
    try {
      await _api.adoptProductToVariantGroup(widget.productId, {
        'variant_group_id': group['id'],
        'variant_attributes': const {},
      });
      widget.onAdopted();
      if (!mounted) return;
      setState(() => _currentGroupName = group['name'] as String?);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo vincular: revise su conexión.'),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentGroupName != null) {
      return Text('Parte de: $_currentGroupName',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary));
    }
    if (_groups.isEmpty) return const SizedBox.shrink();
    return TextButton(
      onPressed: _pickGroup,
      child: const Text('Vincular a un grupo de variantes'),
    );
  }
}
