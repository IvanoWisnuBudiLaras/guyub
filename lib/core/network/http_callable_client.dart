import 'dart:convert';
import 'dart:io';

import 'callable_client.dart';

/// One raw HTTP round trip, so tests can fake the network.
final class CallableHttpResponse {
  const CallableHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

typedef CallableHttpPost = Future<CallableHttpResponse> Function(
  Uri url,
  Map<String, String> headers,
  String body,
);

/// Plain-HTTP transport for the standalone adapter in `functions/server`.
///
/// The adapter answers `{"data": …}` or `{"error": {"code", "message"}}` with
/// the gRPC code name preserved, so boundary classes keep matching the same
/// strings. A transport-level failure maps to `unavailable`, the code the
/// offline paths already handle.
final class HttpCallableClient implements CallableClient {
  HttpCallableClient({
    required this.baseUri,
    this.readIdToken,
    CallableHttpPost? post,
  }) : _post = post ?? _postWithHttpClient;

  final Uri baseUri;

  /// Supplies the Firebase ID token for operator calls. Null when no operator
  /// is signed in; resident calls carry their session token in `data` instead.
  final Future<String?> Function()? readIdToken;

  final CallableHttpPost _post;

  @override
  Future<Object?> call(String name, Map<String, Object?> data) async {
    final headers = <String, String>{'content-type': 'application/json'};
    final token = await readIdToken?.call();
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }

    final CallableHttpResponse response;
    try {
      response = await _post(
        baseUri.resolve('call/$name'),
        headers,
        jsonEncode({'data': data}),
      );
    } catch (_) {
      // Offline, DNS failure, or a dropped connection: the same condition the
      // SDK reports as `unavailable`.
      throw const CallableException(
        'unavailable',
        'Tidak dapat menghubungi server.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const CallableException('internal', 'Balasan backend tidak valid.');
    }
    if (decoded is! Map) {
      throw const CallableException('internal', 'Balasan backend tidak valid.');
    }

    final error = decoded['error'];
    if (error is Map) {
      throw CallableException(
        error['code']?.toString() ?? 'internal',
        error['message']?.toString() ?? '',
      );
    }
    return decoded['data'];
  }
}

Future<CallableHttpResponse> _postWithHttpClient(
  Uri url,
  Map<String, String> headers,
  String body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    headers.forEach(request.headers.set);
    request.write(body);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return CallableHttpResponse(response.statusCode, text);
  } finally {
    client.close();
  }
}
