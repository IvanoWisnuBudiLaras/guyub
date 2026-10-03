import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/data/fake/fake_task_repository.dart';
import 'package:guyub/domain/models/task_campaign.dart';
import 'package:guyub/domain/models/task_template.dart';
import 'package:guyub/features/tasks/presentation/screens/send_confirmation_screen.dart';
import 'package:guyub/features/tasks/presentation/screens/task_catalog_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTaskRepository repository;

  setUp(() {
    repository = FakeTaskRepository();
  });

  group('TaskCatalogScreen (SCR-09) Widget Tests', () {
    testWidgets('renders safe templates and locked instruction banner', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TaskCatalogScreen(taskRepository: repository),
        ),
      );

      // Loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Banner locked safe catalog
      expect(find.textContaining('Katalog Tugas Aman Guyub.id'), findsOneWidget);
      expect(find.text('Inspeksi Saluran Drainase'), findsOneWidget);
      expect(find.text('Distribusi Karung Pasir'), findsOneWidget);
    });

    testWidgets('selecting template displays read-only core & safety instructions (PRD §19, INV-02)', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TaskCatalogScreen(taskRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      // Before selection, detail input is not visible
      expect(find.byKey(const Key('input_deadline')), findsNothing);

      // Tap first template
      await tester.tap(find.text('Inspeksi Saluran Drainase'));
      await tester.pumpAndSettle();

      // Core instruction and Safety instruction are rendered
      expect(find.text('Instruksi Utama (Read-only)'), findsOneWidget);
      expect(find.textContaining('Periksa saluran drainase'), findsOneWidget);
      expect(find.text('Instruksi Keselamatan (Terkunci)'), findsOneWidget);
      expect(find.textContaining('Jangan masuk ke saluran yang dalam'), findsOneWidget);

      // Detail fields are now displayed in viewport
      expect(find.byKey(const Key('input_deadline')), findsOneWidget);
      expect(find.byKey(const Key('input_location')), findsOneWidget);
      expect(find.byKey(const Key('input_note')), findsOneWidget);
    });

    testWidgets('validation snackbar shown when submitting without deadline', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TaskCatalogScreen(taskRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inspeksi Saluran Drainase'));
      await tester.pumpAndSettle();

      // Scroll to submit button and tap
      final proceedButton = find.text('Lanjut ke Konfirmasi');
      await tester.ensureVisible(proceedButton);
      await tester.tap(proceedButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Pilih template tugas dan tentukan batas waktu terlebih dahulu.'),
        findsOneWidget,
      );
    });
  });

  group('SendConfirmationScreen (SCR-10) Widget Tests', () {
    late TaskTemplate sampleTemplate;
    late TaskCampaign sampleDraft;

    setUp(() async {
      final templates = await repository.getEnabledTemplates();
      sampleTemplate = templates.first;
      sampleDraft = await repository.createDraft(
        template: sampleTemplate,
        deadline: DateTime(2026, 10, 15),
        locationNote: 'Blok A-C',
        additionalNote: 'Bawa karung bila ada',
      );
    });

    testWidgets('renders summary and immutable safety snapshot prominently', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SendConfirmationScreen(
            draft: sampleDraft,
            template: sampleTemplate,
            taskRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TUGAS AKAN DIKIRIMKAN KE WARGA'), findsOneWidget);
      expect(find.text(sampleTemplate.title), findsOneWidget);
      expect(find.text('15/10/2026'), findsOneWidget);
      expect(find.text('Blok A-C'), findsOneWidget);
      expect(find.text('Bawa karung bila ada'), findsOneWidget);

      // Safety instruction snapshot is visible
      expect(find.text('Instruksi Keselamatan (Snapshot Terkunci)'), findsOneWidget);
      expect(find.text(sampleDraft.instructionSnapshot.safetyInstruction), findsOneWidget);

      // Send button
      expect(find.byKey(const Key('button_send_campaign')), findsOneWidget);
      expect(find.text('Kirim Ke Warga'), findsOneWidget);
    });

    testWidgets('INV-01 & FR-TSK-005: explicit send activates task and shows WhatsApp copy button', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Mock clipboard
      final List<MethodCall> clipboardLogs = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          clipboardLogs.add(methodCall);
          return null;
        }
        return null;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SendConfirmationScreen(
            draft: sampleDraft,
            template: sampleTemplate,
            taskRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Before send, WhatsApp copy button is not yet shown
      expect(find.byKey(const Key('button_copy_whatsapp')), findsNothing);

      // Tap send button (INV-01) with ensureVisible
      final sendButton = find.byKey(const Key('button_send_campaign'));
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Success feedback
      expect(find.text('Terkirim! Status tugas sekarang AKTIF untuk warga RT.'), findsOneWidget);
      expect(find.text('Tugas Telah Dikirim'), findsOneWidget);

      // WhatsApp copy button is now available (FR-TSK-005, O-06)
      final whatsappButton = find.byKey(const Key('button_copy_whatsapp'));
      expect(whatsappButton, findsOneWidget);

      // Tap copy WhatsApp
      await tester.ensureVisible(whatsappButton);
      await tester.tap(whatsappButton);
      await tester.pumpAndSettle();

      expect(clipboardLogs, isNotEmpty);
      final copiedText = clipboardLogs.last.arguments['text'] as String;
      expect(copiedText, contains('Guyub.id'));
      expect(copiedText, contains(sampleTemplate.title));
      expect(copiedText, contains('Instruksi Keselamatan'));
      expect(find.text('Teks ringkasan tugas disalin! Siap ditempel di grup WhatsApp warga.'), findsOneWidget);
    });
  });
}
