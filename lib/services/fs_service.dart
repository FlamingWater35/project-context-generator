import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/agent_skill.dart';
import '../models/tree_node.dart';

// Helper evaluating pattern structures to parse files matching ignore lists
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

    final bool hasInternalSlash =
        pStrForSlashCheck.contains('/') && !pStrForSlashCheck.startsWith('**/');

    Glob? rootGlob;
    Glob? nestedGlob;
    Glob? dirGlob;
    Glob? pruneGlob;

    if (!isRootAnchored && !hasInternalSlash) {
      if (!onlyDirs) rootGlob = Glob(pStr, context: p.posix);
      if (!onlyDirs) nestedGlob = Glob('**/$pStr', context: p.posix);
      dirGlob = Glob('**/$pStr/**', context: p.posix);
      if (pruneP.isNotEmpty) pruneGlob = Glob('**/$pruneP', context: p.posix);
    } else {
      if (!onlyDirs) rootGlob = Glob(pStr, context: p.posix);
      dirGlob = Glob('$pStr/**', context: p.posix);
      if (pruneP.isNotEmpty) pruneGlob = Glob(pruneP, context: p.posix);
    }

    return _IgnoreRule._(rootGlob, nestedGlob, dirGlob, pruneGlob);
  }

  const _IgnoreRule._(
    this.rootGlob,
    this.nestedGlob,
    this.dirGlob,
    this.pruneGlob,
  );

  final Glob? dirGlob;
  final Glob? nestedGlob;
  final Glob? pruneGlob;
  final Glob? rootGlob;

  // Verifies matches against normalized dynamic locations
  bool matches(String path, String pathWithSlash) {
    if (rootGlob != null && rootGlob!.matches(path)) return true;
    if (nestedGlob != null && nestedGlob!.matches(path)) return true;
    if (dirGlob != null && dirGlob!.matches(pathWithSlash)) return true;
    return false;
  }

  // Verifies matches specifically mapping to folder objects
  bool matchesDir(String path) {
    if (pruneGlob != null && pruneGlob!.matches(path)) return true;
    if (rootGlob != null && rootGlob!.matches(path)) return true;
    if (nestedGlob != null && nestedGlob!.matches(path)) return true;
    return false;
  }
}

// Background utility service analyzing directories, matching ignores, and processing files & skills
class FsService {
  static const int _maxFileSizeBytes = 1024 * 1024;

  // Formats drive indicators on Windows platforms to avoid reference collision
  static String _normalizeDriveLetter(String path) {
    if (Platform.isWindows && path.length >= 2 && path[1] == ':') {
      return path[0].toUpperCase() + path.substring(1);
    }
    return path;
  }

  // Performs folder file discovery on an external Isolate to prevent UI lockups
  Future<Set<String>> scanPaths(
    String rootPath,
    List<String> ignorePatterns,
  ) async {
    try {
      return await Isolate.run(() => _scanPathsSync(rootPath, ignorePatterns));
    } catch (e) {
      debugPrint('Background Isolate path execution failed: $e');
      return const <String>{};
    }
  }

  // Assembles structural TreeNode layouts inside background workers
  Future<TreeNode?> buildTree(
    String rootPath,
    List<String> ignorePatterns, {
    Set<String>? knownPaths,
  }) async {
    try {
      return await Isolate.run(
        () => _buildTreeSync(rootPath, ignorePatterns, knownPaths),
      );
    } catch (e) {
      debugPrint('Background Isolate directory parsing failed: $e');
      return null;
    }
  }

  /// Scans the project directory to detect agent skill files (e.g. SKILL.md, .prompt.md, .cursor/rules, etc.).
  Future<List<AgentSkill>> detectSkills(String rootPath) async {
    if (rootPath.isEmpty) return const [];
    try {
      final dir = Directory(rootPath);
      if (!dir.existsSync()) return const [];

      return await Isolate.run(() => _detectSkillsSync(rootPath));
    } catch (e) {
      debugPrint('Background Isolate skill discovery failed: $e');
      return const [];
    }
  }

  // Safe file reader processing content boundaries, checking file size and binaries
  Future<String> readFile(String path) async {
    final file = File(path);
    try {
      if (!await file.exists()) return '';

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

  // Traverses structures recursively to list paths beneath a target parent
  List<String> getRecursiveFiles(TreeNode dirNode) {
    final List<String> files = [];
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

  // Synchronous traversal analyzer logic designed for Isolate targets
  static Set<String> _scanPathsSync(
    String rootPath,
    List<String> ignorePatterns,
  ) {
    final rules = ignorePatterns
        .map((pattern) => _IgnoreRule(pattern))
        .toList();
    final Set<String> paths = {};
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return paths;

    String canonicalRoot;
    Directory canonicalDir;
    try {
      canonicalRoot = _normalizeDriveLetter(dir.resolveSymbolicLinksSync());
      canonicalDir = Directory(canonicalRoot);
    } catch (e) {
      canonicalRoot = _normalizeDriveLetter(rootPath);
      canonicalDir = dir;
    }

    void traverse(Directory currentDir) {
      try {
        final entities = currentDir.listSync(followLinks: false);
        for (final entity in entities) {
          try {
            final normalizedEntityPath = _normalizeDriveLetter(entity.path);
            final relPath = p
                .relative(normalizedEntityPath, from: canonicalRoot)
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
                traverse(entity);
              }
            }
          } catch (e) {
            continue;
          }
        }
      } catch (e) {
        // Inaccessible directory - skip
      }
    }

    traverse(canonicalDir);
    return paths;
  }

  // Synchronous directory assembler logic designed for background Isolate runners
  static TreeNode? _buildTreeSync(
    String rootPath,
    List<String> ignorePatterns,
    Set<String>? knownPaths,
  ) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return null;

    String canonicalRoot;
    Directory canonicalDir;
    try {
      canonicalRoot = _normalizeDriveLetter(dir.resolveSymbolicLinksSync());
      canonicalDir = Directory(canonicalRoot);
    } catch (e) {
      canonicalRoot = _normalizeDriveLetter(rootPath);
      canonicalDir = dir;
    }

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

    TreeNode populateChildren(TreeNode node) {
      if (!node.isDirectory) return node;

      final dir = Directory(node.path);
      final List<TreeNode> children = [];
      bool anyChildIsNew = false;

      try {
        final entities = dir.listSync(followLinks: false);
        for (final entity in entities) {
          try {
            final normalizedEntityPath = _normalizeDriveLetter(entity.path);
            final relPath = p
                .relative(normalizedEntityPath, from: canonicalRoot)
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
              final populatedChild = populateChildren(childNode);
              children.add(populatedChild);
              if (populatedChild.isNew) anyChildIsNew = true;
            }
          } catch (e) {
            continue;
          }
        }
      } catch (e) {
        // Inaccessible folder
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

    final rootNode = buildNode(canonicalDir, '');
    return populateChildren(rootNode);
  }

  /// Synchronous skill discovery logic designed for background Isolate runners.
  static List<AgentSkill> _detectSkillsSync(String rootPath) {
    final List<AgentSkill> detected = [];
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return detected;

    String canonicalRoot;
    try {
      canonicalRoot = _normalizeDriveLetter(dir.resolveSymbolicLinksSync());
    } catch (_) {
      canonicalRoot = _normalizeDriveLetter(rootPath);
    }

    final Set<String> ignoreFolders = {
      '.git',
      'node_modules',
      'build',
      '.dart_tool',
      'dist',
      'target',
      'vendor',
      '.idea',
      '.vscode',
    };

    void traverse(Directory currentDir) {
      try {
        final entities = currentDir.listSync(followLinks: false);
        for (final entity in entities) {
          try {
            final baseName = p.basename(entity.path);

            if (entity is Directory) {
              if (ignoreFolders.contains(baseName)) continue;
              traverse(entity);
            } else if (entity is File) {
              final lowerName = baseName.toLowerCase();
              final normalizedPath = _normalizeDriveLetter(entity.path);
              final relPath = p
                  .relative(normalizedPath, from: canonicalRoot)
                  .replaceAll('\\', '/');

              final bool isSkillFile =
                  lowerName == 'skill.md' ||
                  lowerName == 'skills.md' ||
                  lowerName.endsWith('.prompt.md') ||
                  relPath.contains('.github/skills/') ||
                  relPath.contains('.claude/skills/') ||
                  relPath.contains('.agents/skills/') ||
                  relPath.contains('.cursor/rules/') ||
                  relPath.contains('.windsurfrules');

              if (isSkillFile) {
                try {
                  final stat = entity.statSync();
                  if (stat.size <= _maxFileSizeBytes) {
                    final content = entity.readAsStringSync();
                    final frontmatter = _parseFrontmatter(content);

                    String name = frontmatter['name'] ?? '';
                    if (name.isEmpty) {
                      final parentDirName = p.basename(entity.parent.path);
                      if (lowerName == 'skill.md' && parentDirName.isNotEmpty) {
                        name = parentDirName;
                      } else {
                        name = p.basenameWithoutExtension(baseName);
                      }
                    }

                    String description = frontmatter['description'] ?? '';
                    if (description.isEmpty) {
                      description = 'Agent skill from $relPath';
                    }

                    detected.add(
                      AgentSkill(
                        id: relPath,
                        name: name,
                        description: description,
                        content: content,
                        sourcePath: relPath,
                        isCustom: false,
                      ),
                    );
                  }
                } catch (e) {
                  // Ignore unreadable skill file
                }
              }
            }
          } catch (_) {
            continue;
          }
        }
      } catch (_) {}
    }

    traverse(Directory(canonicalRoot));
    return detected;
  }

  /// Parses YAML frontmatter headers from markdown content without requiring external YAML dependencies.
  static Map<String, String> _parseFrontmatter(String text) {
    final Map<String, String> result = {};
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('---')) return result;

    final endFrontmatter = trimmed.indexOf('---', 3);
    if (endFrontmatter == -1) return result;

    final yamlContent = trimmed.substring(3, endFrontmatter);
    final lines = yamlContent.split('\n');

    for (final line in lines) {
      final colonIdx = line.indexOf(':');
      if (colonIdx != -1) {
        final key = line.substring(0, colonIdx).trim().toLowerCase();
        var val = line.substring(colonIdx + 1).trim();
        if ((val.startsWith('"') && val.endsWith('"')) ||
            (val.startsWith("'") && val.endsWith("'"))) {
          if (val.length >= 2) {
            val = val.substring(1, val.length - 1);
          }
        }
        result[key] = val;
      }
    }
    return result;
  }

  // Analyzes headers to determine if files contain binary rather than text data
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
