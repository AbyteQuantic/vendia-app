import 'package:flutter_test/flutter_test.dart';

/// Documents the canDelete gate logic: open status + orderId + itemId.
void main() {
  group('Tab review — delete button visibility', () {
    bool canDelete({
      required String status,
      required String? orderId,
      required String serverItemId,
    }) {
      final isOpen = status == 'nuevo' ||
          status == 'preparando' ||
          status == 'listo' ||
          status.isEmpty;
      return isOpen && orderId != null && serverItemId.isNotEmpty;
    }

    test('open status + orderId + itemId → visible', () {
      expect(
          canDelete(status: 'nuevo', orderId: 'ord-1', serverItemId: 'it-1'),
          isTrue);
    });
    test('completed status → hidden', () {
      expect(
          canDelete(status: 'completed', orderId: 'ord-1', serverItemId: 'it-1'),
          isFalse);
    });
    test('paid status → hidden', () {
      expect(
          canDelete(status: 'paid', orderId: 'ord-1', serverItemId: 'it-1'),
          isFalse);
    });
    test('missing itemId (server data not yet loaded) → hidden', () {
      expect(
          canDelete(status: 'nuevo', orderId: 'ord-1', serverItemId: ''),
          isFalse);
    });
    test('missing orderId → hidden', () {
      expect(
          canDelete(status: 'nuevo', orderId: null, serverItemId: 'it-1'),
          isFalse);
    });
  });
}
