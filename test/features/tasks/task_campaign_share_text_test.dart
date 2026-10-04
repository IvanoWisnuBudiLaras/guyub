import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_campaign_share_text.dart';
import 'package:guyub/features/tasks/application/task_template.dart';

void main() {
  final template = TaskTemplate(
    id: 'household_ready',
    version: 2,
    title: 'Persiapan rumah tangga',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen penting dalam wadah yang mudah dijangkau.',
    safetyInstruction:
        'Jangan mendekati air banjir atau instalasi listrik basah.',
    enabled: true,
  );

  TaskCampaignRecord campaign({String status = 'ACTIVE'}) => TaskCampaignRecord(
    campaignId: 'a' * 40,
    rtId: 'internal-rt-id',
    templateSnapshot: template.snapshot(),
    deadline: DateTime.utc(2026, 10, 5, 10),
    status: status,
    createdAt: DateTime.utc(2026, 10, 4),
    locationReference: 'HOUSEHOLD',
  );

  test('summary contains the reviewed task and transparent voluntary copy', () {
    final text = buildTaskCampaignWhatsAppText(
      campaign: campaign(),
      formattedDeadline: '5 Oktober 2026 · 17.00',
    );

    expect(text, contains('TUGAS KESIAPSIAGAAN WARGA'));
    expect(text, contains(template.title));
    expect(text, contains(template.coreInstruction));
    expect(text, contains(template.safetyInstruction));
    expect(text, contains('Rumah masing-masing'));
    expect(text, contains('5 Oktober 2026 · 17.00'));
    expect(text, contains('Keikutsertaan bersifat sukarela'));
    expect(text, contains('bukan peringatan resmi'));
    expect(text, isNot(contains('internal-rt-id')));
    expect(text, isNot(contains(campaign().campaignId)));
  });

  test('draft campaign cannot be copied before explicit activation', () {
    expect(
      () => buildTaskCampaignWhatsAppText(
        campaign: campaign(status: 'DRAFT'),
        formattedDeadline: '5 Oktober 2026 · 17.00',
      ),
      throwsStateError,
    );
  });
}
