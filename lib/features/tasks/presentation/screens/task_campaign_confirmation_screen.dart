import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/indonesian_date_formatter.dart';
import '../../../../core/widgets/tinted_info_box.dart';
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
      formattedDeadline: _formatDeadline(_campaign.deadline),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Konfirmasi Aktivasi Tugas')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${widget.profile.role.label} · RT ${_campaign.rtId}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Periksa sebelum mengaktifkan',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _campaign.templateSnapshot.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          LockedTaskInstructionsCard(snapshot: _campaign.templateSnapshot),
          const SizedBox(height: 16),

          // Clean Summary Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _SummaryRow(
                    icon: Icons.home_work_outlined,
                    label: 'RT tujuan',
                    value: 'RT ${_campaign.rtId}',
                  ),
                  const Divider(height: 16),
                  _SummaryRow(
                    icon: Icons.schedule_outlined,
                    label: 'Batas waktu',
                    value: _formatDeadline(_campaign.deadline),
                  ),
                  if (_campaign.locationReference != null) ...[
                    const Divider(height: 16),
                    _SummaryRow(
                      icon: Icons.place_outlined,
                      label: 'Jenis lokasi umum',
                      value: TaskLocationReferences.label(
                        _campaign.locationReference!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Educational Warning Box (replacing dark green block)
          TintedInfoBox.warning(
            text:
                'Notifikasi push bergantung pada konfigurasi server dan izin '
                'perangkat; pemberitahuan dapat terlambat atau gagal. Tugas tetap '
                'tersedia di aplikasi. Salin teks untuk distribusi manual bila perlu.',
          ),
          const SizedBox(height: 16),

          if (_isActive)
            Card(
              key: const Key('task-campaign-active'),
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tugas aktif untuk RT ini.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              key: const Key('task-campaign-draft'),
              color: colorScheme.surfaceContainerLow,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.edit_note, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Draf belum aktif dan belum dibagikan.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_isActive) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                key: const Key('task-copy-whatsapp'),
                onPressed: _copyTaskSummary,
                icon: const Icon(Icons.copy),
                label: const Text('Salin teks untuk WhatsApp'),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const Key('task-confirm-activation'),
              onPressed: _activating
                  ? null
                  : _isActive
                  ? () => Navigator.of(context).pop()
                  : _activate,
              icon: _activating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
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
          ),
        ],
      ),
    );
  }
}

final class _ClipboardTaskCampaignCopyBoundary
    implements TaskCampaignCopyBoundary {
  const _ClipboardTaskCampaignCopyBoundary();

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

final class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
        ],
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatDeadline(DateTime value) =>
    IndonesianDateFormatter.formatFull(value);
