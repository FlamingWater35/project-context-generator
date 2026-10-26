import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/project_config.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/widgets/sidebar.dart';

import '../helpers/test_utils.dart';

void main() {
  final projects = [
    makeConfig(id: 'alpha', name: 'Alpha', createdAt: DateTime.utc(2024, 1, 1)),
    makeConfig(id: 'beta', name: 'beta', createdAt: DateTime.utc(2024, 1, 2)),
    makeConfig(id: 'gamma', name: 'Gamma', createdAt: DateTime.utc(2024, 1, 3)),
  ];

  Finder dialogTextField() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  List<String> projectOrder(WidgetTester tester) {
    return tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data!)
        .toList();
  }

  Future<void> pumpSidebar(
    WidgetTester tester, {
    List<ProjectConfig> configs = const [],
  }) async {
    await pumpWithConfigs(
      tester,
      const Scaffold(body: Sidebar()),
      configs: configs,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders projects sorted by name ascending', (tester) async {
    await pumpSidebar(tester, configs: projects);

    expect(find.text('Projects'), findsOneWidget);
    expect(projectOrder(tester), ['Alpha', 'beta', 'Gamma']);
  });

  testWidgets('renders an empty project list', (tester) async {
    await pumpSidebar(tester);

    expect(find.text('Projects'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Search projects...'), findsOneWidget);
  });

  testWidgets('sorts descending from the sort menu', (tester) async {
    await pumpSidebar(tester, configs: projects);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name (Z to A)'));
    await tester.pumpAndSettle();

    expect(projectOrder(tester), ['Gamma', 'beta', 'Alpha']);
  });

  testWidgets('sorts by creation date newest and oldest', (tester) async {
    await pumpSidebar(tester, configs: projects);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date (Newest First)'));
    await tester.pumpAndSettle();
    expect(projectOrder(tester), ['Gamma', 'beta', 'Alpha']);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date (Oldest First)'));
    await tester.pumpAndSettle();
    expect(projectOrder(tester), ['Alpha', 'beta', 'Gamma']);
  });

  testWidgets('filters projects by search query and clears the filter', (
    tester,
  ) async {
    await pumpSidebar(tester, configs: projects);

    await tester.enterText(find.byType(TextField), 'be');
    await tester.pumpAndSettle();

    expect(projectOrder(tester), ['beta']);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(projectOrder(tester), ['Alpha', 'beta', 'Gamma']);
  });

  testWidgets('search is case insensitive', (tester) async {
    await pumpSidebar(tester, configs: projects);

    await tester.enterText(find.byType(TextField), 'GAMMA');
    await tester.pumpAndSettle();

    expect(projectOrder(tester), ['Gamma']);
  });

  testWidgets('shows no rows when the search matches nothing', (tester) async {
    await pumpSidebar(tester, configs: projects);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('tapping a project selects it', (tester) async {
    await pumpSidebar(tester, configs: projects);
    final container = containerOf(tester);
    expect(container.read(selectedConfigIdProvider), 'alpha');

    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();

    expect(container.read(selectedConfigIdProvider), 'beta');
    expect(container.read(selectedConfigProvider)!.id, 'beta');
  });

  testWidgets('creates a project through the dialog', (tester) async {
    await pumpSidebar(tester);
    final container = containerOf(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('New Project'), findsOneWidget);

    await tester.enterText(dialogTextField(), '  New Project  ');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final configs = container.read(configsProvider);
    expect(configs, hasLength(1));
    expect(configs.single.name, 'New Project');
    expect(container.read(selectedConfigIdProvider), configs.single.id);
  });

  testWidgets('does not create a project with a blank name', (tester) async {
    await pumpSidebar(tester);
    final container = containerOf(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(dialogTextField(), '   ');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(container.read(configsProvider), isEmpty);
    expect(find.text('New Project'), findsNothing);
  });

  testWidgets('cancelling the create dialog adds nothing', (tester) async {
    await pumpSidebar(tester);
    final container = containerOf(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(dialogTextField(), 'Ignored');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(container.read(configsProvider), isEmpty);
  });

  testWidgets('renames a project through the dialog', (tester) async {
    await pumpSidebar(tester, configs: projects);
    final container = containerOf(tester);

    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();
    expect(find.text('Rename Project'), findsOneWidget);

    await tester.enterText(dialogTextField(), 'Renamed');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await flushConfigs(tester);

    final names = container.read(configsProvider).map((c) => c.name);
    expect(names, contains('Renamed'));
    expect(names, isNot(contains('Alpha')));
  });

  testWidgets('does not rename a project to a blank name', (tester) async {
    await pumpSidebar(tester, configs: projects);
    final container = containerOf(tester);

    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();
    await tester.enterText(dialogTextField(), '   ');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(
      container.read(configsProvider).map((c) => c.name),
      contains('Alpha'),
    );
  });

  testWidgets('deletes a project after confirmation', (tester) async {
    await pumpSidebar(tester, configs: projects);
    final container = containerOf(tester);

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete Project'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Alpha'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(container.read(configsProvider).map((c) => c.id), ['beta', 'gamma']);
    expect(container.read(selectedConfigIdProvider), 'beta');
  });

  testWidgets('cancelling deletion keeps the project', (tester) async {
    await pumpSidebar(tester, configs: projects);
    final container = containerOf(tester);

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(container.read(configsProvider), hasLength(3));
  });
}
