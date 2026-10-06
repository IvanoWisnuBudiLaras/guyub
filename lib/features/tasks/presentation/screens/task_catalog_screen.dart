import 'package:flutter/material.dart';

import '../../../auth/application/operator_profile.dart';
import '../../application/task_campaign_boundary.dart';
import '../../application/task_template.dart';
import '../widgets/locked_instructions_card.dart';
import 'task_draft_screen.dart';

/// Catalog shows only reviewed templates supplied by the trusted backend.
final class TaskCatalogScreen extends StatefulWidget {
  const TaskCatalogScreen({
    required this.profile,
    required this.controller,
    this.recommendedTemplateVersions,
    super.key,
  });

  final OperatorProfile profile;
  final TaskCampaignController controller;

  /// Optional server-derived recommendation filter from a weather suggestion.
  final Set<String>? recommendedTemplateVersions;

  @override
  State<TaskCatalogScreen> createState() => _TaskCatalogScreenState();
}

final class _TaskCatalogScreenState extends State<TaskCatalogScreen> {
  late Future<List<TaskTemplate>> _templatesFuture;

  @override
  void initState() {
    super.initState();
    _templatesFuture = widget.controller.listApprovedTemplates();
  }

  void _reload() {
    setState(
      () => _templatesFuture = widget.controller.listApprovedTemplates(),
    );
  }

  Future<void> _openDraft(TaskTemplate template) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TaskDraftScreen(
          profile: widget.profile,
          template: template,
          controller: widget.controller,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Katalog Tugas Aman')),
    body: FutureBuilder<List<TaskTemplate>>(
      future: _templatesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CatalogMessage(
            message:
                'Katalog tugas belum dapat dimuat. Coba lagi saat tersambung.',
            actionLabel: 'Coba lagi',
            onAction: _reload,
          );
        }
        final loadedTemplates = snapshot.data ?? const <TaskTemplate>[];
        final recommendations = widget.recommendedTemplateVersions;
        final templates = recommendations == null
            ? loadedTemplates
            : loadedTemplates
                  .where(
                    (template) => recommendations.contains(
                      '${template.id}:v${template.version}',
                    ),
                  )
                  .toList(growable: false);
        if (templates.isEmpty) {
          return _CatalogMessage(
            key: const Key('task-catalog-empty'),
            message: recommendations == null
                ? 'Belum ada template yang disetujui untuk digunakan. Hubungi '
                      'administrator RT; jangan membuat instruksi tugas sendiri.'
                : 'Template aman yang disarankan tidak tersedia. Kembali ke saran cuaca atau hubungi pengelola RT.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (recommendations != null) ...[
                const Text(
                  'Ini hanya saran cuaca, bukan peringatan resmi. Tidak ada tugas '
                  'yang aktif otomatis. Tinjau template lalu konfirmasi aktivasi secara terpisah.',
                  key: Key('task-catalog-weather-suggestion-notice'),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'Pilih tugas yang sudah ditinjau. Instruksi inti dan keselamatan '
                'tidak dapat diubah.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              for (final template in templates) ...[
                _TemplateCard(
                  template: template,
                  onSelect: () => _openDraft(template),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    ),
  );
}

final class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onSelect});

  final TaskTemplate template;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(template.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${_categoryLabel(template.category)} · Versi ${template.version}'
            '${template.estimatedDurationMinutes == null ? '' : ' · ${template.estimatedDurationMinutes} menit'}',
          ),
          const SizedBox(height: 12),
          LockedTaskInstructionsCard(snapshot: template.snapshot()),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: Key('task-template-${template.id}-select'),
            onPressed: onSelect,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Pilih template'),
          ),
        ],
      ),
    ),
  );
}

final class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.library_books_outlined, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _categoryLabel(String category) => switch (category) {
  'HOUSEHOLD_PREPARATION' => 'Persiapan rumah tangga',
  'LOGISTICS' => 'Logistik',
  'ENVIRONMENTAL_CLEANUP' => 'Kebersihan lingkungan',
  'SAFE_VISUAL_INSPECTION' => 'Pengamatan dari tempat aman',
  _ => 'Tugas kesiapsiagaan',
};
