import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../models/branch.dart';
import '../../models/employee.dart';

class EmployeeFormScreen extends StatefulWidget {
  /// Pass an existing employee to edit; leave null for creation.
  final Employee? employee;

  /// Sedes available to assign the employee to. Phase-5 mandated
  /// single-branch-per-employee: creates reject submission unless
  /// the user picks one; edits prefill with the current assignment
  /// and allow reassignment. Empty list disables the dropdown and
  /// surfaces a hint pointing the user at "Mis Sucursales".
  final List<Branch> branches;

  /// Optional pre-selected branch — useful when the employee list
  /// is grouped by sede and the "Add employee" button lives inside
  /// one of the sede headers. Defaults to null so the dropdown
  /// starts empty and the validator fires on an un-touched form.
  final String? initialBranchId;

  const EmployeeFormScreen({
    super.key,
    this.employee,
    this.branches = const [],
    this.initialBranchId,
  });

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  EmployeeRole _selectedRole = EmployeeRole.cashier;
  String? _selectedBranchId;

  bool get _isEditing => widget.employee != null;

  // ─── Gradients ───
  static const _adminGradient = LinearGradient(
    colors: [Color(0xFF764BA2), Color(0xFF667EEA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _cashierGradient = LinearGradient(
    colors: [Color(0xFF667EEA), Color(0xFF5A67D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _saveButtonGradient = LinearGradient(
    colors: [Color(0xFF764BA2), Color(0xFF667EEA)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.employee!.name;
      _pinController.text = widget.employee!.pin;
      _selectedRole = widget.employee!.role;
      _selectedBranchId = widget.employee!.branchId;
    } else {
      _selectedBranchId = widget.initialBranchId;
    }
    // Defensive: if the pre-selected branch isn't actually in the
    // options list, drop it so the dropdown doesn't assert on an
    // orphan value when Flutter builds the widget.
    if (_selectedBranchId != null &&
        !widget.branches.any((b) => b.id == _selectedBranchId)) {
      _selectedBranchId = null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _selectRole(EmployeeRole role) {
    HapticFeedback.selectionClick();
    setState(() => _selectedRole = role);
  }

  void _saveEmployee() {
    HapticFeedback.mediumImpact();
    if (!_formKey.currentState!.validate()) return;

    final branchId = _selectedBranchId;
    final employee = _isEditing
        ? widget.employee!.copyWith(
            name: _nameController.text.trim(),
            pin: _pinController.text.trim(),
            role: _selectedRole,
            branchId: branchId,
          )
        : Employee(
            uuid: const Uuid().v4(),
            name: _nameController.text.trim(),
            pin: _pinController.text.trim(),
            role: _selectedRole,
            branchId: branchId,
          );

    Navigator.of(context).pop(employee);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Editar Empleado' : 'Nuevo Empleado',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Name field ───
                const Text(
                  'Nombre completo',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 10),
                _buildNameField(),
                const SizedBox(height: 28),

                // ─── PIN field ───
                const Text(
                  'PIN de 4 d\u00EDgitos',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 10),
                _buildPinField(),
                const SizedBox(height: 32),

                // ─── Branch selector (mandatory) ───
                const Text(
                  'Asignar a Sucursal',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 10),
                _buildBranchDropdown(),
                const SizedBox(height: 32),

                // ─── Role selector ───
                const Text(
                  'Rol del empleado',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 14),
                _buildRoleSelector(),
                const SizedBox(height: 40),

                // ─── Save button ───
                _buildSaveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextFormField(
        controller: _nameController,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          color: Color(0xFF1A1A1A),
        ),
        decoration: InputDecoration(
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 16, right: 12),
            child: Icon(Icons.person_outline, size: 28, color: Color(0xFF764BA2)),
          ),
          hintText: 'Ej: Mar\u00EDa L\u00F3pez',
          hintStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            color: Colors.grey.shade400,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF764BA2), width: 2.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2.5),
          ),
          constraints: const BoxConstraints(minHeight: 60),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Ingresa el nombre del empleado';
          }
          if (value.trim().length < 2) {
            return 'El nombre es muy corto';
          }
          return null;
        },
        onTap: () => HapticFeedback.selectionClick(),
      ),
    );
  }

  Widget _buildPinField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextFormField(
        controller: _pinController,
        obscureText: true,
        obscuringCharacter: '\u2022',
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: 10,
          color: Color(0xFF1A1A1A),
        ),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 16, right: 12),
            child: Icon(Icons.pin_outlined, size: 28, color: Color(0xFF764BA2)),
          ),
          hintText: '\u2022\u2022\u2022\u2022',
          hintStyle: TextStyle(
            fontSize: 28,
            letterSpacing: 10,
            color: Colors.grey.shade300,
          ),
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF764BA2), width: 2.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2.5),
          ),
          constraints: const BoxConstraints(minHeight: 60),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Ingresa un PIN de 4 d\u00EDgitos';
          }
          if (value.length != 4) {
            return 'El PIN debe tener exactamente 4 d\u00EDgitos';
          }
          return null;
        },
        onTap: () => HapticFeedback.selectionClick(),
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildRoleCard(
            role: EmployeeRole.admin,
            gradient: _adminGradient,
            icon: Icons.admin_panel_settings,
            title: 'Administrador',
            description: 'Acceso total: ventas, reportes, configuraci\u00F3n',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildRoleCard(
            role: EmployeeRole.cashier,
            gradient: _cashierGradient,
            icon: Icons.point_of_sale,
            title: 'Cajero',
            description: 'Solo puede vender y fiar',
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard({
    required EmployeeRole role,
    required LinearGradient gradient,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final isSelected = _selectedRole == role;
    final gradientColors = gradient.colors;
    final primaryColor = gradientColors.first;

    return GestureDetector(
      onTap: () => _selectRole(role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade200,
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          children: [
            // Icon with gradient background
            Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 30, color: Colors.white),
                ),
                if (isSelected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.check, size: 14, color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? primaryColor : const Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: Color(0xFF3D3D3D),
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: _saveEmployee,
      child: Container(
        width: double.infinity,
        height: 64,
        decoration: BoxDecoration(
          gradient: _saveButtonGradient,
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
            Icon(Icons.save, color: Colors.white, size: 26),
            SizedBox(width: 12),
            Text(
              'Guardar empleado',
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

  Widget _buildBranchDropdown() {
    // When the tenant hasn't fetched any sedes yet (brand-new
    // session / first-boot) we show a disabled state pointing at
    // the "Mis Sucursales" screen rather than an empty dropdown —
    // the user can't submit the form anyway, and leaving a
    // functioning dropdown with zero options causes an assert in
    // Flutter's DropdownButtonFormField validation.
    if (widget.branches.isEmpty) {
      return Container(
        key: const Key('employee_branch_empty'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF59E0B)),
        ),
        child: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFD97706), size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Crea primero una sucursal en "Mis Sucursales".',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF92400E),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        key: const Key('employee_branch_dropdown'),
        initialValue: _selectedBranchId,
        isExpanded: true,
        items: widget.branches
            .map((b) => DropdownMenuItem<String>(
                  value: b.id,
                  child: Text(
                    b.name,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ))
            .toList(),
        onChanged: (value) {
          HapticFeedback.selectionClick();
          setState(() => _selectedBranchId = value);
        },
        validator: (value) =>
            value == null ? 'Seleccione la sucursal del empleado' : null,
        decoration: InputDecoration(
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 16, right: 12),
            child: Icon(Icons.store_mall_directory_rounded,
                size: 28, color: Color(0xFF764BA2)),
          ),
          hintText: 'Elija una sede',
          hintStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            color: Colors.grey.shade400,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide:
                const BorderSide(color: Color(0xFF764BA2), width: 2.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Colors.redAccent, width: 2.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Colors.redAccent, width: 2.5),
          ),
        ),
      ),
    );
  }
}
