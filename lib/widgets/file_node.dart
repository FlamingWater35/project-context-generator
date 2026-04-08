import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tree_node.dart';
import '../providers/app_state.dart';

class FileNodeWidget extends ConsumerWidget {
  final TreeNode node;
  final int depth;

  const FileNodeWidget({
    super.key,
    required this.node,
    required this.depth,
  });

  bool _hasIncludedChildren(TreeNode node, List<String> includedFiles) {
    if (!node.isDirectory) {
      return includedFiles.contains(node.relativePath);
    }
    for (final child in node.children) {
      if (_hasIncludedChildren(child, includedFiles)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(selectedConfigProvider);
    if (config == null) return const SizedBox.shrink();

    final isIncluded = !node.isDirectory && config.includedFiles.contains(node.relativePath);
    final hasIncluded = node.isDirectory ? _hasIncludedChildren(node, config.includedFiles) : isIncluded;

    final controller = ref.read(appStateControllerProvider);

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        if (node.isDirectory) {
          controller.toggleNodeExpanded(node);
        } else {
          controller.toggleFile(node.relativePath, !isIncluded);
        }
      },
      hoverColor: Colors.white.withOpacity(0.05),
      splashColor: Colors.white.withOpacity(0.1),
      highlightColor: Colors.white.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
        child: Row(
          children:[
            SizedBox(width: depth * 24.0),
            if (node.isDirectory)
              IconButton(
                icon: Icon(node.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 20),
                onPressed: () => controller.toggleNodeExpanded(node),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: hasIncluded ? null : Colors.grey.shade600,
              )
            else
              const SizedBox(width: 20),

            if (!node.isDirectory)
              Checkbox(
                visualDensity: VisualDensity.compact,
                value: isIncluded,
                onChanged: (val) {
                  controller.toggleFile(node.relativePath, val ?? false);
                },
              ),

            Icon(
              node.isDirectory ? Icons.folder : Icons.insert_drive_file,
              size: 20,
              color: node.isDirectory
                  ? (hasIncluded ? Colors.blue : Colors.grey.shade600)
                  : (isIncluded ? Colors.white : Colors.grey.shade600),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.name,
                style: TextStyle(
                  color: hasIncluded || isIncluded ? Colors.white : Colors.grey.shade500,
                  fontWeight: isIncluded ? FontWeight.bold : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            if (node.isDirectory) ...[
              IconButton(
                icon: Icon(Icons.check_box, size: 18, color: Colors.grey.shade500),
                tooltip: 'Select all',
                onPressed: () => controller.selectAll(node),
                splashRadius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                icon: Icon(Icons.check_box_outline_blank, size: 18, color: Colors.grey.shade500),
                tooltip: 'Select none',
                onPressed: () => controller.selectNone(node),
                splashRadius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                icon: Icon(Icons.swap_horiz, size: 18, color: Colors.grey.shade500),
                tooltip: 'Invert selection',
                onPressed: () => controller.invertSelection(node),
                splashRadius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
