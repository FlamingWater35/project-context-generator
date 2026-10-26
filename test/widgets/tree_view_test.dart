import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/project_config.dart';
import 'package:project_context_generator/models/tree_node.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/widgets/tree_view.dart';

import '../helpers/test_utils.dart';

void main() {
  ProjectConfig config({
    List<String> includedFiles = const [],
    List<String> ignorePatterns = const ['build/**'],
  }) {
    return makeConfig(
      id: 'cfg',
      name: 'Project',
      rootPath: '/repo',
      includedFiles: includedFiles,
      ignorePatterns: ignorePatterns,
    );
  }

  TreeNode tree() {
    return TreeNode(
      path: '/repo',
      relativePath: '',
      name: 'repo',
      isDirectory: true,
      children: [
        testDir(
          'lib',
          children: [testFile('lib/main.dart'), testFile('lib/util.dart')],
        ),
        testFile('README.md'),
      ],
    );
  }

  Future<ProviderContainer> pumpTree(
    WidgetTester tester, {
    required ProjectConfig project,
    required FutureOr<TreeNode?> Function(Ref) buildTree,
    List<Override> extraOverrides = const [],
  }) async {
    await pumpWithConfigs(
      tester,
      const Scaffold(body: ProjectTreeView()),
      configs: [project],
      overrides: [
        fileTreeProvider.overrideWith((ref) async => buildTree(ref)),
        ...extraOverrides,
      ],
    );
    await tester.pump();
    return containerOf(tester);
  }

  testWidgets('shows the empty state when no tree is available', (
    tester,
  ) async {
    await pumpTree(tester, project: config(), buildTree: (ref) async => null);
    await tester.pumpAndSettle();

    expect(find.text('No root folder selected.'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
  });

  testWidgets('shows a progress indicator while the tree loads', (
    tester,
  ) async {
    final completer = Completer<TreeNode?>();
    await pumpTree(
      tester,
      project: config(),
      buildTree: (ref) => completer.future,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows an error state and retry action', (tester) async {
    var calls = 0;
    await pumpTree(
      tester,
      project: config(),
      buildTree: (ref) async {
        calls++;
        throw StateError('scan failed');
      },
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Failed to load directory tree'),
      findsOneWidget,
    );
    expect(find.text('Retry Scan'), findsOneWidget);
    expect(calls, 1);

    await tester.tap(find.text('Retry Scan'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(
      find.textContaining('Failed to load directory tree'),
      findsOneWidget,
    );
  });

  testWidgets('renders collapsed top-level nodes initially', (tester) async {
    await pumpTree(tester, project: config(), buildTree: (ref) async => tree());
    await tester.pumpAndSettle();

    expect(find.text('lib'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);
    expect(find.text('util.dart'), findsNothing);
  });

  testWidgets('expands and collapses directories', (tester) async {
    final container = await pumpTree(
      tester,
      project: config(),
      buildTree: (ref) async => tree(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    expect(container.read(expansionStateProvider)['lib'], isTrue);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('util.dart'), findsOneWidget);

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    expect(container.read(expansionStateProvider)['lib'], isFalse);
    expect(find.text('main.dart'), findsNothing);
  });

  testWidgets('marks selected files in expanded rows', (tester) async {
    await pumpTree(
      tester,
      project: config(includedFiles: ['lib/main.dart']),
      buildTree: (ref) async => tree(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes.where((c) => c.value == true), hasLength(1));
  });

  group('multi-selection toolbar', () {
    testWidgets('appears when paths are highlighted', (tester) async {
      final container = await pumpTree(
        tester,
        project: config(),
        buildTree: (ref) async => tree(),
      );
      await tester.pumpAndSettle();

      container.read(selectedNodePathsProvider.notifier).state = {'lib'};
      await tester.pump();

      expect(find.text('1 items highlighted'), findsOneWidget);
      expect(find.text('Check Selected'), findsOneWidget);
      expect(find.text('Uncheck Selected'), findsOneWidget);
      expect(find.text('Ignore Selected'), findsOneWidget);
    });

    testWidgets('Check Selected includes every descendant file', (
      tester,
    ) async {
      final container = await pumpTree(
        tester,
        project: config(),
        buildTree: (ref) async => tree(),
      );
      await tester.pumpAndSettle();
      container.read(selectedNodePathsProvider.notifier).state = {'lib'};
      await tester.pump();

      await tester.tap(find.text('Check Selected'));
      await tester.pump();
      await flushConfigs(tester);

      expect(
        container.read(selectedConfigProvider)!.includedFiles,
        containsAll(['lib/main.dart', 'lib/util.dart']),
      );
      expect(container.read(selectedNodePathsProvider), isEmpty);
    });

    testWidgets('Uncheck Selected removes every descendant file', (
      tester,
    ) async {
      final container = await pumpTree(
        tester,
        project: config(includedFiles: ['lib/main.dart', 'lib/util.dart']),
        buildTree: (ref) async => tree(),
      );
      await tester.pumpAndSettle();
      container.read(selectedNodePathsProvider.notifier).state = {'lib'};
      await tester.pump();

      await tester.tap(find.text('Uncheck Selected'));
      await tester.pump();
      await flushConfigs(tester);

      expect(container.read(selectedConfigProvider)!.includedFiles, isEmpty);
    });

    testWidgets('Ignore Selected adds directory patterns', (tester) async {
      final container = await pumpTree(
        tester,
        project: config(),
        buildTree: (ref) async => tree(),
      );
      await tester.pumpAndSettle();
      container.read(selectedNodePathsProvider.notifier).state = {'lib'};
      await tester.pump();

      await tester.tap(find.text('Ignore Selected'));
      await tester.pump();
      await flushConfigs(tester);

      expect(
        container.read(selectedConfigProvider)!.ignorePatterns,
        contains('lib/**'),
      );
    });

    testWidgets('clear button empties the highlight set', (tester) async {
      final container = await pumpTree(
        tester,
        project: config(),
        buildTree: (ref) async => tree(),
      );
      await tester.pumpAndSettle();
      container.read(selectedNodePathsProvider.notifier).state = {'lib'};
      await tester.pump();

      await tester.tap(find.byTooltip('Clear Selection'));
      await tester.pump();

      expect(container.read(selectedNodePathsProvider), isEmpty);
      expect(find.text('1 items highlighted'), findsNothing);
    });
  });
}
