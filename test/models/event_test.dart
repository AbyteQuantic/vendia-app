// Spec: specs/042-modulo-eventos/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/event.dart';

void main() {
  group('Event', () {
    test('fromJson parsea los campos del backend', () {
      final e = Event.fromJson({
        'id': 'e1',
        'type': 'curso',
        'title': 'Curso de repostería',
        'modality': 'virtual',
        'capacity': 30,
        'price': 50000,
        'status': 'publicado',
        'start_at': '2026-07-01T09:00:00Z',
        'installments_enabled': true,
        'installments_count': 3,
      });
      expect(e.id, 'e1');
      expect(e.title, 'Curso de repostería');
      expect(e.modality, 'virtual');
      expect(e.capacity, 30);
      expect(e.price, 50000);
      expect(e.isPublished, isTrue);
      expect(e.isFree, isFalse);
      expect(e.startAt, isNotNull);
      expect(e.installmentsEnabled, isTrue);
      expect(e.installmentsCount, 3);
    });

    test('toJson/fromJson hacen round-trip', () {
      const original = Event(
        id: 'e2',
        type: EventType.hackaton,
        title: 'Hackatón',
        modality: EventModality.presencial,
        capacity: 100,
        price: 0,
        status: EventStatus.borrador,
      );
      final round = Event.fromJson(original.toJson());
      expect(round.id, original.id);
      expect(round.type, original.type);
      expect(round.title, original.title);
      expect(round.capacity, original.capacity);
      expect(round.isFree, isTrue);
    });

    test('isFree es true con precio 0', () {
      expect(const Event(id: 'x', price: 0).isFree, isTrue);
      expect(const Event(id: 'x', price: 50000).isFree, isFalse);
    });

    test('copyWith reemplaza solo lo indicado', () {
      const e = Event(id: 'e3', title: 'Original', price: 10000);
      final c = e.copyWith(title: 'Editado');
      expect(c.title, 'Editado');
      expect(c.price, 10000);
      expect(c.id, 'e3');
    });

    test('fromJson es defensivo ante datos ausentes', () {
      final e = Event.fromJson({});
      expect(e.id, '');
      expect(e.type, EventType.otro);
      expect(e.status, EventStatus.borrador);
      expect(e.startAt, isNull);
    });

    test('labels en español', () {
      expect(EventType.label('hackaton'), 'Hackatón');
      expect(EventModality.label('hibrido'), 'Híbrido');
      expect(EventStatus.label('publicado'), 'Publicado');
    });
  });
}
