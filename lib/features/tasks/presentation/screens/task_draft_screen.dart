import 'package:flutter/material.dart';

import '../../../auth/application/operator_profile.dart';
import '../../application/task_campaign_boundary.dart';
import '../../application/task_template.dart';
import '../../application/task_location_reference.dart';
import '../widgets/locked_instructions_card.dart';
import 'task_campaign_confirmation_screen.dart';

/// Allows only deadline and controlled, coarse location categories to be changed.
final class TaskDraftScreen extends StatefulWidget {
  const TaskDraftScreen({
    required this.profile,
    required this.template,
    required this.controller,
    super.key,
  });

  final OperatorProfile profile;
  final TaskTemplate template;
  final TaskCampaignController controller;

  @override
  State<TaskDraftScreen> createState() => _TaskDraftScreenState();
}

final class _TaskDraftScreenState extends State<TaskDraftScreen> {
  DateTime? _deadline;
  String? _locationReference;
  bool _saving = false;
  String? _error;

  Future<void> _chooseDeadline() async {
    final now = DateTime.now();
    final current = _deadline ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 100, 12, 31),
      helpText: 'Pilih batas waktu tugas',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: 'Pilih jam batas waktu',
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      _deadline = selected;
      _error = selected.isAfter(DateTime.now())
          ? null
          : 'Batas waktu harus berada di masa depan.';
    });
  }

  Future<void> _createDraft() async {
    final deadline = _deadline;
    if (deadline == null || !deadline.isAfter(DateTime.now())) {
      setState(() => _error = 'Pilih batas waktu di masa depan.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final campaign = await widget.controller.createDraft(
        template: widget.template,
        deadline: deadline,
        locationReference: _locationReference,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TaskCampaignConfirmationScreen(
            profile: widget.profile,
            campaign: campaign,
            controller: widget.controller,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Draf belum dapat dibuat. Periksa koneksi dan batas waktu, lalu coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Siapkan Draf Tugas')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${widget.profile.role.label} · RT ${widget.profile.communityId}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Text(
          widget.template.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        LockedTaskInstructionsCard(snapshot: widget.template.snapshot()),
        const SizedBox(height: 16),
        Text(
          'Bagian yang dapat diatur',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('task-select-deadline'),
          onPressed: _saving ? null : _chooseDeadline,
          icon: const Icon(Icons.schedule),
          label: Text(
            _deadline == null
                ? 'Pilih batas waktu'
                : _formatDeadline(context, _deadline!),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('task-location-reference'),
          initialValue: _locationReference,
          decoration: const InputDecoration(
            labelText: 'Jenis lokasi umum (opsional)',
            helperText: 'Pilih kategori saja; alamat dan instruksi bebas tidak diterima.',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final value in TaskLocationReferences.allowed)
              DropdownMenuItem(
                value: value,
                child: Text(TaskLocationReferences.label(value)),
              ),
          ],
          onChanged: _saving
              ? null
              : (value) => setState(() => _locationReference = value),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('task-create-draft'),
          onPressed: _saving ? null : _createDraft,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward),
          label: const Text('Lanjut ke konfirmasi'),
        ),
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
