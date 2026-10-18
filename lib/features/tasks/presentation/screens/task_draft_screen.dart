import 'package:flutter/material.dart';

import '../../../auth/application/operator_profile.dart';
import '../../../../core/utils/indonesian_date_formatter.dart';
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
  late final TextEditingController _instructionController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _instructionController = TextEditingController(
      text: widget.template.coreInstruction,
    );
  }

  @override
  void dispose() {
    _instructionController.dispose();
    super.dispose();
  }

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
      final customText = _instructionController.text.trim();
      final customInstruction =
          customText != widget.template.coreInstruction.trim() &&
              customText.isNotEmpty
          ? customText
          : null;
      final campaign = await widget.controller.createDraft(
        template: widget.template,
        deadline: deadline,
        locationReference: _locationReference,
        customInstruction: customInstruction,
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

  Future<void> _openInstructionDialog() async {
    final dialogController = TextEditingController(
      text: _instructionController.text,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Instruksi Tugas RT'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sesuaikan instruksi pelaksanaan untuk warga. Template aman tetap menjadi panduan keselamatan.',
                style: Theme.of(ctx).textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('task-custom-instruction'),
                controller: dialogController,
                maxLines: 4,
                maxLength: 3000,
                decoration: const InputDecoration(
                  labelText: 'Instruksi Khusus RT',
                  hintText: 'Tuliskan instruksi pelaksanaan...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              dialogController.text = widget.template.coreInstruction;
            },
            child: const Text('Reset Template'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('task-custom-instruction-save'),
            onPressed: () => Navigator.of(ctx).pop(dialogController.text),
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _instructionController.text = result;
      });
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
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            key: const Key('task-select-deadline'),
            onPressed: _saving ? null : _chooseDeadline,
            icon: const Icon(Icons.schedule),
            label: Text(
              _deadline == null
                  ? 'Pilih batas waktu'
                  : _formatDeadline(_deadline!),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('task-location-reference'),
          initialValue: _locationReference,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Jenis lokasi umum (opsional)',
            helperText: 'Pilih kategori lokasi pelaksanaan tugas.',
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('task-custom-instruction-button'),
          onPressed: _saving ? null : _openInstructionDialog,
          icon: const Icon(Icons.edit_note),
          label: Text(
            _instructionController.text.trim() !=
                        widget.template.coreInstruction.trim() &&
                    _instructionController.text.trim().isNotEmpty
                ? 'Instruksi RT: Disesuaikan'
                : 'Sesuaikan Instruksi RT (Opsional)',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: const Key('task-create-draft'),
            onPressed: _saving ? null : _createDraft,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_forward),
            label: const Text('Lanjut ke konfirmasi'),
          ),
        ),
      ],
    ),
  );
}

String _formatDeadline(DateTime value) =>
    IndonesianDateFormatter.formatFull(value);
