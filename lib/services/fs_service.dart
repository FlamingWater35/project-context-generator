import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/agent_skill.dart';
import '../models/tree_node.dart';

/// Input parameters required for building a project context prompt in a background Isolate.
class PromptBuildParams {
  const PromptBuildParams({
    required this.projectName,
    required this.rootPath,
    required this.includedFiles,
    required this.selectedSkills,
    required this.ignorePatterns,
  });

  final List<String> ignorePatterns;
  final List<String> includedFiles;
  final String projectName;
  final String rootPath;
  final List<AgentSkill> selectedSkills;
}

/// Data model representing a parsed section within the generated prompt text.
class PromptSectionData {
  const PromptSectionData({
    required this.title,
    required this.charIndex,
    required this.iconType,
  });

  final int charIndex;
  final String iconType; // 'tree', 'file', 'skills', 'skill'
  final String title;
}

/// Output parameters produced from background Isolate prompt assembly.
class PromptBuildResult {
  const PromptBuildResult({
    required this.promptText,
    required this.displayText,
    required this.fileCount,
    required this.skillCount,
    required this.totalLines,
    required this.sections,
    required this.isTruncated,
  });

  final String displayText;
  final int fileCount;
  final bool isTruncated;
  final String promptText;
  final List<PromptSectionData> sections;
  final int skillCount;
  final int totalLines;
}

/// Helper evaluating pattern structures to parse files matching ignore lists securely.
class _IgnoreRule {
  factory _IgnoreRule(String pattern) {
    String pStr = pattern.trim();
    if (pStr.isEmpty || pStr.startsWith('#')) {
      return const _IgnoreRule._(null, null, null, null);
    }

    bool onlyDirs = false;
    if (pStr.endsWith('/')) {
      onlyDirs = true;
      pStr = pStr.substring(0, pStr.length - 1);
    }

    String basePattern = pStr;
    if (basePattern.endsWith('/**')) {
      basePattern = basePattern.substring(0, basePattern.length - 3);
    } else if (basePattern.endsWith('/*')) {
      basePattern = basePattern.substring(0, basePattern.length - 2);
    }

    bool isRootAnchored = false;
    if (basePattern.startsWith('/')) {
      isRootAnchored = true;
      basePattern = basePattern.substring(1);
    }

    if (basePattern.isEmpty) {
      return const _IgnoreRule._(null, null, null, null);
    }

    final bool hasInternalSlash = basePattern.contains('/');

    Glob? rootGlob;
    Glob? nestedGlob;
    Glob? dirGlob;
    Glob? pruneGlob;

    try {
      if (!isRootAnchored && !hasInternalSlash) {
        if (!onlyDirs) {
          rootGlob = Glob(basePattern, context: p.posix);
          nestedGlob = Glob('**/$basePattern', context: p.posix);
        }
        dirGlob = Glob('**/$basePattern/**', context: p.posix);
        pruneGlob = Glob('**/$basePattern', context: p.posix);
      } else {
        if (!onlyDirs) {
          rootGlob = Glob(basePattern, context: p.posix);
          nestedGlob = null;
        }
        dirGlob = Glob('$basePattern/**', context: p.posix);
        pruneGlob = Glob(basePattern, context: p.posix);
      }
    } catch (e) {
      debugPrint('Failed to parse ignore pattern "$pattern": $e');
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

  /// Verifies matches against normalized relative path targets.
  bool matches(String path, String pathWithSlash) {
    if (rootGlob != null && rootGlob!.matches(path)) return true;
    if (nestedGlob != null && nestedGlob!.matches(path)) return true;
    if (dirGlob != null && dirGlob!.matches(pathWithSlash)) return true;
    return false;
  }

  /// Verifies matches specifically mapping to folder objects.
  bool matchesDir(String path) {
    if (pruneGlob != null && pruneGlob!.matches(path)) return true;
    if (rootGlob != null && rootGlob!.matches(path)) return true;
    if (nestedGlob != null && nestedGlob!.matches(path)) return true;
    return false;
  }
}

/// Background utility service analyzing directories, matching ignores, and processing files & skills.
class FsService {
  static const int _maxFileSizeBytes = 1024 * 1024;

  /// Formats drive indicators on Windows platforms to avoid reference collision.
  static String _normalizeDriveLetter(String path) {
    if (Platform.isWindows && path.length >= 2 && path[1] == ':') {
      return path[0].toUpperCase() + path.substring(1);
    }
    return path;
  }

  /// Returns absolute normalized canonical root path without un-resolving symlinks inconsistently.
  static String _getCanonicalRootPath(String rootPath) {
    final normalized = p.normalize(p.absolute(rootPath));
    return _normalizeDriveLetter(normalized);
  }

  /// Performs folder file discovery on an external Isolate to prevent UI lockups.
  Future<Set<String>> scanPaths(
    String rootPath,
    List<String> ignorePatterns,
  ) async {
    try {
      return await Isolate.run(() {
        final tree = _buildTreeSync(rootPath, ignorePatterns, null);
        return tree?.getAllRelativePaths() ?? <String>{};
      });
    } catch (e) {
      debugPrint('Background Isolate path execution failed: $e');
      return const <String>{};
    }
  }

  /// Assembles structural TreeNode layouts inside background workers.
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

  /// Assembles the complete context prompt in a background Isolate to prevent UI lockups.
  Future<PromptBuildResult> buildPromptContext(PromptBuildParams params) async {
    try {
      return await Isolate.run(() => _buildPromptContextSync(params));
    } catch (e) {
      debugPrint('Background Isolate prompt construction failed: $e');
      return const PromptBuildResult(
        promptText: 'Error generating prompt context.',
        displayText: 'Error generating prompt context.',
        fileCount: 0,
        skillCount: 0,
        totalLines: 1,
        sections: [],
        isTruncated: false,
      );
    }
  }

  /// Scans the project directory to detect actual agent skill files.
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

  /// Synchronous prompt assembly logic optimized for Isolate execution with zero string array splitting.
  static PromptBuildResult _buildPromptContextSync(PromptBuildParams params) {
    final rootDir = Directory(params.rootPath);
    if (!rootDir.existsSync()) {
      return const PromptBuildResult(
        promptText: 'Root directory does not exist.',
        displayText: 'Root directory does not exist.',
        fileCount: 0,
        skillCount: 0,
        totalLines: 1,
        sections: [],
        isTruncated: false,
      );
    }

    final canonicalRoot = _getCanonicalRootPath(params.rootPath);

    final treeNode = _buildTreeSync(
      params.rootPath,
      params.ignorePatterns,
      null,
    );
    final Set<String> visibleFiles = {};
    if (treeNode != null) {
      void traverse(TreeNode n) {
        if (!n.isDirectory) {
          visibleFiles.add(n.relativePath);
        } else {
          for (final child in n.children) {
            traverse(child);
          }
        }
      }

      traverse(treeNode);
    }

    final effectiveIncluded = params.includedFiles.toSet().intersection(
      visibleFiles,
    );
    final sortedFiles = effectiveIncluded.toList()..sort();

    final buffer = StringBuffer();
    buffer.writeln('--- PROJECT CONTEXT: ${params.projectName} ---');
    buffer.writeln('File Tree Structure:');
    if (treeNode != null) {
      _buildTreeStringSync(treeNode, buffer, '', effectiveIncluded);
    }
    buffer.writeln('--- MAIN FILE(S) CONTENT ---');

    for (final fileRelPath in sortedFiles) {
      final absolutePath = p.join(canonicalRoot, fileRelPath);
      final file = File(absolutePath);

      buffer.writeln('--- File: $fileRelPath ---');
      try {
        if (!file.existsSync()) {
          buffer.writeln('<File does not exist>');
        } else {
          final stat = file.statSync();
          if (stat.size > _maxFileSizeBytes) {
            buffer.writeln(
              '<File too large (${(stat.size / 1024 / 1024).toStringAsFixed(2)} MB)>',
            );
          } else {
            final raf = file.openSync();
            final headerBytes = raf.readSync(8192);
            raf.closeSync();

            if (_isBinaryDataSync(headerBytes)) {
              buffer.writeln('<Binary file>');
            } else {
              buffer.writeln(file.readAsStringSync());
            }
          }
        }
      } catch (e) {
        buffer.writeln('<Error reading file: $e>');
      }
      buffer.writeln('--- End File ---');
    }

    if (params.selectedSkills.isNotEmpty) {
      buffer.writeln('--- AGENT SKILLS ---');

      for (final skill in params.selectedSkills) {
        buffer.writeln('--- Skill: ${skill.name} ---');
        if (skill.description.isNotEmpty) {
          buffer.writeln('Description: ${skill.description}');
        }
        if (skill.sourcePath != null && skill.sourcePath!.isNotEmpty) {
          buffer.writeln('Source: ${skill.sourcePath}');
        }
        buffer.writeln(skill.content);

        if (skill.references.isNotEmpty) {
          for (final ref in skill.references) {
            buffer.writeln('--- Skill Reference: ${ref.relativePath} ---');
            buffer.writeln(ref.content);
            buffer.writeln('--- End Skill Reference ---');
          }
        }

        buffer.writeln('--- End Skill ---');
      }
    }

    final fullText = buffer.toString();

    // Single-pass line counting avoids allocating multi-megabyte String arrays
    int totalLines = 1;
    final len = fullText.length;
    for (int i = 0; i < len; i++) {
      if (fullText.codeUnitAt(i) == 10) {
        totalLines++;
      }
    }

    return PromptBuildResult(
      promptText: fullText,
      displayText: fullText,
      fileCount: sortedFiles.length,
      skillCount: params.selectedSkills.length,
      totalLines: totalLines,
      sections: const [],
      isTruncated: false,
    );
  }

  /// Synchronous tree string builder for prompt assembly.
  static void _buildTreeStringSync(
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
        _buildTreeStringSync(
          child,
          buffer,
          prefix + (isLast ? '    ' : '│   '),
          included,
        );
      }
    }
  }

  /// Synchronous directory assembler logic designed for background Isolate runners.
  static TreeNode? _buildTreeSync(
    String rootPath,
    List<String> ignorePatterns,
    Set<String>? knownPaths,
  ) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return null;

    final canonicalRoot = _getCanonicalRootPath(rootPath);
    final canonicalDir = Directory(canonicalRoot);

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
          } catch (_) {
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

    final rootNode = buildNode(canonicalDir, '');
    return populateChildren(rootNode);
  }

  /// Synchronous skill discovery logic designed for background Isolate runners.
  static List<AgentSkill> _detectSkillsSync(String rootPath) {
    final List<AgentSkill> detected = [];
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return detected;

    final canonicalRoot = _getCanonicalRootPath(rootPath);

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

    final Set<String> processedSkillPaths = {};

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

              final bool isMainSkillFile =
                  lowerName == 'skill.md' ||
                  lowerName == 'skills.md' ||
                  lowerName.endsWith('.prompt.md') ||
                  relPath.contains('.cursor/rules/') ||
                  lowerName == '.windsurfrules';

              if (isMainSkillFile && !processedSkillPaths.contains(relPath)) {
                processedSkillPaths.add(relPath);

                try {
                  final stat = entity.statSync();
                  if (stat.size <= _maxFileSizeBytes) {
                    final content = entity.readAsStringSync();
                    final frontmatter = _parseFrontmatter(content);

                    String name = frontmatter['name'] ?? '';
                    if (name.isEmpty) {
                      final parentDirName = p.basename(entity.parent.path);
                      if ((lowerName == 'skill.md' ||
                              lowerName == 'skills.md') &&
                          parentDirName.isNotEmpty &&
                          parentDirName != 'skills' &&
                          parentDirName != '.agents' &&
                          parentDirName != '.github' &&
                          parentDirName != '.claude') {
                        name = parentDirName;
                      } else {
                        name = p.basenameWithoutExtension(baseName);
                      }
                    }

                    String description = frontmatter['description'] ?? '';
                    if (description.isEmpty) {
                      description = 'Agent skill from $relPath';
                    }

                    final List<AgentSkillReference> references = [];
                    final skillDir = entity.parent;
                    final skillDirNorm = _normalizeDriveLetter(skillDir.path);

                    if (skillDir.existsSync() &&
                        skillDirNorm != canonicalRoot &&
                        (lowerName == 'skill.md' || lowerName == 'skills.md')) {
                      try {
                        final referencesDir = Directory(
                          p.join(skillDir.path, 'references'),
                        );
                        final List<FileSystemEntity> targetEntities = [];

                        if (referencesDir.existsSync()) {
                          targetEntities.addAll(
                            referencesDir.listSync(
                              recursive: true,
                              followLinks: false,
                            ),
                          );
                        } else {
                          targetEntities.addAll(
                            skillDir.listSync(followLinks: false),
                          );
                        }

                        for (final refEntity in targetEntities) {
                          if (refEntity is File) {
                            final refBaseName = p
                                .basename(refEntity.path)
                                .toLowerCase();
                            final refNormPath = _normalizeDriveLetter(
                              refEntity.path,
                            );
                            final refRelToSkill = p
                                .relative(refNormPath, from: skillDirNorm)
                                .replaceAll('\\', '/');

                            if (refBaseName != 'skill.md' &&
                                refBaseName != 'skills.md' &&
                                !refBaseName.startsWith('license') &&
                                refBaseName != 'readme.md' &&
                                !refBaseName.startsWith('.')) {
                              try {
                                final refStat = refEntity.statSync();
                                if (refStat.size <= _maxFileSizeBytes) {
                                  final refContent = refEntity
                                      .readAsStringSync();
                                  references.add(
                                    AgentSkillReference(
                                      relativePath: refRelToSkill,
                                      content: refContent,
                                    ),
                                  );
                                }
                              } catch (_) {}
                            }
                          }
                        }
                      } catch (_) {}
                    }

                    detected.add(
                      AgentSkill(
                        id: relPath,
                        name: name,
                        description: description,
                        content: content,
                        sourcePath: relPath,
                        isCustom: false,
                        references: references,
                      ),
                    );
                  }
                } catch (_) {}
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

  /// Parses YAML frontmatter headers from markdown content without requiring external YAML libraries.
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

  /// Synchronous binary data evaluator checking null byte ratios.
  static bool _isBinaryDataSync(Uint8List data) {
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
