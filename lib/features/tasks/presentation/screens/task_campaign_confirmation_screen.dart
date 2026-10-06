import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../auth/application/operator_profile.dart';
import '../../application/task_campaign_boundary.dart';
import '../../application/task_campaign_copy_boundary.dart';
import '../../application/task_campaign_share_text.dart';
import '../../application/task_location_reference.dart';
import '../widgets/locked_instructions_card.dart';

/// Requires a deliberate operator action before a draft becomes ACTIVE.
final class TaskCampaignConfirmationScreen extends StatefulWidget {
  const TaskCampaignConfirmationScreen({
    required this.profile,
    required this.campaign,
    required this.controller,
    this.copyBoundary,
    super.key,
  });

  final OperatorProfile profile;
  final TaskCampaignRecord campaign;
  final TaskCampaignController controller;
  final TaskCampaignCopyBoundary? copyBoundary;

  @override
  State<TaskCampaignConfirmationScreen> createState() =>
      _TaskCampaignConfirmationScreenState();
}

final class _TaskCampaignConfirmationScreenState
    extends State<TaskCampaignConfirmationScreen> {
  late TaskCampaignRecord _campaign = widget.campaign;
  bool _activating = false;
  String? _error;

  bool get _isActive => _campaign.status == 'ACTIVE';

  Future<void> _copyTaskSummary() async {
    if (!_isActive) return;
    final text = buildTaskCampaignWhatsAppText(
      campaign: _campaign,
      formattedDeadline: _formatDeadline(context, _campaign.deadline),
    );
    try {
      await (widget.copyBoundary ?? const _ClipboardTaskCampaignCopyBoundary())
          .copy(text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Teks disalin. Periksa kembali sebelum membagikannya ke grup RT.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Teks tidak dapat disalin. Tidak ada pesan yang dikirim.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _activate() async {
    setState(() {
      _activating = true;
      _error = null;
    });
    try {
      final updated = await widget.controller.activateCampaign(
        campaignId: _campaign.campaignId,
      );
      if (mounted) setState(() => _campaign = updated);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Tugas belum dapat diaktifkan. Periksa koneksi dan akses RT, lalu coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Konfirmasi Aktivasi Tugas')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${widget.profile.role.label} · RT ${_campaign.rtId}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Periksa sebelum mengaktifkan',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          _campaign.templateSnapshot.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        LockedTaskInstructionsCard(snapshot: _campaign.templateSnapshot),
        const SizedBox(height: 12),
        _SummaryRow(label: 'RT tujuan', value: 'RT ${_campaign.rtId}'),
        _SummaryRow(
          label: 'Batas waktu',
          value: _formatDeadline(context, _campaign.deadline),
        ),
        if (_campaign.locationReference != null)
          _SummaryRow(
            label: 'Jenis lokasi umum',
            value: TaskLocationReferences.label(_campaign.locationReference!),
          ),
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Notifikasi push bergantung pada konfigurasi server dan izin '
              'perangkat; pemberitahuan dapat terlambat atau gagal. Tugas tetap '
              'tersedia di aplikasi. Salin teks untuk distribusi manual bila perlu.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isActive)
          const ListTile(
            key: Key('task-campaign-active'),
            leading: Icon(Icons.check_circle_outline),
            title: Text('Tugas aktif untuk RT ini.'),
          )
        else
          const ListTile(
            key: Key('task-campaign-draft'),
            leading: Icon(Icons.edit_note),
            title: Text('Draf belum aktif dan belum dibagikan.'),
          ),
        if (_isActive) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('task-copy-whatsapp'),
            onPressed: _copyTaskSummary,
            icon: const Icon(Icons.copy),
            label: const Text('Salin teks untuk WhatsApp'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('task-confirm-activation'),
          onPressed: _activating
              ? null
              : _isActive
              ? () => Navigator.of(context).pop()
              : _activate,
          icon: _activating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_isActive ? Icons.arrow_back : Icons.task_alt),
          label: Text(
            _activating
                ? 'Memproses…'
                : _isActive
                ? 'Kembali ke katalog'
                : 'Konfirmasi dan aktifkan',
          ),
        ),
      ],
    ),
  );
}

final class _ClipboardTaskCampaignCopyBoundary
    implements TaskCampaignCopyBoundary {
  const _ClipboardTaskCampaignCopyBoundary();

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

final class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

String _formatDeadline(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final date = MaterialLocalizations.of(context).formatMediumDate(local);
  final time = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date · $time';
}
