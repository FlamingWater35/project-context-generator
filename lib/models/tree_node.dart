import 'package:flutter/foundation.dart';

/// Represents a flattened row item in the virtualized tree list view.
@immutable
class FlatTreeItem {
  const FlatTreeItem({
    required this.node,
    required this.depth,
    required this.isExpanded,
    required this.hasChildren,
  });

  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final TreeNode node;
}

/// Immutable data structure representing a structural node in the filesystem tree.
class TreeNode {
  const TreeNode({
    required this.path,
    required this.relativePath,
    required this.name,
    required this.isDirectory,
    this.children = const [],
    this.isNew = false,
  });

  final List<TreeNode> children;
  final bool isDirectory;
  final bool isNew;
  final String name;
  final String path;
  final String relativePath;

  /// Safely creates a cloned copy of the TreeNode with updated properties.
  TreeNode copyWith({
    String? path,
    String? relativePath,
    String? name,
    bool? isDirectory,
    List<TreeNode>? children,
    bool? isNew,
  }) {
    return TreeNode(
      path: path ?? this.path,
      relativePath: relativePath ?? this.relativePath,
      name: name ?? this.name,
      isDirectory: isDirectory ?? this.isDirectory,
      children: children ?? this.children,
      isNew: isNew ?? this.isNew,
    );
  }

  /// Recursively flattens the visible tree nodes into a 1D list for virtualized ListView rendering using a single accumulator.
  List<FlatTreeItem> flattenVisibleTree(
    Map<String, bool> expansionState, {
    int depth = 0,
  }) {
    final List<FlatTreeItem> result = [];
    _flattenTreeRecursive(this, expansionState, depth, result);
    return result;
  }

  static void _flattenTreeRecursive(
    TreeNode node,
    Map<String, bool> expansionState,
    int depth,
    List<FlatTreeItem> accumulator,
  ) {
    for (final child in node.children) {
      final isExpanded = expansionState[child.relativePath] ?? false;
      final hasChildren = child.isDirectory && child.children.isNotEmpty;

      accumulator.add(
        FlatTreeItem(
          node: child,
          depth: depth,
          isExpanded: isExpanded,
          hasChildren: hasChildren,
        ),
      );

      if (child.isDirectory && isExpanded) {
        _flattenTreeRecursive(child, expansionState, depth + 1, accumulator);
      }
    }
  }

  /// Populates a lookup map of relativePath to TreeNode for O(1) path access.
  void buildPathMap(Map<String, TreeNode> map) {
    map[relativePath] = this;
    for (final child in children) {
      child.buildPathMap(map);
    }
  }

  /// Retrieves all descendant relative file paths recursively under this node.
  List<String> getAllFilePaths() {
    if (!isDirectory) return [relativePath];
    final List<String> paths = [];
    for (final child in children) {
      paths.addAll(child.getAllFilePaths());
    }
    return paths;
  }

  /// Collects all non-empty relative paths (both files and directories) for single-pass snapshot calculation.
  Set<String> getAllRelativePaths() {
    final Set<String> paths = {};
    if (relativePath.isNotEmpty) {
      paths.add(relativePath);
    }
    for (final child in children) {
      paths.addAll(child.getAllRelativePaths());
    }
    return paths;
  }
}
