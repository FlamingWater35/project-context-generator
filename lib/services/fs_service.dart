import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/tree_node.dart';

class _IgnoreRule {
  factory _IgnoreRule(String pattern) {
    String p = pattern.trim();

    if (p.isEmpty || p.startsWith('#')) {
      return _IgnoreRule._(null, null);
    }

    bool onlyDirs = false;
    if (p.endsWith('/')) {
      onlyDirs = true;
      p = p.substring(0, p.length - 1);
    }

    bool isRootAnchored = false;
    if (p.startsWith('/')) {
      isRootAnchored = true;
      p = p.substring(1);
    }

    bool hasInternalSlash = p.contains('/') && !p.startsWith('**/');

    if (!isRootAnchored && !hasInternalSlash) {
      p = '**/$p';
    }

    if (onlyDirs) {
      return _IgnoreRule._(null, Glob('$p/**'));
    } else {
      return _IgnoreRule._(Glob(p), Glob('$p/**'));
    }
  }

  _IgnoreRule._(this.glob, this.dirGlob);

  final Glob? dirGlob;
  final Glob? glob;

  bool matches(String path, String pathWithSlash) {
    if (glob != null && glob!.matches(path)) return true;
    if (dirGlob != null && dirGlob!.matches(pathWithSlash)) return true;
    return false;
  }
}

class FsService {
  Future<TreeNode?> buildTree(
    String rootPath,
    List<String> ignorePatterns,
  ) async {
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) return null;

    final rules = ignorePatterns
        .map((pattern) => _IgnoreRule(pattern))
        .toList();

    TreeNode buildNode(FileSystemEntity entity, String relativePath) {
      final isDir = entity is Directory;
      final name = p.basename(entity.path);
      return TreeNode(
        path: entity.path,
        relativePath: relativePath,
        name: name,
        isDirectory: isDir,
        isExpanded: relativePath.isEmpty,
      );
    }

    final rootNode = buildNode(rootDir, '');

    Future<void> populateChildren(TreeNode node) async {
      if (!node.isDirectory) return;

      final dir = Directory(node.path);
      List<TreeNode> children = [];

      try {
        final entities = await dir.list().toList();
        for (final entity in entities) {
          final relPath = p
              .relative(entity.path, from: rootPath)
              .replaceAll('\\', '/');

          if (!_isIgnored(relPath, entity is Directory, rules)) {
            final childNode = buildNode(entity, relPath);
            children.add(childNode);

            if (childNode.isDirectory) {
              await populateChildren(childNode);
            }
          }
        }
      } catch (e) {}

      children.removeWhere(
        (child) => child.isDirectory && child.children.isEmpty,
      );

      children.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      node.children = children;
    }

    await populateChildren(rootNode);
    return rootNode;
  }

  Future<String> readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return '';
    try {
      return await file.readAsString();
    } catch (e) {
      return '<Binary or unreadable file>';
    }
  }

  List<String> getRecursiveFiles(TreeNode dirNode) {
    List<String> files = [];
    void traverse(TreeNode node) {
      if (!node.isDirectory) {
        files.add(node.relativePath);
      } else {
        for (final child in node.children) {
          traverse(child);
        }
      }
    }

    traverse(dirNode);
    return files;
  }

  bool _isIgnored(String relativePath, bool isDir, List<_IgnoreRule> rules) {
    String normalizedPath = relativePath.replaceAll('\\', '/');
    String pathWithSlash = isDir ? '$normalizedPath/' : normalizedPath;

    for (final rule in rules) {
      if (rule.matches(normalizedPath, pathWithSlash)) {
        return true;
      }
    }
    return false;
  }
}
