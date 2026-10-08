import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/tasks/application/task_response_boundary.dart';
import 'package:guyub/features/tasks/data/firebase_task_response_boundary.dart';

void main() {
  test('deadline-exceeded is an explicit transient timeout', () {
    final mapped = FirebaseTaskResponseErrorMapper.map(
      FirebaseFunctionsException(code: 'deadline-exceeded', message: 'timeout'),
    );
    expect(mapped, isA<TransientTaskNetworkUnavailableException>());
  });

  test('permission denial is not treated as an offline fallback', () {
    final mapped = FirebaseTaskResponseErrorMapper.map(
      FirebaseFunctionsException(code: 'permission-denied', message: 'denied'),
    );
    expect(mapped, isA<TaskResponseRejectedException>());
    expect(mapped, isNot(isA<TransientTaskNetworkUnavailableException>()));
  });

  test('unknown callable failures remain unclassified', () {
    expect(
      FirebaseTaskResponseErrorMapper.map(
        FirebaseFunctionsException(code: 'internal', message: 'internal'),
      ),
      isNull,
    );
  });
}
