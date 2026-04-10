import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/tree_node.dart';

class _IgnoreRule {
  factory _IgnoreRule(String pattern) {
    String p = pattern.trim();
    if (p.isEmpty || p.startsWith('#')) return _IgnoreRule._(null, null, null);

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
      final rootGlob = Glob(p);
      final nestedGlob = Glob('**/$p');

      if (onlyDirs) {
        return _IgnoreRule._(null, null, Glob('**/$p/**'));
      } else {
        return _IgnoreRule._(rootGlob, nestedGlob, Glob('**/$p/**'));
      }
    }

    if (onlyDirs) {
      return _IgnoreRule._(null, null, Glob('$p/**'));
    } else {
      return _IgnoreRule._(Glob(p), null, Glob('$p/**'));
    }
  }

  _IgnoreRule._(this.rootGlob, this.nestedGlob, this.dirGlob);

  final Glob? dirGlob;
  final Glob? nestedGlob;
  final Glob? rootGlob;

  bool matches(String path, String pathWithSlash) {
    if (rootGlob != null && rootGlob!.matches(path)) return true;
    if (nestedGlob != null && nestedGlob!.matches(path)) return true;
    if (dirGlob != null && dirGlob!.matches(pathWithSlash)) return true;
    return false;
  }
}

class FsService {
  static const int _maxFileSizeBytes = 1024 * 1024;

  Future<Set<String>> scanPaths(
    String rootPath,
    List<String> ignorePatterns,
  ) async {
    final rules = ignorePatterns
        .map((pattern) => _IgnoreRule(pattern))
        .toList();
    final Set<String> paths = {};
    final dir = Directory(rootPath);
    if (!await dir.exists()) return paths;

    try {
      final stream = dir.list(recursive: true, followLinks: false);

      await for (final entity in stream.handleError((error) {
        debugPrint('FsService: Skipping inaccessible path during scan: $error');
      })) {
        try {
          final relPath = p
              .relative(entity.path, from: rootPath)
              .replaceAll('\\', '/');
          if (!_isIgnored(relPath, entity is Directory, rules)) {
            paths.add(relPath);
          }
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      debugPrint('FsService: Fatal directory listing error: $e');
    }
    return paths;
  }

  Future<TreeNode?> buildTree(
    String rootPath,
    List<String> ignorePatterns, {
    Set<String>? knownPaths,
  }) async {
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) return null;

    final rules = ignorePatterns
        .map((pattern) => _IgnoreRule(pattern))
        .toList();

    TreeNode buildNode(FileSystemEntity entity, String relativePath) {
      final isDir = entity is Directory;
      final bool isNew =
          knownPaths != null && !knownPaths.contains(relativePath);

      return TreeNode(
        path: entity.path,
        relativePath: relativePath,
        name: p.basename(entity.path),
        isDirectory: isDir,
        isNew: isNew,
      );
    }

    Future<TreeNode> populateChildren(TreeNode node) async {
      if (!node.isDirectory) return node;

      final dir = Directory(node.path);
      List<TreeNode> children = [];
      bool anyChildIsNew = false;

      try {
        final entities = await dir.list().toList().catchError((e) {
          debugPrint('FsService: Cannot list directory ${node.path}: $e');
          return <FileSystemEntity>[];
        });

        for (final entity in entities) {
          try {
            final relPath = p
                .relative(entity.path, from: rootPath)
                .replaceAll('\\', '/');
            if (!_isIgnored(relPath, entity is Directory, rules)) {
              final childNode = buildNode(entity, relPath);
              final populatedChild = await populateChildren(childNode);
              children.add(populatedChild);
              if (populatedChild.isNew) anyChildIsNew = true;
            }
          } catch (e) {
            continue;
          }
        }
      } catch (_) {}

      children.removeWhere(
        (child) => child.isDirectory && child.children.isEmpty,
      );

      children.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return node.copyWith(
        children: children,
        isNew: node.isNew || anyChildIsNew,
      );
    }

    final rootNode = buildNode(rootDir, '');
    return await populateChildren(rootNode);
  }

  Future<String> readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return '';

    try {
      final stat = await file.stat();
      if (stat.size > _maxFileSizeBytes) {
        return '<File too large (${(stat.size / 1024 / 1024).toStringAsFixed(2)} MB)>';
      }

      final raf = await file.open();
      final headerBytes = await raf.read(8192);
      await raf.close();

      if (_isBinaryData(headerBytes)) {
        return '<Binary file>';
      }

      return await file.readAsString();
    } catch (e) {
      return '<Error reading file: $e>';
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

  bool _isBinaryData(Uint8List data) {
    if (data.isEmpty) return false;

    int nullBytes = 0;
    int controlChars = 0;

    for (final byte in data) {
      if (byte == 0) nullBytes++;
      if (byte < 32 && byte != 9 && byte != 10 && byte != 13) {
        controlChars++;
      }
    }

    final ratio = data.length;
    if (nullBytes > 0 && (nullBytes / ratio) > 0.01) return true;
    if ((controlChars / ratio) > 0.1) return true;

    return false;
  }

  bool _isIgnored(String relativePath, bool isDir, List<_IgnoreRule> rules) {
    String normalizedPath = relativePath.replaceAll('\\', '/');
    String pathWithSlash = isDir ? '$normalizedPath/' : normalizedPath;
    for (final rule in rules) {
      if (rule.matches(normalizedPath, pathWithSlash)) return true;
    }
    return false;
  }
}
