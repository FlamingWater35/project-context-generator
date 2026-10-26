import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/widgets/apply_changes_dialog.dart';

import '../helpers/test_utils.dart';

typedef DialogSetup = ({
  FakeClipboard clipboard,
  FakeFsService fs,
  Directory root,
  ProviderContainer container,
});

void main() {
  const llmResponse = r'''
### File: lib/new.dart
```dart
void main() => print('new');
```
''';

  const twoFileResponse = r'''
### File: lib/a.dart
```dart
final a = 1;
```

### File: lib/b.dart
```dart
final b = 2;
```
''';

  Future<void> drainSnackBars(WidgetTester tester) async {
    // Avoid pumpAndSettle here: the listening badge keeps a spinner animating.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  }

  Future<DialogSetup> pumpDialog(
    WidgetTester tester, {
    FakeClipboard? clipboard,
    FakeFsService? fs,
    Directory? root,
    List<String> includedFiles = const ['lib/new.dart'],
    String? clipboardBaseline,
  }) async {
    final baseDir = root ?? createTempDir('pcg_apply_');
    final fakeFs = fs ?? FakeFsService(paths: {'lib/new.dart'});
    final fakeClipboard = clipboard ?? FakeClipboard(clipboardBaseline);
    fakeClipboard.install(tester);
    final config = makeConfig(
      id: 'cfg',
      name: 'Project',
      rootPath: baseDir.path,
      includedFiles: includedFiles,
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
                  builder: (_) => ApplyChangesDialog(config: live),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
      configs: [config],
      overrides: [fsServiceProvider.overrideWithValue(fakeFs)],
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pump(const Duration(milliseconds: 350));

    return (
      clipboard: fakeClipboard,
      fs: fakeFs,
      root: baseDir,
      container: containerOf(tester),
    );
  }

  Future<void> closeDialog(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('renders the empty state and listening indicator', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.text('Apply Code Changes'), findsOneWidget);
    expect(find.text('No code changes detected yet.'), findsOneWidget);
    expect(find.text('Listening to clipboard...'), findsOneWidget);
    expect(find.text('Stop Listening'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('parses manual clipboard content into a new-file change', (
    tester,
  ) async {
    final clipboard = FakeClipboard(llmResponse);
    await pumpDialog(tester, clipboard: clipboard);

    await tester.tap(find.text('Paste Manual'));
    await tester.pumpAndSettle();

    expect(find.text('Changed Files (1)'), findsOneWidget);
    expect(find.text('new.dart'), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text("void main() => print('new');"), findsOneWidget);
    expect(find.textContaining('1 of 1 changes selected'), findsOneWidget);
    expect(
      find.text('Detected 1 file change(s) from clipboard!'),
      findsOneWidget,
    );

    await drainSnackBars(tester);
    await closeDialog(tester);
  });

  testWidgets('reports an empty clipboard for manual paste', (tester) async {
    final clipboard = FakeClipboard();
    await pumpDialog(tester, clipboard: clipboard);

    await tester.tap(find.text('Paste Manual'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Clipboard is empty.'), findsOneWidget);
    expect(find.text('No code changes detected yet.'), findsOneWidget);

    await drainSnackBars(tester);
    await closeDialog(tester);
  });

  testWidgets('applies a new file to disk and closes', (tester) async {
    final clipboard = FakeClipboard(llmResponse);
    final setup = await pumpDialog(tester, clipboard: clipboard);

    await tester.tap(find.text('Paste Manual'));
    await tester.pumpAndSettle();
    // Let the detection snackbar expire so the apply snackbar can be shown.
    await drainSnackBars(tester);
    await tester.tap(find.text('Apply Changes'));
    await pumpUntil(
      tester,
      () => File('${setup.root.path}/lib/new.dart').existsSync(),
      description: 'new file written',
    );
    await pumpUntil(
      tester,
      () => find.text('Apply Code Changes').evaluate().isEmpty,
      description: 'dialog close',
    );
    await tester.pump(const Duration(milliseconds: 100));

    final file = File('${setup.root.path}/lib/new.dart');
    expect(file.readAsStringSync(), "void main() => print('new');");
    expect(find.text('Apply Code Changes'), findsNothing);
    expect(
      find.text('Successfully applied changes to 1 file(s)!'),
      findsOneWidget,
    );
    expect(setup.fs.scanPathsCalls, greaterThanOrEqualTo(1));

    await drainSnackBars(tester);
  });

  testWidgets('marks existing files as modified and overwrites them', (
    tester,
  ) async {
    final root = createTempDir('pcg_apply_existing_');
    writeFile(root, 'lib/existing.dart', 'old content');
    final clipboard = FakeClipboard(r'''
### File: lib/existing.dart
```dart
new content
```
''');
    final setup = await pumpDialog(
      tester,
      clipboard: clipboard,
      root: root,
      includedFiles: const ['lib/existing.dart'],
    );

    await tester.tap(find.text('Paste Manual'));
    await tester.pumpAndSettle();

    expect(find.text('MODIFIED'), findsOneWidget);
    expect(find.text('NEW'), findsNothing);
    await drainSnackBars(tester);

    await tester.tap(find.text('Apply Changes'));
    await pumpUntil(
      tester,
      () =>
          File('${setup.root.path}/lib/existing.dart').existsSync() &&
          File('${setup.root.path}/lib/existing.dart').readAsStringSync() ==
              'new content',
      description: 'existing file overwritten',
    );

    expect(
      File('${setup.root.path}/lib/existing.dart').readAsStringSync(),
      'new content',
    );
    await drainSnackBars(tester);
  });

  testWidgets('deselect all disables Apply and select all re-enables it', (
    tester,
  ) async {
    final clipboard = FakeClipboard(twoFileResponse);
    await pumpDialog(tester, clipboard: clipboard);

    await tester.tap(find.text('Paste Manual'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 changes selected'), findsOneWidget);

    await tester.tap(find.text('Deselect All'));
    await tester.pump();

    expect(find.text('0 of 2 changes selected'), findsOneWidget);
    final disabledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply Changes'),
    );
    expect(disabledButton.onPressed, isNull);

    await tester.tap(find.text('Select All'));
    await tester.pump();

    expect(find.text('2 of 2 changes selected'), findsOneWidget);
    final enabledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply Changes'),
    );
    expect(enabledButton.onPressed, isNotNull);

    await drainSnackBars(tester);
    await closeDialog(tester);
  });

  testWidgets('only selected changes are written', (tester) async {
    final clipboard = FakeClipboard(twoFileResponse);
    final setup = await pumpDialog(tester, clipboard: clipboard);

    await tester.tap(find.text('Paste Manual'));
    await tester.pumpAndSettle();
    await drainSnackBars(tester);

    // Uncheck the first change (lib/a.dart).
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('1 of 2 changes selected'), findsOneWidget);

    await tester.tap(find.text('Apply Changes'));
    await pumpUntil(
      tester,
      () => File('${setup.root.path}/lib/b.dart').existsSync(),
      description: 'selected file written',
    );
    await pumpUntil(
      tester,
      () => find.text('Apply Code Changes').evaluate().isEmpty,
      description: 'dialog close',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(File('${setup.root.path}/lib/a.dart').existsSync(), isFalse);
    expect(
      File('${setup.root.path}/lib/b.dart').readAsStringSync(),
      'final b = 2;',
    );
    expect(
      find.text('Successfully applied changes to 1 file(s)!'),
      findsOneWidget,
    );

    await drainSnackBars(tester);
  });

  testWidgets('detects new clipboard content while listening', (tester) async {
    final clipboard = FakeClipboard('baseline text');
    await pumpDialog(tester, clipboard: clipboard);

    expect(find.text('Listening to clipboard...'), findsOneWidget);

    clipboard.text = llmResponse;
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();

    expect(find.text('Changed Files (1)'), findsOneWidget);
    expect(find.text('new.dart'), findsOneWidget);
    expect(find.text('Listening to clipboard...'), findsNothing);
    expect(find.text('Start Listening'), findsOneWidget);
    expect(
      find.text('Detected 1 file change(s) from clipboard!'),
      findsOneWidget,
    );

    await drainSnackBars(tester);
    await closeDialog(tester);
  });

  testWidgets('stops listening on demand', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('Stop Listening'));
    await tester.pump();

    expect(find.text('Listening to clipboard...'), findsNothing);
    expect(find.text('Start Listening'), findsOneWidget);

    await tester.tap(find.text('Start Listening'));
    await tester.pump();

    expect(find.text('Listening to clipboard...'), findsOneWidget);

    await closeDialog(tester);
  });

  testWidgets('cancel closes without writing files', (tester) async {
    final clipboard = FakeClipboard(llmResponse);
    final setup = await pumpDialog(tester, clipboard: clipboard);

    await tester.tap(find.text('Paste Manual'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Apply Code Changes'), findsNothing);
    expect(File('${setup.root.path}/lib/new.dart').existsSync(), isFalse);

    await drainSnackBars(tester);
  });
}
