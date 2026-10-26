import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/code_change.dart';

void main() {
  group('FileCodeChange', () {
    test('starts selected by default', () {
      final change = FileCodeChange(
        relativePath: 'lib/main.dart',
        newContent: 'void main() {}',
        isNewFile: true,
      );

      expect(change.relativePath, 'lib/main.dart');
      expect(change.newContent, 'void main() {}');
      expect(change.isNewFile, isTrue);
      expect(change.isSelected, isTrue);
    });

    test('isSelected is mutable', () {
      final change = FileCodeChange(
        relativePath: 'a.dart',
        newContent: '',
        isNewFile: false,
      );

      change.isSelected = false;

      expect(change.isSelected, isFalse);
    });

    test('copyWith clones and overrides selection state', () {
      final change = FileCodeChange(
        relativePath: 'a.dart',
        newContent: 'content',
        isNewFile: false,
        isSelected: false,
      );

      final copy = change.copyWith(isSelected: true);

      expect(copy.relativePath, change.relativePath);
      expect(copy.newContent, change.newContent);
      expect(copy.isNewFile, change.isNewFile);
      expect(copy.isSelected, isTrue);
      // The copy must be a distinct object, not an alias.
      copy.isSelected = false;
      expect(change.isSelected, isFalse);
    });

    test('copyWith without arguments preserves selection', () {
      final change = FileCodeChange(
        relativePath: 'a.dart',
        newContent: 'content',
        isNewFile: false,
        isSelected: false,
      );

      expect(change.copyWith().isSelected, isFalse);
    });
  });
}
