import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/app_state.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  Size windowSize = const Size(1000, 700);
  Offset? windowPosition;
  bool isMaximized = false;
  bool isFullScreen = false;

  try {
    final supportDir = await getApplicationSupportDirectory();
    final file = File(p.join(supportDir.path, 'configs', 'window_state.json'));
    if (await file.exists()) {
      final content = await file.readAsString();
      final state = jsonDecode(content) as Map<String, dynamic>;

      if (state['width'] != null && state['height'] != null) {
        windowSize = Size(state['width'] as double, state['height'] as double);
      }
      if (state['x'] != null && state['y'] != null) {
        windowPosition = Offset(state['x'] as double, state['y'] as double);
      }
      isMaximized = state['isMaximized'] as bool? ?? false;
      isFullScreen = state['isFullScreen'] as bool? ?? false;
    }
  } catch (e) {
    debugPrint('Failed to load window state: $e');
  }

  WindowOptions windowOptions = WindowOptions(
    title: 'Project Context Generator',
    size: windowSize,
    minimumSize: const Size(700, 500),
    center: windowPosition == null,
  );

  await windowManager.setPreventClose(true);

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (windowPosition != null) {
      await windowManager.setPosition(windowPosition);
    }
    if (isMaximized) {
      await windowManager.maximize();
    } else if (isFullScreen) {
      await windowManager.setFullScreen(true);
    }
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: ProjectContextGeneratorApp()));
}

class ProjectContextGeneratorApp extends ConsumerStatefulWidget {
  const ProjectContextGeneratorApp({super.key});

  @override
  ConsumerState<ProjectContextGeneratorApp> createState() =>
      _ProjectContextGeneratorAppState();
}

class _ProjectContextGeneratorAppState
    extends ConsumerState<ProjectContextGeneratorApp>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    try {
      final isMaximized = await windowManager.isMaximized();
      final isFullScreen = await windowManager.isFullScreen();

      double? width;
      double? height;
      double? x;
      double? y;

      if (!isMaximized && !isFullScreen) {
        final size = await windowManager.getSize();
        width = size.width;
        height = size.height;

        final pos = await windowManager.getPosition();
        x = pos.dx;
        y = pos.dy;
      } else {
        final configService = ref.read(configServiceProvider);
        final prevState = await configService.loadWindowState();
        if (prevState != null) {
          width = prevState['width'] as double?;
          height = prevState['height'] as double?;
          x = prevState['x'] as double?;
          y = prevState['y'] as double?;
        }
      }

      final configService = ref.read(configServiceProvider);
      await configService.saveWindowState({
        'width': width,
        'height': height,
        'x': x,
        'y': y,
        'isMaximized': isMaximized,
        'isFullScreen': isFullScreen,
      });
    } catch (e) {
      debugPrint('Failed to save window state: $e');
    }

    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(configsProvider, (prev, next) {
      if (next.isNotEmpty && ref.read(selectedConfigIdProvider) == null) {
        ref.read(appStateControllerProvider).selectConfig(next.first.id);
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
