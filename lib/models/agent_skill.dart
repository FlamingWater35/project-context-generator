/// Data model representing a reference file associated with an AI Agent Skill.
class AgentSkillReference {
  const AgentSkillReference({
    required this.relativePath,
    required this.content,
  });

  final String content;
  final String relativePath;

  /// Safely constructs an AgentSkillReference instance from JSON map parameters.
  factory AgentSkillReference.fromJson(Map<String, dynamic> json) {
    return AgentSkillReference(
      relativePath: json['relativePath'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }

  /// Serializes instance attributes to a standard JSON map structure.
  Map<String, dynamic> toJson() {
    return {'relativePath': relativePath, 'content': content};
  }
}

/// Data model representing an AI Agent Skill (auto-detected from skill files or custom user-created).
class AgentSkill {
  const AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.content,
    this.sourcePath,
    this.isCustom = false,
    this.references = const [],
  });

  final String content;
  final String description;
  final String id;
  final bool isCustom;
  final String name;
  final List<AgentSkillReference> references;
  final String? sourcePath;

  /// Safely constructs an AgentSkill instance from JSON map parameters with fallback defaults.
  factory AgentSkill.fromJson(Map<String, dynamic> json) {
    try {
      final List<dynamic>? refsRaw = json['references'] as List<dynamic>?;
      final List<AgentSkillReference> parsedRefs = refsRaw != null
          ? refsRaw
                .map(
                  (e) =>
                      AgentSkillReference.fromJson(e as Map<String, dynamic>),
                )
                .toList()
          : const [];

      return AgentSkill(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unnamed Skill',
        description: json['description'] as String? ?? '',
        content: json['content'] as String? ?? '',
        sourcePath: json['sourcePath'] as String?,
        isCustom: json['isCustom'] as bool? ?? false,
        references: parsedRefs,
      );
    } catch (_) {
      return AgentSkill(
        id: json['id'] as String? ?? 'corrupted_skill',
        name: json['name'] as String? ?? 'Unreadable Skill',
        description: '',
        content: '',
      );
    }
  }

  /// Clones the skill instance with updated field parameters safely.
  AgentSkill copyWith({
    String? id,
    String? name,
    String? description,
    String? content,
    String? sourcePath,
    bool? isCustom,
    List<AgentSkillReference>? references,
  }) {
    return AgentSkill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      content: content ?? this.content,
      sourcePath: sourcePath ?? this.sourcePath,
      isCustom: isCustom ?? this.isCustom,
      references: references ?? this.references,
    );
  }

  /// Serializes instance attributes to a standard JSON map structure.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'content': content,
      'sourcePath': sourcePath,
      'isCustom': isCustom,
      'references': references.map((r) => r.toJson()).toList(),
    };
  }
}
