import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/main.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/screens/home_screen.dart';

import 'helpers/test_utils.dart';

void main() {
  testWidgets('app boots to the home screen with the dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configServiceProvider.overrideWithValue(MemoryConfigService()),
          fsServiceProvider.overrideWithValue(FakeFsService()),
        ],
        child: const ProjectContextGeneratorApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(
      find.text('Create or select a project context configuration.'),
      findsOneWidget,
    );

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme!.brightness, Brightness.dark);
    expect(materialApp.debugShowCheckedModeBanner, isFalse);
  });

  testWidgets('app shows the selected project on launch', (tester) async {
    final service = MemoryConfigService(
      configs: [
        makeConfig(id: 'cfg', name: 'Launch Project', rootPath: '/repo'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configServiceProvider.overrideWithValue(service),
          fsServiceProvider.overrideWithValue(
            FakeFsService(
              tree: testDir('repo', children: [testFile('README.md')]),
              promptResult: samplePromptResult(),
            ),
          ),
        ],
        child: const ProjectContextGeneratorApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Launch Project'), findsWidgets);
    expect(find.text('Generate & Copy'), findsOneWidget);
    expect(find.text('No root folder selected'), findsNothing);
  });
}
