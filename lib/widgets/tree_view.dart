import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tree_node.dart';
import '../providers/app_state.dart';
import 'file_node.dart';

// Helper class to hold a flattened node and its visual depth
class _FlatNode {
  final TreeNode node;
  final int depth;
  _FlatNode(this.node, this.depth);
}

class ProjectTreeView extends ConsumerStatefulWidget {
  const ProjectTreeView({super.key});

  @override
  ConsumerState<ProjectTreeView> createState() => _ProjectTreeViewState();
}

class _ProjectTreeViewState extends ConsumerState<ProjectTreeView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Flattens the nested tree into a 1D list of visible rows based on expansion state
  List<_FlatNode> _flatten(List<TreeNode> nodes, int depth) {
    final result = <_FlatNode>[];
    for (final node in nodes) {
      result.add(_FlatNode(node, depth));
      if (node.isDirectory && node.isExpanded) {
        result.addAll(_flatten(node.children, depth + 1));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(fileTreeProvider);
    ref.watch(treeUpdateSignalProvider); // Ensure ui rebuilds strictly on local expansion change

    return treeAsync.when(
      data: (rootNode) {
        if (rootNode == null) {
          return const Center(child: Text('Please select a valid root folder.'));
        }

        final flatNodes = _flatten(rootNode.children, 0);

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            // Right padding prevents overlaying content on the thumb track
            padding: const EdgeInsets.only(left: 16.0, right: 24.0, top: 8.0, bottom: 8.0),
            itemCount: flatNodes.length,
            itemBuilder: (context, index) {
              final flatNode = flatNodes[index];
              return FileNodeWidget(
                // ValueKey ensures Flutter efficiently updates specific rows instead of recreating them
                key: ValueKey(flatNode.node.path),
                node: flatNode.node,
                depth: flatNode.depth,
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}
