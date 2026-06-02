import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project_config.dart';
import '../providers/app_state.dart';
import '../widgets/generate_button.dart';
import '../widgets/ignore_list.dart';
import '../widgets/sidebar.dart';
import '../widgets/snackbar.dart';
import '../widgets/tree_view.dart';

// Visual primary home screen containing sidebar controls and the project workspace tree view
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _sidebarWidth = 250.0;

  @override
  void initState() {
    super.initState();
    _loadSidebarWidth();
  }

  // Restores saved workspace layout width parameters safely on widget initialization
  Future<void> _loadSidebarWidth() async {
    try {
      final configService = ref.read(configServiceProvider);
      final state = await configService.loadWindowState();
      if (state != null && state['sidebarWidth'] != null) {
        final width = (state['sidebarWidth'] as num).toDouble();
        if (mounted) {
          setState(() {
            _sidebarWidth = width;
          });
        }
        ref.read(sidebarWidthProvider.notifier).state = width;
      }
    } catch (e) {
      debugPrint('Unable to set saved custom layout dimensions: $e');
    }
  }

  // Recovers altered local parameters, verifying disk updates directly
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

  // Triggers OS native directory picking mechanisms with safety handlers
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

  // Assembles header details cards showing file state, target folder paths, and action controls
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
          final isNarrow = headerConstraints.maxWidth < 600;

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
                          const SizedBox(width: 16),
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

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          const minSidebarWidth = 200.0;
          const minMainWidth = 450.0;

          double maxSidebarWidth = totalWidth - minMainWidth;
          if (maxSidebarWidth < minSidebarWidth) {
            maxSidebarWidth = minSidebarWidth;
          }

          final activeSidebarWidth = _sidebarWidth.clamp(
            minSidebarWidth,
            maxSidebarWidth,
          );

          return Row(
            children: [
              SizedBox(width: activeSidebarWidth, child: const Sidebar()),
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(
                        minSidebarWidth,
                        maxSidebarWidth,
                      );
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    ref.read(sidebarWidthProvider.notifier).state =
                        _sidebarWidth;
                  },
                  child: SizedBox(
                    width: 12,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(color: Colors.transparent),
                        const VerticalDivider(width: 12, thickness: 1.5),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: config == null
                    ? const Center(
                        child: Text('Create or select a project config.'),
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
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
