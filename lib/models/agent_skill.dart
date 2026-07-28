/// Data model representing an AI Agent Skill (auto-detected from files or custom user-created).
class AgentSkill {
  const AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.content,
    this.sourcePath,
    this.isCustom = false,
  });

  final String content;
  final String description;
  final String id;
  final bool isCustom;
  final String name;
  final String? sourcePath;

  /// Safely constructs an AgentSkill instance from JSON map parameters with fallback defaults.
  factory AgentSkill.fromJson(Map<String, dynamic> json) {
    try {
      return AgentSkill(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unnamed Skill',
        description: json['description'] as String? ?? '',
        content: json['content'] as String? ?? '',
        sourcePath: json['sourcePath'] as String?,
        isCustom: json['isCustom'] as bool? ?? false,
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
  }) {
    return AgentSkill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      content: content ?? this.content,
      sourcePath: sourcePath ?? this.sourcePath,
      isCustom: isCustom ?? this.isCustom,
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
    };
  }
}
