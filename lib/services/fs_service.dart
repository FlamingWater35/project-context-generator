import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/tree_node.dart';

class _IgnoreRule {
  _IgnoreRule(String pattern)
    : exact = Glob(pattern),
      anywhere = _createAnywhereGlob(pattern),
      rootFallback = pattern.startsWith('**/')
          ? Glob(pattern.substring(3))
          : null;

  final Glob? anywhere;
  final Glob exact;
  final Glob? rootFallback;

  bool matches(String path, String pathWithSlash) {
    if (exact.matches(path) || exact.matches(pathWithSlash)) return true;
    if (anywhere != null &&
        (anywhere!.matches(path) || anywhere!.matches(pathWithSlash))) {
      return true;
    }
    if (rootFallback != null &&
        (rootFallback!.matches(path) || rootFallback!.matches(pathWithSlash))) {
      return true;
    }
    return false;
  }

  static Glob? _createAnywhereGlob(String pattern) {
    if (pattern.startsWith('**/') || pattern.startsWith('/')) return null;

    final isFolderPattern = pattern.endsWith('/**');
    final strippedFolder = isFolderPattern
        ? pattern.substring(0, pattern.length - 3)
        : pattern;

    if (strippedFolder.contains('/')) return null;

    return Glob('**/$pattern');
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
      } catch (e) {
        // Handle permission denied securely
      }

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
