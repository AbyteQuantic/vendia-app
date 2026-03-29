import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/employee.dart';

/// Full-screen modal that lets the user pick a cashier and enter their PIN.
/// Returns the authenticated [Employee] via Navigator.pop on success.
class CashierSelectorScreen extends StatefulWidget {
  final List<Employee> employees;

  const CashierSelectorScreen({
    super.key,
    required this.employees,
  });

  @override
  State<CashierSelectorScreen> createState() => _CashierSelectorScreenState();
}

class _CashierSelectorScreenState extends State<CashierSelectorScreen> {
  Employee? _selectedEmployee;
  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();
  String? _pinError;

  // ─── Gradients ───
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

  List<Employee> get _activeEmployees =>
      widget.employees.where((e) => e.isActive).toList();

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _onEmployeeTap(Employee employee) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedEmployee = employee;
      _pinController.clear();
      _pinError = null;
    });
    // Focus the PIN field after selecting
    Future.delayed(const Duration(milliseconds: 150), () {
      _pinFocusNode.requestFocus();
    });
  }

  void _validatePin() {
    HapticFeedback.mediumImpact();
    final pin = _pinController.text.trim();
    if (_selectedEmployee == null) return;

    if (pin.length != 4) {
      setState(() => _pinError = 'Ingresa los 4 d\u00EDgitos');
      return;
    }

    if (pin == _selectedEmployee!.pin) {
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop(_selectedEmployee);
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _pinError = 'PIN incorrecto, intenta de nuevo');
      _pinController.clear();
    }
  }

  void _clearSelection() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedEmployee = null;
      _pinController.clear();
      _pinError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Container(
              width: 335,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: _selectedEmployee == null
                  ? _buildSelectionView()
                  : _buildPinView(),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Step 1: Choose employee ───
  Widget _buildSelectionView() {
    final employees = _activeEmployees;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '\u00BFQui\u00E9n va a vender?',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Toque su nombre para iniciar turno',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            color: Color(0xFF3D3D3D),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // Grid of avatars
        if (employees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No hay empleados activos',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                color: Color(0xFF3D3D3D),
              ),
            ),
          )
        else
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: employees.map(_buildAvatarTile).toList(),
          ),
      ],
    );
  }

  Widget _buildAvatarTile(Employee employee) {
    final isAdmin = employee.role == EmployeeRole.admin;
    return GestureDetector(
      onTap: () => _onEmployeeTap(employee),
      child: SizedBox(
        width: 100,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: isAdmin
                    ? _adminAvatarGradient
                    : _cashierAvatarGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isAdmin
                            ? const Color(0xFF764BA2)
                            : const Color(0xFF667EEA))
                        .withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                employee.initials,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              employee.name.split(' ').first,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 2: Enter PIN ───
  Widget _buildPinView() {
    final employee = _selectedEmployee!;
    final isAdmin = employee.role == EmployeeRole.admin;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: _clearSelection,
            child: Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              child: const Icon(
                Icons.arrow_back,
                size: 28,
                color: Color(0xFF3D3D3D),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Selected employee avatar
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: isAdmin ? _adminAvatarGradient : _cashierAvatarGradient,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            employee.initials,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 14),

        Text(
          employee.name,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 28),

        const Text(
          'Ingrese su PIN de 4 d\u00EDgitos',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            color: Color(0xFF3D3D3D),
          ),
        ),
        const SizedBox(height: 20),

        // Dot indicators + hidden text field
        _buildPinInput(),
        const SizedBox(height: 10),

        if (_pinError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _pinError!,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPinInput() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _pinFocusNode.requestFocus();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Hidden text field for system keyboard
          Opacity(
            opacity: 0,
            child: SizedBox(
              width: 1,
              height: 1,
              child: TextFormField(
                controller: _pinController,
                focusNode: _pinFocusNode,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  setState(() => _pinError = null);
                  if (value.length == 4) {
                    _validatePin();
                  }
                },
              ),
            ),
          ),

          // Visual dot indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final isFilled = index < _pinController.text.length;
              final hasError = _pinError != null;
              return Container(
                width: 52,
                height: 52,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isFilled
                      ? const Color(0xFF764BA2)
                      : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: hasError
                        ? const Color(0xFFDC2626)
                        : isFilled
                            ? const Color(0xFF764BA2)
                            : Colors.grey.shade300,
                    width: 2.5,
                  ),
                ),
                alignment: Alignment.center,
                child: isFilled
                    ? const Text(
                        '\u2022',
                        style: TextStyle(
                          fontSize: 28,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              );
            }),
          ),
        ],
      ),
    );
  }
}
