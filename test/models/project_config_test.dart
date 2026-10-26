import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/agent_skill.dart';
import 'package:project_context_generator/models/project_config.dart';

void main() {
  group('ProjectConfig constructor', () {
    test('applies documented defaults', () {
      final before = DateTime.now();
      final config = ProjectConfig(id: 'id', name: 'Name');
      final after = DateTime.now();

      expect(config.id, 'id');
      expect(config.name, 'Name');
      expect(config.rootPath, '');
      expect(config.includedFiles, isEmpty);
      expect(config.ignorePatterns, ['.git/**', 'node_modules/**', 'build/**']);
      expect(config.selectedSkillIds, isEmpty);
      expect(config.customSkills, isEmpty);
      expect(
        config.createdAt.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(
        config.createdAt.isAfter(after.add(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('honours an explicit createdAt', () {
      final created = DateTime.utc(2020, 1, 2, 3, 4, 5);

      final config = ProjectConfig(id: 'id', name: 'Name', createdAt: created);

      expect(config.createdAt, created);
    });
  });

  group('ProjectConfig JSON', () {
    test('round-trips all fields', () {
      final created = DateTime.utc(2024, 5, 6, 7, 8, 9);
      final config = ProjectConfig(
        id: 'project-1',
        name: 'My Project',
        rootPath: r'C:\work\repo',
        includedFiles: const ['lib/main.dart', 'README.md'],
        ignorePatterns: const ['build/**', '*.log'],
        selectedSkillIds: const ['skill-a', 'skill-b'],
        customSkills: const [
          AgentSkill(
            id: 'custom-1',
            name: 'Custom',
            description: 'Custom skill',
            content: 'Do things.',
            isCustom: true,
            references: [
              AgentSkillReference(relativePath: 'r.md', content: 'body'),
            ],
          ),
        ],
        createdAt: created,
      );

      final restored = ProjectConfig.fromJson(config.toJson());

      expect(restored.id, 'project-1');
      expect(restored.name, 'My Project');
      expect(restored.rootPath, r'C:\work\repo');
      expect(restored.includedFiles, ['lib/main.dart', 'README.md']);
      expect(restored.ignorePatterns, ['build/**', '*.log']);
      expect(restored.selectedSkillIds, ['skill-a', 'skill-b']);
      expect(restored.customSkills, hasLength(1));
      expect(restored.customSkills.single.id, 'custom-1');
      expect(restored.customSkills.single.references.single.content, 'body');
      expect(restored.createdAt, created);
    });

    test('falls back when required fields are missing', () {
      final config = ProjectConfig.fromJson(const {});

      expect(config.id, 'corrupted_fallback');
      expect(config.name, 'Unreadable Config');
      expect(config.rootPath, '');
      expect(config.includedFiles, isEmpty);
      expect(config.ignorePatterns, ['.git/**', 'node_modules/**', 'build/**']);
    });

    test('falls back when id/name have the wrong runtime type', () {
      final config = ProjectConfig.fromJson(const {'id': 42, 'name': true});

      expect(config.id, 'corrupted_fallback');
      expect(config.name, 'Unreadable Config');
    });

    test('keeps a valid partial record when only optional data is missing', () {
      final config = ProjectConfig.fromJson(const {
        'id': 'partial',
        'name': 'Partial',
      });

      expect(config.id, 'partial');
      expect(config.name, 'Partial');
      expect(config.rootPath, '');
      expect(config.includedFiles, isEmpty);
      expect(config.ignorePatterns, ['.git/**', 'node_modules/**', 'build/**']);
      expect(config.selectedSkillIds, isEmpty);
      expect(config.customSkills, isEmpty);
    });

    test('treats null ignorePatterns as the default ignore list', () {
      final config = ProjectConfig.fromJson(const {
        'id': 'id',
        'name': 'name',
        'ignorePatterns': null,
      });

      expect(config.ignorePatterns, ['.git/**', 'node_modules/**', 'build/**']);
    });

    test('accepts an empty ignorePatterns list verbatim', () {
      final config = ProjectConfig.fromJson(const {
        'id': 'id',
        'name': 'name',
        'ignorePatterns': <String>[],
      });

      expect(config.ignorePatterns, isEmpty);
    });

    test('uses now when createdAt cannot be parsed', () {
      final before = DateTime.now();
      final config = ProjectConfig.fromJson(const {
        'id': 'id',
        'name': 'name',
        'createdAt': 'not-a-date',
      });

      expect(
        config.createdAt.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('falls back when a list has an invalid runtime type', () {
      final config = ProjectConfig.fromJson(const {
        'id': 'id',
        'name': 'name',
        'customSkills': 'not-a-list',
      });

      expect(config.id, 'id');
      expect(config.name, 'name');
      expect(config.customSkills, isEmpty);
    });

    test('drops corrupted custom skills through the skill fallback', () {
      final config = ProjectConfig.fromJson(const {
        'id': 'id',
        'name': 'name',
        'customSkills': [
          {'id': 'skill', 'name': 'Skill', 'references': null},
        ],
      });

      expect(config.customSkills, hasLength(1));
      expect(config.customSkills.single.id, 'skill');
      expect(config.customSkills.single.name, 'Skill');
    });
  });

  group('ProjectConfig.copyWith', () {
    test('replaces every supplied field and preserves the rest', () {
      final created = DateTime.utc(2020);
      final config = ProjectConfig(
        id: 'id',
        name: 'Name',
        rootPath: '/root',
        includedFiles: const ['a.dart'],
        ignorePatterns: const ['x/**'],
        selectedSkillIds: const ['skill'],
        customSkills: const [
          AgentSkill(id: 'skill', name: 'Skill', description: '', content: ''),
        ],
        createdAt: created,
      );

      final copy = config.copyWith(
        id: 'new-id',
        name: 'New Name',
        rootPath: '/new-root',
        includedFiles: const ['b.dart'],
        ignorePatterns: const ['y/**'],
        selectedSkillIds: const ['skill-2'],
        customSkills: const [],
        createdAt: DateTime.utc(2022),
      );

      expect(copy.id, 'new-id');
      expect(copy.name, 'New Name');
      expect(copy.rootPath, '/new-root');
      expect(copy.includedFiles, ['b.dart']);
      expect(copy.ignorePatterns, ['y/**']);
      expect(copy.selectedSkillIds, ['skill-2']);
      expect(copy.customSkills, isEmpty);
      expect(copy.createdAt, DateTime.utc(2022));
    });

    test('without arguments produces an equivalent config', () {
      final config = ProjectConfig(
        id: 'id',
        name: 'Name',
        rootPath: '/root',
        includedFiles: const ['a.dart'],
      );

      final copy = config.copyWith();

      expect(copy.id, config.id);
      expect(copy.name, config.name);
      expect(copy.rootPath, config.rootPath);
      expect(copy.includedFiles, config.includedFiles);
      expect(copy.ignorePatterns, config.ignorePatterns);
      expect(copy.selectedSkillIds, config.selectedSkillIds);
      expect(copy.customSkills, config.customSkills);
      expect(copy.createdAt, config.createdAt);
    });
  });
}
