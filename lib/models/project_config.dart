import 'agent_skill.dart';

// Configuration model representing a unique project with its ignore, inclusions, skills, and creation date
class ProjectConfig {
  ProjectConfig({
    required this.id,
    required this.name,
    this.rootPath = '',
    this.includedFiles = const [],
    this.ignorePatterns = const ['.git/**', 'node_modules/**', 'build/**'],
    this.selectedSkillIds = const [],
    this.customSkills = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Decodes a configuration map with boundary safety checks, migration fallbacks, and error boundaries
  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    try {
      final String? id = json['id'] as String?;
      final String? name = json['name'] as String?;

      if (id == null || name == null) {
        throw const FormatException(
          'Missing required fields inside configuration.',
        );
      }

      final String? createdAtStr = json['createdAt'] as String?;
      final DateTime parsedCreatedAt = createdAtStr != null
          ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
          : DateTime.now();

      final List<dynamic>? customSkillsRaw =
          json['customSkills'] as List<dynamic>?;
      final List<AgentSkill> customSkillsParsed = customSkillsRaw != null
          ? customSkillsRaw
                .map((e) => AgentSkill.fromJson(e as Map<String, dynamic>))
                .toList()
          : const [];

      return ProjectConfig(
        id: id,
        name: name,
        rootPath: json['rootPath'] as String? ?? '',
        includedFiles: List<String>.from(
          json['includedFiles'] ?? const <String>[],
        ),
        ignorePatterns: json.containsKey('ignorePatterns')
            ? List<String>.from(json['ignorePatterns'])
            : const ['.git/**', 'node_modules/**', 'build/**'],
        selectedSkillIds: List<String>.from(
          json['selectedSkillIds'] ?? const <String>[],
        ),
        customSkills: customSkillsParsed,
        createdAt: parsedCreatedAt,
      );
    } catch (e) {
      // Avoid raw failure by fallback parsing to protect user interface startup
      return ProjectConfig(
        id: json['id'] as String? ?? 'corrupted_fallback',
        name: json['name'] as String? ?? 'Unreadable Config',
        rootPath: '',
        includedFiles: const <String>[],
        ignorePatterns: const ['.git/**', 'node_modules/**', 'build/**'],
        selectedSkillIds: const <String>[],
        customSkills: const [],
        createdAt: DateTime.now(),
      );
    }
  }

  final DateTime createdAt;
  final List<AgentSkill> customSkills;
  final String id;
  final List<String> ignorePatterns;
  final List<String> includedFiles;
  final String name;
  final String rootPath;
  final List<String> selectedSkillIds;

  // Clones existing project state structures while applying new fields safely
  ProjectConfig copyWith({
    String? id,
    String? name,
    String? rootPath,
    List<String>? includedFiles,
    List<String>? ignorePatterns,
    List<String>? selectedSkillIds,
    List<AgentSkill>? customSkills,
    DateTime? createdAt,
  }) {
    return ProjectConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      rootPath: rootPath ?? this.rootPath,
      includedFiles: includedFiles ?? this.includedFiles,
      ignorePatterns: ignorePatterns ?? this.ignorePatterns,
      selectedSkillIds: selectedSkillIds ?? this.selectedSkillIds,
      customSkills: customSkills ?? this.customSkills,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Serializes model properties to dynamic JSON parameters
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'rootPath': rootPath,
      'includedFiles': includedFiles,
      'ignorePatterns': ignorePatterns,
      'selectedSkillIds': selectedSkillIds,
      'customSkills': customSkills.map((s) => s.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
