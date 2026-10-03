import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../data/fake/fake_task_repository.dart';
import '../../../../domain/models/task_template.dart';
import '../../../../domain/repositories/task_repository.dart';
import '../../../../shared/widgets/primary_button.dart';
import 'send_confirmation_screen.dart';

/// SCR-09. Operator memilih 1 template terkunci dari safe catalog, lalu mengisi
/// slot yang memang boleh diedit (deadline/lokasi/catatan) — INV-02: core & safety
/// text TIDAK PERNAH jadi TextField di sini.
///
/// Sesuai PRD §19: Instruksi keselamatan tidak disembunyikan di balik UI sekunder
/// saat tugas dapat ditindaklanjuti.
class TaskCatalogScreen extends StatefulWidget {
  const TaskCatalogScreen({
    super.key,
    this.taskRepository,
  });

  final TaskRepository? taskRepository;

  @override
  State<TaskCatalogScreen> createState() => _TaskCatalogScreenState();
}

class _TaskCatalogScreenState extends State<TaskCatalogScreen> {
  late final TaskRepository _taskRepository;
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
    _taskRepository = widget.taskRepository ?? FakeTaskRepository();
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
          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
    });
  }

  Future<void> _proceed() async {
    if (_selected == null || _deadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih template tugas dan tentukan batas waktu terlebih dahulu.'),
        ),
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
      appBar: AppBar(
        title: const Text('Katalog Tugas Aman'),
      ),
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
                  border: Border.all(color: AppColors.borderGray),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, size: 20, color: AppColors.primaryBlue),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Katalog Tugas Aman Guyub.id (INV-02):\n'
                        'Instruksi inti dan panduan keselamatan bersifat terkunci demi keselamatan warga. '
                        'Operator RT hanya menentukan batas waktu, lokasi, dan catatan.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'PILIH TEMPLATE TUGAS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              for (final template in templates)
                _TemplateCard(
                  template: template,
                  selected: _selected?.templateId == template.templateId,
                  onTap: () {
                    setState(() {
                      _selected = template;
                    });
                  },
                ),
              if (_selected != null) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'ATUR DETAIL TUGAS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Text('Batas Waktu (Wajib)', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('input_deadline'),
                  controller: _deadlineController,
                  readOnly: true,
                  onTap: _pickDeadline,
                  decoration: const InputDecoration(
                    hintText: 'Pilih tanggal batas waktu',
                    suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Catatan Lokasi (Opsional)', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('input_location'),
                  controller: _locationController,
                  decoration: const InputDecoration(hintText: 'cth. Fokus di Selokan Blok A s/d C'),
                ),
                const SizedBox(height: 16),
                Text('Catatan Tambahan (Opsional)', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('input_note'),
                  controller: _noteController,
                  decoration: const InputDecoration(hintText: 'cth. Bawa cangkul atau karung bila ada'),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Lanjut ke Konfirmasi',
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : AppColors.borderGray,
                width: selected ? 1.8 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
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
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle, color: AppColors.primaryBlue, size: 20),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Chip(label: template.category, color: AppColors.successGreen),
                    if (template.estimatedDurationOptional != null)
                      _Chip(
                        label: template.estimatedDurationOptional!,
                        color: AppColors.textSecondary,
                      ),
                    const _Chip(
                      label: 'Instruksi Terkunci',
                      color: AppColors.primaryBlue,
                    ),
                  ],
                ),
                // PRD §19: Tampilkan instruksi keselamatan & inti secara jelas
                // saat template dipilih (actionable)
                if (selected) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.assignment_outlined, size: 16, color: AppColors.primaryBlue),
                      SizedBox(width: 6),
                      Text(
                        'Instruksi Utama (Read-only)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    template.coreInstruction,
                    style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warningYellowBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.brown),
                            SizedBox(width: 6),
                            Text(
                              'Instruksi Keselamatan (Terkunci)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.brown,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          template.safetyInstruction,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Colors.brown,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
