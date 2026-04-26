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
                          allBranches: _branches,
                          roleLabels: _roleLabels,
                          roleColor: _roleColor,
                          onDelete: _deleteEmployee,
                          onUpdated: _fetchAll,
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
  final List<Branch> allBranches;
  final Map<String, String> roleLabels;
  final Color Function(String role) roleColor;
  final Future<void> Function(String id) onDelete;
  final Future<void> Function() onUpdated;
  final VoidCallback onAddEmployee;

  const _BranchSection({
    required this.branchName,
    required this.isDefault,
    required this.employees,
    required this.allBranches,
    required this.roleLabels,
    required this.roleColor,
    required this.onDelete,
    required this.onUpdated,
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
                  allBranches: widget.allBranches,
                  roleLabels: widget.roleLabels,
                  roleColor: widget.roleColor,
                  onDelete: widget.onDelete,
                  onUpdated: widget.onUpdated,
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
  final List<Branch> allBranches;
  final Map<String, String> roleLabels;
  final Color Function(String) roleColor;
  final Future<void> Function(String) onDelete;
  final Future<void> Function() onUpdated;

  const _EmployeeTile({
    required this.emp,
    required this.allBranches,
    required this.roleLabels,
    required this.roleColor,
    required this.onDelete,
    required this.onUpdated,
  });

  void _openAdminSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _EmployeeAdminSheet(
        emp: emp,
        allBranches: allBranches,
        onUpdated: onUpdated,
        onDelete: () async {
          Navigator.of(sheetCtx).pop();
          HapticFeedback.mediumImpact();
          await onDelete(emp['id'] as String? ?? '');
        },
      ),
    );
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
// Full-featured edit surface for an existing employee. Lets the
// OWNER (or admin) change every operational field without leaving
// the sheet:
//   * Nombre + celular (TextFormFields with validation).
//   * Rol (Cajero / Admin) — chip selector with a permission summary
//     that updates live so the tendero understands what each role
//     can see and do.
//   * Sede asignada — dropdown of the tenant's branches plus a
//     "Sin asignar" sentinel for mono-sede tenants.
//   * Cuenta activa / inactiva — Switch (hidden for the dueño).
//   * 🔑 Asignar / cambiar contraseña — opens its own dialog and
//     POSTs /employees/:id/password.
//   * 🗑️ Eliminar empleado — destructive at the bottom.
//
// "Guardar cambios" PATCHes only the fields that actually changed
// so a no-op save doesn't show up as a noisy update in audit logs.
// On success calls `onUpdated` so the parent screen reloads its
// grouped list (e.g. branch reassignment moves the row visually).
class _EmployeeAdminSheet extends StatefulWidget {
  const _EmployeeAdminSheet({
    required this.emp,
    required this.allBranches,
    required this.onUpdated,
    required this.onDelete,
  });

  final Map<String, dynamic> emp;
  final List<Branch> allBranches;
  final Future<void> Function() onUpdated;
  final VoidCallback onDelete;

  @override
  State<_EmployeeAdminSheet> createState() => _EmployeeAdminSheetState();
}

class _EmployeeAdminSheetState extends State<_EmployeeAdminSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  final _formKey = GlobalKey<FormState>();
  late final ApiService _api;

  // Current edited values — null branch = "Sin asignar".
  String? _branchId;
  String _role = 'cashier';
  bool _isActive = true;
  bool _saving = false;
  bool _passwordSaving = false;

  // Original values to detect deltas and avoid no-op PATCHes.
  late final String _origName;
  late final String _origPhone;
  late final String? _origBranchId;
  late final String _origRole;
  late final bool _origActive;

  bool get _isOwner => widget.emp['is_owner'] as bool? ?? false;

  String get _employeeId => widget.emp['id'] as String? ?? '';

  bool get _hasPhone => _phoneCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());

    _origName = (widget.emp['name'] as String? ?? '').trim();
    _origPhone = (widget.emp['phone'] as String? ?? '').trim();
    _origBranchId = widget.emp['branch_id'] as String?;
    _origRole = (widget.emp['role'] as String?) ?? 'cashier';
    _origActive = widget.emp['is_active'] as bool? ?? true;

    _nameCtrl = TextEditingController(text: _origName);
    _phoneCtrl = TextEditingController(text: _origPhone);
    _branchId = _origBranchId;
    _role = _origRole;
    _isActive = _origActive;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _flashError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _flashOk(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Builds a partial PATCH payload of only the fields that changed.
  /// Returns null when there's nothing to send.
  Map<String, dynamic>? _buildDeltaPayload() {
    final delta = <String, dynamic>{};
    final newName = _nameCtrl.text.trim();
    final newPhone = _phoneCtrl.text.trim();
    if (newName != _origName) delta['name'] = newName;
    if (newPhone != _origPhone) delta['phone'] = newPhone;
    if (_role != _origRole && !_isOwner) delta['role'] = _role;
    if (_branchId != _origBranchId) {
      // Backend accepts empty string for "clear assignment".
      delta['branch_id'] = _branchId ?? '';
    }
    if (_isActive != _origActive && !_isOwner) {
      delta['is_active'] = _isActive;
    }
    return delta.isEmpty ? null : delta;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final delta = _buildDeltaPayload();
    if (delta == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.updateEmployee(_employeeId, delta);
      if (!mounted) return;
      _flashOk('Cambios guardados');
      await widget.onUpdated();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      _flashError('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _promptPassword() async {
    if (_isOwner) return;
    if (!_hasPhone) {
      _flashError('Primero registra un celular y guarda los cambios.');
      return;
    }
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;
    final newPassword = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: const Text('Asignar contraseña'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'El empleado podrá iniciar sesión con ${_phoneCtrl.text.trim()} y esta contraseña.',
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
                      onPressed: () => setSt(() => obscure = !obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
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
      }),
    );
    if (newPassword == null || newPassword.isEmpty) return;
    if (!mounted) return;
    setState(() => _passwordSaving = true);
    try {
      final res = await _api.setEmployeePassword(
        employeeUuid: _employeeId,
        password: newPassword,
      );
      if (!mounted) return;
      final alreadySet = res['password_already_set'] == true;
      _flashOk(alreadySet
          ? 'Quedó vinculado a este negocio. Su clave personal no se cambió.'
          : 'Contraseña asignada al empleado');
    } catch (e) {
      _flashError('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _passwordSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeBranches =
        widget.allBranches.where((b) => b.isActive).toList();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6D0C8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        _isOwner
                            ? Icons.star_rounded
                            : Icons.person_rounded,
                        color: AppTheme.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _origName.isEmpty ? 'Empleado' : _origName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isOwner
                                ? 'Dueño del negocio'
                                : 'Editar datos y permisos',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isOwner)
                      Switch(
                        key: const Key('employee_admin_active_switch'),
                        value: _isActive,
                        activeColor: AppTheme.success,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _isActive = v),
                      ),
                  ],
                ),
                if (!_isOwner)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      _isActive ? 'Cuenta activa' : 'Cuenta inactiva',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: _isActive
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // ── Datos básicos ─────────────────────────
                _SectionLabel('Datos básicos'),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('employee_admin_name'),
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 2)
                          ? 'Nombre demasiado corto'
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('employee_admin_phone'),
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Celular',
                    helperText: 'Lo usará para iniciar sesión',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null; // phone is optional
                    if (t.replaceAll(RegExp(r'\D'), '').length < 7) {
                      return 'Celular incompleto';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Sede asignada ─────────────────────────
                _SectionLabel('Sede asignada'),
                const SizedBox(height: 8),
                if (activeBranches.isEmpty)
                  _InfoChip(
                    color: AppTheme.warning,
                    text:
                        'Aún no tienes sucursales. El empleado quedará en el negocio principal.',
                  )
                else
                  DropdownButtonFormField<String?>(
                    key: const Key('employee_admin_branch'),
                    initialValue: _branchId,
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Sin asignar'),
                      ),
                      ...activeBranches.map(
                        (b) => DropdownMenuItem<String?>(
                          value: b.id,
                          child: Text(
                              b.isDefault ? '${b.name} · Principal' : b.name),
                        ),
                      ),
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Sucursal',
                    ),
                    onChanged: _saving || _isOwner
                        ? null
                        : (v) => setState(() => _branchId = v),
                  ),
                const SizedBox(height: 16),

                // ── Rol y permisos ────────────────────────
                if (!_isOwner) ...[
                  _SectionLabel('Rol y permisos'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _RoleChip(
                        label: 'Cajero',
                        active: _role == 'cashier',
                        onTap: () => setState(() => _role = 'cashier'),
                      ),
                      const SizedBox(width: 8),
                      _RoleChip(
                        label: 'Administrador',
                        active: _role == 'admin',
                        onTap: () => setState(() => _role = 'admin'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _PermissionsSummary(role: _role),
                  const SizedBox(height: 16),
                ],

                // ── Acciones ──────────────────────────────
                FilledButton.icon(
                  key: const Key('employee_admin_save'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppTheme.primary,
                  ),
                ),
                if (!_isOwner) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('employee_admin_set_password'),
                    onPressed:
                        _passwordSaving ? null : _promptPassword,
                    icon: _passwordSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5),
                          )
                        : const Icon(Icons.key_rounded),
                    label: Text(_passwordSaving
                        ? 'Guardando contraseña...'
                        : 'Asignar / cambiar contraseña'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                          color:
                              AppTheme.primary.withValues(alpha: 0.4)),
                      foregroundColor: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    key: const Key('employee_admin_delete'),
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Eliminar empleado'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.color, required this.text});
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text,
          style:
              const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? AppTheme.primary.withValues(alpha: 0.1)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? AppTheme.primary.withValues(alpha: 0.5)
                  : Colors.grey.shade300,
              width: active ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: active ? AppTheme.primary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionsSummary extends StatelessWidget {
  const _PermissionsSummary({required this.role});
  final String role;

  // Static map keeps the source of truth in one spot — matches the
  // capability getters on RoleManager so the UX never lies about what
  // a role can or can't do.
  static const Map<String, _RoleCapabilities> _capabilities = {
    'admin': _RoleCapabilities(
      canSeeFinances: true,
      canManageBusinessSettings: true,
      canManageEmployees: true,
      canSell: true,
      canApplyPromotions: true,
      canManageInventory: true,
      canVoidPastSales: true,
    ),
    'cashier': _RoleCapabilities(
      canSell: true,
      canApplyPromotions: true,
      canManageInventory: true,
      // Everything else is false — explicit so the table renders it.
    ),
  };

  @override
  Widget build(BuildContext context) {
    final caps = _capabilities[role] ?? const _RoleCapabilities();
    final rows = <_PermLine>[
      _PermLine('Vender en POS', caps.canSell),
      _PermLine('Aplicar promociones', caps.canApplyPromotions),
      _PermLine('Agregar / editar productos', caps.canManageInventory),
      _PermLine('Ver ventas y ganancias', caps.canSeeFinances),
      _PermLine('Anular ventas pasadas', caps.canVoidPastSales),
      _PermLine('Configurar pagos / sedes',
          caps.canManageBusinessSettings),
      _PermLine('Crear / borrar empleados', caps.canManageEmployees),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lo que podrá hacer:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    r.allowed
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 16,
                    color:
                        r.allowed ? AppTheme.success : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: r.allowed
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermLine {
  const _PermLine(this.label, this.allowed);
  final String label;
  final bool allowed;
}

class _RoleCapabilities {
  const _RoleCapabilities({
    this.canSeeFinances = false,
    this.canManageBusinessSettings = false,
    this.canManageEmployees = false,
    this.canSell = false,
    this.canApplyPromotions = false,
    this.canManageInventory = false,
    this.canVoidPastSales = false,
  });
  final bool canSeeFinances;
  final bool canManageBusinessSettings;
  final bool canManageEmployees;
  final bool canSell;
  final bool canApplyPromotions;
  final bool canManageInventory;
  final bool canVoidPastSales;
}
