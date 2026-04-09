class ProjectConfig {
  ProjectConfig({
    required this.id,
    required this.name,
    this.rootPath = '',
    this.includedFiles = const [],
    this.ignorePatterns = const ['.git/**', 'node_modules/**', 'build/**'],
  });

  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    return ProjectConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      rootPath: json['rootPath'] as String? ?? '',
      includedFiles: List<String>.from(json['includedFiles'] ?? []),
      ignorePatterns: json.containsKey('ignorePatterns')
          ? List<String>.from(json['ignorePatterns'])
          : ['.git/**', 'node_modules/**', 'build/**'],
    );
  }

  final String id;
  final List<String> ignorePatterns;
  final List<String> includedFiles;
  final String name;
  final String rootPath;

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
