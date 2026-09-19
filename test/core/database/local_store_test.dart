import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/database/in_memory_local_store.dart';
import 'package:guyub/core/database/local_store.dart';

void main() {
  group('Local Persistence Smoke Test (LocalStore)', () {
    late LocalStore store;

    setUp(() {
      // 1. Initialize
      store = InMemoryLocalStore();
    });

    tearDown(() async {
      // 5. Close / Cleanup
      await store.close();
    });

    test(
      'siklus lengkap: initialize -> write -> read -> verify -> cleanup/close',
      () async {
        // 2. Write test value
        const testKey = 'persiapan_banjir_rt05';
        const testPayload =
            '{"status":"active","task":"Pembersihan Selokan Utama"}';
        await store.write(testKey, testPayload);

        // 3. Read
        final retrieved = await store.read(testKey);

        // 4. Verify
        expect(retrieved, isNotNull);
        expect(retrieved, testPayload);
        expect(await store.containsKey(testKey), isTrue);

        // Hapus kunci spesifik
        await store.delete(testKey);
        expect(await store.read(testKey), isNull);
        expect(await store.containsKey(testKey), isFalse);
      },
    );

    test('clear menghapus seluruh entri yang ada di penyimpanan', () async {
      await store.write('kunci_1', 'nilai_1');
      await store.write('kunci_2', 'nilai_2');

      await store.clear();

      expect(await store.read('kunci_1'), isNull);
      expect(await store.read('kunci_2'), isNull);
    });

    test('membaca kunci yang tidak ada mengembalikan null tanpa melempar exception', () async {
      final value = await store.read('kunci_fiktif');
      expect(value, isNull);
    });

    test('melempar StateError jika store telah ditutup (closed)', () async {
      await store.close();
      expect(() => store.read('kunci_apapun'), throwsStateError);
      expect(() => store.write('kunci_apapun', 'nilai'), throwsStateError);
    });
  });
}
