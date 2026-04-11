import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tree_node.dart';
import '../providers/app_state.dart';
import 'file_node.dart';
import 'smooth_scroll.dart';

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

        return LayoutBuilder(
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
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}
