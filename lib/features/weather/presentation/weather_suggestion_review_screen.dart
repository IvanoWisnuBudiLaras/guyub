import 'package:flutter/material.dart';

import '../../auth/application/operator_profile.dart';
import '../../tasks/application/task_campaign_boundary.dart';
import '../../tasks/application/task_template.dart';
import '../../tasks/presentation/screens/task_catalog_screen.dart';
import '../application/weather_snapshot_boundary.dart';
import '../application/weather_snapshot_store.dart';
import '../application/weather_suggestion.dart';
import '../application/weather_suggestion_boundary.dart';
import 'weather_snapshot_card.dart';

/// Read-only suggestion review. A suggestion can only open the approved task
/// catalog; it never creates or activates a campaign by itself.
final class WeatherSuggestionReviewScreen extends StatefulWidget {
  const WeatherSuggestionReviewScreen({
    required this.profile,
    required this.suggestionBoundary,
    required this.taskCampaignController,
    this.weatherSnapshotStore,
    this.weatherSnapshotSyncController,
    super.key,
  });

  final OperatorProfile profile;
  final WeatherSuggestionBoundary suggestionBoundary;
  final TaskCampaignController taskCampaignController;
  final WeatherSnapshotStore? weatherSnapshotStore;
  final WeatherSnapshotSyncController? weatherSnapshotSyncController;

  @override
  State<WeatherSuggestionReviewScreen> createState() =>
      _WeatherSuggestionReviewScreenState();
}

final class _WeatherSuggestionReviewScreenState
    extends State<WeatherSuggestionReviewScreen> {
  late Future<_WeatherReviewData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_WeatherReviewData> _load() async {
    final results = await Future.wait<Object>([
      widget.suggestionBoundary.listWeatherSuggestions(),
      widget.taskCampaignController.listApprovedTemplates(),
    ]);
    return _WeatherReviewData(
      suggestions: results[0] as List<WeatherSuggestion>,
      templates: results[1] as List<TaskTemplate>,
    );
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() => _dataFuture = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tinjau Saran Cuaca')),
    body: FutureBuilder<_WeatherReviewData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReviewMessage(
            message:
                'Saran cuaca belum dapat dimuat. Coba lagi saat tersambung.',
            actionLabel: 'Coba lagi',
            onAction: _reload,
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return _ReviewMessage(
            message: 'Saran cuaca belum tersedia.',
            actionLabel: 'Coba lagi',
            onAction: _reload,
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            key: const Key('weather-suggestion-review-list'),
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.weatherSnapshotStore case final store?) ...[
                WeatherSnapshotCard(
                  store: store,
                  communityId: widget.profile.communityId,
                  onRefresh: widget.weatherSnapshotSyncController == null
                      ? null
                      : () => widget.weatherSnapshotSyncController!
                            .refreshForOperator(
                              communityId: widget.profile.communityId,
                            ),
                ),
                const SizedBox(height: 12),
              ],
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Saran cuaca hanya konteks untuk ditinjau. Saran tidak '
                    'membuat tugas aktif atau mengirim peringatan resmi. '
                    'Gunakan katalog tugas aman; distribusi tetap memerlukan '
                    'konfirmasi operator.',
                    key: Key('weather-suggestion-safety-copy'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (data.suggestions.isEmpty)
                const _ReviewMessage(
                  key: Key('weather-suggestions-empty'),
                  message: 'Belum ada saran cuaca untuk RT ini. Tidak ada tugas yang dibuat otomatis.',
                )
              else
                for (final suggestion in data.suggestions) ...[
                  _SuggestionCard(
                    suggestion: suggestion,
                    templates: data.templates,
                    onOpenCatalog: (versions) =>
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => TaskCatalogScreen(
                              profile: widget.profile,
                              controller: widget.taskCampaignController,
                              recommendedTemplateVersions: versions,
                            ),
                          ),
                        ),
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

final class _WeatherReviewData {
  const _WeatherReviewData({
    required this.suggestions,
    required this.templates,
  });

  final List<WeatherSuggestion> suggestions;
  final List<TaskTemplate> templates;
}

final class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.templates,
    required this.onOpenCatalog,
  });

  final WeatherSuggestion suggestion;
  final List<TaskTemplate> templates;
  final ValueChanged<Set<String>> onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    final recommended = <TaskTemplate>[];
    final versions = <String>{};
    for (final reference in suggestion.recommendedTemplateVersions) {
      final template = _findTemplate(
        templates,
        reference.templateId,
        reference.version,
      );
      if (template != null) {
        recommended.add(template);
        versions.add('${template.id}:v${template.version}');
      }
    }
    final canReview = !suggestion.isStale && versions.isNotEmpty;
    return Card(
      key: Key('weather-suggestion-${suggestion.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Saran BMKG · Menunggu tinjauan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (suggestion.rainfallMm != null) ...[
              const SizedBox(height: 8),
              Text(
                'Curah hujan pada prakiraan: '
                '${suggestion.rainfallMm!.toStringAsFixed(1).replaceAll('.', ',')} mm',
              ),
            ],
            if (suggestion.sourceUpdatedAt != null)
              Text(
                'Pembaruan sumber: ${_formatDate(suggestion.sourceUpdatedAt!)}',
              ),
            if (suggestion.fetchedAt != null)
              Text('Diterima server: ${_formatDate(suggestion.fetchedAt!)}'),
            const SizedBox(height: 8),
            Text(suggestion.explanation),
            const SizedBox(height: 8),
            if (suggestion.isStale)
              const Text(
                'Saran ini memakai data yang sudah lama. Jangan gunakan untuk menyiapkan tugas.',
                key: Key('weather-suggestion-stale'),
              )
            else if (recommended.isEmpty)
              const Text(
                'Template aman yang disarankan tidak tersedia. Hubungi pengelola RT.',
              )
            else ...[
              const Text('Template aman yang disarankan:'),
              for (final template in recommended)
                Text('• ${template.title} · versi ${template.version}'),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: Key('weather-suggestion-review-${suggestion.id}'),
              onPressed: canReview ? () => onOpenCatalog(versions) : null,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Tinjau template aman'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ReviewMessage extends StatelessWidget {
  const _ReviewMessage({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

TaskTemplate? _findTemplate(
  List<TaskTemplate> templates,
  String id,
  int version,
) {
  for (final template in templates) {
    if (template.id == id && template.version == version) return template;
  }
  return null;
}
