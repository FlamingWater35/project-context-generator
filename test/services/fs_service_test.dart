import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:project_context_generator/models/agent_skill.dart';
import 'package:project_context_generator/services/fs_service.dart';

import '../helpers/test_utils.dart';

void main() {
  late FsService service;

  setUp(() {
    service = FsService();
  });

  Directory createProjectFixture() {
    final root = createTempDir('pcg_fs_');
    writeFile(root, 'README.md', '# Readme');
    writeFile(root, 'lib/main.dart', "void main() => print('hi');");
    writeFile(root, 'lib/util.dart', 'String trimIt(String v) => v.trim();');
    writeFile(root, 'src/nested/deep.txt', 'deep');
    writeFile(root, 'src/other.txt', 'other');
    writeFile(root, 'src/lib/keep.txt', 'keep');
    writeFile(root, 'docs/guide.md', '# Guide');
    writeFile(root, 'build/out.txt', 'build output');
    writeFile(root, 'node_modules/pkg/index.js', 'module.exports = {};');
    writeFile(root, 'logs/app.log', 'log line');
    writeFile(root, '.git/config', '[core]');
    writeFile(root, '.hidden', 'hidden');
    writeBytes(root, 'binary.bin', [0, 1, 2, 3, 0, 0, 0]);
    Directory(p.join(root.path, 'empty')).createSync();
    return root;
  }

  const defaultIgnores = ['.git/**', 'node_modules/**', 'build/**', '*.log'];

  group('buildTree', () {
    test('returns null for a missing root', () async {
      expect(
        await service.buildTree(
          p.join(createTempDir('pcg_missing_').path, 'does-not-exist'),
          const [],
        ),
        isNull,
      );
    });

    test(
      'builds a sorted hierarchy and prunes ignored/empty directories',
      () async {
        final root = createProjectFixture();

        final tree = await service.buildTree(root.path, defaultIgnores);

        expect(tree, isNotNull);
        expect(tree!.children.map((c) => c.name), [
          'docs',
          'lib',
          'src',
          '.hidden',
          'binary.bin',
          'README.md',
        ]);
        expect(
          tree.children.any(
            (c) => ['build', 'node_modules', 'logs', '.git'].contains(c.name),
          ),
          isFalse,
        );
        expect(tree.children.any((c) => c.name == 'empty'), isFalse);

        final lib = tree.children.firstWhere((c) => c.name == 'lib');
        expect(lib.isDirectory, isTrue);
        expect(lib.children.map((c) => c.name), ['main.dart', 'util.dart']);
        expect(lib.children.first.relativePath, 'lib/main.dart');

        final src = tree.children.firstWhere((c) => c.name == 'src');
        expect(src.children.map((c) => c.name), ['lib', 'nested', 'other.txt']);
        final nested = src.children.firstWhere((c) => c.name == 'nested');
        expect(nested.children.single.relativePath, 'src/nested/deep.txt');
      },
    );

    test('reports relative paths with forward slashes', () async {
      final root = createProjectFixture();

      final tree = await service.buildTree(root.path, defaultIgnores);

      final paths = tree!.getAllRelativePaths();
      expect(paths, contains('lib/main.dart'));
      expect(paths, contains('src/nested/deep.txt'));
      expect(paths.every((path) => !path.contains(r'\')), isTrue);
    });

    test('honours root-anchored patterns only at the root', () async {
      final root = createProjectFixture();

      final tree = await service.buildTree(root.path, const ['/lib/**']);

      expect(tree!.children.map((c) => c.name), isNot(contains('lib')));
      final src = tree.children.firstWhere((c) => c.name == 'src');
      expect(src.children.map((c) => c.name), contains('lib'));
    });

    test('honours directory-only patterns at the project root', () async {
      final root = createProjectFixture();

      final tree = await service.buildTree(root.path, const ['docs/']);

      expect(tree!.children.map((c) => c.name), isNot(contains('docs')));
    });

    test('honours **/ wrapped directory patterns at any depth', () async {
      final root = createProjectFixture();
      writeFile(root, 'nested/inside.txt', 'root nested');

      final tree = await service.buildTree(root.path, const ['**/nested/**']);

      expect(tree!.children.map((c) => c.name), isNot(contains('nested')));
      final src = tree.children.firstWhere((c) => c.name == 'src');
      expect(src.children.map((c) => c.name), isNot(contains('nested')));
    });

    test('prunes files matching a wildcard extension pattern', () async {
      final root = createProjectFixture();

      final tree = await service.buildTree(root.path, const ['*.dart']);

      expect(tree!.children.map((c) => c.name), isNot(contains('lib')));
      expect(
        tree.getAllRelativePaths().every((path) => !path.endsWith('.dart')),
        isTrue,
      );
    });

    test('ignores blank patterns, comments, and invalid globs', () async {
      final root = createProjectFixture();

      final tree = await service.buildTree(root.path, const [
        '',
        '   ',
        '# a comment',
        '[invalid',
      ]);

      expect(tree, isNotNull);
      expect(tree!.children.map((c) => c.name), contains('README.md'));
      expect(tree.children.map((c) => c.name), contains('lib'));
    });

    test('marks paths missing from the known snapshot as new', () async {
      final root = createProjectFixture();

      final tree = await service.buildTree(
        root.path,
        defaultIgnores,
        knownPaths: {'lib/main.dart'},
      );

      final lib = tree!.children.firstWhere((c) => c.name == 'lib');
      expect(lib.isNew, isTrue);
      expect(
        lib.children.firstWhere((c) => c.name == 'main.dart').isNew,
        isFalse,
      );
      expect(
        lib.children.firstWhere((c) => c.name == 'util.dart').isNew,
        isTrue,
      );

      final docs = tree.children.firstWhere((c) => c.name == 'docs');
      expect(docs.isNew, isTrue);
    });
  });

  group('scanPaths', () {
    test('returns every visible entry using the same ignore rules', () async {
      final root = createProjectFixture();

      final paths = await service.scanPaths(root.path, defaultIgnores);

      expect(paths, containsAll(['lib', 'lib/main.dart', 'docs/guide.md']));
      expect(paths, isNot(contains('build')));
      expect(paths, isNot(contains('logs')));
      expect(paths.any((path) => path.endsWith('.log')), isFalse);
    });

    test('returns an empty set for a missing root', () async {
      final paths = await service.scanPaths(
        p.join(createTempDir('pcg_missing_').path, 'nope'),
        const [],
      );

      expect(paths, isEmpty);
    });
  });

  group('buildPromptContext', () {
    test('assembles project header, tree, and selected file content', () async {
      final root = createProjectFixture();
      const skill = AgentSkill(
        id: 'review',
        name: 'Reviewer',
        description: 'Reviews code',
        content: 'Always add tests.',
        sourcePath: 'skills/reviewer/SKILL.md',
        references: [
          AgentSkillReference(
            relativePath: 'references/style.md',
            content: 'Use trailing commas.',
          ),
        ],
      );

      final result = await service.buildPromptContext(
        PromptBuildParams(
          projectName: 'Demo',
          rootPath: root.path,
          includedFiles: const [
            'lib/main.dart',
            'docs/guide.md',
            'logs/app.log',
            'missing.dart',
          ],
          selectedSkills: const [skill],
          ignorePatterns: defaultIgnores,
        ),
      );

      expect(result.promptText, startsWith('--- PROJECT CONTEXT: Demo ---'));
      expect(result.promptText, contains('File Tree Structure:'));
      expect(result.promptText, contains('main.dart [selected]'));
      expect(result.promptText, contains('guide.md [selected]'));
      expect(result.promptText, isNot(contains('app.log')));

      expect(result.promptText, contains('--- MAIN FILE(S) CONTENT ---'));
      expect(result.promptText, contains('--- File: lib/main.dart ---'));
      expect(result.promptText, contains("void main() => print('hi');"));
      expect(result.promptText, contains('--- File: docs/guide.md ---'));
      expect(result.promptText, contains('--- End File ---'));

      expect(result.promptText, contains('--- AGENT SKILLS ---'));
      expect(result.promptText, contains('--- Skill: Reviewer ---'));
      expect(result.promptText, contains('Description: Reviews code'));
      expect(result.promptText, contains('Source: skills/reviewer/SKILL.md'));
      expect(result.promptText, contains('Always add tests.'));
      expect(
        result.promptText,
        contains('--- Skill Reference: references/style.md ---'),
      );
      expect(result.promptText, contains('Use trailing commas.'));

      expect(result.fileCount, 2);
      expect(result.skillCount, 1);
      expect(result.totalLines, result.promptText.split('\n').length);
      expect(result.sections, isEmpty);
      expect(result.isTruncated, isFalse);
      expect(result.displayText, result.promptText);
    });

    test(
      'omits the agent skills section when no skills are selected',
      () async {
        final root = createProjectFixture();

        final result = await service.buildPromptContext(
          PromptBuildParams(
            projectName: 'Demo',
            rootPath: root.path,
            includedFiles: const ['README.md'],
            selectedSkills: const [],
            ignorePatterns: defaultIgnores,
          ),
        );

        expect(result.promptText, isNot(contains('AGENT SKILLS')));
        expect(result.skillCount, 0);
        expect(result.fileCount, 1);
      },
    );

    test('uses placeholders for binary and oversized files', () async {
      final root = createTempDir('pcg_binary_');
      writeBytes(root, 'binary.bin', List<int>.generate(64, (i) => i % 4));
      // Deliberately well above the 1 MiB limit to avoid a boundary race
      // between the write and the stat call made from the isolate.
      writeFile(root, 'huge.txt', 'x' * (2 * 1024 * 1024));

      final result = await service.buildPromptContext(
        PromptBuildParams(
          projectName: 'Binary',
          rootPath: root.path,
          includedFiles: const ['binary.bin', 'huge.txt'],
          selectedSkills: const [],
          ignorePatterns: const [],
        ),
      );

      expect(result.promptText, contains('<Binary file>'));
      expect(result.promptText, contains('<File too large (2.00 MB)>'));
      expect(result.fileCount, 2);
    });

    test('reports a missing root without throwing', () async {
      final result = await service.buildPromptContext(
        PromptBuildParams(
          projectName: 'Missing',
          rootPath: p.join(createTempDir('pcg_missing_').path, 'nope'),
          includedFiles: const ['a.dart'],
          selectedSkills: const [],
          ignorePatterns: const [],
        ),
      );

      expect(result.promptText, 'Root directory does not exist.');
      expect(result.displayText, 'Root directory does not exist.');
      expect(result.fileCount, 0);
      expect(result.totalLines, 1);
    });

    test('handles an empty selected file list', () async {
      final root = createProjectFixture();

      final result = await service.buildPromptContext(
        PromptBuildParams(
          projectName: 'Empty',
          rootPath: root.path,
          includedFiles: const [],
          selectedSkills: const [],
          ignorePatterns: defaultIgnores,
        ),
      );

      expect(result.fileCount, 0);
      expect(result.promptText, contains('--- MAIN FILE(S) CONTENT ---'));
      expect(result.promptText, isNot(contains('--- File:')));
    });
  });

  group('detectSkills', () {
    test('returns an empty list for empty or missing roots', () async {
      expect(await service.detectSkills(''), isEmpty);
      expect(
        await service.detectSkills(
          p.join(createTempDir('pcg_missing_').path, 'nope'),
        ),
        isEmpty,
      );
    });

    test('detects and parses skill files with frontmatter', () async {
      final root = createTempDir('pcg_skills_');
      writeFile(root, 'skills/reviewer/SKILL.md', '''
---
name: "Reviewer"
description: 'Reviews code changes'
---
Always review diffs.
''');
      writeFile(root, 'docs/guide.prompt.md', '# Guide');
      writeFile(root, '.windsurfrules', 'Follow the rules.');
      writeFile(root, '.cursor/rules/style.md', '# Style');
      writeFile(root, 'SKILL.md', '# Root skill');

      final skills = await service.detectSkills(root.path);
      final byId = {for (final skill in skills) skill.id: skill};

      expect(
        byId.keys,
        containsAll([
          'skills/reviewer/SKILL.md',
          'docs/guide.prompt.md',
          '.windsurfrules',
          '.cursor/rules/style.md',
          'SKILL.md',
        ]),
      );

      final reviewer = byId['skills/reviewer/SKILL.md']!;
      expect(reviewer.name, 'Reviewer');
      expect(reviewer.description, 'Reviews code changes');
      expect(reviewer.content, contains('Always review diffs.'));
      expect(reviewer.isCustom, isFalse);
      expect(reviewer.sourcePath, 'skills/reviewer/SKILL.md');

      expect(byId['docs/guide.prompt.md']!.name, 'guide.prompt');
      expect(
        byId['docs/guide.prompt.md']!.description,
        'Agent skill from docs/guide.prompt.md',
      );
      expect(byId['.windsurfrules']!.content, 'Follow the rules.');
      expect(byId['.cursor/rules/style.md']!.name, 'style');
      // Root-level SKILL.md falls back to its own filename, not the project folder.
      expect(byId['SKILL.md']!.name, 'SKILL');
    });

    test('uses parent directory names for nested SKILL.md files', () async {
      final root = createTempDir('pcg_skills_');
      writeFile(root, '.claude/skills/beta/SKILL.md', 'Beta body');
      writeFile(root, '.github/skills/gamma/SKILL.md', 'Gamma body');
      writeFile(root, '.github/SKILL.md', 'Github body');
      writeFile(root, 'skills/SKILL.md', 'Skills body');

      final skills = await service.detectSkills(root.path);
      final byId = {for (final skill in skills) skill.id: skill};

      expect(byId['.claude/skills/beta/SKILL.md']!.name, 'beta');
      expect(byId['.github/skills/gamma/SKILL.md']!.name, 'gamma');
      expect(byId['.github/SKILL.md']!.name, 'SKILL');
      expect(byId['skills/SKILL.md']!.name, 'SKILL');
    });

    test('ignores build, dependency, and VCS folders', () async {
      final root = createTempDir('pcg_skills_');
      writeFile(root, 'node_modules/pkg/SKILL.md', 'ignored');
      writeFile(root, 'build/SKILL.md', 'ignored');
      writeFile(root, '.git/SKILL.md', 'ignored');
      writeFile(root, 'dist/SKILL.md', 'ignored');
      writeFile(root, 'target/SKILL.md', 'ignored');
      writeFile(root, 'vendor/SKILL.md', 'ignored');
      writeFile(root, '.idea/SKILL.md', 'ignored');
      writeFile(root, '.vscode/SKILL.md', 'ignored');
      writeFile(root, 'src/SKILL.md', 'kept');

      final skills = await service.detectSkills(root.path);

      expect(skills.map((s) => s.id), ['src/SKILL.md']);
    });

    test('discovers reference files in a references directory', () async {
      final root = createTempDir('pcg_skills_');
      writeFile(root, 'skills/alpha/SKILL.md', 'Alpha');
      writeFile(root, 'skills/alpha/references/one.md', 'One');
      writeFile(root, 'skills/alpha/references/sub/two.txt', 'Two');
      writeFile(root, 'skills/alpha/README.md', 'Readme');
      writeFile(root, 'skills/alpha/LICENSE', 'License');
      writeFile(root, 'skills/alpha/.hidden', 'Hidden');

      final skills = await service.detectSkills(root.path);
      final alpha = skills.single;

      expect(
        alpha.references.map((r) => r.relativePath),
        containsAll(['references/one.md', 'references/sub/two.txt']),
      );
      expect(
        alpha.references.any((r) => r.relativePath.contains('README.md')),
        isFalse,
      );
      expect(
        alpha.references.any((r) => r.relativePath.contains('LICENSE')),
        isFalse,
      );
      expect(
        alpha.references.any((r) => r.relativePath.contains('.hidden')),
        isFalse,
      );
    });

    test(
      'discovers sibling reference files when no references folder exists',
      () async {
        final root = createTempDir('pcg_skills_');
        writeFile(root, 'skills/beta/SKILL.md', 'Beta');
        writeFile(root, 'skills/beta/notes.md', 'Notes');
        writeFile(root, 'skills/beta/extra.txt', 'Extra');
        writeFile(root, 'skills/beta/README.md', 'Readme');
        writeFile(root, 'skills/beta/LICENSE.md', 'License');
        writeFile(root, 'skills/beta/.secret', 'Secret');
        writeFile(root, 'skills/beta/nested/inner.md', 'Inner');

        final skills = await service.detectSkills(root.path);
        final beta = skills.single;
        final refs = beta.references.map((r) => r.relativePath).toList();

        expect(refs, containsAll(['notes.md', 'extra.txt']));
        expect(refs, isNot(contains('README.md')));
        expect(refs, isNot(contains('LICENSE.md')));
        expect(refs, isNot(contains('.secret')));
        expect(refs, isNot(contains('nested/inner.md')));
      },
    );

    test('does not attach references to prompt files', () async {
      final root = createTempDir('pcg_skills_');
      writeFile(root, 'rules.prompt.md', 'Prompt');
      writeFile(root, 'notes.md', 'Notes');

      final skills = await service.detectSkills(root.path);

      expect(skills.single.references, isEmpty);
    });

    test('skips skill files larger than one megabyte', () async {
      final root = createTempDir('pcg_skills_');
      final big = 'x' * (1024 * 1024 + 1);
      writeFile(root, 'skills/big/SKILL.md', big);
      writeFile(root, 'skills/small/SKILL.md', 'Small');

      final skills = await service.detectSkills(root.path);

      expect(skills.map((s) => s.id), ['skills/small/SKILL.md']);
    });
  });
}
