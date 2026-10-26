import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/tree_node.dart';

void main() {
  final tree = TreeNode(
    path: r'C:\root',
    relativePath: '',
    name: 'root',
    isDirectory: true,
    children: [
      TreeNode(
        path: r'C:\root\lib',
        relativePath: 'lib',
        name: 'lib',
        isDirectory: true,
        children: [
          TreeNode(
            path: r'C:\root\lib\main.dart',
            relativePath: 'lib/main.dart',
            name: 'main.dart',
            isDirectory: false,
          ),
          TreeNode(
            path: r'C:\root\lib\util.dart',
            relativePath: 'lib/util.dart',
            name: 'util.dart',
            isDirectory: false,
          ),
        ],
      ),
      TreeNode(
        path: r'C:\root\README.md',
        relativePath: 'README.md',
        name: 'README.md',
        isDirectory: false,
      ),
    ],
  );

  group('copyWith', () {
    test('replaces only supplied values', () {
      const node = TreeNode(
        path: '/a',
        relativePath: 'a',
        name: 'a',
        isDirectory: false,
        isNew: true,
      );

      final copy = node.copyWith(name: 'b', isDirectory: true);

      expect(copy.path, '/a');
      expect(copy.relativePath, 'a');
      expect(copy.name, 'b');
      expect(copy.isDirectory, isTrue);
      expect(copy.isNew, isTrue);
      expect(copy.children, isEmpty);
    });

    test('preserves children when not supplied', () {
      final copy = tree.copyWith();

      expect(copy.children, same(tree.children));
      expect(copy.isDirectory, tree.isDirectory);
      expect(copy.isNew, tree.isNew);
    });
  });

  group('flattenVisibleTree', () {
    test('shows only collapsed roots by default', () {
      final items = tree.flattenVisibleTree(const {});

      expect(items.map((i) => i.node.name), ['lib', 'README.md']);
      expect(items.every((i) => i.depth == 0), isTrue);
      expect(items.first.isExpanded, isFalse);
      expect(items.first.hasChildren, isTrue);
      expect(items[1].hasChildren, isFalse);
    });

    test('includes children with increased depth when expanded', () {
      final items = tree.flattenVisibleTree(const {'lib': true});

      expect(items.map((i) => i.node.relativePath), [
        'lib',
        'lib/main.dart',
        'lib/util.dart',
        'README.md',
      ]);
      expect(items[0].depth, 0);
      expect(items[1].depth, 1);
      expect(items[2].depth, 1);
      expect(items[3].depth, 0);
      expect(items[0].isExpanded, isTrue);
    });

    test('honours a custom starting depth', () {
      final items = tree.flattenVisibleTree(const {}, depth: 3);

      expect(items.every((i) => i.depth == 3), isTrue);
    });

    test('reports leaf nodes as having no children', () {
      final items = tree.flattenVisibleTree(const {'lib': true});
      final mainNode = items.firstWhere(
        (i) => i.node.relativePath == 'lib/main.dart',
      );

      expect(mainNode.hasChildren, isFalse);
      expect(mainNode.isExpanded, isFalse);
    });
  });

  group('buildPathMap', () {
    test('indexes every node including the root', () {
      final map = <String, TreeNode>{};
      tree.buildPathMap(map);

      expect(map.keys, containsAll(['', 'lib', 'lib/main.dart', 'README.md']));
      expect(map['lib'], same(tree.children.first));
      expect(map['lib/main.dart']!.name, 'main.dart');
    });
  });

  group('getAllFilePaths', () {
    test('returns its own path for a file', () {
      expect(tree.children.last.getAllFilePaths(), ['README.md']);
    });

    test('returns every descendant file for a directory', () {
      expect(tree.getAllFilePaths(), [
        'lib/main.dart',
        'lib/util.dart',
        'README.md',
      ]);
    });

    test('returns an empty list for an empty directory', () {
      const empty = TreeNode(
        path: '/empty',
        relativePath: 'empty',
        name: 'empty',
        isDirectory: true,
      );

      expect(empty.getAllFilePaths(), isEmpty);
    });
  });

  group('getAllRelativePaths', () {
    test('includes directories and files but omits the empty root path', () {
      final paths = tree.getAllRelativePaths();

      expect(paths, {'lib', 'lib/main.dart', 'lib/util.dart', 'README.md'});
    });

    test('omits an empty directory because it has no children', () {
      const empty = TreeNode(
        path: '/empty',
        relativePath: 'empty',
        name: 'empty',
        isDirectory: true,
      );

      expect(empty.getAllRelativePaths(), {'empty'});
    });
  });
}
