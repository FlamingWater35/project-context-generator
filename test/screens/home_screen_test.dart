import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/project_config.dart';
import 'package:project_context_generator/models/tree_node.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/screens/home_screen.dart';

import '../helpers/test_utils.dart';

void main() {
  ProjectConfig config({
    List<String> includedFiles = const ['README.md'],
    String rootPath = '/repo',
  }) {
    return makeConfig(
      id: 'cfg',
      name: 'Demo Project',
      rootPath: rootPath,
      includedFiles: includedFiles,
    );
  }

  TreeNode tree() {
    return TreeNode(
      path: '/repo',
      relativePath: '',
      name: 'repo',
      isDirectory: true,
      children: [testFile('README.md')],
    );
  }

  FakeFsService fsService() {
    return FakeFsService(
      tree: tree(),
      paths: {'README.md'},
      promptResult: samplePromptResult(
        promptText: 'CONTEXT PROMPT',
        fileCount: 1,
        totalLines: 2,
      ),
    );
  }

  Future<FakeFsService> pumpHome(
    WidgetTester tester, {
    List<ProjectConfig> configs = const [],
    FakeFsService? fs,
    Size surfaceSize = const Size(1200, 800),
  }) async {
    final fakeFs = fs ?? fsService();
    await pumpWithConfigs(
      tester,
      const HomeScreen(),
      configs: configs,
      surfaceSize: surfaceSize,
      overrides: [
        fsServiceProvider.overrideWithValue(fakeFs),
        fileTreeProvider.overrideWith((ref) async => tree()),
      ],
    );
    await tester.pump();
    if (configs.isNotEmpty) {
      // Let the debounced prompt statistics settle, including the rebuild
      // triggered when skill detection completes.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    return fakeFs;
  }

  testWidgets('shows the empty state without a project', (tester) async {
    await pumpHome(tester);

    expect(
      find.text('Create or select a project context configuration.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.folder_special), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
  });

  testWidgets('renders project details, controls, tree, and metrics', (
    tester,
  ) async {
    await pumpHome(tester, configs: [config()]);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Demo Project'), findsNWidgets(2));
    expect(find.text('/repo'), findsOneWidget);
    expect(find.text('Ignores'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Apply Changes'), findsOneWidget);
    expect(find.text('Generate & Copy'), findsOneWidget);
    expect(find.text('Check for Changes'), findsOneWidget);
    expect(find.text('Select Root Folder'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('1 files selected'), findsOneWidget);
  });

  testWidgets('uses the compact header on narrow windows without overflow', (
    tester,
  ) async {
    await pumpHome(
      tester,
      configs: [config()],
      surfaceSize: const Size(760, 600),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Demo Project'), findsNWidgets(2));
    expect(find.text('Ignores'), findsOneWidget);
    expect(find.text('Generate & Copy'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the wide header when there is enough room', (tester) async {
    await pumpHome(
      tester,
      configs: [config()],
      surfaceSize: const Size(1600, 900),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Demo Project'), findsNWidgets(2));
    expect(find.text('Ignores'), findsOneWidget);
    expect(find.text('Check for Changes'), findsOneWidget);
    expect(find.text('Select Root Folder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+G action generates and copies the prompt', (tester) async {
    final clipboard = FakeClipboard();
    clipboard.install(tester);
    final fs = await pumpHome(tester, configs: [config()]);
    containerOf(tester).read(projectSnapshotsProvider.notifier).state = {
      'cfg': {'README.md'},
    };
    // Ignore the background statistics builds that already ran.
    fs.promptParams.clear();

    Actions.invoke(
      tester.element(find.text('Check for Changes')),
      const GenerateIntent(),
    );
    await pumpUntil(
      tester,
      () => clipboard.text == 'CONTEXT PROMPT',
      description: 'shortcut clipboard write',
    );
    await tester.pump();

    expect(clipboard.text, 'CONTEXT PROMPT');
    expect(fs.promptParams, hasLength(1));
    expect(
      find.text('Prompt generated and copied to clipboard! (1 files, 2 lines)'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  });

  testWidgets('shortcut action validates the root folder', (tester) async {
    await pumpHome(tester, configs: [config(rootPath: '')]);

    Actions.invoke(
      tester.element(find.text('Check for Changes')),
      const GenerateIntent(),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Please select a valid root folder first.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  });

  testWidgets('Check for Changes acknowledges and refreshes the tree', (
    tester,
  ) async {
    final fs = await pumpHome(tester, configs: [config()]);

    await tester.tap(find.text('Check for Changes'));
    await tester.pump();
    await tester.pump();

    expect(fs.scanPathsCalls, greaterThanOrEqualTo(1));
    expect(
      find.text('Project structure updated and snapshot synchronized.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  });

  testWidgets('Ignores button opens the ignore dialog', (tester) async {
    await pumpHome(tester, configs: [config()]);

    await tester.tap(find.text('Ignores'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Ignore Patterns'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Ignore Patterns'), findsNothing);
  });

  testWidgets('Skills button opens the skills dialog', (tester) async {
    await pumpHome(tester, configs: [config()]);

    await tester.tap(find.text('Skills'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    expect(find.text('Agent Skills'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Agent Skills'), findsNothing);
  });

  testWidgets('Apply Changes button opens the clipboard dialog', (
    tester,
  ) async {
    final clipboard = FakeClipboard();
    clipboard.install(tester);
    await pumpHome(tester, configs: [config()]);

    await tester.tap(find.text('Apply Changes'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Apply Code Changes'), findsOneWidget);
    expect(find.text('No code changes detected yet.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Apply Code Changes'), findsNothing);
  });
}
