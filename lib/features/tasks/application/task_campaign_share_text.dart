import 'task_campaign_boundary.dart';
import 'task_location_reference.dart';

/// Formats a human-readable task summary for manual WhatsApp sharing.
///
/// Only active campaigns may be copied. This function never dispatches a task
/// or sends a message.
String buildTaskCampaignWhatsAppText({
  required TaskCampaignRecord campaign,
  required String formattedDeadline,
}) {
  if (campaign.status != 'ACTIVE') {
    throw StateError('Only an active task can be shared.');
  }

  return [
    'TUGAS KESIAPSIAGAAN WARGA',
    '',
    campaign.templateSnapshot.title,
    '',
    campaign.templateSnapshot.coreInstruction,
    '',
    'Keselamatan: ${campaign.templateSnapshot.safetyInstruction}',
    if (campaign.locationReference != null)
      'Jenis lokasi umum: ${TaskLocationReferences.label(campaign.locationReference!)}',
    'Batas waktu: $formattedDeadline',
    '',
    'Keikutsertaan bersifat sukarela. Warga dapat memilih ikut atau tidak ikut.',
    'Ini adalah tugas kesiapsiagaan, bukan peringatan resmi.',
  ].join('\n');
}
