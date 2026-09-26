import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../data/fake/fake_task_repository.dart';
import '../../../../domain/models/task_template.dart';
import '../../../../domain/repositories/task_repository.dart';
import '../../../../shared/widgets/primary_button.dart';
import 'send_confirmation_screen.dart';

/// SCR-09. Operator pilih 1 template terkunci, isi slot yang memang boleh
/// diedit (deadline/lokasi/catatan) — INV-02: core & safety text TIDAK
/// pernah jadi TextField di sini.
class TaskCatalogScreen extends StatefulWidget {
  const TaskCatalogScreen({super.key});

  @override
  State<TaskCatalogScreen> createState() => _TaskCatalogScreenState();
}

class _TaskCatalogScreenState extends State<TaskCatalogScreen> {
  // TODO(integrasi): ganti ke implementasi Firestore asli begitu siap.
  final TaskRepository _taskRepository = FakeTaskRepository();

  late Future<List<TaskTemplate>> _templatesFuture;
  TaskTemplate? _selected;

  final _deadlineController = TextEditingController();
  final _locationController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime? _deadline;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _templatesFuture = _taskRepository.getEnabledTemplates();
  }

  @override
  void dispose() {
    _deadlineController.dispose();
    _locationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked == null) return;
    setState(() {
      _deadline = picked;
      _deadlineController.text =
          '${picked.day}/${picked.month}/${picked.year}';
    });
  }

  Future<void> _proceed() async {
    if (_selected == null || _deadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih template dan batas waktu dulu.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final draft = await _taskRepository.createDraft(
        template: _selected!,
        deadline: _deadline!,
        locationNote: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        additionalNote: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SendConfirmationScreen(
            draft: draft,
            template: _selected!,
            taskRepository: _taskRepository,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Katalog Tugas')),
      body: FutureBuilder<List<TaskTemplate>>(
        future: _templatesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat template: ${snapshot.error}'));
          }
          final templates = snapshot.data ?? [];
          if (templates.isEmpty) {
            return const Center(child: Text('Belum ada template tersedia.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.neutralBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Konten instruksi & keselamatan disusun oleh Tim Guyub.id. '
                  'Anda hanya bisa mengatur batas waktu, lokasi, dan catatan.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              for (final template in templates)
                _TemplateCard(
                  template: template,
                  selected: _selected?.templateId == template.templateId,
                  onTap: () => setState(() => _selected = template),
                ),
              if (_selected != null) ...[
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Text('Batas Waktu', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  controller: _deadlineController,
                  readOnly: true,
                  onTap: _pickDeadline,
                  decoration: const InputDecoration(
                    hintText: 'Pilih tanggal',
                    suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Catatan Lokasi', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  controller: _locationController,
                  decoration: const InputDecoration(hintText: 'cth. Fokus di Blok A-C'),
                ),
                const SizedBox(height: 16),
                Text('Catatan Tambahan', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(hintText: 'Opsional...'),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Lanjut → Konfirmasi',
                  isLoading: _isSubmitting,
                  onPressed: _proceed,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final TaskTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : AppColors.borderGray,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        template.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle, color: AppColors.successGreen, size: 20),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Instruksi & Keselamatan',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _Chip(label: template.category, color: AppColors.successGreen),
                    if (template.estimatedDurationOptional != null)
                      _Chip(
                        label: template.estimatedDurationOptional!,
                        color: AppColors.textSecondary,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
