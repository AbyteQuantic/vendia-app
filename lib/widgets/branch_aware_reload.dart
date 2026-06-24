// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/branch_provider.dart';

/// Mixin para pantallas con datos POR SEDE: cuando el tendero cambia de sede con
/// el BranchSelectorChip (en el AppBar), la pantalla debe RECARGAR sus datos —
/// si no, muestra los de la sede anterior (datos viejos). La pantalla implementa
/// [onBranchChanged] con su recarga (ej. _loadProducts). Spec 078 council.
mixin BranchAwareReload<T extends StatefulWidget> on State<T> {
  String? _branchReloadPrev;
  BranchProvider? _branchReloadProvider;

  /// La pantalla implementa su recarga aquí (re-fetch con la sede nueva).
  void onBranchChanged();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final bp = context.read<BranchProvider>();
        _branchReloadProvider = bp;
        _branchReloadPrev = bp.currentBranchId;
        bp.addListener(_onBranchReload);
      } catch (_) {/* sin provider (tests) → no-op */}
    });
  }

  void _onBranchReload() {
    if (!mounted) return;
    final id = _branchReloadProvider?.currentBranchId;
    if (id != _branchReloadPrev) {
      _branchReloadPrev = id;
      onBranchChanged();
    }
  }

  @override
  void dispose() {
    _branchReloadProvider?.removeListener(_onBranchReload);
    super.dispose();
  }
}
