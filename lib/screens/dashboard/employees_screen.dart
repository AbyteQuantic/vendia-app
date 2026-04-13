import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Employee management screen — loads from backend, Gerontodiseño.
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  late final ApiService _api;
  List<Map<String, dynamic>> _employees = [];
  bool _loading = true;

  static const _roles = ['admin', 'cashier'];
  static const _roleLabels = {'admin': 'Administrador', 'cashier': 'Cajero'};

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final list = await _api.fetchEmployees();
      if (mounted) setState(() { _employees = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteEmployee(String id) async {
    try {
      await _api.deleteEmployee(id);
      _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: const TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _showAddSheet() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'cashier';

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
                  Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6D0C8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text('Nuevo Empleado',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(fontSize: 20, color: Colors.black87),
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 20, color: Colors.black87),
                    decoration: const InputDecoration(
                      labelText: 'Teléfono (opcional)',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 20, color: Colors.black87),
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      prefixIcon: Icon(Icons.badge_rounded),
                    ),
                    dropdownColor: Colors.white,
                    items: _roles
                        .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(_roleLabels[r] ?? r,
                                style: const TextStyle(fontSize: 20, color: Colors.black87))))
                        .toList(),
                    onChanged: (v) => setSheetState(() => selectedRole = v ?? 'cashier'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    style: const TextStyle(fontSize: 24, color: Colors.black87,
                        letterSpacing: 8),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'PIN de 4 dígitos',
                      prefixIcon: Icon(Icons.lock_rounded),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    style: const TextStyle(fontSize: 20, color: Colors.black87),
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: Icon(Icons.key_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty || pinCtrl.text.length != 4
                            || passCtrl.text.trim().isEmpty) return;
                        Navigator.of(ctx).pop();
                        try {
                          await _api.createEmployee({
                            'name': nameCtrl.text.trim(),
                            'phone': phoneCtrl.text.trim(),
                            'role': selectedRole,
                            'pin': pinCtrl.text,
                            'password': passCtrl.text,
                          });
                          _fetch();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AppTheme.error,
                            ));
                          }
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 24),
                      label: const Text('Crear Empleado',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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

  Color _roleColor(String role) =>
      role == 'admin' ? AppTheme.primary : const Color(0xFF10B981);

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
        title: const Text('Empleados',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _employees.isEmpty
              ? Center(
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
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _employees.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final emp = _employees[i];
                    final name = emp['name'] as String? ?? '';
                    final role = emp['role'] as String? ?? 'cashier';
                    final isOwner = emp['is_owner'] as bool? ?? false;
                    final color = _roleColor(role);

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              isOwner ? Icons.star_rounded : Icons.person_rounded,
                              color: color, size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold,
                                    color: Colors.black87)),
                                Text(
                                  isOwner
                                      ? 'Dueño'
                                      : (_roleLabels[role] ?? role),
                                  style: TextStyle(fontSize: 15, color: color),
                                ),
                              ],
                            ),
                          ),
                          if (!isOwner)
                            IconButton(
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                _deleteEmployee(emp['id'] as String);
                              },
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: AppTheme.error, size: 24),
                            ),
                        ],
                      ),
                    );
                  },
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
            onPressed: _showAddSheet,
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
}
