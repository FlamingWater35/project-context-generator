import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tree_node.dart';
import '../providers/app_state.dart';

class FileNodeWidget extends ConsumerWidget {
  const FileNodeWidget({super.key, required this.node, required this.depth});

  final int depth;
  final TreeNode node;

  bool _hasIncludedChildren(TreeNode node, List<String> includedFiles) {
    if (!node.isDirectory) return includedFiles.contains(node.relativePath);
    for (final child in node.children) {
      if (_hasIncludedChildren(child, includedFiles)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(selectedConfigProvider);
    if (config == null) return const SizedBox.shrink();

    final expansionState = ref.watch(expansionStateProvider);
    final isExpanded = expansionState[node.relativePath] ?? false;

    final isIncluded =
        !node.isDirectory && config.includedFiles.contains(node.relativePath);
    final hasIncluded = node.isDirectory
        ? _hasIncludedChildren(node, config.includedFiles)
        : isIncluded;
    final controller = ref.read(appStateControllerProvider);

    String ignorePattern = node.isDirectory
        ? '${node.relativePath}/**'
        : (() {
            int firstDot = node.name.indexOf('.', 1);
            if (firstDot != -1) {
              return '*${node.name.substring(firstDot)}';
            }
            return node.relativePath;
          })();

    String tooltip = node.isDirectory
        ? 'Ignore directory'
        : 'Ignore all files with this extension ($ignorePattern)';

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => node.isDirectory
          ? controller.toggleNodeExpanded(node.relativePath)
          : controller.toggleFile(node.relativePath, !isIncluded),
      hoverColor: Colors.white.withAlpha(13),
      splashColor: Colors.white.withAlpha(26),
      highlightColor: Colors.white.withAlpha(13),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
        child: Row(
          children: [
            SizedBox(width: depth * 24.0),
            if (node.isDirectory)
              IconButton(
                icon: Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 20,
                ),
                onPressed: () =>
                    controller.toggleNodeExpanded(node.relativePath),
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
                onChanged: (val) =>
                    controller.toggleFile(node.relativePath, val ?? false),
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
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      node.name,
                      style: TextStyle(
                        color: hasIncluded || isIncluded
                            ? Colors.white
                            : Colors.grey.shade500,
                        fontWeight: isIncluded ? FontWeight.bold : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (node.isNew) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade800,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (node.isDirectory) ...[
              IconButton(
                icon: Icon(
                  Icons.check_box,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
                tooltip: 'Select all',
                onPressed: () => controller.selectAll(node),
              ),
              IconButton(
                icon: Icon(
                  Icons.check_box_outline_blank,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
                tooltip: 'Select none',
                onPressed: () => controller.selectNone(node),
              ),
              IconButton(
                icon: Icon(
                  Icons.swap_horiz,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
                tooltip: 'Invert selection',
                onPressed: () => controller.invertSelection(node),
              ),
            ],
            IconButton(
              icon: Icon(
                Icons.visibility_off,
                size: 18,
                color: Colors.grey.shade500,
              ),
              tooltip: tooltip,
              onPressed: () => controller.addIgnorePattern(ignorePattern),
            ),
          ],
        ),
      ),
    );
  }
}
