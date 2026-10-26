import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/project_config.dart';
import 'package:project_context_generator/models/tree_node.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/widgets/file_node.dart';

import '../helpers/test_utils.dart';

void main() {
  Future<ProviderContainer> pumpNode(
    WidgetTester tester, {
    required ProjectConfig config,
    required FlatTreeItem item,
    Set<String> activeParents = const {},
    List<Override> overrides = const [],
  }) async {
    await pumpWithConfigs(
      tester,
      Scaffold(
        body: FileNodeWidget(
          item: item,
          activeParentDirectories: activeParents,
        ),
      ),
      configs: [config],
      overrides: overrides,
    );
    return containerOf(tester);
  }

  ProjectConfig fileConfig({
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

  group('rendering', () {
    testWidgets('renders a file row with checkbox and name', (tester) async {
      await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: testFile('lib/main.dart'),
          depth: 1,
          isExpanded: false,
          hasChildren: false,
        ),
      );

      expect(find.text('main.dart'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(find.byIcon(Icons.code), findsOneWidget);
      expect(find.text('NEW'), findsNothing);
    });

    testWidgets('reflects included files in the checkbox', (tester) async {
      await pumpNode(
        tester,
        config: fileConfig(includedFiles: ['lib/main.dart']),
        item: FlatTreeItem(
          node: testFile('lib/main.dart'),
          depth: 1,
          isExpanded: false,
          hasChildren: false,
        ),
      );

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('shows a NEW badge for newly detected files', (tester) async {
      await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: testFile('lib/main.dart', isNew: true),
          depth: 1,
          isExpanded: false,
          hasChildren: false,
        ),
      );

      expect(find.text('NEW'), findsOneWidget);
    });

    testWidgets('renders a directory row without a checkbox', (tester) async {
      final dir = testDir('lib', children: [testFile('lib/main.dart')]);
      await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: dir,
          depth: 0,
          isExpanded: false,
          hasChildren: true,
        ),
      );

      expect(find.text('lib'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byIcon(Icons.folder), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.folder)).color,
        Colors.amber.shade700,
      );
    });

    testWidgets('uses a blue folder icon when descendants are included', (
      tester,
    ) async {
      final dir = testDir('lib', children: [testFile('lib/main.dart')]);
      await pumpNode(
        tester,
        config: fileConfig(includedFiles: ['lib/main.dart']),
        item: FlatTreeItem(
          node: dir,
          depth: 0,
          isExpanded: false,
          hasChildren: true,
        ),
        activeParents: {'lib'},
      );

      expect(
        tester.widget<Icon>(find.byIcon(Icons.folder)).color,
        Colors.blue.shade400,
      );
    });

    testWidgets('renders distinct icons for common file extensions', (
      tester,
    ) async {
      final cases = <String, IconData>{
        'main.dart': Icons.code,
        'app.js': Icons.javascript,
        'app.tsx': Icons.javascript,
        'app.py': Icons.terminal,
        'index.html': Icons.html,
        'style.scss': Icons.html,
        'data.json': Icons.data_object,
        'README.md': Icons.article,
        'logo.png': Icons.image,
        'pubspec.lock': Icons.lock_clock,
        'unknown.xyz': Icons.insert_drive_file,
      };

      for (final entry in cases.entries) {
        await pumpNode(
          tester,
          config: fileConfig(),
          item: FlatTreeItem(
            node: testFile('lib/${entry.key}'),
            depth: 1,
            isExpanded: false,
            hasChildren: false,
          ),
        );

        expect(
          find.byIcon(entry.value),
          findsOneWidget,
          reason: 'icon for ${entry.key}',
        );
      }
    });
  });

  group('selection interactions', () {
    testWidgets('tapping a file toggles its inclusion', (tester) async {
      final container = await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: testFile('lib/main.dart'),
          depth: 1,
          isExpanded: false,
          hasChildren: false,
        ),
      );

      await tester.tap(find.text('main.dart'));
      await tester.pump();
      await flushConfigs(tester);

      expect(
        container.read(selectedConfigProvider)!.includedFiles,
        contains('lib/main.dart'),
      );

      await tester.tap(find.text('main.dart'));
      await tester.pump();
      await flushConfigs(tester);

      expect(
        container.read(selectedConfigProvider)!.includedFiles,
        isNot(contains('lib/main.dart')),
      );
    });

    testWidgets('tapping the checkbox toggles inclusion', (tester) async {
      final container = await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: testFile('lib/main.dart'),
          depth: 1,
          isExpanded: false,
          hasChildren: false,
        ),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await flushConfigs(tester);

      expect(
        container.read(selectedConfigProvider)!.includedFiles,
        contains('lib/main.dart'),
      );
    });

    testWidgets('tapping a directory toggles its expansion state', (
      tester,
    ) async {
      final container = await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: testDir('lib', children: [testFile('lib/main.dart')]),
          depth: 0,
          isExpanded: false,
          hasChildren: true,
        ),
      );

      await tester.tap(find.text('lib'));
      await tester.pump();

      expect(container.read(expansionStateProvider)['lib'], isTrue);
    });

    testWidgets('long press activates multi-select highlighting', (
      tester,
    ) async {
      final container = await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: testFile('lib/main.dart'),
          depth: 1,
          isExpanded: false,
          hasChildren: false,
        ),
      );

      await tester.longPress(find.text('main.dart'));
      await tester.pump();

      expect(container.read(selectedNodePathsProvider), {'lib/main.dart'});
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      // Multi-select disables the inline checkbox and ignore action.
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.visibility_off),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('main.dart'));
      await tester.pump();

      expect(container.read(selectedNodePathsProvider), isEmpty);
    });

    testWidgets('highlight button toggles multi-select without long press', (
      tester,
    ) async {
      final container = await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: testFile('lib/main.dart'),
          depth: 1,
          isExpanded: false,
          hasChildren: false,
        ),
      );

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.check_circle_outline),
      );
      await tester.pump();

      expect(container.read(selectedNodePathsProvider), {'lib/main.dart'});
    });
  });

  group('ignore options', () {
    testWidgets('file menu offers file name and extension patterns', (
      tester,
    ) async {
      final container = await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: testFile('lib/main.dart'),
          depth: 1,
          isExpanded: false,
          hasChildren: false,
        ),
      );

      await tester.tap(find.widgetWithIcon(IconButton, Icons.visibility_off));
      await tester.pumpAndSettle();

      expect(find.text('Only this file (lib/main.dart)'), findsOneWidget);
      expect(find.text('All files named "main.dart"'), findsOneWidget);
      expect(find.text('All files with extension ".dart"'), findsOneWidget);

      await tester.tap(find.text('Only this file (lib/main.dart)'));
      await tester.pumpAndSettle();
      await flushConfigs(tester);

      expect(
        container.read(selectedConfigProvider)!.ignorePatterns,
        contains('lib/main.dart'),
      );
    });

    testWidgets('directory menu offers directory-wide patterns', (
      tester,
    ) async {
      final container = await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: testDir('lib', children: [testFile('lib/main.dart')]),
          depth: 0,
          isExpanded: false,
          hasChildren: true,
        ),
      );

      await tester.tap(find.widgetWithIcon(IconButton, Icons.visibility_off));
      await tester.pumpAndSettle();

      expect(find.text('Only this directory (lib)'), findsOneWidget);
      expect(find.text('All directories named "lib"'), findsOneWidget);

      await tester.tap(find.text('All directories named "lib"'));
      await tester.pumpAndSettle();
      await flushConfigs(tester);

      expect(
        container.read(selectedConfigProvider)!.ignorePatterns,
        contains('**/lib/**'),
      );
    });

    testWidgets('directory popup can select every contained file', (
      tester,
    ) async {
      final container = await pumpNode(
        tester,
        config: fileConfig(),
        item: FlatTreeItem(
          node: testDir('lib', children: [testFile('lib/main.dart')]),
          depth: 0,
          isExpanded: false,
          hasChildren: true,
        ),
      );

      await tester.tap(find.byIcon(Icons.done_all));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all contained files'));
      await tester.pumpAndSettle();
      await flushConfigs(tester);

      expect(
        container.read(selectedConfigProvider)!.includedFiles,
        contains('lib/main.dart'),
      );
    });

    testWidgets('directory popup can deselect every contained file', (
      tester,
    ) async {
      final container = await pumpNode(
        tester,
        config: fileConfig(includedFiles: ['lib/main.dart']),
        item: FlatTreeItem(
          node: testDir('lib', children: [testFile('lib/main.dart')]),
          depth: 0,
          isExpanded: false,
          hasChildren: true,
        ),
      );

      await tester.tap(find.byIcon(Icons.done_all));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deselect all contained files'));
      await tester.pumpAndSettle();
      await flushConfigs(tester);

      expect(container.read(selectedConfigProvider)!.includedFiles, isEmpty);
    });

    testWidgets('directory popup can invert the selection', (tester) async {
      final container = await pumpNode(
        tester,
        config: fileConfig(includedFiles: ['lib/main.dart']),
        item: FlatTreeItem(
          node: testDir('lib', children: [testFile('lib/main.dart')]),
          depth: 0,
          isExpanded: false,
          hasChildren: true,
        ),
      );

      await tester.tap(find.byIcon(Icons.done_all));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invert selection'));
      await tester.pumpAndSettle();
      await flushConfigs(tester);

      expect(container.read(selectedConfigProvider)!.includedFiles, isEmpty);
    });
  });
}
