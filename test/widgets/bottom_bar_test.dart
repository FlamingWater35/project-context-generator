import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/services/fs_service.dart';
import 'package:project_context_generator/widgets/bottom_bar.dart';

import '../helpers/test_utils.dart';

void main() {
  Future<void> pumpBottomBar(
    WidgetTester tester,
    AsyncValue<PromptBuildResult?> stats,
  ) async {
    await pumpApp(
      tester,
      const Scaffold(body: BottomBar()),
      overrides: [promptStatsProvider.overrideWithValue(stats)],
    );
  }

  testWidgets('renders the empty state when stats are null', (tester) async {
    await pumpBottomBar(tester, const AsyncData(null));

    expect(find.text('No files selected'), findsOneWidget);
    expect(find.text('0 files | 0 lines | 0 B | ~0 tokens'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders the empty state when zero files are selected', (
    tester,
  ) async {
    await pumpBottomBar(tester, AsyncData(samplePromptResult(fileCount: 0)));

    expect(find.text('No files selected'), findsOneWidget);
  });

  testWidgets('renders file, skill, line, size, and token metrics', (
    tester,
  ) async {
    final prompt = 'a' * 4000;
    await pumpBottomBar(
      tester,
      AsyncData(
        samplePromptResult(
          promptText: prompt,
          fileCount: 2,
          skillCount: 1,
          totalLines: 10,
        ),
      ),
    );

    expect(find.text('2 files selected'), findsOneWidget);
    expect(find.text('1 skills'), findsOneWidget);
    expect(find.text('10 lines'), findsOneWidget);
    // 4000 characters -> 3.9 KB and ~1000 tokens -> 1.0k.
    expect(find.text('3.9 KB'), findsOneWidget);
    expect(find.text('~1.0k tokens'), findsOneWidget);
  });

  testWidgets('hides the skills metric when no skills are selected', (
    tester,
  ) async {
    await pumpBottomBar(
      tester,
      AsyncData(
        samplePromptResult(promptText: 'abc', fileCount: 1, totalLines: 1),
      ),
    );

    expect(find.text('1 files selected'), findsOneWidget);
    expect(find.textContaining('skills'), findsNothing);
    expect(find.text('3 B'), findsOneWidget);
    expect(find.text('~1 tokens'), findsOneWidget);
  });

  testWidgets('renders byte sizes below one kilobyte verbatim', (tester) async {
    await pumpBottomBar(
      tester,
      AsyncData(
        samplePromptResult(promptText: 'a' * 500, fileCount: 1, totalLines: 3),
      ),
    );

    expect(find.text('500 B'), findsOneWidget);
    expect(find.text('~125 tokens'), findsOneWidget);
  });

  testWidgets('renders megabyte sizes with two decimals', (tester) async {
    await pumpBottomBar(
      tester,
      AsyncData(
        samplePromptResult(
          promptText: 'a' * (2 * 1024 * 1024),
          fileCount: 3,
          totalLines: 5,
        ),
      ),
    );

    expect(find.text('2.00 MB'), findsOneWidget);
    expect(find.text('~524.3k tokens'), findsOneWidget);
  });

  testWidgets('renders the loading state', (tester) async {
    await pumpBottomBar(tester, const AsyncLoading());

    expect(find.text('Calculating prompt metrics...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders the error state', (tester) async {
    await pumpBottomBar(
      tester,
      AsyncError(StateError('boom'), StackTrace.current),
    );

    expect(find.text('Error calculating metrics'), findsOneWidget);
  });
}
