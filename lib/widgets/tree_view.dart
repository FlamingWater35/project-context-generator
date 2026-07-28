import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tree_node.dart';
import '../providers/app_state.dart';
import 'file_node.dart';
import 'smooth_scroll.dart';

// Nested directory render node that renders folders and subfolders iteratively
class _RecursiveDirectoryNode extends ConsumerWidget {
  const _RecursiveDirectoryNode({
    super.key,
    required this.node,
    required this.depth,
  });

  final int depth;
  final TreeNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expansionState = ref.watch(expansionStateProvider);
    final isExpanded = expansionState[node.relativePath] ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FileNodeWidget(
          key: ValueKey('${node.path}_file'),
          node: node,
          depth: depth,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: isExpanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: node.children.map((child) {
                    if (child.isDirectory) {
                      return _RecursiveDirectoryNode(
                        key: ValueKey(child.path),
                        node: child,
                        depth: depth + 1,
                      );
                    }
                    return FileNodeWidget(
                      key: ValueKey(child.path),
                      node: child,
                      depth: depth + 1,
                    );
                  }).toList(),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// Tree view layout organizing folder hierarchies inside horizontal and vertical scrolls with multi-selection action toolbar
class ProjectTreeView extends ConsumerStatefulWidget {
  const ProjectTreeView({super.key});

  @override
  ConsumerState<ProjectTreeView> createState() => _ProjectTreeViewState();
}

class _ProjectTreeViewState extends ConsumerState<ProjectTreeView> {
  final ScrollController _horizontalController = ScrollController();
  final SmoothScrollController _scrollController = SmoothScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  // Analyzes structural expansion paths to find the maximum horizontal depth
  int _calculateMaxVisibleDepth(
    List<TreeNode> nodes,
    Map<String, bool> expansionState,
    int currentDepth,
  ) {
    int maxD = currentDepth;
    for (final node in nodes) {
      if (currentDepth > maxD) maxD = currentDepth;
      if (node.isDirectory && (expansionState[node.relativePath] ?? false)) {
        final d = _calculateMaxVisibleDepth(
          node.children,
          expansionState,
          currentDepth + 1,
        );
        if (d > maxD) maxD = d;
      }
    }
    return maxD;
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(fileTreeProvider);
    final expansionState = ref.watch(expansionStateProvider);
    final selectedPaths = ref.watch(selectedNodePathsProvider);
    final controller = ref.read(appStateControllerProvider);

    return treeAsync.when(
      data: (rootNode) {
        if (rootNode == null) {
          return const Center(
            child: Text('Please select a valid root folder.'),
          );
        }

        final maxDepth = _calculateMaxVisibleDepth(
          rootNode.children,
          expansionState,
          0,
        );
        final requiredWidth = maxDepth * 24.0 + 350.0;

        return Column(
          children: [
            // Multi-selection Action Toolbar
            if (selectedPaths.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                    color: Theme.of(context).colorScheme.primary.withAlpha(100),
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
                      icon: const Icon(Icons.check_box_outline_blank, size: 16),
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

            // Scrollable File Tree Container
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final targetWidth = requiredWidth > constraints.maxWidth
                      ? requiredWidth
                      : constraints.maxWidth;

                  return Scrollbar(
                    controller: _horizontalController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                          maxWidth: targetWidth,
                        ),
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(
                              left: 16.0,
                              right: 24.0,
                              top: 8.0,
                              bottom: 8.0,
                            ),
                            child: RepaintBoundary(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: rootNode.children.map((child) {
                                  if (child.isDirectory) {
                                    return _RecursiveDirectoryNode(
                                      key: ValueKey(child.path),
                                      node: child,
                                      depth: 0,
                                    );
                                  }
                                  return FileNodeWidget(
                                    key: ValueKey(child.path),
                                    node: child,
                                    depth: 0,
                                  );
                                }).toList(),
                              ),
                            ),
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}
