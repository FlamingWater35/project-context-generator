import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tree_node.dart';
import '../providers/app_state.dart';
import 'file_node.dart';
import 'smooth_scroll.dart';

class _FlatNode {
  _FlatNode(this.node, this.depth);

  final int depth;
  final TreeNode node;
}

class ProjectTreeView extends ConsumerStatefulWidget {
  const ProjectTreeView({super.key});

  @override
  ConsumerState<ProjectTreeView> createState() => _ProjectTreeViewState();
}

class _ProjectTreeViewState extends ConsumerState<ProjectTreeView> {
  final ScrollController _horizontalController = ScrollController();
  int _maxDepth = 0;
  final SmoothScrollController _scrollController = SmoothScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  List<_FlatNode> _flatten(List<TreeNode> nodes, int depth) {
    final expansionState = ref.watch(expansionStateProvider);
    final result = <_FlatNode>[];

    if (depth > _maxDepth) _maxDepth = depth;

    for (final node in nodes) {
      result.add(_FlatNode(node, depth));
      if (node.isDirectory) {
        final isExpanded = expansionState[node.relativePath] ?? false;
        if (isExpanded) {
          result.addAll(_flatten(node.children, depth + 1));
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(fileTreeProvider);
    ref.watch(treeUpdateSignalProvider);
    ref.watch(expansionStateProvider);

    return treeAsync.when(
      data: (rootNode) {
        if (rootNode == null) {
          return const Center(
            child: Text('Please select a valid root folder.'),
          );
        }

        _maxDepth = 0;
        final flatNodes = _flatten(rootNode.children, 0);

        final requiredWidth = _maxDepth * 24.0 + 350.0;

        return LayoutBuilder(
          builder: (context, constraints) {
            return Scrollbar(
              controller: _horizontalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    maxWidth: requiredWidth > constraints.maxWidth
                        ? requiredWidth
                        : constraints.maxWidth,
                  ),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(
                        left: 16.0,
                        right: 24.0,
                        top: 8.0,
                        bottom: 8.0,
                      ),
                      itemCount: flatNodes.length,
                      itemBuilder: (context, index) {
                        final flatNode = flatNodes[index];
                        return FileNodeWidget(
                          key: ValueKey(flatNode.node.path),
                          node: flatNode.node,
                          depth: flatNode.depth,
                        );
                      },
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
