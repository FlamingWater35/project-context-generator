import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:silky_scroll/silky_scroll.dart';

import '../providers/app_state.dart';
import 'file_node.dart';

/// Helper widget wrapping animated switcher transitions in IgnorePointer during animation playback.
class _AnimationIgnorePointer extends StatelessWidget {
  const _AnimationIgnorePointer({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return IgnorePointer(ignoring: !animation.isCompleted, child: child!);
        },
        child: child,
      ),
    );
  }
}

/// Virtualized tree view layout rendering flattened directory items cleanly across responsive viewports with smooth load fade transitions.
class ProjectTreeView extends ConsumerStatefulWidget {
  const ProjectTreeView({super.key});

  @override
  ConsumerState<ProjectTreeView> createState() => _ProjectTreeViewState();
}

class _ProjectTreeViewState extends ConsumerState<ProjectTreeView> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(fileTreeProvider);
    final expansionState = ref.watch(expansionStateProvider);
    final selectedPaths = ref.watch(selectedNodePathsProvider);
    final controller = ref.read(appStateControllerProvider);

    // Precompute active parent directory paths containing checked files in O(N) for O(1) row rendering
    final includedSet = ref.watch(selectedIncludedFilesSetProvider);
    final Set<String> activeParentDirectories = {};
    for (final fileRelPath in includedSet) {
      final parts = fileRelPath.split('/');
      for (int i = 1; i < parts.length; i++) {
        activeParentDirectories.add(parts.sublist(0, i).join('/'));
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) {
        return _AnimationIgnorePointer(animation: animation, child: child);
      },
      child: treeAsync.when(
        data: (rootNode) {
          if (rootNode == null) {
            return Center(
              key: const ValueKey('file_tree_empty'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 48,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No root folder selected.',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                  ),
                ],
              ),
            );
          }

          final flatItems = rootNode.flattenVisibleTree(expansionState);

          int maxDepth = 0;
          for (final item in flatItems) {
            if (item.depth > maxDepth) maxDepth = item.depth;
          }

          return Column(
            key: ValueKey('file_tree_content_${rootNode.path}'),
            children: [
              // Multi-selection Action Toolbar
              if (selectedPaths.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withAlpha(180),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(100),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${selectedPaths.length} items highlighted',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.check_box, size: 16),
                        label: const Text('Check Selected'),
                        onPressed: () {
                          controller.checkFiles(selectedPaths);
                        },
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(
                          Icons.check_box_outline_blank,
                          size: 16,
                        ),
                        label: const Text('Uncheck Selected'),
                        onPressed: () {
                          controller.uncheckFiles(selectedPaths);
                        },
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.visibility_off, size: 16),
                        label: const Text('Ignore Selected'),
                        onPressed: () {
                          controller.addIgnorePatterns(selectedPaths.toList());
                          ref.read(selectedNodePathsProvider.notifier).state =
                              const {};
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Clear Selection',
                        onPressed: () {
                          ref.read(selectedNodePathsProvider.notifier).state =
                              const {};
                        },
                      ),
                    ],
                  ),
                ),

              // Responsive Virtualized ListView File Tree Container with Silky Scroll
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double calculatedWidth = maxDepth * 22.0 + 500.0;
                    final double targetWidth = math.max(
                      constraints.maxWidth,
                      calculatedWidth,
                    );

                    return Scrollbar(
                      controller: _horizontalController,
                      thumbVisibility: true,
                      child: SilkySingleChildScrollView(
                        controller: _horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: targetWidth,
                          height: constraints.maxHeight,
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            child: SilkyListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 6.0,
                              ),
                              itemCount: flatItems.length,
                              itemBuilder: (context, index) {
                                final item = flatItems[index];
                                return RepaintBoundary(
                                  key: ValueKey(item.node.path),
                                  child: FileNodeWidget(
                                    item: item,
                                    activeParentDirectories:
                                        activeParentDirectories,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(
          key: ValueKey('file_tree_loading'),
          child: CircularProgressIndicator(),
        ),
        error: (err, stack) => Center(
          key: const ValueKey('file_tree_error'),
          child: Text(
            'Error building directory tree: $err',
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ),
    );
  }
}
