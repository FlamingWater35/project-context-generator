// Configuration model representing a unique project with its ignore and inclusions
class ProjectConfig {
  const ProjectConfig({
    required this.id,
    required this.name,
    this.rootPath = '',
    this.includedFiles = const [],
    this.ignorePatterns = const ['.git/**', 'node_modules/**', 'build/**'],
  });

  // Decodes a configuration map with boundary safety checks and fallback values on error
  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    try {
      final String? id = json['id'] as String?;
      final String? name = json['name'] as String?;

      if (id == null || name == null) {
        throw const FormatException(
          'Missing required fields inside configuration.',
        );
      }

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
      );
    } catch (e) {
      // Avoid raw failure by fallback parsing to protect user interface startup
      return ProjectConfig(
        id: json['id'] as String? ?? 'corrupted_fallback',
        name: json['name'] as String? ?? 'Unreadable Config',
        rootPath: '',
        includedFiles: const <String>[],
        ignorePatterns: const ['.git/**', 'node_modules/**', 'build/**'],
      );
    }
  }

  final String id;
  final List<String> ignorePatterns;
  final List<String> includedFiles;
  final String name;
  final String rootPath;

  // Clones existing project state structures while applying new fields safely
  ProjectConfig copyWith({
    String? id,
    String? name,
    String? rootPath,
    List<String>? includedFiles,
    List<String>? ignorePatterns,
  }) {
    return ProjectConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      rootPath: rootPath ?? this.rootPath,
      includedFiles: includedFiles ?? this.includedFiles,
      ignorePatterns: ignorePatterns ?? this.ignorePatterns,
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
    };
  }
}
