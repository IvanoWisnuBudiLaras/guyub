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
          suggestionBoundary: _FakeSuggestionBoundary([
            [suggestion()],
          ]),
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
            [suggestion(stale: true)],
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

  testWidgets('suggestion becoming stale cannot open the catalog after load', (
    tester,
  ) async {
    final boundary = _FakeSuggestionBoundary([
      [suggestion()],
      [suggestion(stale: true)],
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: WeatherSuggestionReviewScreen(
          profile: profile,
          suggestionBoundary: boundary,
          taskCampaignController: TaskCampaignController(
            _FakeCampaignBoundary(templates),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final review = find.byKey(Key('weather-suggestion-review-${'a' * 40}'));
    expect(tester.widget<OutlinedButton>(review).onPressed, isNotNull);
    await tester.tap(review);
    await tester.pumpAndSettle();

    expect(boundary.listCalls, 3);
    expect(find.byKey(const Key('weather-suggestion-stale')), findsOneWidget);
    expect(
      find.byKey(const Key('task-catalog-weather-suggestion-notice')),
      findsNothing,
    );
    expect(tester.widget<OutlinedButton>(review).onPressed, isNull);
  });

  testWidgets(
    'ignore requires confirmation and removes the suggestion from the list',
    (tester) async {
      final boundary = _FakeSuggestionBoundary([
        [suggestion()],
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: WeatherSuggestionReviewScreen(
            profile: profile,
            suggestionBoundary: boundary,
            taskCampaignController: TaskCampaignController(
              _FakeCampaignBoundary(templates),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(Key('weather-suggestion-ignore-${'a' * 40}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Abaikan saran cuaca?'), findsOneWidget);
      expect(boundary.ignoredSuggestionIds, isEmpty);

      await tester.tap(
        find.byKey(const Key('weather-suggestion-ignore-confirm')),
      );
      await tester.pumpAndSettle();

      expect(boundary.ignoredSuggestionIds, ['a' * 40]);
      expect(
        find.byKey(const Key('weather-suggestions-empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('task-catalog-weather-suggestion-notice')),
        findsNothing,
      );
    },
  );

  testWidgets('postpone returns without changing the RT suggestion', (
    tester,
  ) async {
    final boundary = _FakeSuggestionBoundary([
      [suggestion()],
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('weather-home'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => WeatherSuggestionReviewScreen(
                    profile: profile,
                    suggestionBoundary: boundary,
                    taskCampaignController: TaskCampaignController(
                      _FakeCampaignBoundary(templates),
                    ),
                  ),
                ),
              ),
              child: const Text('Beranda'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('weather-home')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(Key('weather-suggestion-postpone-${'a' * 40}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beranda'), findsOneWidget);
    expect(boundary.ignoredSuggestionIds, isEmpty);

    await tester.tap(find.byKey(const Key('weather-home')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('weather-suggestion-${'a' * 40}')), findsOneWidget);
  });

  testWidgets('catalog review fails closed when freshness cannot be checked', (
    tester,
  ) async {
    final boundary = _FakeSuggestionBoundary([
      [suggestion()],
    ], failOnListCall: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: WeatherSuggestionReviewScreen(
          profile: profile,
          suggestionBoundary: boundary,
          taskCampaignController: TaskCampaignController(
            _FakeCampaignBoundary(templates),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final review = find.byKey(Key('weather-suggestion-review-${'a' * 40}'));
    await tester.tap(review);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Kebaruan saran belum dapat diperiksa. Coba lagi saat tersambung.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('task-catalog-weather-suggestion-notice')),
      findsNothing,
    );
  });
}

final class _FakeSuggestionBoundary implements WeatherSuggestionBoundary {
  _FakeSuggestionBoundary(this.responses, {this.failOnListCall});

  final List<List<WeatherSuggestion>> responses;
  final int? failOnListCall;
  final ignoredSuggestionIds = <String>[];
  int listCalls = 0;

  @override
  Future<List<WeatherSuggestion>> listWeatherSuggestions() async {
    final call = listCalls++;
    if (call == failOnListCall) {
      throw StateError('Suggestion freshness could not be checked.');
    }
    final index = call < responses.length ? call : responses.length - 1;
    return responses[index];
  }

  @override
  Future<void> ignoreWeatherSuggestion({required String suggestionId}) async {
    ignoredSuggestionIds.add(suggestionId);
    for (var index = 0; index < responses.length; index++) {
      responses[index] = responses[index]
          .where((suggestion) => suggestion.id != suggestionId)
          .toList();
    }
  }
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
