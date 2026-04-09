class TreeNode {
  TreeNode({
    required this.path,
    required this.relativePath,
    required this.name,
    required this.isDirectory,
    this.children = const [],
    this.isExpanded = false,
  });

  List<TreeNode> children;
  final bool isDirectory;
  bool isExpanded;
  final String name;
  final String path;
  final String relativePath;
}
