import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/branch.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/branch_provider.dart';
import '../../theme/app_theme.dart';

/// EmployeesScreen — employees grouped by branch using ExpansionTile.
/// Implements the multi-branch hierarchy: Negocio → Sucursal → Empleados.
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  late final ApiService _api;
  List<Map<String, dynamic>> _employees = [];
  List<Branch> _branches = [];
  bool _loading = true;

  static const _roles = ['admin', 'cashier'];
  static const _roleLabels = {
    'admin': 'Administrador',
    'cashier': 'Cajero',
  };

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    try {
      final empsFuture = _api.fetchEmployees();
      final branchesFuture = _api.fetchBranches();
      final emps = await empsFuture;
      final branchMaps = await branchesFuture;
      if (!mounted) return;
      setState(() {
        _employees = emps;
        _branches = branchMaps.map(Branch.fromJson).toList();
        _loading = false;
      });
      // Sync the branch provider if not yet loaded
      if (mounted && _branches.isNotEmpty) {
        context.read<BranchProvider>().setBranches(_branches);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteEmployee(String id) async {
    try {
      await _api.deleteEmployee(id);
      _fetchAll();
    } catch (e) {
      if (mounted) {
        _showSnack('Error al eliminar: $e', isError: true);
      }
    }
  }

  /// Employees grouped by branch_id. Employees with null branch_id go into
  /// a "Sin sucursal asignada" fallback group.
  Map<String?, List<Map<String, dynamic>>> get _grouped {
    final map = <String?, List<Map<String, dynamic>>>{};
    for (final emp in _employees) {
      final key = emp['branch_id'] as String?;
      map.putIfAbsent(key, () => []).add(emp);
    }
    return map;
  }

  void _showAddSheet({String? preselectedBranchId}) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'cashier';
    String? selectedBranchId = preselectedBranchId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6D0C8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'Nuevo Empleado',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                  const SizedBox(height: 16),

                  // Name
                  _buildSheetField(
                      ctrl: nameCtrl,
                      label: 'Nombre completo',
                      icon: Icons.person_rounded),
                  const SizedBox(height: 12),

                  // Phone
                  _buildSheetField(
                      ctrl: phoneCtrl,
                      label: 'Teléfono',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone),
                  const SizedBox(height: 12),

                  // Role dropdown
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 18, color: Colors.black87),
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      prefixIcon: Icon(Icons.badge_rounded),
                    ),
                    dropdownColor: Colors.white,
                    items: _roles
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(_roleLabels[r] ?? r,
                                  style: const TextStyle(
                                      fontSize: 18, color: Colors.black87)),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => selectedRole = v ?? 'cashier'),
                  ),
                  const SizedBox(height: 12),

                  // ── Branch selector (REQUIRED) ──────────────────────
                  DropdownButtonFormField<String>(
                    key: const Key('emp_branch_selector'),
                    value: selectedBranchId,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 18, color: Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'Asignar a Sucursal *',
                      prefixIcon: const Icon(
                          Icons.store_mall_directory_rounded,
                          color: AppTheme.primary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppTheme.primary, width: 2),
                      ),
                    ),
                    dropdownColor: Colors.white,
                    hint: const Text('Selecciona una sede'),
                    items: _branches
                        .where((b) => b.isActive)
                        .map((b) => DropdownMenuItem(
                              value: b.id,
                              child: Text(b.name,
                                  style: const TextStyle(
                                      fontSize: 18, color: Colors.black87)),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => selectedBranchId = v),
                    validator: (v) =>
                        v == null ? 'Selecciona una sucursal' : null,
                  ),
                  const SizedBox(height: 12),

                  // PIN
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    style: const TextStyle(
                        fontSize: 24, color: Colors.black87, letterSpacing: 8),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'PIN de 4 dígitos',
                      prefixIcon: Icon(Icons.lock_rounded),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Password
                  _buildSheetField(
                      ctrl: passCtrl,
                      label: 'Contraseña',
                      icon: Icons.key_rounded,
                      obscure: true),
                  const SizedBox(height: 20),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty ||
                            phoneCtrl.text.trim().length < 7 ||
                            pinCtrl.text.length != 4 ||
                            passCtrl.text.trim().isEmpty ||
                            selectedBranchId == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text(
                                'Completa todos los campos incluyendo la sucursal'),
                            backgroundColor: AppTheme.error,
                          ));
                          return;
                        }
                        Navigator.of(ctx).pop();
                        try {
                          await _api.createEmployee({
                            'name': nameCtrl.text.trim(),
                            'phone': phoneCtrl.text.trim(),
                            'role': selectedRole,
                            'pin': pinCtrl.text,
                            'password': passCtrl.text,
                            'branch_id': selectedBranchId,
                          });
                          _fetchAll();
                        } catch (e) {
                          if (mounted) _showSnack('Error: $e', isError: true);
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 24),
                      label: const Text('Crear Empleado',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
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
        ),
      ),
    );
  }

  Widget _buildSheetField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(fontSize: 18, color: Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
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

  Color _roleColor(String role) =>
      role == 'admin' ? AppTheme.primary : const Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    // Build section list: known branches first (sorted: default first), then nulls
    final orderedBranchIds = [
      ..._branches
          .where((b) => grouped.containsKey(b.id))
          .map((b) => b.id)
          .toList(),
      if (grouped.containsKey(null)) null,
    ];

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
          'Empleados',
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _employees.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _fetchAll,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: orderedBranchIds.length,
                    itemBuilder: (_, i) {
                      final branchId = orderedBranchIds[i];
                      final branch = branchId != null
                          ? _branches.where((b) => b.id == branchId).firstOrNull
                          : null;
                      final branchName = branch?.name ?? 'Sin sucursal asignada';
                      final emps = grouped[branchId] ?? [];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _BranchSection(
                          branchName: branchName,
                          isDefault: branch?.isDefault ?? false,
                          employees: emps,
                          roleLabels: _roleLabels,
                          roleColor: _roleColor,
                          onDelete: _deleteEmployee,
                          onAddEmployee: () =>
                              _showAddSheet(preselectedBranchId: branchId),
                        ),
                      );
                    },
                  ),
                ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF7),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          height: 60,
          child: ElevatedButton.icon(
            onPressed: () => _showAddSheet(),
            icon: const Icon(Icons.person_add_rounded, size: 24),
            label: const Text('Agregar Empleado',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline_rounded,
              size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('Sin empleados registrados',
              style: TextStyle(fontSize: 20, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

// ─── Branch Section Widget ────────────────────────────────────────────────────

class _BranchSection extends StatefulWidget {
  final String branchName;
  final bool isDefault;
  final List<Map<String, dynamic>> employees;
  final Map<String, String> roleLabels;
  final Color Function(String role) roleColor;
  final Future<void> Function(String id) onDelete;
  final VoidCallback onAddEmployee;

  const _BranchSection({
    required this.branchName,
    required this.isDefault,
    required this.employees,
    required this.roleLabels,
    required this.roleColor,
    required this.onDelete,
    required this.onAddEmployee,
  });

  @override
  State<_BranchSection> createState() => _BranchSectionState();
}

class _BranchSectionState extends State<_BranchSection> {

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: Key('branch_tile_${widget.branchName}'),
          initiallyExpanded: true,
          onExpansionChanged: (_) {},
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              widget.isDefault
                  ? Icons.home_work_rounded
                  : Icons.store_mall_directory_rounded,
              color: AppTheme.primary,
              size: 22,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  widget.branchName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.employees.length} empl.',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          children: [
            const Divider(height: 1, indent: 16, endIndent: 16),
            ...widget.employees.map((emp) => _EmployeeTile(
                  emp: emp,
                  roleLabels: widget.roleLabels,
                  roleColor: widget.roleColor,
                  onDelete: widget.onDelete,
                )),
            // Add employee to this branch
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onAddEmployee();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        style: BorderStyle.solid),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_add_rounded,
                          color: AppTheme.primary, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Agregar empleado a esta sede',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Employee Tile ─────────────────────────────────────────────────────────────

class _EmployeeTile extends StatelessWidget {
  final Map<String, dynamic> emp;
  final Map<String, String> roleLabels;
  final Color Function(String) roleColor;
  final Future<void> Function(String) onDelete;

  const _EmployeeTile({
    required this.emp,
    required this.roleLabels,
    required this.roleColor,
    required this.onDelete,
  });

  void _openAdminSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    final isOwner = emp['is_owner'] as bool? ?? false;
    final id = emp['id'] as String? ?? '';
    final phone = emp['phone'] as String? ?? '';
    final hasPhone = phone.trim().isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _EmployeeAdminSheet(
        employeeName: emp['name'] as String? ?? '',
        employeeId: id,
        canDelete: !isOwner,
        canSetPassword: !isOwner && hasPhone,
        missingPhoneHint: !hasPhone,
        onSetPassword: () async {
          Navigator.of(sheetCtx).pop();
          await _promptPasswordChange(context, id);
        },
        onDelete: () {
          Navigator.of(sheetCtx).pop();
          HapticFeedback.mediumImpact();
          onDelete(id);
        },
      ),
    );
  }

  Future<void> _promptPasswordChange(
      BuildContext context, String employeeId) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;

    final newPassword = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Asignar contraseña'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'El empleado podrá iniciar sesión con su celular y esta contraseña.',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('employee_password_field'),
                    controller: ctrl,
                    obscureText: obscure,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Nueva contraseña',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded),
                        onPressed: () =>
                            setState(() => obscure = !obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 6) {
                        return 'Mínimo 6 caracteres';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.of(dialogCtx).pop(ctrl.text);
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        });
      },
    );

    if (newPassword == null || newPassword.isEmpty) return;
    if (!context.mounted) return;

    try {
      final api = ApiService(AuthService());
      final res = await api.setEmployeePassword(
        employeeUuid: employeeId,
        password: newPassword,
      );
      if (!context.mounted) return;
      final alreadySet = res['password_already_set'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(alreadySet
              ? 'Quedó vinculado a este negocio. Su clave personal no se cambió.'
              : 'Contraseña asignada al empleado'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = emp['name'] as String? ?? '';
    final role = emp['role'] as String? ?? 'cashier';
    final isOwner = emp['is_owner'] as bool? ?? false;
    final color = roleColor(role);

    return InkWell(
      onTap: () => _openAdminSheet(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isOwner ? Icons.star_rounded : Icons.person_rounded,
                color: color, size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  Text(
                    isOwner ? 'Dueño' : (roleLabels[role] ?? role),
                    style: TextStyle(fontSize: 13, color: color),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.grey, size: 22),
          ],
        ),
      ),
    );
  }
}

// ─── Admin BottomSheet ─────────────────────────────────────────────────────────
//
// Tap on any non-owner employee opens this sheet so the OWNER has a
// concentrated set of admin actions in one place. Currently exposes
// the password-reset flow + delete; future iterations can drop role
// changes / branch reassignments here without re-opening every
// surface that lists employees.
class _EmployeeAdminSheet extends StatelessWidget {
  const _EmployeeAdminSheet({
    required this.employeeName,
    required this.employeeId,
    required this.canDelete,
    required this.canSetPassword,
    required this.missingPhoneHint,
    required this.onSetPassword,
    required this.onDelete,
  });

  final String employeeName;
  final String employeeId;
  final bool canDelete;
  final bool canSetPassword;
  final bool missingPhoneHint;
  final VoidCallback onSetPassword;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFD6D0C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            employeeName.isEmpty ? 'Empleado' : employeeName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '¿Qué quieres hacer con este empleado?',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 18),

          if (canSetPassword)
            _AdminAction(
              key: const Key('employee_admin_set_password'),
              icon: Icons.key_rounded,
              emoji: '🔑',
              label: 'Asignar / Cambiar Contraseña',
              subtitle: 'Para que pueda iniciar sesión en la app',
              color: AppTheme.primary,
              onTap: onSetPassword,
            )
          else if (missingPhoneHint)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Para asignar contraseña, primero registra un celular para este empleado.',
                style:
                    TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              ),
            ),

          if (canDelete) ...[
            const SizedBox(height: 8),
            _AdminAction(
              key: const Key('employee_admin_delete'),
              icon: Icons.delete_outline_rounded,
              emoji: '🗑️',
              label: 'Eliminar empleado',
              subtitle: 'Pierde acceso al instante',
              color: AppTheme.error,
              onTap: onDelete,
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _AdminAction extends StatelessWidget {
  const _AdminAction({
    super.key,
    required this.icon,
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String emoji;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$emoji  $label',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
