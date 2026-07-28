/// Data model representing a parsed file code change from an LLM response.
class FileCodeChange {
  FileCodeChange({
    required this.relativePath,
    required this.newContent,
    required this.isNewFile,
    this.isSelected = true,
  });

  /// Whether the target file currently does not exist on disk.
  final bool isNewFile;

  /// Updated content to be written to disk.
  final String newContent;

  /// Relative file path inside the project repository.
  final String relativePath;

  /// User toggle state indicating if this specific change should be applied.
  bool isSelected;

  /// Clones the current instance with updated selection state.
  FileCodeChange copyWith({bool? isSelected}) {
    return FileCodeChange(
      relativePath: relativePath,
      newContent: newContent,
      isNewFile: isNewFile,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}
