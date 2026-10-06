import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/proposals/application/resident_proposal_boundary.dart';
import 'package:guyub/features/proposals/data/flutter_secure_resident_proposal_request_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'secure store persists only opaque ID and payload fingerprint',
    () async {
      final scopeHash = 'a' * 64;
      final request = PendingResidentProposalRequest(
        requestId: 'r' * 40,
        payloadFingerprint: 'b' * 64,
      );
      const storage = FlutterSecureStorage();
      final store = FlutterSecureResidentProposalRequestStore(storage: storage);

      await store.write(scopeHash: scopeHash, request: request);
      final raw = await storage.read(
        key: 'guyub.pending_resident_proposal.v1.$scopeHash',
      );
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), {'requestId', 'payloadFingerprint'});
      expect(decoded['requestId'], request.requestId);
      expect(decoded['payloadFingerprint'], request.payloadFingerprint);
      final restored = await store.read(scopeHash: scopeHash);
      expect(restored?.requestId, request.requestId);
      expect(restored?.payloadFingerprint, request.payloadFingerprint);
    },
  );

  test('clear only removes a matching request ID', () async {
    final scopeHash = 'c' * 64;
    final request = PendingResidentProposalRequest(
      requestId: 'r' * 40,
      payloadFingerprint: 'd' * 64,
    );
    final store = FlutterSecureResidentProposalRequestStore();
    await store.write(scopeHash: scopeHash, request: request);

    await store.clearIfMatches(scopeHash: scopeHash, requestId: 'n' * 40);
    expect(await store.read(scopeHash: scopeHash), isNotNull);

    await store.clearIfMatches(
      scopeHash: scopeHash,
      requestId: request.requestId,
    );
    expect(await store.read(scopeHash: scopeHash), isNull);
  });

  test('invalid scope and corrupted retry metadata fail closed', () async {
    final store = FlutterSecureResidentProposalRequestStore();
    await expectLater(
      store.read(scopeHash: 'resident-1'),
      throwsFormatException,
    );

    final scopeHash = 'e' * 64;
    FlutterSecureStorage.setMockInitialValues({
      'guyub.pending_resident_proposal.v1.$scopeHash':
          '{"requestId":"not-an-opaque-id"}',
    });
    await expectLater(store.read(scopeHash: scopeHash), throwsFormatException);
  });
}
