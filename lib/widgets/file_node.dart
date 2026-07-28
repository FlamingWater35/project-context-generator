import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tree_node.dart';
import '../providers/app_state.dart';

/// Renders an individual tree node row item with file-type-aware icons, depth indentation guide lines, and inline action buttons.
class FileNodeWidget extends ConsumerWidget {
  const FileNodeWidget({super.key, required this.item});

  final FlatTreeItem item;

  /// Helper evaluating file extension or folder type to return distinct visual icons.
  Widget _buildNodeIcon(
    BuildContext context,
    bool isIncluded,
    bool hasIncluded,
  ) {
    final node = item.node;
    if (node.isDirectory) {
      return Icon(
        item.isExpanded ? Icons.folder_open : Icons.folder,
        size: 20,
        color: hasIncluded ? Colors.blue.shade400 : Colors.amber.shade700,
      );
    }

    final ext = node.name.contains('.')
        ? node.name.split('.').last.toLowerCase()
        : '';

    IconData iconData = Icons.insert_drive_file;
    Color iconColor = isIncluded ? Colors.white : Colors.grey.shade500;

    switch (ext) {
      case 'dart':
        iconData = Icons.code;
        iconColor = Colors.cyan.shade300;
        break;
      case 'js':
      case 'jsx':
      case 'ts':
      case 'tsx':
        iconData = Icons.javascript;
        iconColor = Colors.amber.shade300;
        break;
      case 'py':
        iconData = Icons.terminal;
        iconColor = Colors.green.shade300;
        break;
      case 'html':
      case 'css':
      case 'scss':
        iconData = Icons.html;
        iconColor = Colors.deepOrange.shade300;
        break;
      case 'json':
      case 'yaml':
      case 'yml':
      case 'toml':
        iconData = Icons.data_object;
        iconColor = Colors.purple.shade300;
        break;
      case 'md':
      case 'txt':
        iconData = Icons.article;
        iconColor = Colors.blue.shade200;
        break;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'svg':
      case 'ico':
        iconData = Icons.image;
        iconColor = Colors.lightGreen.shade300;
        break;
      case 'lock':
        iconData = Icons.lock_clock;
        iconColor = Colors.red.shade300;
        break;
    }

    return Icon(iconData, size: 20, color: iconColor);
  }

  /// Checks if any nested children under this node are checked in O(1) set lookups.
  bool _hasIncludedChildren(TreeNode node, Set<String> includedSet) {
    if (!node.isDirectory) return includedSet.contains(node.relativePath);
    for (final child in node.children) {
      if (_hasIncludedChildren(child, includedSet)) return true;
    }
    return false;
  }

  /// Toggles multi-selection highlight state for batch processing.
  void _toggleMultiSelect(WidgetRef ref) {
    final selectedPaths = Set<String>.from(ref.read(selectedNodePathsProvider));
    if (selectedPaths.contains(item.node.relativePath)) {
      selectedPaths.remove(item.node.relativePath);
    } else {
      selectedPaths.add(item.node.relativePath);
    }
    ref.read(selectedNodePathsProvider.notifier).state = selectedPaths;
  }

  /// Opens explicit ignore options popup menu.
  void _showIgnoreOptionsMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
  ) {
    final controller = ref.read(appStateControllerProvider);
    final node = item.node;
    final List<PopupMenuEntry<String>> items = [];

    if (node.isDirectory) {
      items.addAll([
        PopupMenuItem<String>(
          value: '${node.relativePath}/**',
          child: Row(
            children: [
              const Icon(Icons.folder, size: 20, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Only this directory (${node.relativePath})'),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: '**/${node.name}/**',
          child: Row(
            children: [
              const Icon(Icons.folder_copy, size: 20, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(child: Text('All directories named "${node.name}"')),
            ],
          ),
        ),
      ]);
    } else {
      items.addAll([
        PopupMenuItem<String>(
          value: node.relativePath,
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text('Only this file (${node.relativePath})')),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: '**/${node.name}',
          child: Row(
            children: [
              const Icon(Icons.file_copy, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text('All files named "${node.name}"')),
            ],
          ),
        ),
      ]);

      final dotIdx = node.name.lastIndexOf('.');
      if (dotIdx > 0 && dotIdx < node.name.length - 1) {
        final ext = node.name.substring(dotIdx);
        items.add(
          PopupMenuItem<String>(
            value: '*$ext',
            child: Row(
              children: [
                const Icon(
                  Icons.extension,
                  size: 20,
                  color: Colors.purpleAccent,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('All files with extension "$ext"')),
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
    final node = item.node;
    final selectedPaths = ref.watch(selectedNodePathsProvider);
    final isHighlighted = selectedPaths.contains(node.relativePath);
    final bool isMultiSelectActive = selectedPaths.isNotEmpty;

    final includedSet = ref.watch(selectedIncludedFilesSetProvider);
    final isIncluded =
        !node.isDirectory && includedSet.contains(node.relativePath);
    final hasIncluded = node.isDirectory
        ? _hasIncludedChildren(node, includedSet)
        : isIncluded;
    final controller = ref.read(appStateControllerProvider);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 0.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () {
          if (isMultiSelectActive) {
            _toggleMultiSelect(ref);
          } else {
            if (node.isDirectory) {
              controller.toggleNodeExpanded(node.relativePath);
            } else {
              controller.toggleFile(node.relativePath, !isIncluded);
            }
          }
        },
        onLongPress: () => _toggleMultiSelect(ref),
        onSecondaryTapDown: (details) {
          if (isMultiSelectActive) {
            _toggleMultiSelect(ref);
          } else {
            _showIgnoreOptionsMenu(context, ref, details.globalPosition);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.5),
          decoration: BoxDecoration(
            color: isHighlighted
                ? Theme.of(context).colorScheme.primaryContainer.withAlpha(120)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              // Structural Depth Indentation Guides (Explicit height matches tight row padding)
              for (int i = 0; i < item.depth; i++)
                const SizedBox(
                  width: 22,
                  child: Center(
                    child: SizedBox(
                      width: 1,
                      height: 24,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.white12),
                      ),
                    ),
                  ),
                ),

              if (node.isDirectory)
                IconButton(
                  icon: AnimatedRotation(
                    turns: item.isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    child: const Icon(Icons.keyboard_arrow_right, size: 20),
                  ),
                  onPressed: isMultiSelectActive
                      ? null
                      : () => controller.toggleNodeExpanded(node.relativePath),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  color: hasIncluded ? null : Colors.grey.shade600,
                )
              else
                const SizedBox(width: 24),

              if (!node.isDirectory) ...[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    visualDensity: VisualDensity.compact,
                    value: isIncluded,
                    onChanged: isMultiSelectActive
                        ? null
                        : (val) {
                            if (val != null) {
                              controller.toggleFile(node.relativePath, val);
                            }
                          },
                  ),
                ),
                // Explicit padding between checkbox and file icon
                const SizedBox(width: 12),
              ],

              _buildNodeIcon(context, isIncluded, hasIncluded),
              const SizedBox(width: 10),

              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        node.name,
                        style: TextStyle(
                          fontSize: 14,
                          color: hasIncluded || isIncluded
                              ? Colors.white
                              : Colors.grey.shade400,
                          fontWeight: isIncluded ? FontWeight.w600 : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (node.isNew) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade900,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Folder selection dropdown menu button (for directories)
              if (node.isDirectory)
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.done_all,
                    size: 18,
                    color: isMultiSelectActive
                        ? Colors.grey.shade700
                        : Colors.grey.shade500,
                  ),
                  tooltip: 'Folder Selection Options',
                  enabled: !isMultiSelectActive,
                  onSelected: (action) {
                    if (action == 'select_all') {
                      controller.selectAll(node);
                    } else if (action == 'select_none') {
                      controller.selectNone(node);
                    } else if (action == 'invert') {
                      controller.invertSelection(node);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'select_all',
                      child: Text('Select all contained files'),
                    ),
                    PopupMenuItem<String>(
                      value: 'select_none',
                      child: Text('Deselect all contained files'),
                    ),
                    PopupMenuItem<String>(
                      value: 'invert',
                      child: Text('Invert selection'),
                    ),
                  ],
                ),

              // Multi-select toggle button
              IconButton(
                icon: Icon(
                  isHighlighted
                      ? Icons.check_circle
                      : Icons.check_circle_outline,
                  size: 18,
                  color: isHighlighted
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade600,
                ),
                tooltip: isHighlighted
                    ? 'Remove from multi-select'
                    : 'Add to multi-select',
                onPressed: () => _toggleMultiSelect(ref),
              ),

              // Ignore Options IconButton
              Builder(
                builder: (btnContext) => IconButton(
                  icon: Icon(
                    Icons.visibility_off,
                    size: 18,
                    color: isMultiSelectActive
                        ? Colors.grey.shade700
                        : Colors.grey.shade500,
                  ),
                  tooltip: isMultiSelectActive
                      ? 'Ignore options disabled in multi-select mode'
                      : 'Ignore Options',
                  onPressed: isMultiSelectActive
                      ? null
                      : () {
                          final box =
                              btnContext.findRenderObject() as RenderBox?;
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
    );
  }
}
