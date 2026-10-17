import 'package:flutter/material.dart';

import '../../auth/application/resident_session.dart';
import '../../tasks/application/task_location_reference.dart';
import '../application/resident_proposal_boundary.dart';
import '../../../../core/widgets/tinted_info_box.dart';

/// Resident proposal form. Submitted text remains a proposal and is never a task.
final class ResidentProposalScreen extends StatefulWidget {
  const ResidentProposalScreen({
    required this.session,
    required this.controller,
    super.key,
  });

  final ResidentSession session;
  final ResidentProposalController controller;

  @override
  State<ResidentProposalScreen> createState() => _ResidentProposalScreenState();
}

final class _ResidentProposalScreenState extends State<ResidentProposalScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  ResidentProposalCategory _category =
      ResidentProposalCategory.householdPreparation;
  String? _locationReference;
  ResidentProposalRecord? _submitted;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if (title.isEmpty || description.isEmpty) {
      setState(() => _error = 'Isi judul dan penjelasan usulan.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = await widget.controller.submit(
        residentId: widget.session.residentId,
        communityId: widget.session.communityId,
        title: title,
        description: description,
        category: _category,
        locationReference: _locationReference,
      );
      if (mounted) setState(() => _submitted = record);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Usulan belum dapat dikirim. Periksa koneksi, lalu coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Usulkan Persiapan Warga')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Warga • ${widget.session.rtLabel}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 12),
        const TintedInfoBox(
          tint: TintType.info,
          icon: Icons.info_outline,
          child: Text(
            'Usulan tidak otomatis menjadi tugas aktif. RT dapat memilih template aman untuk membuat draf; '
            'teks usulan bukan instruksi, dan aktivasi tetap memerlukan konfirmasi operator.',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('proposal-title'),
          controller: _titleController,
          enabled: !_saving && _submitted == null,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Judul usulan',
            hintText: 'Judul usulan',
            border: OutlineInputBorder(),
          ),
        ),
        TextField(
          key: const Key('proposal-description'),
          controller: _descriptionController,
          enabled: !_saving && _submitted == null,
          maxLength: 1000,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Penjelasan singkat',
            hintText: 'Penjelasan singkat',
            helperText: 'Jangan masukkan NIK, nomor telepon, alamat, atau koordinat GPS.',
            helperMaxLines: 4,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ResidentProposalCategory>(
          key: const Key('proposal-category'),
          isExpanded: true,
          initialValue: _category,
          decoration: const InputDecoration(
            labelText: 'Kategori usulan',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final category in ResidentProposalCategory.values)
              DropdownMenuItem(value: category, child: Text(category.label)),
          ],
          onChanged: _saving || _submitted != null
              ? null
              : (category) {
                  if (category != null) setState(() => _category = category);
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('proposal-location'),
          isExpanded: true,
          initialValue: _locationReference,
          decoration: const InputDecoration(
            labelText: 'Jenis lokasi umum (opsional)',
            helperText: 'Pilih kategori, bukan alamat atau titik GPS.',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final location in TaskLocationReferences.allowed)
              DropdownMenuItem(
                value: location,
                child: Text(TaskLocationReferences.label(location)),
              ),
          ],
          onChanged: _saving || _submitted != null
              ? null
              : (location) => setState(() => _locationReference = location),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          TintedInfoBox.danger(text: _error!),
        ],
        if (_submitted case final submitted?) ...[
          const SizedBox(height: 16),
          TintedInfoBox(
            key: const Key('proposal-submitted'),
            tint: submitted.state == 'SUBMITTED'
                ? TintType.warning
                : TintType.info,
            icon: submitted.state == 'SUBMITTED'
                ? Icons.schedule_outlined
                : Icons.visibility_outlined,
            title: submitted.state == 'SUBMITTED'
                ? 'Menunggu Tinjauan RT'
                : 'Usulan telah ditinjau RT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Usulan ini belum menjadi tugas. Tidak ada tugas yang diaktifkan atau dikirim.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Usulan: ${submitted.title}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('proposal-submit'),
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: const Text('Kirim usulan ke RT'),
          ),
        ],
      ],
    ),
  );
}
