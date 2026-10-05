import 'package:flutter/material.dart';

import '../../auth/application/resident_session.dart';
import '../../tasks/application/task_location_reference.dart';
import '../application/resident_proposal_boundary.dart';

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
        const Text(
          'Usulan tidak otomatis menjadi tugas aktif. RT dapat memilih template aman untuk membuat draf; '
          'teks usulan bukan instruksi, dan aktivasi tetap memerlukan konfirmasi operator.',
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
            helperText: 'Jangan masukkan NIK, nomor telepon, alamat, atau koordinat GPS.',
            border: OutlineInputBorder(),
          ),
        ),
        DropdownButtonFormField<ResidentProposalCategory>(
          key: const Key('proposal-category'),
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
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_submitted case final submitted?) ...[
          const SizedBox(height: 16),
          Card(
            key: const Key('proposal-submitted'),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    submitted.state == 'SUBMITTED'
                        ? 'Menunggu Tinjauan RT'
                        : 'Usulan telah ditinjau RT',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Usulan ini belum menjadi tugas. Tidak ada tugas yang diaktifkan atau dikirim.',
                  ),
                  const SizedBox(height: 8),
                  Text('Usulan: ${submitted.title}'),
                ],
              ),
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
