import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/code_change.dart';

/// Service parsing file code changes from LLM responses by pairing each code block with its preceding file path.
class CodeParserService {
  /// Known source code and configuration file extensions for path verification.
  static const Set<String> _knownExtensions = {
    'dart',
    'js',
    'jsx',
    'ts',
    'tsx',
    'py',
    'html',
    'css',
    'scss',
    'json',
    'yaml',
    'yml',
    'toml',
    'xml',
    'md',
    'txt',
    'cpp',
    'c',
    'h',
    'hpp',
    'java',
    'kt',
    'rs',
    'go',
    'sh',
    'swift',
    'rb',
    'php',
    'gradle',
    'properties',
    'env',
    'lock',
    'png',
    'jpg',
    'jpeg',
    'svg',
    'im',
    'pro',
    'conf',
    'ini',
  };

  /// Parses LLM text sequentially by matching each code block with its closest preceding path.
  static List<FileCodeChange> parseCodeChanges(String text, String rootPath) {
    if (text.trim().isEmpty || rootPath.isEmpty) return [];

    final Map<String, String> parsedFiles = {};

    // 1. Locate all markdown code blocks (``` ... ```)
    final codeBlockRegex = RegExp(r'```([^\r\n]*)\r?\n([\s\S]*?)\r?\n```');
    final matches = codeBlockRegex.allMatches(text).toList();

    if (matches.isNotEmpty) {
      int lastIndex = 0;

      for (final match in matches) {
        final header = match.group(1)?.trim() ?? '';
        final content = match.group(2) ?? '';

        String? detectedPath;

        // A. Check if the code block header itself contains a path (e.g. ```dart:lib/main.dart or ```lib/main.dart)
        detectedPath = _extractPathFromHeader(header, rootPath);

        // B. If header has no path, search text preceding this code block (after the previous code block)
        if (detectedPath == null) {
          final precedingText = text.substring(lastIndex, match.start);
          detectedPath = _extractPathFromText(precedingText, rootPath);
        }

        lastIndex = match.end;

        if (detectedPath != null) {
          parsedFiles[detectedPath] = content;
        }
      }
    } else {
      // 2. Fallback for non-markdown format: --- File: path --- \n content \n --- End File ---
      final fallbackRegex = RegExp(
        r'--- File:\s*([^\r\n]+?)\s*---\r?\n([\s\S]*?)(?=\r?\n--- End File ---|\r?\n--- File:|$)',
        caseSensitive: false,
      );

      for (final m in fallbackRegex.allMatches(text)) {
        final relPath = _cleanPathString(m.group(1) ?? '', rootPath);
        if (relPath != null) {
          parsedFiles[relPath] = _stripCodeFence(m.group(2) ?? '');
        }
      }
    }

    // Assemble validated results
    final List<FileCodeChange> results = [];
    final canonicalRoot = p.normalize(p.absolute(rootPath));

    for (final entry in parsedFiles.entries) {
      final relPath = entry.key;
      final targetPath = p.normalize(p.join(canonicalRoot, relPath));

      final file = File(targetPath);
      final bool isNew = !file.existsSync();

      results.add(
        FileCodeChange(
          relativePath: relPath,
          newContent: entry.value,
          isNewFile: isNew,
        ),
      );
    }

    return results;
  }

  /// Extracts path directly from code block header if present (e.g. ```dart:lib/main.dart).
  static String? _extractPathFromHeader(String header, String rootPath) {
    if (header.isEmpty) return null;

    final parts = header.split(RegExp(r'[:\s]+'));
    for (final part in parts.reversed) {
      final cleaned = _cleanPathString(part, rootPath);
      if (cleaned != null) return cleaned;
    }
    return null;
  }

  /// Extracts the most recent valid file path from text preceding a code block.
  static String? _extractPathFromText(String text, String rootPath) {
    if (text.trim().isEmpty) return null;

    final pathRegex = RegExp(
      r'(?:###|##|#|\*\*|---)?\s*(?:File:\s*)?`?([a-zA-Z0-9_\-\/\.\+]+?\.[a-zA-Z0-9]+)`?',
      caseSensitive: false,
    );

    final matches = pathRegex.allMatches(text).toList();

    // Iterate backwards to find the closest path reference right before the code block
    for (final m in matches.reversed) {
      final rawCandidate = m.group(1) ?? '';
      final cleaned = _cleanPathString(rawCandidate, rootPath);
      if (cleaned != null) {
        return cleaned;
      }
    }

    return null;
  }

  /// Cleans and validates candidate path strings safely using triple-quoted raw string regexes.
  static String? _cleanPathString(String raw, String rootPath) {
    var cleaned = raw.replaceAll(RegExp(r'''[`"':,\s\(\)]'''), '').trim();
    if (cleaned.isEmpty) return null;

    // Standardize slashes
    cleaned = cleaned.replaceAll('\\', '/');
    if (cleaned.startsWith('./')) {
      cleaned = cleaned.substring(2);
    } else if (cleaned.startsWith('/')) {
      cleaned = cleaned.substring(1);
    }

    // Ignore URLs or package / system imports
    if (cleaned.startsWith('http://') ||
        cleaned.startsWith('https://') ||
        cleaned.startsWith('package:') ||
        cleaned.startsWith('dart:')) {
      return null;
    }

    // Must contain slashes OR have a known file extension
    final bool hasSlash = cleaned.contains('/');
    final extMatch = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(cleaned);
    final ext = extMatch?.group(1)?.toLowerCase();

    final bool isKnownExt = ext != null && _knownExtensions.contains(ext);

    if (!hasSlash && !isKnownExt) {
      return null;
    }

    // Path safety validation against project root
    if (isPathSafe(rootPath, cleaned)) {
      return cleaned;
    }

    return null;
  }

  /// Evaluates target relative paths strictly against canonical project roots to prevent path traversal attacks.
  static bool isPathSafe(String rootPath, String relativePath) {
    if (rootPath.isEmpty || relativePath.isEmpty) return false;
    try {
      final canonicalRoot = p.normalize(p.absolute(rootPath));
      final targetPath = p.normalize(p.join(canonicalRoot, relativePath));

      return p.isWithin(canonicalRoot, targetPath) ||
          p.equals(canonicalRoot, targetPath);
    } catch (e) {
      debugPrint('Path safety validation error: $e');
      return false;
    }
  }

  /// Removes surrounding markdown code block fences if present inside parsed blocks.
  static String _stripCodeFence(String text) {
    var trimmed = text.trim();
    final fenceStart = RegExp(r'^```[a-zA-Z0-9_-]*\r?\n');
    if (fenceStart.hasMatch(trimmed) && trimmed.endsWith('```')) {
      trimmed = trimmed.replaceFirst(fenceStart, '');
      trimmed = trimmed.substring(0, trimmed.length - 3).trimRight();
    }
    return trimmed;
  }
}
