import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/network/callable_client.dart';
import 'package:guyub/core/network/http_callable_client.dart';

void main() {
  Uri? seenUrl;
  Map<String, String>? seenHeaders;
  String? seenBody;

  HttpCallableClient clientReturning(String body, {int status = 200}) =>
      HttpCallableClient(
        baseUri: Uri.parse('http://127.0.0.1:8787/'),
        readIdToken: () async => null,
        post: (url, headers, payload) async {
          seenUrl = url;
          seenHeaders = headers;
          seenBody = payload;
          return CallableHttpResponse(status, body);
        },
      );

  setUp(() {
    seenUrl = null;
    seenHeaders = null;
    seenBody = null;
  });

  test('posts the callable name and unwraps the data envelope', () async {
    final client = clientReturning(
      jsonEncode({
        'data': {'revoked': true},
      }),
    );

    final result = await client.call('revokeResidentSession', const {
      'sessionToken': 'abc',
    });

    expect(
      seenUrl.toString(),
      'http://127.0.0.1:8787/call/revokeResidentSession',
    );
    expect(seenHeaders?['content-type'], 'application/json');
    expect(jsonDecode(seenBody!), {
      'data': {'sessionToken': 'abc'},
    });
    expect(result, {'revoked': true});
  });

  test('sends the ID token as a bearer header when signed in', () async {
    final client = HttpCallableClient(
      baseUri: Uri.parse('http://127.0.0.1:8787/'),
      readIdToken: () async => 'operator-token',
      post: (url, headers, payload) async {
        seenHeaders = headers;
        return CallableHttpResponse(200, jsonEncode({'data': {}}));
      },
    );

    await client.call('listActiveTaskCampaigns', const {});

    expect(seenHeaders?['authorization'], 'Bearer operator-token');
  });

  test('omits the header entirely for a resident call', () async {
    final client = clientReturning(jsonEncode({'data': {}}));

    await client.call('getEmergencyDirectory', const {'sessionToken': 'abc'});

    expect(seenHeaders?.containsKey('authorization'), isFalse);
  });

  test('preserves the gRPC code name the boundaries match on', () async {
    final client = clientReturning(
      jsonEncode({
        'error': {'code': 'failed-precondition', 'message': 'already recorded'},
      }),
      status: 400,
    );

    await expectLater(
      () => client.call('submitTaskCompletion', const {}),
      throwsA(
        isA<CallableException>()
            .having((e) => e.code, 'code', 'failed-precondition')
            .having((e) => e.message, 'message', 'already recorded'),
      ),
    );
  });

  test(
    'permission-denied stays permission-denied across the transport',
    () async {
      final client = clientReturning(
        jsonEncode({
          'error': {
            'code': 'permission-denied',
            'message': 'Akses operator tidak valid.',
          },
        }),
        status: 403,
      );

      await expectLater(
        () => client.call('verifyTaskCompletion', const {}),
        throwsA(
          isA<CallableException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
    },
  );

  test('a dead network becomes unavailable, the offline code', () async {
    final client = HttpCallableClient(
      baseUri: Uri.parse('http://127.0.0.1:8787/'),
      readIdToken: () async => null,
      post: (url, headers, payload) async =>
          throw const SocketException('network down'),
    );

    await expectLater(
      () => client.call('listResidentActiveTasks', const {}),
      throwsA(
        isA<CallableException>().having((e) => e.code, 'code', 'unavailable'),
      ),
    );
  });

  test('a non-JSON body never leaks a raw parse error', () async {
    final client = clientReturning('<html>502 Bad Gateway</html>', status: 502);

    await expectLater(
      () => client.call('listResidentActiveTasks', const {}),
      throwsA(
        isA<CallableException>().having((e) => e.code, 'code', 'internal'),
      ),
    );
  });
}
