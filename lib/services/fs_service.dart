import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/tree_node.dart';

class _IgnoreRule {
  factory _IgnoreRule(String pattern) {
    String pStr = pattern.trim();
    if (pStr.isEmpty || pStr.startsWith('#')) {
      return _IgnoreRule._(null, null, null, null);
    }

    bool onlyDirs = false;
    if (pStr.endsWith('/')) {
      onlyDirs = true;
      pStr = pStr.substring(0, pStr.length - 1);
    }

    String pruneP = pStr;
    if (pruneP.endsWith('/**')) {
      pruneP = pruneP.substring(0, pruneP.length - 3);
    } else if (pruneP.endsWith('/*')) {
      pruneP = pruneP.substring(0, pruneP.length - 2);
    }

    bool isRootAnchored = false;
    if (pStr.startsWith('/')) {
      isRootAnchored = true;
      pStr = pStr.substring(1);
      if (pruneP.startsWith('/')) pruneP = pruneP.substring(1);
    }

    String pStrForSlashCheck = pStr;
    if (pStrForSlashCheck.endsWith('/**')) {
      pStrForSlashCheck = pStrForSlashCheck.substring(
        0,
        pStrForSlashCheck.length - 3,
      );
    } else if (pStrForSlashCheck.endsWith('/*')) {
      pStrForSlashCheck = pStrForSlashCheck.substring(
        0,
        pStrForSlashCheck.length - 2,
      );
    }

    bool hasInternalSlash =
        pStrForSlashCheck.contains('/') && !pStrForSlashCheck.startsWith('**/');

    Glob? rootGlob;
    Glob? nestedGlob;
    Glob? dirGlob;
    Glob? pruneGlob;

    if (!isRootAnchored && !hasInternalSlash) {
      if (!onlyDirs) rootGlob = Glob(pStr);
      if (!onlyDirs) nestedGlob = Glob('**/$pStr');
      dirGlob = Glob('**/$pStr/**');
      if (pruneP.isNotEmpty) pruneGlob = Glob('**/$pruneP');
    } else {
      if (!onlyDirs) rootGlob = Glob(pStr);
      dirGlob = Glob('$pStr/**');
      if (pruneP.isNotEmpty) pruneGlob = Glob(pruneP);
    }

    return _IgnoreRule._(rootGlob, nestedGlob, dirGlob, pruneGlob);
  }

  _IgnoreRule._(this.rootGlob, this.nestedGlob, this.dirGlob, this.pruneGlob);

  final Glob? dirGlob;
  final Glob? nestedGlob;
  final Glob? pruneGlob;
  final Glob? rootGlob;

  bool matches(String path, String pathWithSlash) {
    if (rootGlob != null && rootGlob!.matches(path)) return true;
    if (nestedGlob != null && nestedGlob!.matches(path)) return true;
    if (dirGlob != null && dirGlob!.matches(pathWithSlash)) return true;
    return false;
  }

  bool matchesDir(String path) {
    if (pruneGlob != null && pruneGlob!.matches(path)) return true;
    if (rootGlob != null && rootGlob!.matches(path)) return true;
    if (nestedGlob != null && nestedGlob!.matches(path)) return true;
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

    Future<void> traverse(Directory currentDir) async {
      try {
        final entities = await currentDir.list(followLinks: false).toList();
        for (final entity in entities) {
          try {
            final relPath = p
                .relative(entity.path, from: rootPath)
                .replaceAll('\\', '/');
            final isDir = entity is Directory;

            bool skip = false;
            for (final rule in rules) {
              if (isDir) {
                if (rule.matchesDir(relPath) ||
                    rule.matches(relPath, '$relPath/')) {
                  skip = true;
                  break;
                }
              } else {
                if (rule.matches(relPath, relPath)) {
                  skip = true;
                  break;
                }
              }
            }

            if (!skip) {
              paths.add(relPath);
              if (isDir) {
                await traverse(entity);
              }
            }
          } catch (e) {
            continue;
          }
        }
      } catch (e) {
        debugPrint('FsService: Skipping inaccessible path during scan: $e');
      }
    }

    await traverse(dir);
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
        final entities = await dir.list().toList();
        for (final entity in entities) {
          try {
            final relPath = p
                .relative(entity.path, from: rootPath)
                .replaceAll('\\', '/');
            final isDir = entity is Directory;

            bool skip = false;
            for (final rule in rules) {
              if (isDir) {
                if (rule.matchesDir(relPath) ||
                    rule.matches(relPath, '$relPath/')) {
                  skip = true;
                  break;
                }
              } else {
                if (rule.matches(relPath, relPath)) {
                  skip = true;
                  break;
                }
              }
            }

            if (!skip) {
              final childNode = buildNode(entity, relPath);
              final populatedChild = await populateChildren(childNode);
              children.add(populatedChild);
              if (populatedChild.isNew) anyChildIsNew = true;
            }
          } catch (e) {
            continue;
          }
        }
      } catch (e) {
        debugPrint('FsService: Cannot list directory ${node.path}: $e');
      }

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

    final length = data.length;
    if (nullBytes > 0 && (nullBytes / length) > 0.01) return true;
    if ((controlChars / length) > 0.1) return true;

    return false;
  }
}
