import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tree_node.dart';
import '../providers/app_state.dart';

// Tree node widget representing a filesystem leaf or directories containing folder metadata
class FileNodeWidget extends ConsumerWidget {
  const FileNodeWidget({super.key, required this.node, required this.depth});

  final int depth;
  final TreeNode node;

  // Verifies recursively if any nested child is checked utilizing O(1) Set lookups
  bool _hasIncludedChildren(TreeNode node, Set<String> includedSet) {
    if (!node.isDirectory) return includedSet.contains(node.relativePath);
    for (final child in node.children) {
      if (_hasIncludedChildren(child, includedSet)) return true;
    }
    return false;
  }

  /// Displays granular ignore options popup menu for files or folders
  void _showIgnoreOptionsMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
  ) {
    final controller = ref.read(appStateControllerProvider);
    final List<PopupMenuEntry<String>> items = [];

    if (node.isDirectory) {
      final onlyThisDir = '${node.relativePath}/**';
      final allDirsWithName = '**/${node.name}/**';

      items.addAll([
        PopupMenuItem<String>(
          value: onlyThisDir,
          child: Row(
            children: [
              const Icon(Icons.folder, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Only this directory (${node.relativePath})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: allDirsWithName,
          child: Row(
            children: [
              const Icon(Icons.folder_copy, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'All directories named "${node.name}"',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ]);
    } else {
      final onlyThisFile = node.relativePath;
      final allFilesWithName = '**/${node.name}';

      items.add(
        PopupMenuItem<String>(
          value: onlyThisFile,
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Only this file (${node.relativePath})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );

      items.add(
        PopupMenuItem<String>(
          value: allFilesWithName,
          child: Row(
            children: [
              const Icon(Icons.file_copy, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'All files named "${node.name}"',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );

      final dotIdx = node.name.lastIndexOf('.');
      if (dotIdx > 0 && dotIdx < node.name.length - 1) {
        final ext = node.name.substring(dotIdx);
        final sameExtPattern = '*$ext';
        items.add(
          PopupMenuItem<String>(
            value: sameExtPattern,
            child: Row(
              children: [
                const Icon(
                  Icons.extension,
                  size: 18,
                  color: Colors.purpleAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All files with extension "$ext"',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: items,
    ).then((selectedPattern) {
      if (selectedPattern != null) {
        controller.addIgnorePattern(selectedPattern);
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(selectedConfigProvider);
    if (config == null) return const SizedBox.shrink();

    final expansionState = ref.watch(expansionStateProvider);
    final isExpanded = expansionState[node.relativePath] ?? false;

    final selectedPaths = ref.watch(selectedNodePathsProvider);
    final isHighlighted = selectedPaths.contains(node.relativePath);

    final includedSet = ref.watch(selectedIncludedFilesSetProvider);
    final isIncluded =
        !node.isDirectory && includedSet.contains(node.relativePath);
    final hasIncluded = node.isDirectory
        ? _hasIncludedChildren(node, includedSet)
        : isIncluded;
    final controller = ref.read(appStateControllerProvider);

    return MouseRegion(
      onEnter: (_) {
        if (ref.watch(isTreeDraggingProvider)) {
          final set = Set<String>.from(ref.read(selectedNodePathsProvider));
          set.add(node.relativePath);
          ref.read(selectedNodePathsProvider.notifier).state = set;
        }
      },
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          if (!selectedPaths.contains(node.relativePath)) {
            ref.read(selectedNodePathsProvider.notifier).state = {
              node.relativePath,
            };
          }
          _showIgnoreOptionsMenu(context, ref, details.globalPosition);
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            if (node.isDirectory) {
              controller.toggleNodeExpanded(node.relativePath);
            } else {
              controller.toggleFile(node.relativePath, !isIncluded);
            }
          },
          hoverColor: Colors.white.withAlpha(13),
          splashColor: Colors.white.withAlpha(26),
          highlightColor: Colors.white.withAlpha(13),
          child: Container(
            decoration: BoxDecoration(
              color: isHighlighted
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withAlpha(120)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
            child: Row(
              children: [
                SizedBox(width: depth * 24.0),
                if (node.isDirectory)
                  IconButton(
                    icon: AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: const Icon(Icons.keyboard_arrow_right, size: 20),
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
                    onChanged: (val) {
                      if (val != null) {
                        controller.toggleFile(node.relativePath, val);
                      }
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
                    tooltip: 'Select all existing files',
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
                    tooltip: 'Invert selection (existing files)',
                    onPressed: () => controller.invertSelection(node),
                  ),
                ],
                Builder(
                  builder: (btnContext) => IconButton(
                    icon: Icon(
                      Icons.visibility_off,
                      size: 18,
                      color: Colors.grey.shade500,
                    ),
                    tooltip: 'Ignore Options',
                    onPressed: () {
                      final box = btnContext.findRenderObject() as RenderBox?;
                      final pos = box != null
                          ? box.localToGlobal(Offset.zero)
                          : Offset.zero;
                      _showIgnoreOptionsMenu(context, ref, pos);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
