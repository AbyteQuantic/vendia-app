import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/branch.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/branch_provider.dart';
import '../../theme/app_theme.dart';

/// BranchesListScreen — "Mis Sucursales"
/// Lists all branches for the current tenant and lets the owner add/edit them.
/// Restricted to PRO or active TRIAL plans (enforced via backend 403 on create).
class BranchesListScreen extends StatefulWidget {
  const BranchesListScreen({super.key});

  @override
  State<BranchesListScreen> createState() => _BranchesListScreenState();
}

class _BranchesListScreenState extends State<BranchesListScreen> {
  late final ApiService _api;
  bool _loading = true;

  static const _headerGradient = LinearGradient(
    colors: [Color(0xFF5A67D8), Color(0xFF764BA2)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    final provider = context.read<BranchProvider>();
    provider.setLoading(true);
    try {
      final list = await _api.fetchBranches();
      final branches = list.map(Branch.fromJson).toList();
      if (mounted) provider.setBranches(branches);
    } catch (e) {
      if (mounted) provider.setError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteBranch(Branch branch) async {
    if (branch.isDefault) {
      _showSnack('La sede principal no puede eliminarse', isError: true);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Eliminar sede?', style: TextStyle(fontSize: 20)),
        content: Text(
          'Se eliminará "${branch.name}". Esta acción no se puede deshacer.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _api.deleteBranch(branch.id);
      if (mounted) context.read<BranchProvider>().removeBranch(branch.id);
      if (mounted) _showSnack('Sede eliminada');
    } catch (e) {
      if (mounted) _showSnack('Error: $e', isError: true);
    }
  }

  void _showBranchSheet({Branch? branch}) {
    final nameCtrl = TextEditingController(text: branch?.name ?? '');
    final addressCtrl = TextEditingController(text: branch?.address ?? '');
    final isEditing = branch != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                isEditing ? 'Editar Sede' : 'Nueva Sede',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 20),
              _buildSheetField(
                controller: nameCtrl,
                label: 'Nombre de la sede *',
                hint: 'Ej: Sede Norte, Sede Principal',
                icon: Icons.store_mall_directory_rounded,
              ),
              const SizedBox(height: 14),
              _buildSheetField(
                controller: addressCtrl,
                label: 'Dirección (opcional)',
                hint: 'Ej: Cra 5 #12-34, Bogotá',
                icon: Icons.location_on_rounded,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    Navigator.of(ctx).pop();
                    try {
                      if (isEditing) {
                        // branch is non-null when isEditing==true
                        final b = branch; // ignore: unnecessary_local_variable
                        final updated = await _api.updateBranch(b!.id, {
                          'name': name,
                          'address': addressCtrl.text.trim(),
                        });
                        if (mounted) {
                          context.read<BranchProvider>()
                              .upsertBranch(Branch.fromJson(updated));
                        }
                        if (mounted) _showSnack('Sede actualizada');
                      } else {
                        final created = await _api.createBranch({
                          'name': name,
                          'address': addressCtrl.text.trim(),
                        });
                        if (mounted) {
                          context.read<BranchProvider>()
                              .upsertBranch(Branch.fromJson(created));
                        }
                        if (mounted) _showSnack('Sede creada');
                      }
                    } catch (e) {
                      if (mounted) _showSnack('Error: $e', isError: true);
                    }
                  },
                  icon: Icon(isEditing ? Icons.save_rounded : Icons.add_rounded,
                      size: 22),
                  label: Text(
                    isEditing ? 'Guardar Cambios' : 'Agregar Sede',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(fontSize: 18, color: Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 16)),
      backgroundColor: isError ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BranchProvider>();
    final branches = provider.branches;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      body: Column(
        children: [
          _buildHeader(branches.length),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : provider.error != null
                    ? _buildErrorState(provider.error!)
                    : branches.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            color: AppTheme.primary,
                            onRefresh: _fetchBranches,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                              itemCount: branches.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) =>
                                  _buildBranchCard(branches[i], provider),
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildHeader(int count) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, topPadding + 20, 24, 28),
      decoration: const BoxDecoration(
        gradient: _headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 26),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Mis Sucursales',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Text(
              '$count ${count == 1 ? 'sede registrada' : 'sedes registradas'}',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchCard(Branch branch, BranchProvider provider) {
    final isSelected = provider.currentBranch?.id == branch.id;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        provider.selectBranch(branch);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : const Color(0xFFE8E4DF),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary.withValues(alpha: 0.12)
                    : const Color(0xFFF0EEF8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                branch.isDefault
                    ? Icons.home_work_rounded
                    : Icons.store_mall_directory_rounded,
                color: isSelected ? AppTheme.primary : const Color(0xFF764BA2),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),

            // Name + address
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          branch.name,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? AppTheme.primary
                                : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (branch.isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Principal',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (branch.address case final addr? when addr.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      addr,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (isSelected) ...[
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: AppTheme.success, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Sede activa',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Actions
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppTheme.textSecondary, size: 22),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_rounded, size: 18, color: AppTheme.primary),
                    SizedBox(width: 10),
                    Text('Editar'),
                  ]),
                ),
                if (!branch.isDefault)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 18, color: AppTheme.error),
                      SizedBox(width: 10),
                      Text('Eliminar',
                          style: TextStyle(color: AppTheme.error)),
                    ]),
                  ),
              ],
              onSelected: (action) {
                if (action == 'edit') _showBranchSheet(branch: branch);
                if (action == 'delete') _deleteBranch(branch);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _showBranchSheet();
      },
      child: Container(
        height: 60,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5A67D8), Color(0xFF764BA2)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 24),
            SizedBox(width: 10),
            Text(
              'Agregar Nueva Sede',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_mall_directory_outlined,
                size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 20),
            const Text(
              'Sin sedes registradas',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w600,
                  color: Color(0xFF3D3D3D)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Agrega tu primera sucursal para\norganizar tu equipo e inventario',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 60, color: AppTheme.error),
            const SizedBox(height: 16),
            const Text('Error al cargar sedes',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchBranches,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
