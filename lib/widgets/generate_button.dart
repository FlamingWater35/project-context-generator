import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/tree_node.dart';
import '../providers/app_state.dart';
import 'snackbar.dart';

class GenerateButton extends ConsumerStatefulWidget {
  const GenerateButton({super.key});

  @override
  ConsumerState<GenerateButton> createState() => _GenerateButtonState();
}

class _GenerateButtonState extends ConsumerState<GenerateButton> {
  bool _isLoading = false;

  Future<void> _handleGenerate() async {
    setState(() => _isLoading = true);

    try {
      final config = ref.read(selectedConfigProvider);
      if (config == null || config.rootPath.isEmpty) return;

      final fs = ref.read(fsServiceProvider);
      final snapshots = ref.read(projectSnapshotsProvider);
      final knownPaths = snapshots[config.id] ?? {};

      final currentPaths = await fs.scanPaths(
        config.rootPath,
        config.ignorePatterns,
      );

      final bool hasChanged =
          currentPaths.length != knownPaths.length ||
          !currentPaths.containsAll(knownPaths);

      if (hasChanged) {
        if (mounted) {
          final bool? shouldRegenerate = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Project State Changed'),
              content: const Text(
                'The physical files on disk have changed since the last check. Would you like to refresh the project state and then generate the prompt?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Refresh & Generate'),
                ),
              ],
            ),
          );

          if (shouldRegenerate == true) {
            await ref
                .read(appStateControllerProvider)
                .refreshSnapshot(acknowledge: true);
            ref.invalidate(fileTreeProvider);

            await Future.delayed(const Duration(milliseconds: 100));
            if (mounted) await _performCopy();
          }
        }
      } else {
        if (mounted) {
          await _performCopy();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _performCopy() async {
    final config = ref.read(selectedConfigProvider);
    if (config == null) return;

    final treeNode = await ref.read(fileTreeProvider.future);
    if (treeNode == null) return;

    final fsService = ref.read(fsServiceProvider);
    final visibleFiles = _getVisibleFiles(treeNode);
    final effectiveIncluded = config.includedFiles.toSet().intersection(
      visibleFiles,
    );

    if (effectiveIncluded.isEmpty) {
      if (mounted) {
        showErrorSnackBar(
          context,
          'No files selected or all selected files are ignored.',
        );
      }
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('--- PROJECT CONTEXT: ${config.name} ---');
    buffer.writeln('File Tree Structure:');
    _buildTreeString(treeNode, buffer, '', effectiveIncluded);
    buffer.writeln('--- MAIN FILE(S) CONTENT ---');

    final sortedFiles = effectiveIncluded.toList()..sort();
    for (final fileRelPath in sortedFiles) {
      final absolutePath = p.join(config.rootPath, fileRelPath);
      final content = await fsService.readFile(absolutePath);
      buffer.writeln('--- File: $fileRelPath ---');
      buffer.writeln(content);
      buffer.writeln('--- End File ---');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      showSuccessSnackBar(context, 'Context copied to clipboard!');
    }
  }

  Set<String> _getVisibleFiles(TreeNode node) {
    final set = <String>{};
    void traverse(TreeNode n) {
      if (!n.isDirectory) {
        set.add(n.relativePath);
      } else {
        for (final child in n.children) {
          traverse(child);
        }
      }
    }

    traverse(node);
    return set;
  }

  void _buildTreeString(
    TreeNode node,
    StringBuffer buffer,
    String prefix,
    Set<String> included,
  ) {
    final children = node.children.where((child) {
      if (!child.isDirectory) {
        return included.contains(child.relativePath);
      }
      return _hasIncludedDescendant(child, included);
    }).toList();

    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final isLast = i == children.length - 1;
      final connector = isLast ? '└── ' : '├── ';
      buffer.writeln(
        '$prefix$connector${child.name}${child.isDirectory ? '/' : ''}',
      );
      if (child.isDirectory) {
        _buildTreeString(
          child,
          buffer,
          prefix + (isLast ? '    ' : '│   '),
          included,
        );
      }
    }
  }

  bool _hasIncludedDescendant(TreeNode node, Set<String> included) {
    if (!node.isDirectory) return included.contains(node.relativePath);
    for (final child in node.children) {
      if (!child.isDirectory) {
        if (included.contains(child.relativePath)) return true;
      } else {
        if (_hasIncludedDescendant(child, included)) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.copy),
      label: Text(_isLoading ? 'Generating...' : 'Generate & Copy'),
      onPressed: _isLoading ? null : _handleGenerate,
    );
  }
}
