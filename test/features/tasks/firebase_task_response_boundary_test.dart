import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/network/callable_client.dart';
import 'package:guyub/features/tasks/application/task_response_boundary.dart';
import 'package:guyub/features/tasks/data/firebase_task_response_boundary.dart';

void main() {
  test('deadline-exceeded is an explicit transient timeout', () {
    final mapped = FirebaseTaskResponseErrorMapper.map(
      const CallableException('deadline-exceeded', 'timeout'),
    );
    expect(mapped, isA<TransientTaskNetworkUnavailableException>());
  });

  test('failed-precondition remains a conflict with its original code', () {
    final mapped = FirebaseTaskResponseErrorMapper.map(
      const CallableException(
        'failed-precondition',
        'response already recorded',
      ),
    );
    expect(mapped, isA<TaskResponseConflictException>());
    expect(
      (mapped! as TaskResponseConflictException).code,
      'failed-precondition',
    );
  });

  test('permission denial is not treated as an offline fallback', () {
    final mapped = FirebaseTaskResponseErrorMapper.map(
      const CallableException('permission-denied', 'denied'),
    );
    expect(mapped, isA<TaskResponseRejectedException>());
    expect(mapped, isNot(isA<TransientTaskNetworkUnavailableException>()));
  });

  test('unknown callable failures remain unclassified', () {
    expect(
      FirebaseTaskResponseErrorMapper.map(
        const CallableException('internal', 'internal'),
      ),
      isNull,
    );
  });
}
