// Spec: specs/047-offline-sync-contract/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/database/sync/pending_product_push.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add registra y all() lo devuelve', () async {
    await PendingProductPush.add('p-1');
    await PendingProductPush.add('p-2');
    expect(await PendingProductPush.all(), {'p-1', 'p-2'});
  });

  test('add es idempotente (sin duplicados)', () async {
    await PendingProductPush.add('p-1');
    await PendingProductPush.add('p-1');
    expect((await PendingProductPush.all()).length, 1);
  });

  test('uuid vacío se ignora', () async {
    await PendingProductPush.add('');
    expect(await PendingProductPush.all(), isEmpty);
  });

  test('remove lo quita (ya se subió)', () async {
    await PendingProductPush.add('p-1');
    await PendingProductPush.add('p-2');
    await PendingProductPush.remove('p-1');
    expect(await PendingProductPush.all(), {'p-2'});
  });

  test('all() vacío por defecto', () async {
    expect(await PendingProductPush.all(), isEmpty);
  });
}
