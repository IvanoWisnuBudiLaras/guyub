import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/auth/application/operator_profile.dart';
import 'package:guyub/features/tasks/application/task_campaign_boundary.dart';
import 'package:guyub/features/tasks/application/task_template.dart';
import 'package:guyub/features/weather/application/weather_suggestion.dart';
import 'package:guyub/features/weather/application/weather_suggestion_boundary.dart';
import 'package:guyub/features/weather/presentation/weather_suggestion_review_screen.dart';

void main() {
  final profile = OperatorProfile(
    uid: 'operator-a',
    communityId: 'rt-a',
    role: OperatorRole.ketuaRtRw,
    displayName: 'Ketua RT',
  );
  final templates = [
    TaskTemplate(
      id: 'home-check',
      version: 2,
      title: 'Persiapan rumah tangga',
      category: 'HOUSEHOLD_PREPARATION',
      coreInstruction: 'Simpan dokumen penting di tempat aman.',
      safetyInstruction: 'Jangan mendekati air banjir.',
      enabled: true,
    ),
    TaskTemplate(
      id: 'unrelated-task',
      version: 1,
      title: 'Tugas lain',
      category: 'LOGISTICS',
      coreInstruction: 'Ikuti instruksi yang aman.',
      safetyInstruction: 'Jangan melakukan kegiatan berbahaya.',
      enabled: true,
    ),
  ];

  WeatherSuggestion suggestion({bool stale = false}) =>
      WeatherSuggestion.fromJson({
        'suggestionId': 'a' * 40,
        'source': 'BMKG',
        'snapshotId': 'b' * 40,
        'sourceUpdatedAt': '2026-10-05T06:00:00.000Z',
        'fetchedAt': '2026-10-05T07:00:00.000Z',
        'rainfallMm': 32.5,
        'ruleId': 'heavy-rain-preparation',
        'ruleVersion': 1,
        'recommendedTemplateVersions': [
          {'templateId': 'home-check', 'version': 2},
        ],
        'explanation': 'Tinjau persiapan rumah berdasarkan konteks BMKG.',
        'state': 'SUGGESTED',
        'createdAt': '2026-10-05T07:00:00.000Z',
        'isStale': stale,
      });

  testWidgets('review opens only the recommended safe catalog templates', (
    tester,
  ) async {
    final campaigns = _FakeCampaignBoundary(templates);
    await tester.pumpWidget(
      MaterialApp(
        home: WeatherSuggestionReviewScreen(
          profile: profile,
          suggestionBoundary: _FakeSuggestionBoundary([suggestion()]),
          taskCampaignController: TaskCampaignController(campaigns),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tinjau Saran Cuaca'), findsOneWidget);
    expect(find.text('Saran BMKG · Menunggu tinjauan'), findsOneWidget);
    expect(find.textContaining('mengirim peringatan resmi'), findsOneWidget);
    final review = find.byKey(Key('weather-suggestion-review-${'a' * 40}'));
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('task-catalog-weather-suggestion-notice')),
      findsOneWidget,
    );
    expect(find.text('Persiapan rumah tangga'), findsOneWidget);
    expect(find.text('Tugas lain'), findsNothing);
    expect(campaigns.listCalls, 2);
  });

  testWidgets('stale weather suggestions cannot open the task catalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeatherSuggestionReviewScreen(
          profile: profile,
          suggestionBoundary: _FakeSuggestionBoundary([
            suggestion(stale: true),
          ]),
          taskCampaignController: TaskCampaignController(
            _FakeCampaignBoundary(templates),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('weather-suggestion-stale')), findsOneWidget);
    final route = find.byKey(Key('weather-suggestion-review-${'a' * 40}'));
    expect(tester.widget<OutlinedButton>(route).onPressed, isNull);
  });
}

final class _FakeSuggestionBoundary implements WeatherSuggestionBoundary {
  _FakeSuggestionBoundary(this.suggestions);
  final List<WeatherSuggestion> suggestions;

  @override
  Future<List<WeatherSuggestion>> listWeatherSuggestions() async => suggestions;
}

final class _FakeCampaignBoundary implements TaskCampaignBoundary {
  _FakeCampaignBoundary(this.templates);
  final List<TaskTemplate> templates;
  int listCalls = 0;

  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async {
    listCalls += 1;
    return templates;
  }

  @override
  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String requestId,
  }) => throw UnimplementedError();

  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) => throw UnimplementedError();
}
