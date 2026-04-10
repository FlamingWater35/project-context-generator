import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/app_state.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    title: 'Project Context Generator',
    size: Size(1000, 700),
    minimumSize: Size(700, 500),
    center: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: ProjectContextGeneratorApp()));
}

class ProjectContextGeneratorApp extends ConsumerWidget {
  const ProjectContextGeneratorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(configsProvider, (prev, next) {
      if (next.isNotEmpty && ref.read(selectedConfigIdProvider) == null) {
        ref.read(appStateControllerProvider).selectConfig(next.first.id);
      }
    });

    ref.listen(selectedConfigIdProvider, (prev, next) {
      if (next != null && prev != next) {
        ref.read(appStateControllerProvider).selectConfig(next);
      }
    });

    return MaterialApp(
      title: 'Project Context Generator',
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
