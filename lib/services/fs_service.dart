import 'dart:io';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import '../models/tree_node.dart';

class FsService {
  bool _isIgnored(String relativePath, bool isDir, List<Glob> ignores) {
    String normalizedPath = relativePath.replaceAll('\\', '/');
    final pathsToTest =[
      normalizedPath,
      if (isDir) '$normalizedPath/',
    ];

    for (final glob in ignores) {
      for (final path in pathsToTest) {
        if (glob.matches(path)) {
          return true;
        }
      }
    }
    return false;
  }

  Future<TreeNode?> buildTree(String rootPath, List<String> ignorePatterns) async {
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) return null;

    final ignores = ignorePatterns.map((pattern) => Glob(pattern)).toList();

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
      List<TreeNode> children =[];

      try {
        final entities = await dir.list().toList();
        for (final entity in entities) {
          final relPath = p.relative(entity.path, from: rootPath).replaceAll('\\', '/');
          if (!_isIgnored(relPath, entity is Directory, ignores)) {
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

      children.removeWhere((child) => child.isDirectory && child.children.isEmpty);

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
    List<String> files =[];
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
}
