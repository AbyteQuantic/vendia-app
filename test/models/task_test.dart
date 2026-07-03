// Spec: specs/078-centro-tareas-unificado/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/task.dart';

Task _t(String kind, {String urgency = 'normal'}) => Task(
      id: '$kind:t1',
      kind: kind,
      sourceId: 't1',
      title: 't',
      subtitle: '',
      urgency: urgency,
      actionLabel: '',
      deepLink: '',
    );

void main() {
  test('reorder_out es posponible como reorder/perishable (agregada)', () {
    expect(_t('reorder_out', urgency: 'high').isDismissable, isTrue);
    expect(_t('reorder').isDismissable, isTrue);
    expect(_t('perishable').isDismissable, isTrue);
  });

  test('tareas con entidad propia NO son posponibles', () {
    expect(_t('online_order', urgency: 'critical').isDismissable, isFalse);
    expect(_t('table_account', urgency: 'critical').isDismissable, isFalse);
  });

  test('reorder_out (high) es urgente y gana el toast', () {
    expect(_t('reorder_out', urgency: 'high').isUrgent, isTrue);
  });
}
