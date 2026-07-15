// Spec: specs/105-hito-restaurante-comandas/spec.md — F4 (QR en recibo ESC/POS, Spec 046).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/receipt_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('el tiquete localizador lleva turno gigante + QR y termina en corte',
      () async {
    final bytes = await LocatorSlipBuilder(
      orderLabel: 'Pedido 7',
      trackingUrl: 'https://tienda.vendia.store/t/tok-123',
    ).build();

    expect(bytes, isNotEmpty);
    final raw = latin1.decode(bytes, allowInvalid: true);
    expect(raw, contains('SU TURNO'));
    expect(raw, contains('Pedido 7'));
    // El payload del QR viaja dentro del comando GS ( k.
    expect(raw, contains('tienda.vendia.store/t/tok-123'));
  });

  test('sin URL (offline) imprime solo el turno — nunca un QR roto', () async {
    final bytes = await LocatorSlipBuilder(
      orderLabel: 'Pedido 9',
      trackingUrl: '',
    ).build();
    final raw = latin1.decode(bytes, allowInvalid: true);
    expect(raw, contains('Pedido 9'));
    expect(raw, isNot(contains('Escanee')));
  });
}
