import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';

void main() {
  test('only documented operator roles map from the trusted wire value', () {
    expect(
      OperatorRoleLabel.fromWireValue('KETUA_RT_RW'),
      OperatorRole.ketuaRtRw,
    );
    expect(
      OperatorRoleLabel.fromWireValue('PENDAMPING_RT'),
      OperatorRole.pendampingRt,
    );
    expect(OperatorRoleLabel.fromWireValue('RESIDENT'), isNull);
    expect(OperatorRoleLabel.fromWireValue(null), isNull);
  });

  test('operator profile requires an RT-scoped minimal identity', () {
    expect(
      () => OperatorProfile(
        uid: 'operator-1',
        communityId: '',
        role: OperatorRole.ketuaRtRw,
        displayName: 'Ketua',
      ),
      throwsArgumentError,
    );
  });
}
