import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/app_state.dart';
import 'screens/home_screen.dart';

// Entry point initialization of global app layout, window sizes, and state providers
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await windowManager.ensureInitialized();
  } catch (e) {
    debugPrint('Failed to initialize window manager: $e');
  }

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
        windowSize = Size(
          (state['width'] as num).toDouble(),
          (state['height'] as num).toDouble(),
        );
      }
      if (state['x'] != null && state['y'] != null) {
        windowPosition = Offset(
          (state['x'] as num).toDouble(),
          (state['y'] as num).toDouble(),
        );
      }
      isMaximized = state['isMaximized'] as bool? ?? false;
      isFullScreen = state['isFullScreen'] as bool? ?? false;
    }
  } catch (e) {
    debugPrint('Failed to load window state configuration: $e');
  }

  final windowOptions = WindowOptions(
    title: 'Project Context Generator',
    size: windowSize,
    minimumSize: const Size(700, 500),
    center: windowPosition == null,
  );

  try {
    await windowManager.setPreventClose(true);
  } catch (e) {
    debugPrint('Failed to set window close prevention: $e');
  }

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    try {
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
    } catch (e) {
      debugPrint('Failed to configure or show the window container: $e');
    }
  });

  runApp(const ProviderScope(child: ProjectContextGeneratorApp()));
}

// Global root container that manages window close listeners and theme parameters
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
      await windowManager.hide();
    } catch (e) {
      debugPrint('Failed to hide window frame during exit: $e');
    }

    try {
      ref.read(configsProvider.notifier).flush();
    } catch (e) {
      debugPrint('Failed to save pending configurations before exit: $e');
    }

    try {
      final metrics = await Future.wait([
        windowManager.isMaximized(),
        windowManager.isFullScreen(),
        windowManager.getSize(),
        windowManager.getPosition(),
      ]);

      final isMaximized = metrics[0] as bool;
      final isFullScreen = metrics[1] as bool;
      final size = metrics[2] as Size;
      final pos = metrics[3] as Offset;

      double? width;
      double? height;
      double? x;
      double? y;

      if (!isMaximized && !isFullScreen) {
        width = size.width;
        height = size.height;
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

      final sidebarWidth = ref.read(sidebarWidthProvider);
      final configService = ref.read(configServiceProvider);

      await configService.saveWindowState({
        'width': width,
        'height': height,
        'x': x,
        'y': y,
        'isMaximized': isMaximized,
        'isFullScreen': isFullScreen,
        'sidebarWidth': sidebarWidth,
      });
    } catch (e) {
      debugPrint('Failed to serialize and save window configurations: $e');
    }

    try {
      await windowManager.destroy();
    } catch (e) {
      debugPrint('Failed to safely destroy native window context: $e');
    }
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
