import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/widgets/snackbar.dart';

import '../helpers/test_utils.dart';

void main() {
  Future<void> pumpSnackButtons(
    WidgetTester tester, {
    required void Function(BuildContext context) show,
  }) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => show(context),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows a success snackbar', (tester) async {
    await pumpSnackButtons(
      tester,
      show: (context) => showSuccessSnackBar(context, 'Saved successfully'),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    expect(find.text('Saved successfully'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('shows an error snackbar', (tester) async {
    await pumpSnackButtons(
      tester,
      show: (context) => showErrorSnackBar(context, 'Something failed'),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    expect(find.text('Something failed'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('shows an info snackbar', (tester) async {
    await pumpSnackButtons(
      tester,
      show: (context) => showInfoSnackBar(context, 'Heads up'),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    expect(find.text('Heads up'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('does not throw when no ScaffoldMessenger is available', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(() => showSuccessSnackBar(captured, 'a'), returnsNormally);
    expect(() => showErrorSnackBar(captured, 'b'), returnsNormally);
    expect(() => showInfoSnackBar(captured, 'c'), returnsNormally);
  });
}
