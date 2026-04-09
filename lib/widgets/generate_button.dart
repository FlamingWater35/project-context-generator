import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/tree_node.dart';
import '../providers/app_state.dart';
import 'snackbar.dart';

class GenerateButton extends ConsumerWidget {
  const GenerateButton({super.key});

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
    final children = node.children;
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final isLast = i == children.length - 1;
      final connector = isLast ? '└── ' : '├── ';
      buffer.writeln(
        '$prefix$connector${child.name}${child.isDirectory ? '/' : ''}',
      );

      if (child.isDirectory) {
        final childPrefix = isLast ? '    ' : '│   ';
        _buildTreeString(child, buffer, prefix + childPrefix, included);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      icon: const Icon(Icons.copy),
      label: const Text('Generate & Copy'),
      onPressed: () async {
        final config = ref.read(selectedConfigProvider);
        if (config == null || config.rootPath.isEmpty) return;

        final treeNode = await ref.read(fileTreeProvider.future);
        if (treeNode == null) return;

        final fsService = ref.read(fsServiceProvider);
        final visibleFiles = _getVisibleFiles(treeNode);

        final effectiveIncluded = config.includedFiles.toSet().intersection(
          visibleFiles,
        );

        if (effectiveIncluded.isEmpty) {
          if (context.mounted) {
            showSnackBar(
              context,
              message: 'No files selected or all selected files are ignored.',
              isError: true,
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

        if (context.mounted) {
          showSnackBar(
            context,
            message: 'Context copied to clipboard!',
            isError: false,
          );
        }
      },
    );
  }
}
