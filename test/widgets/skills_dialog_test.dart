import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/agent_skill.dart';
import 'package:project_context_generator/models/project_config.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/widgets/skills_dialog.dart';

import '../helpers/test_utils.dart';

void main() {
  const detectedOne = AgentSkill(
    id: 'detected-1',
    name: 'Detected One',
    description: 'First skill',
    content: 'Body one',
  );
  const detectedTwo = AgentSkill(
    id: 'detected-2',
    name: 'Detected Two',
    description: '',
    content: 'Body two',
    sourcePath: 'skills/two.md',
  );
  const customSkill = AgentSkill(
    id: 'custom-existing',
    name: 'Existing Custom',
    description: 'Custom description',
    content: 'Custom body',
    isCustom: true,
  );

  Future<ProviderContainer> pumpSkills(
    WidgetTester tester, {
    ProjectConfig? config,
    List<AgentSkill> detected = const [detectedOne, detectedTwo],
    List<Override> extraOverrides = const [],
  }) async {
    final project =
        config ??
        makeConfig(
          id: 'cfg',
          name: 'Project',
          rootPath: '/repo',
          selectedSkillIds: const ['detected-1'],
        );

    await pumpWithConfigs(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => const SkillsDialog(),
                );
              },
              child: const Text('Open Skills'),
            ),
          ),
        ),
      ),
      configs: [project],
      overrides: [
        fsServiceProvider.overrideWithValue(FakeFsService(skills: detected)),
        ...extraOverrides,
      ],
    );

    await tester.tap(find.text('Open Skills'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();
    return containerOf(tester);
  }

  Future<void> closeDialog(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('lists detected skills with selection counts', (tester) async {
    await pumpSkills(tester);

    expect(find.text('Agent Skills'), findsOneWidget);
    expect(find.text('Detected One'), findsOneWidget);
    expect(find.text('Detected Two'), findsOneWidget);
    expect(find.text('First skill'), findsOneWidget);
    expect(find.text('skills/two.md'), findsOneWidget);
    expect(find.text('1 of 2 skills selected'), findsOneWidget);
    expect(find.text('Detected'), findsNWidgets(2));

    await closeDialog(tester);
  });

  testWidgets('renders custom skills with a Custom badge', (tester) async {
    await pumpSkills(
      tester,
      config: makeConfig(
        id: 'cfg',
        name: 'Project',
        rootPath: '/repo',
        customSkills: const [customSkill],
        selectedSkillIds: const ['custom-existing'],
      ),
    );

    expect(find.text('Existing Custom'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('1 of 3 skills selected'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('toggling a checkbox updates the selection', (tester) async {
    final container = await pumpSkills(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await flushConfigs(tester);

    expect(
      container.read(selectedConfigProvider)!.selectedSkillIds,
      isNot(contains('detected-1')),
    );
    expect(find.text('0 of 2 skills selected'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await flushConfigs(tester);

    expect(
      container.read(selectedConfigProvider)!.selectedSkillIds,
      contains('detected-1'),
    );

    await closeDialog(tester);
  });

  testWidgets('Select All and Deselect All update every skill', (tester) async {
    final container = await pumpSkills(tester);

    await tester.tap(find.text('Select All'));
    await tester.pump();
    await flushConfigs(tester);

    expect(
      container.read(selectedConfigProvider)!.selectedSkillIds,
      containsAll(['detected-1', 'detected-2']),
    );
    expect(find.text('2 of 2 skills selected'), findsOneWidget);

    await tester.tap(find.text('Deselect All'));
    await tester.pump();
    await flushConfigs(tester);

    expect(container.read(selectedConfigProvider)!.selectedSkillIds, isEmpty);
    expect(find.text('0 of 2 skills selected'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('previews skill content in a nested dialog', (tester) async {
    await pumpSkills(tester);

    await tester.tap(find.byIcon(Icons.visibility).first);
    await tester.pumpAndSettle();

    expect(find.text('Detected One'), findsNWidgets(2));
    expect(find.text('Body one'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Body one'), findsNothing);
    expect(find.text('Agent Skills'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('adds a custom skill through the nested dialog', (tester) async {
    final container = await pumpSkills(tester);

    await tester.tap(find.text('Add Custom Skill'));
    await tester.pumpAndSettle();
    expect(find.text('New Custom Skill'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'My Custom');
    await tester.enterText(find.byType(TextField).at(1), 'My description');
    await tester.enterText(find.byType(TextField).at(2), 'My content');
    await tester.tap(find.text('Add Skill'));
    await tester.pumpAndSettle();

    final config = container.read(selectedConfigProvider)!;
    expect(config.customSkills, hasLength(1));
    expect(config.customSkills.single.name, 'My Custom');
    expect(config.customSkills.single.description, 'My description');
    expect(config.customSkills.single.content, 'My content');
    expect(config.customSkills.single.isCustom, isTrue);
    expect(config.selectedSkillIds, contains(config.customSkills.single.id));
    expect(find.text('My Custom'), findsOneWidget);
    expect(find.text('2 of 3 skills selected'), findsOneWidget);

    await flushConfigs(tester);
    await closeDialog(tester);
  });

  testWidgets('blank custom skill names are ignored', (tester) async {
    final container = await pumpSkills(tester);

    await tester.tap(find.text('Add Custom Skill'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '   ');
    await tester.tap(find.text('Add Skill'));
    await tester.pumpAndSettle();

    // Invalid input keeps the editor open instead of silently discarding it.
    expect(find.text('New Custom Skill'), findsOneWidget);
    expect(container.read(selectedConfigProvider)!.customSkills, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('New Custom Skill'), findsNothing);

    await closeDialog(tester);
  });

  testWidgets('custom skill description defaults when omitted', (tester) async {
    final container = await pumpSkills(tester);

    await tester.tap(find.text('Add Custom Skill'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'No Description');
    await tester.tap(find.text('Add Skill'));
    await tester.pumpAndSettle();

    expect(
      container.read(selectedConfigProvider)!.customSkills.single.description,
      'Custom user-defined skill',
    );

    await flushConfigs(tester);
    await closeDialog(tester);
  });

  testWidgets('deletes a custom skill and its selection', (tester) async {
    final container = await pumpSkills(
      tester,
      config: makeConfig(
        id: 'cfg',
        name: 'Project',
        rootPath: '/repo',
        customSkills: const [customSkill],
        selectedSkillIds: const ['custom-existing'],
      ),
    );

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pump();
    await flushConfigs(tester);

    final config = container.read(selectedConfigProvider)!;
    expect(config.customSkills, isEmpty);
    expect(config.selectedSkillIds, isNot(contains('custom-existing')));
    expect(find.text('Existing Custom'), findsNothing);

    await closeDialog(tester);
  });

  testWidgets('shows an empty state when no skills exist', (tester) async {
    await pumpSkills(
      tester,
      detected: const [],
      config: makeConfig(id: 'cfg', name: 'Project', rootPath: '/repo'),
    );

    expect(
      find.text('No agent skills detected in this project.'),
      findsOneWidget,
    );
    expect(find.text('0 of 0 skills selected'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('rescan asks the filesystem service again', (tester) async {
    final fs = FakeFsService(skills: const [detectedOne]);
    await pumpWithConfigs(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const SkillsDialog(),
              ),
              child: const Text('Open Skills'),
            ),
          ),
        ),
      ),
      configs: [makeConfig(id: 'cfg', name: 'Project', rootPath: '/repo')],
      overrides: [fsServiceProvider.overrideWithValue(fs)],
    );
    await tester.tap(find.text('Open Skills'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    final firstCount = fs.detectSkillsCalls;
    expect(firstCount, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump();

    expect(fs.detectSkillsCalls, 2);

    await closeDialog(tester);
  });

  testWidgets('shows a loading state while scanning', (tester) async {
    await pumpSkills(
      tester,
      extraOverrides: [
        detectedSkillsProvider.overrideWith(
          (ref) => Completer<List<AgentSkill>>().future,
        ),
      ],
    );

    expect(find.text('Scanning for agent skills...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('shows an error state when scanning fails', (tester) async {
    await pumpSkills(
      tester,
      extraOverrides: [
        detectedSkillsProvider.overrideWith(
          (ref) async => throw StateError('scan failed'),
        ),
      ],
    );
    await tester.pump();

    expect(find.textContaining('Failed to detect skills'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('Done closes the dialog', (tester) async {
    await pumpSkills(tester);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Agent Skills'), findsNothing);
  });
}
