import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/assistance/application/assistance_volunteer_boundary.dart';
import 'package:guyub/features/assistance/presentation/assistance_volunteer_screen.dart';
import 'package:guyub/features/auth/application/resident_session.dart';

final _assignmentId = List.filled(40, 'c').join();

final class _VolunteerBoundary implements AssistanceVolunteerBoundary {
  bool willingToHelp = false;
  String? lastDecision;
  String? lastToken;
  List<HelperAssignmentRecord> assignments = const [];

  @override
  Future<ResidentVolunteerData> getVolunteerData({
    required String sessionToken,
  }) async {
    lastToken = sessionToken;
    return ResidentVolunteerData(
      willingToHelp: willingToHelp,
      assignments: assignments,
      isPartial: false,
    );
  }

  @override
  Future<bool> updateVolunteerConsent({
    required String sessionToken,
    required bool willingToHelp,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async {
    lastToken = sessionToken;
    this.willingToHelp = willingToHelp;
    return willingToHelp;
  }

  @override
  Future<HelperAssignmentResult> respondToHelperAssignment({
    required String sessionToken,
    required String assignmentId,
    required String decision,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async {
    lastToken = sessionToken;
    lastDecision = decision;
    assignments = decision == 'ACCEPTED'
        ? [
            HelperAssignmentRecord(
              assignmentId: assignmentId,
              state: 'ACCEPTED',
              createdAt: DateTime.utc(2026, 10, 6),
            ),
          ]
        : const [];
    return HelperAssignmentResult(assignmentId: assignmentId, state: decision);
  }
}

ResidentSession _session() => ResidentSession(
  residentId: List.filled(40, 'a').join(),
  communityId: 'rt-a',
  communityName: 'RT A',
  rtLabel: 'RT A',
  nickname: 'Relawan',
  expiresAt: DateTime.utc(2026, 10, 7),
);

void main() {
  test('resident volunteer parser rejects any household identity field', () {
    expect(
      () => ResidentVolunteerData.fromWire({
        'willingToHelp': false,
        'assignments': [
          {
            'assignmentId': _assignmentId,
            'state': 'OFFERED',
            'createdAt': '2026-10-06T00:00:00.000Z',
            'residentNeedingHelpId': List.filled(40, 'd').join(),
          },
        ],
        'isPartial': false,
      }),
      throwsFormatException,
    );
  });

  testWidgets('resident opt-in waits for an explicit voluntary confirmation', (
    tester,
  ) async {
    final boundary = _VolunteerBoundary();
    final controller = AssistanceVolunteerController(
      boundary: boundary,
      readSessionToken: () async => 'private-resident-session-token',
      idFactory: () => 'command-id-123456789012345678901234567890',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AssistanceVolunteerScreen(
          session: _session(),
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('helper-willingness-toggle')));
    await tester.pumpAndSettle();
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('helper-consent-save')),
    );
    expect(save.onPressed, isNull);
    await tester.tap(find.byKey(const Key('helper-consent-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('helper-consent-save')));
    await tester.pumpAndSettle();
    expect(boundary.willingToHelp, isTrue);
    expect(boundary.lastToken, 'private-resident-session-token');
  });

  testWidgets('helper may decline without seeing household identity', (
    tester,
  ) async {
    final boundary = _VolunteerBoundary()
      ..assignments = [
        HelperAssignmentRecord(
          assignmentId: _assignmentId,
          state: 'OFFERED',
          createdAt: DateTime.utc(2026, 10, 6),
        ),
      ];
    final controller = AssistanceVolunteerController(
      boundary: boundary,
      readSessionToken: () async => 'private-resident-session-token',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AssistanceVolunteerScreen(
          session: _session(),
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Detail rumah tangga tidak ditampilkan.'),
      findsOneWidget,
    );
    expect(find.text('Nenek Sari'), findsNothing);
    await tester.tap(find.byKey(Key('helper-decline-$_assignmentId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('helper-decision-confirm-DECLINED')));
    await tester.pumpAndSettle();
    expect(boundary.lastDecision, 'DECLINED');
  });
}
