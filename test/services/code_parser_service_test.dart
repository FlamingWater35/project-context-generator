import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/services/code_parser_service.dart';

import '../helpers/test_utils.dart';

void main() {
  late String rootPath;

  setUp(() {
    rootPath = createTempDir('pcg_parser_').path;
  });

  group('markdown code block parsing', () {
    test('returns an empty list for empty input or empty root', () {
      expect(CodeParserService.parseCodeChanges('', rootPath), isEmpty);
      expect(CodeParserService.parseCodeChanges('   \n\t ', rootPath), isEmpty);
      expect(CodeParserService.parseCodeChanges('text', ''), isEmpty);
    });

    test('uses a path found in the code fence header', () {
      const text = '''
Here is the updated file:
```dart:lib/main.dart
void main() => print('hello');
```
''';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);

      expect(changes, hasLength(1));
      expect(changes.single.relativePath, 'lib/main.dart');
      expect(changes.single.newContent, "void main() => print('hello');");
      expect(changes.single.isNewFile, isTrue);
    });

    test('accepts a bare path in the code fence header', () {
      const text = '''
```lib/service.dart
const value = 1;
```
''';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);

      expect(changes.single.relativePath, 'lib/service.dart');
      expect(changes.single.newContent, 'const value = 1;');
    });

    test('recognises extensionless well-known files in headers', () {
      const text = '''
```Dockerfile
FROM scratch
```
''';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);

      expect(changes.single.relativePath, 'Dockerfile');
    });

    test('uses the closest preceding "File:" heading', () {
      const text = '''
### File: lib/a.dart
```dart
final a = 1;
```

### File: lib/b.dart
```dart
final b = 2;
```
''';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);

      expect(changes, hasLength(2));
      final byPath = {for (final c in changes) c.relativePath: c.newContent};
      expect(byPath['lib/a.dart'], 'final a = 1;');
      expect(byPath['lib/b.dart'], 'final b = 2;');
    });

    test('uses bold and backticked paths preceding a block', () {
      const text = '''
Update **lib/bold.dart**:
```dart
final bold = true;
```

Now update `lib/quoted file.dart`:
```dart
final spaced = true;
```
''';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);

      expect(changes, hasLength(2));
      final byPath = {for (final c in changes) c.relativePath: c.newContent};
      expect(byPath['lib/bold.dart'], 'final bold = true;');
      expect(byPath['lib/quoted file.dart'], 'final spaced = true;');
    });

    test(
      'does not produce changes when only URLs or imports precede blocks',
      () {
        const text = '''
See https://example.com/remote.dart for details.
```dart
final x = 1;
```

import 'package:flutter/material.dart';
```dart
final y = 2;
```
''';

        final changes = CodeParserService.parseCodeChanges(text, rootPath);

        expect(changes, isEmpty);
      },
    );

    test('later blocks for the same path override earlier content', () {
      const text = '''
### File: lib/a.dart
```dart
final first = 1;
```

### File: lib/a.dart
```dart
final second = 2;
```
''';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);

      expect(changes, hasLength(1));
      expect(changes.single.newContent, 'final second = 2;');
    });

    test('ignores blocks without any determinable path', () {
      const text = '''
Some prose without a path.
```dart
final lonely = true;
```
''';

      expect(CodeParserService.parseCodeChanges(text, rootPath), isEmpty);
    });

    test('normalises Windows separators in parsed paths', () {
      const text = r'''
### File: lib\windows\style.dart
```dart
final windows = true;
```
''';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);

      expect(changes.single.relativePath, 'lib/windows/style.dart');
    });

    test('strips leading ./ from parsed paths', () {
      const text = '''
### File: ./lib/main.dart
```dart
final main = true;
```
''';

      expect(
        CodeParserService.parseCodeChanges(text, rootPath).single.relativePath,
        'lib/main.dart',
      );
    });

    test('marks existing files as modified and missing files as new', () {
      final root = createTempDir('pcg_parser_existing_');
      writeFile(root, 'lib/existing.dart', 'old');

      const text = '''
### File: lib/existing.dart
```dart
new
```

### File: lib/new.dart
```dart
fresh
```
''';

      final changes = CodeParserService.parseCodeChanges(text, root.path);
      final byPath = {for (final c in changes) c.relativePath: c};

      expect(byPath['lib/existing.dart']!.isNewFile, isFalse);
      expect(byPath['lib/new.dart']!.isNewFile, isTrue);
    });

    test('rejects path traversal attempts', () {
      const text = '''
### File: ../outside.dart
```dart
bad
```

### File: lib/../../outside.dart
```dart
bad
```
''';

      expect(CodeParserService.parseCodeChanges(text, rootPath), isEmpty);
    });

    test('handles CRLF line endings', () {
      const text =
          '### File: lib/crlf.dart\r\n```dart\r\nfinal crlf = true;\r\n```\r\n';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);

      expect(changes.single.relativePath, 'lib/crlf.dart');
      expect(changes.single.newContent, 'final crlf = true;');
    });

    test('preserves trailing code content without trimming indentation', () {
      const text = '''
```dart:lib/indent.dart
void main() {
  print('hi');
}
```
''';

      expect(
        CodeParserService.parseCodeChanges(text, rootPath).single.newContent,
        "void main() {\n  print('hi');\n}",
      );
    });
  });

  group('fallback --- File: ... --- parsing', () {
    test('parses generated prompt sections', () {
      const text = '''
--- File: lib/a.dart ---
final a = 1;
--- End File ---

--- File: README.md ---
# Readme
--- End File ---
''';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);
      final byPath = {for (final c in changes) c.relativePath: c.newContent};

      expect(changes, hasLength(2));
      expect(byPath['lib/a.dart'], 'final a = 1;');
      expect(byPath['README.md'], '# Readme');
    });

    test('is case-insensitive for section markers', () {
      const text = '''
--- file: lib/a.dart ---
final a = 1;
--- end file ---
''';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);

      expect(changes.single.relativePath, 'lib/a.dart');
      expect(changes.single.newContent, 'final a = 1;');
    });

    test('supports a section without an end marker', () {
      const text = '''
--- File: lib/a.dart ---
final a = 1;
''';

      final changes = CodeParserService.parseCodeChanges(text, rootPath);

      expect(changes.single.relativePath, 'lib/a.dart');
      expect(changes.single.newContent, 'final a = 1;');
    });

    test('rejects unsafe fallback sections', () {
      const text = '''
--- File: ../evil.dart ---
bad
--- End File ---
''';

      expect(CodeParserService.parseCodeChanges(text, rootPath), isEmpty);
    });
  });

  group('isPathSafe', () {
    test('accepts nested and root-level relative paths', () {
      expect(CodeParserService.isPathSafe(rootPath, 'lib/main.dart'), isTrue);
      expect(CodeParserService.isPathSafe(rootPath, 'README.md'), isTrue);
    });

    test('rejects traversal outside the root', () {
      expect(CodeParserService.isPathSafe(rootPath, '../secret.txt'), isFalse);
      expect(
        CodeParserService.isPathSafe(rootPath, 'lib/../../secret.txt'),
        isFalse,
      );
    });

    test('rejects empty inputs', () {
      expect(CodeParserService.isPathSafe('', 'a.dart'), isFalse);
      expect(CodeParserService.isPathSafe(rootPath, ''), isFalse);
    });
  });
}
