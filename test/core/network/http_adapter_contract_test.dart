@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/network/callable_client.dart';
import 'package:guyub/core/network/http_callable_client.dart';

/// Contract test: the Dart HTTP client against the real Node adapter in
/// `functions/server/http_adapter.js`. Nothing is faked on either side.
///
/// Needs the emulator suite and the adapter running; see
/// `tool/test_callable_adapters.sh`. Skipped when `GUYUB_ADAPTER_URL` is unset so
/// `flutter test` stays self-contained.
void main() {
  final base = Platform.environment['GUYUB_ADAPTER_URL'];

  test(
    'health reports the same callable count the registry declares',
    () async {
      if (base == null) {
        markTestSkipped('GUYUB_ADAPTER_URL not set');
        return;
      }
      final client = HttpCallableClient(baseUri: Uri.parse('$base/'));

      // An unknown callable must be a clean domain refusal, which proves the
      // adapter is reachable and speaking the same protocol the client expects.
      await expectLater(
        () => client.call('thisCallableDoesNotExist', const {}),
        throwsA(
          isA<CallableException>().having((e) => e.code, 'code', 'not-found'),
        ),
      );
    },
  );

  test('a resident enrollment round trip works over plain HTTP', () async {
    if (base == null) {
      markTestSkipped('GUYUB_ADAPTER_URL not set');
      return;
    }
    final client = HttpCallableClient(baseUri: Uri.parse('$base/'));

    // The join code is seeded by the Node test helper before this runs.
    final result = await client.call('createResidentSession', {
      'joinCode': 'KODEFLOW1234',
      'nickname': 'Sari',
      'requestId': 'dart-client-request-id-000000000000',
    });

    final data = result! as Map;
    expect(data['sessionToken'], isA<String>());
    expect((data['sessionToken']! as String).length, greaterThanOrEqualTo(32));
    expect(data['communityId'], 'rt-flow');
  });

  test('an invalid join code is refused with the generic message', () async {
    if (base == null) {
      markTestSkipped('GUYUB_ADAPTER_URL not set');
      return;
    }
    final client = HttpCallableClient(baseUri: Uri.parse('$base/'));

    await expectLater(
      () => client.call('createResidentSession', {
        'joinCode': 'NOSUCHCODE123',
        'nickname': 'Sari',
        'requestId': 'dart-client-request-id-111111111111',
      }),
      throwsA(
        isA<CallableException>()
            .having((e) => e.code, 'code', 'permission-denied')
            .having(
              (e) => e.message,
              'message',
              'Kode RT tidak valid atau tidak aktif.',
            ),
      ),
    );
  });
}
