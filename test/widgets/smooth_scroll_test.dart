import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/widgets/smooth_scroll.dart';

import '../helpers/test_utils.dart';

void main() {
  testWidgets('renders its builder content inside a scroll view', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Scaffold(
        body: SizedBox(
          height: 400,
          child: SmoothScrollView(
            builder: (context, controller, physics) => ListView(
              controller: controller,
              physics: physics,
              children: const [Text('First item'), Text('Second item')],
            ),
          ),
        ),
      ),
    );

    expect(find.text('First item'), findsOneWidget);
    expect(find.text('Second item'), findsOneWidget);
  });
}
