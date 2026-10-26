import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/project_config.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/widgets/ignore_list.dart';

import '../helpers/test_utils.dart';

void main() {
  Future<ProviderContainer> pumpIgnores(
    WidgetTester tester, {
    ProjectConfig? config,
  }) async {
    final project =
        config ??
        makeConfig(
          id: 'cfg',
          name: 'Project',
          rootPath: '/repo',
          ignorePatterns: const ['build/**', '*.log'],
        );

    await pumpWithConfigs(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                final live = ProviderScope.containerOf(
                  context,
                ).read(selectedConfigProvider)!;
                showDialog<void>(
                  context: context,
                  builder: (_) => IgnoreListDialog(config: live),
                );
              },
              child: const Text('Open Ignores'),
            ),
          ),
        ),
      ),
      configs: [project],
    );

    await tester.tap(find.text('Open Ignores'));
    await tester.pump(const Duration(milliseconds: 350));
    return containerOf(tester);
  }

  testWidgets('lists current patterns and presets', (tester) async {
    await pumpIgnores(tester);

    expect(find.text('Ignore Patterns'), findsOneWidget);
    // Each of these patterns is both an active row and a preset chip.
    expect(find.text('build/**'), findsNWidgets(2));
    expect(find.text('*.log'), findsNWidgets(2));
    expect(find.text('Common Presets'), findsOneWidget);
    expect(find.text('node_modules/**'), findsOneWidget);
    expect(find.text('.dart_tool/**'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows an empty state without patterns', (tester) async {
    await pumpIgnores(
      tester,
      config: makeConfig(id: 'cfg', name: 'Project', ignorePatterns: const []),
    );

    expect(find.text('No active ignore patterns.'), findsOneWidget);
    expect(find.text('Common Presets'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('adds a custom pattern and applies it', (tester) async {
    final container = await pumpIgnores(tester);

    await tester.enterText(find.byType(TextField), '**/temp/*');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('**/temp/*'), findsOneWidget);

    await tester.tap(find.text('Apply Changes'));
    await tester.pumpAndSettle();
    await flushConfigs(tester);

    expect(
      container.read(selectedConfigProvider)!.ignorePatterns,
      contains('**/temp/*'),
    );
    expect(find.text('Ignore Patterns'), findsNothing);
  });

  testWidgets('submitting the text field adds a pattern', (tester) async {
    await pumpIgnores(tester);

    await tester.enterText(find.byType(TextField), 'generated/**');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('generated/**'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('ignores blank and duplicate custom patterns', (tester) async {
    await pumpIgnores(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.widgetWithText(ListTile, '   '), findsNothing);

    await tester.enterText(find.byType(TextField), 'build/**');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // No duplicate row was created for the already-present pattern.
    expect(find.widgetWithText(ListTile, 'build/**'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('removing a pattern updates the list', (tester) async {
    final container = await pumpIgnores(tester);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();

    // The active row is gone; build/** remains only as a preset chip.
    expect(find.widgetWithText(ListTile, 'build/**'), findsNothing);
    expect(find.text('build/**'), findsOneWidget);

    await tester.tap(find.text('Apply Changes'));
    await tester.pumpAndSettle();
    await flushConfigs(tester);

    expect(
      container.read(selectedConfigProvider)!.ignorePatterns,
      isNot(contains('build/**')),
    );
  });

  testWidgets('toggles a preset from the preset panel', (tester) async {
    final container = await pumpIgnores(
      tester,
      config: makeConfig(id: 'cfg', name: 'Project', ignorePatterns: const []),
    );

    await tester.tap(find.text('.dart_tool/**'));
    await tester.pump();

    expect(find.text('.dart_tool/**'), findsNWidgets(2));

    await tester.tap(find.text('Apply Changes'));
    await tester.pumpAndSettle();
    await flushConfigs(tester);

    expect(
      container.read(selectedConfigProvider)!.ignorePatterns,
      contains('.dart_tool/**'),
    );
  });

  testWidgets('deselecting a preset removes it', (tester) async {
    final container = await pumpIgnores(
      tester,
      config: makeConfig(
        id: 'cfg',
        name: 'Project',
        ignorePatterns: const ['.dart_tool/**'],
      ),
    );

    await tester.tap(find.widgetWithText(FilterChip, '.dart_tool/**'));
    await tester.pump();

    expect(find.text('.dart_tool/**'), findsOneWidget);

    await tester.tap(find.text('Apply Changes'));
    await tester.pumpAndSettle();
    await flushConfigs(tester);

    expect(container.read(selectedConfigProvider)!.ignorePatterns, isEmpty);
  });

  testWidgets('can hide and show the preset panel', (tester) async {
    await pumpIgnores(tester);

    await tester.tap(find.byIcon(Icons.view_sidebar));
    await tester.pump();

    expect(find.text('Common Presets'), findsNothing);

    await tester.tap(find.byIcon(Icons.view_sidebar_outlined));
    await tester.pump();

    expect(find.text('Common Presets'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancel discards pending changes', (tester) async {
    final container = await pumpIgnores(tester);

    await tester.enterText(find.byType(TextField), 'discarded/**');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      container.read(selectedConfigProvider)!.ignorePatterns,
      isNot(contains('discarded/**')),
    );
    expect(find.text('Ignore Patterns'), findsNothing);
  });
}
