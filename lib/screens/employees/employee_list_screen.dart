import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/branch.dart';
import '../../models/employee.dart';

class EmployeeListScreen extends StatelessWidget {
  final List<Employee> employees;

  /// Sedes to group employees under. When non-empty (multi-branch
  /// tenant, typical PRO plan), the body switches to an ExpansionTile
  /// per sede. Empty list falls back to the legacy flat list — keeps
  /// brand-new tenants with a single "Sede Principal" looking the
  /// same as before the Phase-5 refactor.
  final List<Branch> branches;

  final VoidCallback? onAddEmployee;

  /// Fired when the user taps "Agregar empleado" inside a specific
  /// sede group. Passing the branch id lets the caller pre-select
  /// the sede on the form — one less tap in the happy path.
  final ValueChanged<String>? onAddEmployeeToBranch;

  final ValueChanged<Employee>? onEmployeeTap;

  const EmployeeListScreen({
    super.key,
    required this.employees,
    this.branches = const [],
    this.onAddEmployee,
    this.onAddEmployeeToBranch,
    this.onEmployeeTap,
  });

  /// Groups employees by branch id, returning a map keyed by branch
  /// (null = unassigned). Exported as a public static so the widget
  /// tests can assert on grouping without rendering the tree.
  static Map<String?, List<Employee>> groupByBranch(
    List<Employee> employees,
  ) {
    final map = <String?, List<Employee>>{};
    for (final e in employees) {
      map.putIfAbsent(e.branchId, () => []).add(e);
    }
    return map;
  }

  // ─── Gradient constants ───
  static const _headerGradient = LinearGradient(
    colors: [Color(0xFF764BA2), Color(0xFF667EEA)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const _adminAvatarGradient = LinearGradient(
    colors: [Color(0xFF764BA2), Color(0xFF667EEA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _cashierAvatarGradient = LinearGradient(
    colors: [Color(0xFF667EEA), Color(0xFF5A67D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _fabGradient = LinearGradient(
    colors: [Color(0xFF764BA2), Color(0xFF667EEA)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildBody(context)),
        ],
      ),
      floatingActionButton: _buildFAB(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (employees.isEmpty) return _buildEmptyState(context);

    // Single-branch tenants (or callers that haven't loaded branches
    // yet) get the legacy flat list — grouping adds a collapsed tile
    // header that feels heavy for a solo sede.
    if (branches.length <= 1) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        itemCount: employees.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) =>
            _buildEmployeeCard(context, employees[index]),
      );
    }

    // Multi-branch: ExpansionTile per sede.
    final grouped = groupByBranch(employees);
    final sections = <Widget>[];

    for (final branch in branches) {
      sections.add(_buildBranchSection(
        context,
        branch,
        grouped[branch.id] ?? const [],
      ));
    }
    // Empleados sin sucursal asignada (rows que predatan la
    // migración 025). Dejarlos visibles para que el operador pueda
    // reasignarlos manualmente en vez de esconderlos.
    final orphans = grouped[null] ?? const [];
    if (orphans.isNotEmpty) {
      sections.add(_buildOrphanSection(context, orphans));
    }

    return ListView(
      key: const Key('employees_grouped_list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: sections,
    );
  }

  Widget _buildBranchSection(
    BuildContext context,
    Branch branch,
    List<Employee> branchEmployees,
  ) {
    return Card(
      key: Key('employees_branch_section_${branch.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.store_mall_directory_rounded,
            color: Color(0xFF764BA2), size: 26),
        title: Text(
          branch.name,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
        subtitle: Text(
          branchEmployees.length == 1
              ? '1 empleado'
              : '${branchEmployees.length} empleados',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        children: [
          for (final e in branchEmployees)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildEmployeeCard(context, e),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: OutlinedButton.icon(
              key: Key('add_employee_to_${branch.id}'),
              onPressed: () {
                HapticFeedback.lightImpact();
                (onAddEmployeeToBranch ?? (_) {})(branch.id);
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(
                branchEmployees.isEmpty
                    ? 'Agregar empleado a esta sede'
                    : 'Agregar otro empleado',
                style: const TextStyle(fontSize: 15),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF764BA2),
                side: const BorderSide(color: Color(0xFF764BA2)),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrphanSection(
    BuildContext context,
    List<Employee> orphans,
  ) {
    return Card(
      key: const Key('employees_orphan_section'),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.warning_amber_rounded,
            color: Color(0xFFD97706), size: 26),
        title: const Text(
          'Sin sucursal asignada',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF92400E)),
        ),
        subtitle: Text(
          '${orphans.length} empleado${orphans.length == 1 ? '' : 's'} por reasignar',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: Colors.grey.shade600),
        ),
        children: [
          for (final e in orphans)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildEmployeeCard(context, e),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
          const Text(
            'Mi Equipo',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${employees.length} personas registradas',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 20),
            const Text(
              'Sin empleados',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3D3D3D),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Agrega a tu primer empleado\npara comenzar',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                color: Color(0xFF3D3D3D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeCard(BuildContext context, Employee employee) {
    final isAdmin = employee.role == EmployeeRole.admin;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onEmployeeTap?.call(employee);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient:
                    isAdmin ? _adminAvatarGradient : _cashierAvatarGradient,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                employee.initials,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Name + role
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.name,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildRoleBadge(employee),
                      if (employee.isOwner) ...[
                        const SizedBox(width: 8),
                        const Text(
                          '\u00B7 Due\u00F1o',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF764BA2),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Chevron
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade400,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(Employee employee) {
    final isAdmin = employee.role == EmployeeRole.admin;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isAdmin
            ? const Color(0xFF764BA2).withValues(alpha: 0.12)
            : const Color(0xFF667EEA).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        employee.roleLabel,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isAdmin ? const Color(0xFF764BA2) : const Color(0xFF667EEA),
        ),
      ),
    );
  }

  Widget _buildFAB(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onAddEmployee?.call();
      },
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: _fabGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF764BA2).withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add, color: Colors.white, size: 26),
            SizedBox(width: 12),
            Text(
              'Agregar empleado',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
