import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/project_config.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/services/fs_service.dart';
import 'package:project_context_generator/widgets/generate_button.dart';

import '../helpers/test_utils.dart';

void main() {
  ProjectConfig config({
    String rootPath = '/repo',
    List<String> includedFiles = const ['lib/main.dart'],
  }) {
    return makeConfig(
      id: 'cfg',
      name: 'Project',
      rootPath: rootPath,
      includedFiles: includedFiles,
      ignorePatterns: const ['build/**'],
    );
  }

  FakeFsService createFs({
    Set<String>? paths,
    PromptBuildResult? promptResult,
  }) {
    return FakeFsService(
      paths: paths ?? {'lib/main.dart'},
      promptResult:
          promptResult ??
          samplePromptResult(promptText: 'PROMPT', fileCount: 1, totalLines: 2),
    );
  }

  Future<void> drainSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> pumpButton(
    WidgetTester tester, {
    required List<ProjectConfig> configs,
    required FakeFsService fs,
    FakeClipboard? clipboard,
  }) async {
    clipboard?.install(tester);
    await pumpWithConfigs(
      tester,
      const Scaffold(body: GenerateButton()),
      configs: configs,
      overrides: [fsServiceProvider.overrideWithValue(fs)],
    );
  }

  testWidgets('asks for a root folder when no project is selected', (
    tester,
  ) async {
    await pumpButton(tester, configs: [], fs: createFs());

    await tester.tap(find.text('Generate & Copy'));
    await tester.pump();

    expect(
      find.text('Please select a valid root folder first.'),
      findsOneWidget,
    );
    await drainSnackBars(tester);
  });

  testWidgets('asks for a root folder when the project has no root', (
    tester,
  ) async {
    await pumpButton(
      tester,
      configs: [config(rootPath: '')],
      fs: createFs(),
    );

    await tester.tap(find.text('Generate & Copy'));
    await tester.pump();

    expect(
      find.text('Please select a valid root folder first.'),
      findsOneWidget,
    );
    await drainSnackBars(tester);
  });

  testWidgets('asks for files when nothing is included', (tester) async {
    await pumpButton(
      tester,
      configs: [config(includedFiles: const [])],
      fs: createFs(),
    );

    await tester.tap(find.text('Generate & Copy'));
    await tester.pump();

    expect(
      find.text('No files selected to include in prompt context.'),
      findsOneWidget,
    );
    await drainSnackBars(tester);
  });

  testWidgets('generates and copies the prompt when nothing changed', (
    tester,
  ) async {
    final fs = createFs();
    final clipboard = FakeClipboard();
    await pumpButton(tester, configs: [config()], fs: fs, clipboard: clipboard);
    final container = containerOf(tester);
    container.read(projectSnapshotsProvider.notifier).state = {
      'cfg': {'lib/main.dart'},
    };

    await tester.tap(find.text('Generate & Copy'));
    await pumpUntil(
      tester,
      () => clipboard.text == 'PROMPT',
      description: 'clipboard write',
    );
    await tester.pump();

    expect(clipboard.text, 'PROMPT');
    expect(fs.scanPathsCalls, 1);
    expect(fs.promptParams, hasLength(1));
    expect(fs.promptParams.single.projectName, 'Project');
    expect(
      find.text('Prompt generated and copied to clipboard! (1 files, 2 lines)'),
      findsOneWidget,
    );
    await drainSnackBars(tester);
  });

  testWidgets('warns and can review when the disk state changed', (
    tester,
  ) async {
    final fs = createFs();
    final clipboard = FakeClipboard();
    await pumpButton(tester, configs: [config()], fs: fs, clipboard: clipboard);
    containerOf(tester).read(projectSnapshotsProvider.notifier).state = {
      'cfg': {'old.dart'},
    };

    await tester.tap(find.text('Generate & Copy'));
    await pumpUntil(
      tester,
      () => find.text('Project State Changed').evaluate().isNotEmpty,
      description: 'changed-state dialog',
    );

    expect(find.text('Project State Changed'), findsOneWidget);

    await tester.tap(find.text('Review Project'));
    await tester.pumpAndSettle();
    await flushConfigs(tester);

    expect(fs.scanPathsCalls, greaterThanOrEqualTo(1));
    expect(fs.promptParams, isEmpty);
    expect(clipboard.text, isNull);
    expect(
      find.text(
        'Project structure updated. Please review your file selections.',
      ),
      findsOneWidget,
    );
    await drainSnackBars(tester);
  });

  testWidgets('confirms changed state and then generates', (tester) async {
    final fs = createFs();
    final clipboard = FakeClipboard();
    await pumpButton(tester, configs: [config()], fs: fs, clipboard: clipboard);
    containerOf(tester).read(projectSnapshotsProvider.notifier).state = {
      'cfg': {'old.dart'},
    };

    await tester.tap(find.text('Generate & Copy'));
    await pumpUntil(
      tester,
      () => find.text('Project State Changed').evaluate().isNotEmpty,
      description: 'changed-state dialog',
    );
    await tester.tap(find.text('Confirm'));
    await pumpUntil(
      tester,
      () => clipboard.text == 'PROMPT',
      description: 'clipboard write after confirm',
    );
    await flushConfigs(tester);

    expect(clipboard.text, 'PROMPT');
    expect(fs.promptParams, hasLength(1));
    await drainSnackBars(tester);
  });

  testWidgets('dismissing the changed-state dialog cancels generation', (
    tester,
  ) async {
    final fs = createFs();
    final clipboard = FakeClipboard();
    await pumpButton(tester, configs: [config()], fs: fs, clipboard: clipboard);
    containerOf(tester).read(projectSnapshotsProvider.notifier).state = {
      'cfg': {'old.dart'},
    };

    await tester.tap(find.text('Generate & Copy'));
    await pumpUntil(
      tester,
      () => find.text('Project State Changed').evaluate().isNotEmpty,
      description: 'changed-state dialog',
    );
    await tester.tapAt(const Offset(5, 5));
    await pumpUntil(
      tester,
      () => find.text('Generate & Copy').evaluate().isNotEmpty,
      description: 'dialog dismissal',
    );
    await tester.pumpAndSettle();

    expect(find.text('Project State Changed'), findsNothing);
    expect(fs.promptParams, isEmpty);
    expect(find.text('Generate & Copy'), findsOneWidget);
  });

  testWidgets('shows an error when no files survive filtering', (tester) async {
    final fs = createFs(promptResult: samplePromptResult(fileCount: 0));
    await pumpButton(
      tester,
      configs: [config()],
      fs: fs,
      clipboard: FakeClipboard(),
    );
    containerOf(tester).read(projectSnapshotsProvider.notifier).state = {
      'cfg': {'lib/main.dart'},
    };

    await tester.tap(find.text('Generate & Copy'));
    await tester.pumpAndSettle();

    expect(
      find.text('No files selected or all selected files are ignored.'),
      findsOneWidget,
    );
    await drainSnackBars(tester);
  });

  testWidgets('shows an error when prompt construction fails', (tester) async {
    final fs = createFs()..promptError = StateError('prompt failed');
    await pumpButton(
      tester,
      configs: [config()],
      fs: fs,
      clipboard: FakeClipboard(),
    );
    containerOf(tester).read(projectSnapshotsProvider.notifier).state = {
      'cfg': {'lib/main.dart'},
    };

    await tester.tap(find.text('Generate & Copy'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Failed to copy prompt to clipboard'),
      findsOneWidget,
    );
    await drainSnackBars(tester);
  });

  testWidgets('shows an error when the filesystem scan fails', (tester) async {
    final fs = createFs()..scanPathsError = StateError('scan failed');
    await pumpButton(
      tester,
      configs: [config()],
      fs: fs,
      clipboard: FakeClipboard(),
    );

    await tester.tap(find.text('Generate & Copy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Generation process failed'), findsOneWidget);
    await drainSnackBars(tester);
  });

  testWidgets('disables the button while generating', (tester) async {
    final fs = createFs();
    final completer = Completer<PromptBuildResult>();
    fs.promptCompleter = completer;
    final clipboard = FakeClipboard();
    await pumpButton(tester, configs: [config()], fs: fs, clipboard: clipboard);
    containerOf(tester).read(projectSnapshotsProvider.notifier).state = {
      'cfg': {'lib/main.dart'},
    };

    await tester.tap(find.text('Generate & Copy'));
    await tester.pump();

    expect(find.text('Generating...'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generating...'),
    );
    expect(button.onPressed, isNull);

    completer.complete(
      samplePromptResult(promptText: 'DONE', fileCount: 1, totalLines: 1),
    );
    await pumpUntil(
      tester,
      () => clipboard.text == 'DONE',
      description: 'deferred clipboard write',
    );

    expect(find.text('Generate & Copy'), findsOneWidget);
    await drainSnackBars(tester);
  });
}
