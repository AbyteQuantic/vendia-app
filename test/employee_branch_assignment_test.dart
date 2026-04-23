import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/models/branch.dart';
import 'package:vendia_pos/models/employee.dart';
import 'package:vendia_pos/screens/employees/employee_form_screen.dart';
import 'package:vendia_pos/screens/employees/employee_list_screen.dart';

/// Phase-5 multi-branch architecture tests. The contract under test:
///   1. EmployeeFormScreen requires the user to pick a sede before
///      submitting. Un-assigned employees are rejected by the
///      backend (migration 025 + /api/v1/employees POST), so the
///      form stops them client-side too.
///   2. EmployeeListScreen groups employees by sede when more than
///      one branch exists. Solo-sede tenants still get the legacy
///      flat list so the UI doesn't feel heavy for the 90% case.
///   3. A pre-selected branch (initialBranchId, e.g. tapping
///      "Agregar a esta sede" from a group header) shortcuts the
///      dropdown so the user just fills name + PIN and submits.

Branch _branch(String id, String name) => Branch(
      id: id,
      tenantId: 'tenant-a',
      name: name,
      createdAt: DateTime(2026, 4, 23),
    );

Employee _employee({
  required String uuid,
  required String name,
  String? branchId,
  EmployeeRole role = EmployeeRole.cashier,
}) =>
    Employee(uuid: uuid, name: name, pin: '1234', role: role, branchId: branchId);

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmployeeListScreen.groupByBranch', () {
    test('buckets each employee under its branch id', () {
      final map = EmployeeListScreen.groupByBranch([
        _employee(uuid: 'e1', name: 'Pedro', branchId: 'br-1'),
        _employee(uuid: 'e2', name: 'Ana', branchId: 'br-1'),
        _employee(uuid: 'e3', name: 'Juan', branchId: 'br-2'),
      ]);

      expect(map['br-1']!.map((e) => e.name), ['Pedro', 'Ana']);
      expect(map['br-2']!.map((e) => e.name), ['Juan']);
      expect(map.containsKey('br-3'), isFalse);
    });

    test('parks employees without branch_id under the null key', () {
      final map = EmployeeListScreen.groupByBranch([
        _employee(uuid: 'e1', name: 'Pre-migration', branchId: null),
      ]);
      expect(map[null], isNotNull);
      expect(map[null]!.single.name, 'Pre-migration');
    });

    test('empty input returns empty map', () {
      expect(EmployeeListScreen.groupByBranch(const []), isEmpty);
    });
  });

  group('EmployeeFormScreen — branch picker (creation)', () {
    testWidgets(
        'submit without picking a branch surfaces the "Seleccione la sucursal" validator',
        (tester) async {
      // Widen the viewport so the save button and validator text
      // aren't clipped below the fold — default 800x600 truncates
      // the form and tests can't tap / assert on off-screen widgets.
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(EmployeeFormScreen(
        branches: [
          _branch('br-1', 'Sede Principal'),
          _branch('br-2', 'Sede Norte'),
        ],
      )));

      // Fill name + PIN so only the branch picker is missing.
      await tester.enterText(find.byType(TextFormField).at(0), 'Pedro Díaz');
      await tester.enterText(find.byType(TextFormField).at(1), '1234');

      await tester.ensureVisible(find.text('Guardar empleado'));
      await tester.tap(find.text('Guardar empleado'));
      await tester.pump();

      expect(find.text('Seleccione la sucursal del empleado'), findsOneWidget,
          reason: 'the validator must block submission when no sede is picked');
    });

    testWidgets(
        'selecting a branch + filling fields fires Navigator.pop with Employee.branchId set',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Employee? returned;

      await tester.pumpWidget(_wrap(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                returned = await Navigator.of(context).push<Employee>(
                  MaterialPageRoute(
                    builder: (_) => EmployeeFormScreen(
                      branches: [
                        _branch('br-1', 'Sede Principal'),
                        _branch('br-2', 'Sede Norte'),
                      ],
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      )));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Ana Gómez');
      await tester.enterText(find.byType(TextFormField).at(1), '4321');

      // Open the dropdown and pick Sede Norte.
      await tester.tap(find.byKey(const Key('employee_branch_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sede Norte').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Guardar empleado'));
      await tester.tap(find.text('Guardar empleado'));
      await tester.pumpAndSettle();

      expect(returned, isNotNull);
      expect(returned!.name, 'Ana Gómez');
      expect(returned!.branchId, 'br-2',
          reason: 'the pop payload must carry the picked sede uuid');
    });

    testWidgets(
        'initialBranchId pre-fills the dropdown so the user only types name + PIN',
        (tester) async {
      await tester.pumpWidget(_wrap(EmployeeFormScreen(
        branches: [
          _branch('br-1', 'Sede Principal'),
          _branch('br-2', 'Sede Norte'),
        ],
        initialBranchId: 'br-2',
      )));

      // The dropdown should render the pre-selected branch label.
      expect(find.text('Sede Norte'), findsWidgets);
    });

    testWidgets(
        'empty branches list shows the "crear primero una sucursal" warning',
        (tester) async {
      await tester.pumpWidget(_wrap(const EmployeeFormScreen(branches: [])));

      expect(find.byKey(const Key('employee_branch_empty')), findsOneWidget);
      expect(find.textContaining('Crea primero una sucursal'), findsOneWidget);
    });

    testWidgets(
        'editing an existing employee prefills the dropdown with their branch',
        (tester) async {
      final existing = _employee(
        uuid: 'e-exist', name: 'Existing User', branchId: 'br-1',
      );

      await tester.pumpWidget(_wrap(EmployeeFormScreen(
        employee: existing,
        branches: [
          _branch('br-1', 'Sede Principal'),
          _branch('br-2', 'Sede Norte'),
        ],
      )));

      expect(find.text('Sede Principal'), findsWidgets);
    });
  });

  group('EmployeeListScreen — grouping render', () {
    testWidgets(
        'multi-branch tenant renders one ExpansionTile per sede with employee count',
        (tester) async {
      await tester.pumpWidget(_wrap(EmployeeListScreen(
        employees: [
          _employee(uuid: 'e1', name: 'Pedro', branchId: 'br-1'),
          _employee(uuid: 'e2', name: 'Ana', branchId: 'br-1'),
          _employee(uuid: 'e3', name: 'Juan', branchId: 'br-2'),
        ],
        branches: [
          _branch('br-1', 'Sede Principal'),
          _branch('br-2', 'Sede Norte'),
        ],
      )));

      expect(find.byKey(const Key('employees_grouped_list')), findsOneWidget);
      expect(
        find.byKey(const Key('employees_branch_section_br-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('employees_branch_section_br-2')),
        findsOneWidget,
      );

      // Header shows the count.
      expect(find.text('2 empleados'), findsOneWidget);
      expect(find.text('1 empleado'), findsOneWidget);
    });

    testWidgets(
        'single-branch tenant falls back to the legacy flat list (no ExpansionTile)',
        (tester) async {
      await tester.pumpWidget(_wrap(EmployeeListScreen(
        employees: [
          _employee(uuid: 'e1', name: 'Pedro', branchId: 'br-1'),
        ],
        branches: [_branch('br-1', 'Sede Principal')],
      )));

      expect(find.byKey(const Key('employees_grouped_list')), findsNothing,
          reason: 'solo-sede stays flat for low-friction UX');
      expect(find.byType(ExpansionTile), findsNothing);
    });

    testWidgets('unassigned employees surface in an amber "Sin sucursal" bucket',
        (tester) async {
      await tester.pumpWidget(_wrap(EmployeeListScreen(
        employees: [
          _employee(uuid: 'e1', name: 'Pedro', branchId: 'br-1'),
          _employee(uuid: 'ghost', name: 'Pre-migration', branchId: null),
        ],
        branches: [
          _branch('br-1', 'Sede Principal'),
          _branch('br-2', 'Sede Norte'),
        ],
      )));

      expect(find.byKey(const Key('employees_orphan_section')), findsOneWidget);
      expect(find.text('Sin sucursal asignada'), findsOneWidget);
    });

    testWidgets(
        'tapping "Agregar empleado" inside a sede section fires onAddEmployeeToBranch with the branch id',
        (tester) async {
      String? captured;

      await tester.pumpWidget(_wrap(EmployeeListScreen(
        employees: [],
        branches: [
          _branch('br-1', 'Sede Principal'),
          _branch('br-2', 'Sede Norte'),
        ],
        onAddEmployeeToBranch: (id) => captured = id,
      )));

      // Grouping only kicks in when employees is non-empty. Seed one
      // employee per sede so both section headers render.
      await tester.pumpWidget(_wrap(EmployeeListScreen(
        employees: [
          _employee(uuid: 'e1', name: 'Seed', branchId: 'br-1'),
        ],
        branches: [
          _branch('br-1', 'Sede Principal'),
          _branch('br-2', 'Sede Norte'),
        ],
        onAddEmployeeToBranch: (id) => captured = id,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_employee_to_br-2')));
      await tester.pump();

      expect(captured, 'br-2');
    });
  });
}
