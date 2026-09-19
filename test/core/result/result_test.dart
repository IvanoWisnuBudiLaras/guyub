import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/result/app_error.dart';
import 'package:guyub/core/result/result.dart';

void main() {
  group('Result (Success / Failure)', () {
    test('Success menyimpan value data dan flag isOk bernilai true', () {
      const result = Result<int>.ok(100);

      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.dataOrNull, 100);
      expect(result.errorOrNull, isNull);

      final mapped = result.when(ok: (val) => val * 2, err: (_) => 0);
      expect(mapped, 200);
    });

    test('Failure menyimpan AppError dan flag isErr bernilai true', () {
      const error = NetworkError(
        message: 'Server BMKG sedang tidak dapat dihubungi',
      );
      const result = Result<String>.err(error);

      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      expect(result.dataOrNull, isNull);
      expect(result.errorOrNull, error);

      final message = result.when(
        ok: (_) => 'berhasil',
        err: (err) => err.userMessage,
      );
      expect(message, 'Server BMKG sedang tidak dapat dihubungi');
    });
  });

  group('Hierarki AppError (Bahasa Indonesia & Kode)', () {
    test('NetworkError memiliki kode ERR_NETWORK dan pesan ramah pengguna', () {
      const err = NetworkError();
      expect(err.code, 'ERR_NETWORK');
      expect(err.userMessage, contains('internet'));
    });

    test('AuthError memiliki kode ERR_AUTH dan pesan otentikasi', () {
      const err = AuthError();
      expect(err.code, 'ERR_AUTH');
      expect(err.userMessage, contains('Akses tidak diizinkan'));
    });

    test('ValidationError membawa pesan validasi kustom', () {
      const err = ValidationError(
        message: 'Kode RT harus terdiri dari 3 digit',
      );
      expect(err.code, 'ERR_VALIDATION');
      expect(err.userMessage, 'Kode RT harus terdiri dari 3 digit');
    });

    test('DatabaseError memiliki kode ERR_DATABASE', () {
      const err = DatabaseError();
      expect(err.code, 'ERR_DATABASE');
      expect(err.userMessage, contains('penyimpanan'));
    });

    test('SyncError memiliki kode ERR_SYNC', () {
      const err = SyncError();
      expect(err.code, 'ERR_SYNC');
      expect(err.userMessage, contains('Sinkronisasi'));
    });

    test('UnknownError memiliki kode ERR_UNKNOWN', () {
      const err = UnknownError();
      expect(err.code, 'ERR_UNKNOWN');
    });
  });
}
