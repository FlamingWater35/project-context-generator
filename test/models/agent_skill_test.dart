import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/agent_skill.dart';

void main() {
  group('AgentSkillReference', () {
    test('round-trips through JSON', () {
      const reference = AgentSkillReference(
        relativePath: 'references/guide.md',
        content: '# Guide',
      );

      final json = reference.toJson();

      expect(json['relativePath'], 'references/guide.md');
      expect(json['content'], '# Guide');

      final restored = AgentSkillReference.fromJson(json);
      expect(restored.relativePath, 'references/guide.md');
      expect(restored.content, '# Guide');
    });

    test('defaults missing values to empty strings', () {
      final reference = AgentSkillReference.fromJson(const {});

      expect(reference.relativePath, '');
      expect(reference.content, '');
    });
  });

  group('AgentSkill', () {
    test('round-trips through JSON including references', () {
      const skill = AgentSkill(
        id: 'skill-1',
        name: 'Reviewer',
        description: 'Reviews code',
        content: 'Always test.',
        sourcePath: '.agents/skills/reviewer/SKILL.md',
        isCustom: true,
        references: [
          AgentSkillReference(relativePath: 'ref.md', content: 'ref body'),
        ],
      );

      final json = skill.toJson();
      final restored = AgentSkill.fromJson(json);

      expect(restored.id, skill.id);
      expect(restored.name, skill.name);
      expect(restored.description, skill.description);
      expect(restored.content, skill.content);
      expect(restored.sourcePath, skill.sourcePath);
      expect(restored.isCustom, isTrue);
      expect(restored.references, hasLength(1));
      expect(restored.references.single.relativePath, 'ref.md');
      expect(restored.references.single.content, 'ref body');
    });

    test('applies defaults when JSON keys are absent', () {
      final skill = AgentSkill.fromJson(const {});

      expect(skill.id, '');
      expect(skill.name, 'Unnamed Skill');
      expect(skill.description, '');
      expect(skill.content, '');
      expect(skill.sourcePath, isNull);
      expect(skill.isCustom, isFalse);
      expect(skill.references, isEmpty);
    });

    test('falls back safely when reference entries are corrupted', () {
      final skill = AgentSkill.fromJson(const {
        'id': 'broken',
        'name': 'Broken Skill',
        'references': [
          {'relativePath': 1, 'content': 2},
        ],
      });

      expect(skill.id, 'broken');
      expect(skill.name, 'Broken Skill');
      expect(skill.description, '');
      expect(skill.content, '');
      expect(skill.references, isEmpty);
    });

    test('falls back safely when id and name have wrong types', () {
      final skill = AgentSkill.fromJson(const {'id': 7, 'name': false});

      expect(skill.id, 'corrupted_skill');
      expect(skill.name, 'Unreadable Skill');
    });

    test('copyWith replaces only the supplied fields', () {
      const skill = AgentSkill(
        id: 'id',
        name: 'Name',
        description: 'Description',
        content: 'Content',
        sourcePath: 'source.md',
        references: [AgentSkillReference(relativePath: 'a', content: 'b')],
      );

      final copy = skill.copyWith(name: 'New name', isCustom: true);

      expect(copy.id, 'id');
      expect(copy.name, 'New name');
      expect(copy.description, 'Description');
      expect(copy.content, 'Content');
      expect(copy.sourcePath, 'source.md');
      expect(copy.isCustom, isTrue);
      expect(copy.references, same(skill.references));
    });

    test('copyWith without arguments preserves every value', () {
      const skill = AgentSkill(
        id: 'id',
        name: 'Name',
        description: 'Description',
        content: 'Content',
        sourcePath: 'source.md',
      );

      final copy = skill.copyWith();

      expect(copy.id, skill.id);
      expect(copy.name, skill.name);
      expect(copy.description, skill.description);
      expect(copy.content, skill.content);
      expect(copy.sourcePath, skill.sourcePath);
      expect(copy.isCustom, skill.isCustom);
      expect(copy.references, skill.references);
    });
  });
}
