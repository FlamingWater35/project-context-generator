import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/tree_node.dart';
import '../providers/app_state.dart';
import 'snackbar.dart';

// Button that triggers directory sync-checks and copies project structure with contents to the clipboard
class GenerateButton extends ConsumerStatefulWidget {
  const GenerateButton({super.key});

  @override
  ConsumerState<GenerateButton> createState() => _GenerateButtonState();
}

class _GenerateButtonState extends ConsumerState<GenerateButton> {
  bool _isLoading = false;

  // Verifies disk configurations and processes text extraction with user decision options
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
          // Three-option action flow allowing stale copies if preferred
          final String? actionChoice = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Project State Changed'),
              content: const Text(
                'The physical files on disk have changed since the last check. Would you like to refresh your project snapshot or generate using the existing configuration?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'copy_anyway'),
                  child: const Text('Copy Anyway'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'refresh'),
                  child: const Text('Refresh & Copy'),
                ),
              ],
            ),
          );

          if (actionChoice == 'refresh') {
            await ref.read(appStateControllerProvider).acknowledgeChanges();
            ref.invalidate(fileTreeProvider);
            if (mounted) await _performCopy();
          } else if (actionChoice == 'copy_anyway') {
            if (mounted) await _performCopy();
          }
        }
      } else {
        if (mounted) {
          await _performCopy();
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Generation process failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Extracts verified documents, constructs output trees, and copies text contents onto clipboard
  Future<void> _performCopy() async {
    final config = ref.read(selectedConfigProvider);
    if (config == null) return;

    try {
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

      final List<String> fileContents = await Future.wait(
        sortedFiles.map((fileRelPath) {
          final absolutePath = p.join(config.rootPath, fileRelPath);
          return fsService.readFile(absolutePath);
        }),
      );

      for (int i = 0; i < sortedFiles.length; i++) {
        final fileRelPath = sortedFiles[i];
        final content = fileContents[i];
        buffer.writeln('--- File: $fileRelPath ---');
        buffer.writeln(content);
        buffer.writeln('--- End File ---');
      }

      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (mounted) {
        showSuccessSnackBar(context, 'Context copied to clipboard!');
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Failed to build clipboard contents: $e');
      }
    }
  }

  // Traverses trees to register and compile visible relative paths
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

  // Builds structured text tree mapping outputs matching file inclusion lists
  void _buildTreeString(
    TreeNode node,
    StringBuffer buffer,
    String prefix,
    Set<String> included,
  ) {
    final children = node.children;

    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final isLast = i == children.length - 1;
      final connector = isLast ? '└── ' : '├── ';

      final String selectionIndicator =
          (!child.isDirectory && included.contains(child.relativePath))
          ? ' [selected]'
          : '';

      buffer.writeln(
        '$prefix$connector${child.name}${child.isDirectory ? '/' : ''}$selectionIndicator',
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
