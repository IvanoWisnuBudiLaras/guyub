import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/task_campaign.dart';
import '../../domain/models/task_template.dart';
import '../../domain/repositories/task_repository.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/primary_button.dart';

/// SCR-10. Ini titik "human approval before distribution" (INV-01) —
/// tombol "Kirim Ke Warga" WAJIB terasa sebagai keputusan sadar, bukan
/// tombol biasa. Tidak ada jalur lain yang boleh transisi DRAFT -> ACTIVE.
class SendConfirmationScreen extends StatefulWidget {
  const SendConfirmationScreen({
    super.key,
    required this.draft,
    required this.template,
    required this.taskRepository,
  });

  final TaskCampaign draft;
  final TaskTemplate template;
  final TaskRepository taskRepository;

  @override
  State<SendConfirmationScreen> createState() => _SendConfirmationScreenState();
}

class _SendConfirmationScreenState extends State<SendConfirmationScreen> {
  late Future<RecipientPreview> _previewFuture;
  bool _isSending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _previewFuture = widget.taskRepository.getRecipientPreview();
  }

  Future<void> _send() async {
    setState(() => _isSending = true);
    try {
      await widget.taskRepository.activateCampaign(widget.draft);
      if (!mounted) return;
      setState(() => _sent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tugas berhasil dikirim ke warga.')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Scaffold(
      appBar: AppBar(title: const Text('Konfirmasi Pengiriman')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              filled: true,
              fillColor: AppColors.deepBlueBanner,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TUGAS AKAN DIKIRIM',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.template.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'Batas Waktu', value: _formatDate(draft.deadline)),
            if (draft.locationNote != null)
              _InfoRow(label: 'Lokasi', value: draft.locationNote!),
            const SizedBox(height: 16),
            FutureBuilder<RecipientPreview>(
              future: _previewFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                final preview = snapshot.data!;
                return AppCard(
                  child: Row(
                    children: [
                      Text(
                        'Penerima (${preview.totalCount})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final name in preview.sampleNames)
                            Chip(
                              label: Text(name, style: const TextStyle(fontSize: 11)),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (preview.totalCount > preview.sampleNames.length)
                            Chip(
                              label: Text(
                                '+${preview.totalCount - preview.sampleNames.length} lainnya',
                                style: const TextStyle(fontSize: 11),
                              ),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningYellowBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notifications_active_outlined, size: 18, color: Colors.brown),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Warga akan menerima notifikasi push setelah Anda mengirim tugas ini.',
                      style: TextStyle(fontSize: 12, color: Colors.brown),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (_sent)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Terkirim — status tugas sekarang AKTIF.',
                  style: TextStyle(color: AppColors.successGreen, fontWeight: FontWeight.w600),
                ),
              ),
            PrimaryButton(
              label: _sent ? 'Terkirim' : 'Kirim Ke Warga',
              isLoading: _isSending,
              onPressed: _sent ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
