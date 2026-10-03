import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../domain/models/task_campaign.dart';
import '../../../../domain/models/task_template.dart';
import '../../../../domain/repositories/task_repository.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/primary_button.dart';

/// SCR-10. Titik "human approval before distribution" (INV-01) —
/// tombol "Kirim Ke Warga" WAJIB merupakan keputusan sadar operator RT.
/// Tidak ada jalur otomatis yang boleh mentransisikan DRAFT -> ACTIVE.
///
/// Menyediakan tombol salin teks ringkasan untuk grup WhatsApp RT (FR-TSK-005, O-06).
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
        const SnackBar(
          content: Text('Tugas berhasil diaktifkan dan dikirim ke warga RT.'),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _buildWhatsAppText() {
    final t = widget.template;
    final d = widget.draft;
    final deadline = _formatDate(d.deadline);
    final lokasi = d.locationNote != null && d.locationNote!.trim().isNotEmpty
        ? '\n📍 *Lokasi:* ${d.locationNote}'
        : '';
    final catatan = d.additionalNote != null && d.additionalNote!.trim().isNotEmpty
        ? '\n📝 *Catatan:* ${d.additionalNote}'
        : '';

    return '*[Guyub.id — Kesiapsiagaan Banjir]*\n'
        '📋 *${t.title}*\n\n'
        '${d.instructionSnapshot.coreInstruction}\n\n'
        '⚠️ *Instruksi Keselamatan (Wajib Dipatuhi):*\n'
        '${d.instructionSnapshot.safetyInstruction}\n\n'
        '⏰ *Batas Waktu:* $deadline'
        '$lokasi'
        '$catatan\n\n'
        '_Buka aplikasi Guyub.id untuk melihat detail tugas dan konfirmasi partisipasi warga._';
  }

  void _copyWhatsAppText() {
    final text = _buildWhatsAppText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Teks ringkasan tugas disalin! Siap ditempel di grup WhatsApp warga.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Konfirmasi Pengiriman'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
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
                    const Row(
                      children: [
                        Icon(Icons.send_rounded, color: Colors.white70, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'TUGAS AKAN DIKIRIMKAN KE WARGA',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
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

              // Detail Parameter Slot
              AppCard(
                child: Column(
                  children: [
                    _InfoRow(label: 'Kategori', value: widget.template.category),
                    const Divider(height: 12),
                    _InfoRow(label: 'Batas Waktu', value: _formatDate(draft.deadline)),
                    if (draft.locationNote != null && draft.locationNote!.trim().isNotEmpty) ...[
                      const Divider(height: 12),
                      _InfoRow(label: 'Lokasi', value: draft.locationNote!),
                    ],
                    if (draft.additionalNote != null && draft.additionalNote!.trim().isNotEmpty) ...[
                      const Divider(height: 12),
                      _InfoRow(label: 'Catatan RT', value: draft.additionalNote!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // PRD §19 & §9 SCR-10: Tampilkan Instruksi Keselamatan Terkunci
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningYellowBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 18, color: Colors.brown),
                        SizedBox(width: 8),
                        Text(
                          'Instruksi Keselamatan (Snapshot Terkunci)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.brown,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      draft.instructionSnapshot.safetyInstruction,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.brown,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Recipient Preview
              FutureBuilder<RecipientPreview>(
                future: _previewFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: LinearProgressIndicator()),
                    );
                  }
                  final preview = snapshot.data!;
                  return AppCard(
                    child: Row(
                      children: [
                        Text(
                          'Estimasi Penerima (${preview.totalCount} KK)',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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

              // Notifikasi Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.neutralBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderGray),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.primaryBlue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Warga akan menerima notifikasi tugas ini. Tugas bersifat sukarela dan tidak memaksa.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Status Terkirim & WhatsApp Action
              if (_sent) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.successGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.successGreen),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: AppColors.successGreen, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Terkirim! Status tugas sekarang AKTIF untuk warga RT.',
                          style: TextStyle(
                            color: AppColors.successGreen,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('button_copy_whatsapp'),
                  onPressed: _copyWhatsAppText,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Salin Ringkasan untuk WhatsApp'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.primaryBlue),
                    foregroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Tombol Utama (INV-01)
              PrimaryButton(
                key: const Key('button_send_campaign'),
                label: _sent ? 'Tugas Telah Dikirim' : 'Kirim Ke Warga',
                isLoading: _isSending,
                onPressed: _sent ? null : _send,
              ),
            ],
          ),
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
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
