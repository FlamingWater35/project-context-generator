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
}
