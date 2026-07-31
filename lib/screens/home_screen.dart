import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project_config.dart';
import '../providers/app_state.dart';
import '../services/fs_service.dart';
import '../widgets/apply_changes_dialog.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/generate_button.dart';
import '../widgets/ignore_list.dart';
import '../widgets/sidebar.dart';
import '../widgets/skills_dialog.dart';
import '../widgets/snackbar.dart';
import '../widgets/tree_view.dart';

/// Intent object handling global shortcut triggers.
class GenerateIntent extends Intent {
  const GenerateIntent();
}

/// Visual primary home screen containing sidebar controls, top header bar, tree view, and status bar.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final ValueNotifier<double> _sidebarWidthNotifier;

  @override
  void initState() {
    super.initState();
    _sidebarWidthNotifier = ValueNotifier<double>(250.0);
    _loadSidebarWidth();
  }

  @override
  void dispose() {
    _sidebarWidthNotifier.dispose();
    super.dispose();
  }

  /// Restores saved workspace layout width parameters safely on widget initialization.
  Future<void> _loadSidebarWidth() async {
    try {
      final configService = ref.read(configServiceProvider);
      final state = await configService.loadWindowState();
      if (state != null && state['sidebarWidth'] != null) {
        final width = (state['sidebarWidth'] as num).toDouble();
        _sidebarWidthNotifier.value = width;
        ref.read(sidebarWidthProvider.notifier).state = width;
      }
    } catch (e) {
      debugPrint('Unable to set saved custom layout dimensions: $e');
    }
  }

  /// Generates prompt context and copies directly to system clipboard for keyboard shortcuts.
  Future<void> _handleGlobalGenerateShortcut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final config = ref.read(selectedConfigProvider);
      if (config == null || config.rootPath.isEmpty) {
        if (context.mounted) {
          showErrorSnackBar(
            context,
            'Please select a valid root folder first.',
          );
        }
        return;
      }

      if (config.includedFiles.isEmpty) {
        if (context.mounted) {
          showErrorSnackBar(
            context,
            'No files selected to include in prompt context.',
          );
        }
        return;
      }

      final fsService = ref.read(fsServiceProvider);
      final selectedSkillIds = config.selectedSkillIds.toSet();
      final allSkills = ref.read(allProjectSkillsProvider);
      final selectedSkills = allSkills
          .where((s) => selectedSkillIds.contains(s.id))
          .toList();

      final params = PromptBuildParams(
        projectName: config.name,
        rootPath: config.rootPath,
        includedFiles: config.includedFiles,
        selectedSkills: selectedSkills,
        ignorePatterns: config.ignorePatterns,
      );

      final result = await fsService.buildPromptContext(params);

      if (result.fileCount == 0) {
        if (context.mounted) {
          showErrorSnackBar(
            context,
            'No files selected or all selected files are ignored.',
          );
        }
        return;
      }

      await Clipboard.setData(ClipboardData(text: result.promptText));

      if (context.mounted) {
        showSuccessSnackBar(
          context,
          'Prompt generated and copied to clipboard! (${result.fileCount} files, ${result.totalLines} lines)',
        );
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, 'Shortcut prompt generation failed: $e');
      }
    }
  }

  /// Recovers altered local parameters, verifying disk updates directly.
  Future<void> _handleCheckChanges(BuildContext context, WidgetRef ref) async {
    ref.invalidate(fileTreeProvider);
    try {
      await ref.read(fileTreeProvider.future);
      if (context.mounted) {
        showInfoSnackBar(
          context,
          'Directory structure updated (new files marked)',
        );
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, 'Failed to update directory structure: $e');
      }
    }
  }

  /// Triggers OS native directory picking mechanisms with safety handlers.
  Future<void> _handleSelectFolder(BuildContext context, WidgetRef ref) async {
    try {
      final String? selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select root folder',
      );
      if (selectedDirectory != null) {
        await ref
            .read(appStateControllerProvider)
            .updateCurrentConfig(rootPath: selectedDirectory);
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, 'Failed to pick directory: $e');
      }
    }
  }

  /// Assembles header details cards showing file state, target folder paths, skills, and action controls.
  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    ProjectConfig config,
  ) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, headerConstraints) {
          final isNarrow = headerConstraints.maxWidth < 880;
          final skillCount = config.selectedSkillIds.length;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isNarrow)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        config.rootPath.isEmpty
                            ? 'No root folder selected'
                            : config.rootPath,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.settings),
                            label: const Text('Ignores'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) =>
                                    IgnoreListDialog(config: config),
                              );
                            },
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.psychology),
                            label: Text(
                              skillCount == 0
                                  ? 'Skills'
                                  : 'Skills ($skillCount)',
                            ),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => const SkillsDialog(),
                              );
                            },
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.build_circle_outlined),
                            label: const Text('Apply Changes'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) =>
                                    ApplyChangesDialog(config: config),
                              );
                            },
                          ),
                          const GenerateButton(),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Check for Changes'),
                            onPressed: () => _handleCheckChanges(context, ref),
                          ),
                          ElevatedButton(
                            onPressed: () => _handleSelectFolder(context, ref),
                            child: const Text('Select Root Folder'),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              config.name,
                              style: Theme.of(context).textTheme.headlineSmall,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.settings),
                            label: const Text('Ignores'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) =>
                                    IgnoreListDialog(config: config),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.psychology),
                            label: Text(
                              skillCount == 0
                                  ? 'Skills'
                                  : 'Skills ($skillCount)',
                            ),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => const SkillsDialog(),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.build_circle_outlined),
                            label: const Text('Apply Changes'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) =>
                                    ApplyChangesDialog(config: config),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          const GenerateButton(),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              config.rootPath.isEmpty
                                  ? 'No root folder selected'
                                  : config.rootPath,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Check for Changes'),
                            onPressed: () => _handleCheckChanges(context, ref),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _handleSelectFolder(context, ref),
                            child: const Text('Select Root Folder'),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(selectedConfigProvider);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyG):
            const GenerateIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyG):
            const GenerateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          GenerateIntent: CallbackAction<GenerateIntent>(
            onInvoke: (intent) {
              _handleGlobalGenerateShortcut(context, ref);
              return null;
            },
          ),
        },
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              const minSidebarWidth = 200.0;
              const minMainWidth = 450.0;

              double maxSidebarWidth = totalWidth - minMainWidth;
              if (maxSidebarWidth < minSidebarWidth) {
                maxSidebarWidth = minSidebarWidth;
              }

              return ValueListenableBuilder<double>(
                valueListenable: _sidebarWidthNotifier,
                builder: (context, currentSidebarWidth, child) {
                  final activeSidebarWidth = currentSidebarWidth.clamp(
                    minSidebarWidth,
                    maxSidebarWidth,
                  );

                  return Row(
                    children: [
                      SizedBox(
                        width: activeSidebarWidth,
                        child: const Sidebar(),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragUpdate: (details) {
                            _sidebarWidthNotifier.value =
                                (_sidebarWidthNotifier.value + details.delta.dx)
                                    .clamp(minSidebarWidth, maxSidebarWidth);
                          },
                          onHorizontalDragEnd: (_) {
                            ref.read(sidebarWidthProvider.notifier).state =
                                _sidebarWidthNotifier.value;
                          },
                          child: SizedBox(
                            width: 12,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(color: Colors.transparent),
                                const VerticalDivider(
                                  width: 12,
                                  thickness: 1.5,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: config == null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.folder_special,
                                        size: 64,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Create or select a project context configuration.',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildHeader(context, ref, config),
                                  const Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      clipBehavior: Clip.hardEdge,
                                      child: ProjectTreeView(),
                                    ),
                                  ),
                                  const BottomBar(),
                                ],
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
