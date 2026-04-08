class TreeNode {
  final String path;
  final String relativePath;
  final String name;
  final bool isDirectory;
  List<TreeNode> children;
  bool isExpanded;

  TreeNode({
    required this.path,
    required this.relativePath,
    required this.name,
    required this.isDirectory,
    this.children = const[],
    this.isExpanded = false,
  });
}
