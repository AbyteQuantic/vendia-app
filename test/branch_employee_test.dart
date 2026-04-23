import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/branch.dart';
import 'package:vendia_pos/models/employee.dart';
import 'package:vendia_pos/services/branch_provider.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Branch _branch({
  String id = 'branch-001',
  String name = 'Sede Principal',
  bool isDefault = true,
}) {
  return Branch(
    id: id,
    tenantId: 'tenant-abc',
    name: name,
    isDefault: isDefault,
    createdAt: DateTime(2026, 1, 1),
  );
}

Employee _employee({
  String uuid = 'emp-001',
  String name = 'María López',
  String pin = '1234',
  EmployeeRole role = EmployeeRole.cashier,
  String? branchId,
  String? branchName,
}) {
  return Employee(
    uuid: uuid,
    name: name,
    pin: pin,
    role: role,
    branchId: branchId,
    branchName: branchName,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPLOYEE MODEL TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('Employee.branchId — asignación a sucursal', () {
    test('Employee se crea sin branchId por default (backward compat)', () {
      final emp = _employee();
      expect(emp.branchId, isNull);
      expect(emp.branchName, isNull);
    });

    test('Employee acepta branchId al construirse', () {
      final emp = _employee(branchId: 'branch-001', branchName: 'Sede Norte');
      expect(emp.branchId, equals('branch-001'));
      expect(emp.branchName, equals('Sede Norte'));
    });

    test('Employee.fromJson mapea branch_id y branch_name correctamente', () {
      final json = {
        'uuid': 'emp-xyz',
        'name': 'Carlos Ruiz',
        'pin': '9999',
        'role': 'cashier',
        'is_active': true,
        'is_owner': false,
        'branch_id': 'branch-north',
        'branch_name': 'Sede Norte',
      };
      final emp = Employee.fromJson(json);
      expect(emp.branchId, equals('branch-north'));
      expect(emp.branchName, equals('Sede Norte'));
    });

    test('Employee.fromJson soporta branch_id nulo (empleados legacy)', () {
      final json = {
        'uuid': 'emp-legacy',
        'name': 'Pedro Viejo',
        'pin': '0000',
        'role': 'admin',
        'is_active': true,
        'is_owner': true,
      };
      final emp = Employee.fromJson(json);
      expect(emp.branchId, isNull);
      expect(emp.branchName, isNull);
    });

    test('Employee.toJson incluye branch_id cuando está presente', () {
      final emp = _employee(branchId: 'branch-001');
      final json = emp.toJson();
      expect(json['branch_id'], equals('branch-001'));
    });

    test('Employee.toJson omite branch_id cuando es nulo', () {
      final emp = _employee();
      final json = emp.toJson();
      expect(json.containsKey('branch_id'), isFalse);
    });

    test('Employee.copyWith actualiza branchId preservando los demás campos', () {
      final original = _employee(
        uuid: 'emp-001',
        branchId: 'branch-001',
        branchName: 'Sede Principal',
      );
      final updated = original.copyWith(
        branchId: 'branch-002',
        branchName: 'Sede Sur',
      );
      expect(updated.uuid, equals('emp-001')); // unchanged
      expect(updated.branchId, equals('branch-002'));
      expect(updated.branchName, equals('Sede Sur'));
    });

    test('Employee.copyWith sin branchId mantiene el valor original', () {
      final emp = _employee(branchId: 'branch-001');
      final copied = emp.copyWith(name: 'Nuevo Nombre');
      expect(copied.branchId, equals('branch-001'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BRANCH MODEL TESTS
  // ─────────────────────────────────────────────────────────────────────────

  group('Branch model', () {
    test('Branch.fromJson parsea correctamente todos los campos', () {
      final json = {
        'id': 'branch-001',
        'tenant_id': 'tenant-abc',
        'name': 'Sede Norte',
        'address': 'Cra 5 #12-34',
        'latitude': 4.6097,
        'longitude': -74.0817,
        'is_default': false,
        'is_active': true,
        'created_at': '2026-01-15T10:00:00Z',
      };
      final branch = Branch.fromJson(json);
      expect(branch.id, equals('branch-001'));
      expect(branch.name, equals('Sede Norte'));
      expect(branch.address, equals('Cra 5 #12-34'));
      expect(branch.latitude, closeTo(4.6097, 0.0001));
      expect(branch.isDefault, isFalse);
      expect(branch.isActive, isTrue);
    });

    test('Branch.fromJson acepta "uuid" como clave alternativa de ID', () {
      final json = {
        'uuid': 'branch-uuid-alt',
        'tenant_id': 'tenant-xyz',
        'name': 'Sede Sur',
        'created_at': '2026-01-15T10:00:00Z',
      };
      final branch = Branch.fromJson(json);
      expect(branch.id, equals('branch-uuid-alt'));
    });

    test('Branch.toJson incluye solo campos no-nulos opcionales', () {
      final branch = _branch(id: 'b1', name: 'Sede A');
      final json = branch.toJson();
      expect(json['name'], equals('Sede A'));
      expect(json.containsKey('latitude'), isFalse);
      expect(json.containsKey('longitude'), isFalse);
    });

    test('Branch equality se basa en id', () {
      final a = _branch(id: 'same-id', name: 'Nombre A');
      final b = _branch(id: 'same-id', name: 'Nombre B');
      expect(a == b, isTrue);
    });

    test('Branch copyWith preserva campos no modificados', () {
      final branch = _branch(id: 'b1', name: 'Original');
      final updated = branch.copyWith(name: 'Actualizado');
      expect(updated.id, equals('b1'));
      expect(updated.name, equals('Actualizado'));
      expect(updated.isDefault, isTrue); // preserved
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BRANCH PROVIDER TESTS
  // ─────────────────────────────────────────────────────────────────────────

  group('BranchProvider', () {
    late BranchProvider provider;

    setUp(() => provider = BranchProvider());
    tearDown(() => provider.dispose());

    test('estado inicial: sin ramas, sin selección', () {
      expect(provider.branches, isEmpty);
      expect(provider.currentBranch, isNull);
      expect(provider.currentBranchId, isNull);
    });

    test('setBranches selecciona la rama por defecto automáticamente', () {
      final branches = [
        _branch(id: 'b1', name: 'Sede Norte', isDefault: false),
        _branch(id: 'b2', name: 'Sede Principal', isDefault: true),
      ];
      provider.setBranches(branches);
      expect(provider.currentBranch?.id, equals('b2'));
    });

    test('selectBranch cambia la sede activa', () {
      final branches = [
        _branch(id: 'b1', isDefault: true),
        _branch(id: 'b2', name: 'Sede Sur', isDefault: false),
      ];
      provider.setBranches(branches);
      provider.selectBranch(branches[1]);
      expect(provider.currentBranchId, equals('b2'));
    });

    test('selectBranch con misma sede no emite notificación innecesaria', () {
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      final branches = [_branch(id: 'b1', isDefault: true)];
      provider.setBranches(branches); // notify 1
      provider.selectBranch(branches[0]); // should NOT notify (same branch)

      expect(notifyCount, equals(1));
    });

    test('isMultiBranch es false con una sola sede', () {
      provider.setBranches([_branch()]);
      expect(provider.isMultiBranch, isFalse);
    });

    test('isMultiBranch es true con dos o más sedes activas', () {
      provider.setBranches([
        _branch(id: 'b1', isDefault: true),
        _branch(id: 'b2', name: 'Sede Sur', isDefault: false),
      ]);
      expect(provider.isMultiBranch, isTrue);
    });

    test('upsertBranch agrega una nueva rama', () {
      provider.setBranches([_branch(id: 'b1', isDefault: true)]);
      provider.upsertBranch(_branch(id: 'b2', name: 'Nueva Sede', isDefault: false));
      expect(provider.branches.length, equals(2));
    });

    test('upsertBranch actualiza una rama existente', () {
      provider.setBranches([_branch(id: 'b1', name: 'Original', isDefault: true)]);
      provider.upsertBranch(_branch(id: 'b1', name: 'Actualizada', isDefault: true));
      expect(provider.branches.length, equals(1));
      expect(provider.branches.first.name, equals('Actualizada'));
    });

    test('removeBranch elimina la rama y hace fallback al default', () {
      final branches = [
        _branch(id: 'b1', isDefault: true),
        _branch(id: 'b2', name: 'Sede Sur', isDefault: false),
      ];
      provider.setBranches(branches);
      provider.selectBranch(branches[1]); // select non-default
      provider.removeBranch('b2');
      expect(provider.branches.length, equals(1));
      expect(provider.currentBranchId, equals('b1')); // fallback to default
    });

    test('reset limpia todo el estado', () {
      provider.setBranches([_branch()]);
      provider.reset();
      expect(provider.branches, isEmpty);
      expect(provider.currentBranch, isNull);
    });

    test('selectBranchById es seguro con ID inexistente', () {
      provider.setBranches([_branch(id: 'b1', isDefault: true)]);
      provider.selectBranchById('nonexistent');
      expect(provider.currentBranchId, equals('b1')); // unchanged
    });

    test('currentBranchId retorna el id de la sede seleccionada', () {
      provider.setBranches([_branch(id: 'branch-abc', isDefault: true)]);
      expect(provider.currentBranchId, equals('branch-abc'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // INTEGRATION: Employee assigned to Branch
  // ─────────────────────────────────────────────────────────────────────────

  group('Employee ↔ Branch assignment', () {
    test('un empleado puede asignarse a una sucursal por ID', () {
      final branch = _branch(id: 'branch-norte', name: 'Sede Norte');
      final emp = _employee(branchId: branch.id, branchName: branch.name);
      expect(emp.branchId, equals(branch.id));
    });

    test('empleados se pueden agrupar por branchId', () {
      final employees = [
        _employee(uuid: 'e1', branchId: 'b1'),
        _employee(uuid: 'e2', branchId: 'b1'),
        _employee(uuid: 'e3', branchId: 'b2'),
        _employee(uuid: 'e4'), // no branch
      ];

      final grouped = <String?, List<Employee>>{};
      for (final emp in employees) {
        grouped.putIfAbsent(emp.branchId, () => []).add(emp);
      }

      expect(grouped['b1']?.length, equals(2));
      expect(grouped['b2']?.length, equals(1));
      expect(grouped[null]?.length, equals(1));
    });

    test('filtrar empleados por sede activa del BranchProvider', () {
      final provider = BranchProvider();
      provider.setBranches([
        _branch(id: 'b1', isDefault: true),
        _branch(id: 'b2', name: 'Sede Sur', isDefault: false),
      ]);
      provider.selectBranchById('b1');

      final allEmployees = [
        _employee(uuid: 'e1', branchId: 'b1'),
        _employee(uuid: 'e2', branchId: 'b2'),
        _employee(uuid: 'e3', branchId: 'b1'),
      ];

      final filtered = allEmployees
          .where((e) => e.branchId == provider.currentBranchId)
          .toList();

      expect(filtered.length, equals(2));
      expect(filtered.every((e) => e.branchId == 'b1'), isTrue);
      provider.dispose();
    });
  });
}
