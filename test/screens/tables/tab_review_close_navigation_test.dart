import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTab {
  final String status;
  _FakeTab(this.status);
}

void main() {
  testWidgets(
    'auto-close logic shows snackbar on completed status',
    (tester) async {
      final controller = StreamController<_FakeTab?>();

      // Build a simple widget tree with the core auto-close logic
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StreamBuilder<_FakeTab?>(
            stream: controller.stream,
            builder: (ctx, snap) {
              final tab = snap.data;
              final closed = tab != null &&
                  (tab.status == 'completed' || tab.status == 'paid');

              if (closed) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('¡Cuenta Pagada y Cerrada!'),
                    ),
                  );
                });
              }

              return Center(
                child: Text(tab?.status ?? 'waiting'),
              );
            },
          ),
        ),
      ));

      // Initial state
      expect(find.text('waiting'), findsOneWidget);

      // Emit completed status
      controller.add(_FakeTab('completed'));
      await tester.pumpAndSettle();

      // Verify snackbar appears
      expect(find.text('¡Cuenta Pagada y Cerrada!'), findsOneWidget);
      expect(find.text('completed'), findsOneWidget);

      await controller.close();
    },
  );
}
