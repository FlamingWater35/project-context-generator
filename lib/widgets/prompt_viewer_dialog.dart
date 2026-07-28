import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/fs_service.dart';
import 'snackbar.dart';

/// High-performance TextEditingController that highlights pre-computed search matches without layout painting lag.
class SearchHighlightController extends TextEditingController {
  SearchHighlightController({super.text});

  String _searchPattern = '';
  List<int> _matchIndices = [];
  int _currentMatchCharIndex = -1;

  /// Updates current search query pattern, match positions, and active match index for span highlighting
  void setSearchMatches(
    String pattern,
    List<int> matchIndices,
    int currentMatchCharIndex,
  ) {
    _searchPattern = pattern;
    _matchIndices = matchIndices;
    _currentMatchCharIndex = currentMatchCharIndex;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_searchPattern.isEmpty || text.isEmpty || _matchIndices.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final List<InlineSpan> children = [];
    final int patternLen = _searchPattern.length;
    int start = 0;

    // Window highlighting to max 300 visible matches around active match to guarantee 60 FPS rendering
    final int totalMatches = _matchIndices.length;
    int activeIdxInList = _matchIndices.indexOf(_currentMatchCharIndex);
    if (activeIdxInList == -1) activeIdxInList = 0;

    final int startMatch = (activeIdxInList - 150).clamp(0, totalMatches);
    final int endMatch = (activeIdxInList + 150).clamp(0, totalMatches);

    for (int i = startMatch; i < endMatch; i++) {
      final int matchIndex = _matchIndices[i];
      if (matchIndex < start) continue;
      if (matchIndex + patternLen > text.length) break;

      if (matchIndex > start) {
        children.add(
          TextSpan(text: text.substring(start, matchIndex), style: style),
        );
      }

      final bool isCurrentMatch = matchIndex == _currentMatchCharIndex;
      final String matchedText = text.substring(
        matchIndex,
        matchIndex + patternLen,
      );

      children.add(
        TextSpan(
          text: matchedText,
          style: style?.copyWith(
            backgroundColor: isCurrentMatch
                ? Colors.orange.shade700
                : Colors.amber.shade900.withAlpha(190),
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      start = matchIndex + patternLen;
    }

    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start), style: style));
    }

    return TextSpan(children: children, style: style);
  }
}

/// Section item for the quick-jump section selector in the prompt viewer.
class _PromptSection {
  const _PromptSection({
    required this.title,
    required this.charIndex,
    required this.icon,
  });

  final int charIndex;
  final IconData icon;
  final String title;
}

/// Modern IDE-style modal dialog for previewing, inspecting, searching, and copying generated context prompts.
class PromptViewerDialog extends StatefulWidget {
  const PromptViewerDialog({
    super.key,
    required this.projectName,
    required this.promptFuture,
  });

  final String projectName;
  final Future<PromptBuildResult> promptFuture;

  @override
  State<PromptViewerDialog> createState() => _PromptViewerDialogState();
}

class _PromptViewerDialogState extends State<PromptViewerDialog> {
  static const int _maxDisplayLines = 2000;

  late final SearchHighlightController _textController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _editorScrollController = ScrollController();
  final FocusNode _editorFocusNode = FocusNode();

  Timer? _searchDebounceTimer;
  bool _isLoading = true;
  String? _errorMessage;
  PromptBuildResult? _buildResult;

  bool _isCopied = false;
  bool _isTruncated = false;
  int _totalLines = 0;
  String _displayText = '';
  String _fullPromptText = '';

  List<_PromptSection> _sections = [];
  _PromptSection? _selectedSection;
  int _currentSearchMatchIndex = -1;
  List<int> _searchMatchIndices = [];

  @override
  void initState() {
    super.initState();
    _textController = SearchHighlightController();
    _loadPrompt();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _textController.dispose();
    _searchController.dispose();
    _editorScrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  /// Asynchronously awaits prompt generation from background Isolate
  Future<void> _loadPrompt() async {
    try {
      final result = await widget.promptFuture;
      if (!mounted) return;

      if (result.fileCount == 0) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'No files selected or all selected files are ignored.';
        });
        return;
      }

      setState(() {
        _buildResult = result;
        _fullPromptText = result.promptText;
        _prepareDisplayText(result.promptText);
        _textController.text = _displayText;
        _parseSections();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to generate context prompt: $e';
        });
      }
    }
  }

  /// Prepares display text safely to ensure 60fps rendering without Flutter text layout lockups
  void _prepareDisplayText(String fullText) {
    final lines = fullText.split('\n');
    _totalLines = lines.length;

    if (lines.length > _maxDisplayLines) {
      _isTruncated = true;
      final previewLines = lines.take(_maxDisplayLines).join('\n');
      _displayText =
          '$previewLines\n\n--- [PREVIEW TRUNCATED: Showing first $_maxDisplayLines of $_totalLines lines. Click "Copy Full Prompt" to copy 100% of context] ---';
    } else {
      _isTruncated = false;
      _displayText = fullText;
    }
  }

  /// Parses logical sections from prompt text for quick navigation
  void _parseSections() {
    final List<_PromptSection> parsed = [];

    final treeIdx = _displayText.indexOf('File Tree Structure:');
    if (treeIdx != -1) {
      parsed.add(
        _PromptSection(
          title: 'File Tree Structure',
          charIndex: treeIdx,
          icon: Icons.account_tree_outlined,
        ),
      );
    }

    final RegExp fileHeaderRegex = RegExp(
      r'^--- File: (.*?) ---$',
      multiLine: true,
    );
    for (final match in fileHeaderRegex.allMatches(_displayText)) {
      final fileName = match.group(1) ?? 'File';
      parsed.add(
        _PromptSection(
          title: 'File: $fileName',
          charIndex: match.start,
          icon: Icons.insert_drive_file_outlined,
        ),
      );
    }

    final skillsIdx = _displayText.indexOf('--- AGENT SKILLS ---');
    if (skillsIdx != -1) {
      parsed.add(
        _PromptSection(
          title: 'Agent Skills Section',
          charIndex: skillsIdx,
          icon: Icons.psychology_outlined,
        ),
      );
    }

    final RegExp skillHeaderRegex = RegExp(
      r'^--- Skill: (.*?) ---$',
      multiLine: true,
    );
    for (final match in skillHeaderRegex.allMatches(_displayText)) {
      final skillName = match.group(1) ?? 'Skill';
      parsed.add(
        _PromptSection(
          title: 'Skill: $skillName',
          charIndex: match.start,
          icon: Icons.extension_outlined,
        ),
      );
    }

    setState(() {
      _sections = parsed;
    });
  }

  /// Jumps the text editor view to a target parsed section and scrolls smoothly
  void _jumpToSection(_PromptSection section) {
    setState(() => _selectedSection = section);

    if (section.charIndex < _displayText.length) {
      final precedingText = _displayText.substring(0, section.charIndex);
      final lineIndex = precedingText.split('\n').length - 1;
      const double approxLineHeight = 18.85;
      final double targetOffset = lineIndex * approxLineHeight;

      if (_editorScrollController.hasClients) {
        final maxExtent = _editorScrollController.position.maxScrollExtent;
        _editorScrollController.animateTo(
          targetOffset.clamp(0.0, maxExtent),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }

      _textController.selection = TextSelection.collapsed(
        offset: section.charIndex,
      );
    }
  }

  /// Searches display text with 200ms debouncing and non-blocking match scanning
  void _performSearch(String query) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      final trimmed = query.trim().toLowerCase();
      if (trimmed.isEmpty) {
        if (mounted) {
          setState(() {
            _searchMatchIndices = [];
            _currentSearchMatchIndex = -1;
          });
          _textController.setSearchMatches('', const [], -1);
        }
        return;
      }

      final List<int> matches = [];
      final lowerText = _displayText.toLowerCase();
      int start = 0;
      while (start < lowerText.length) {
        final index = lowerText.indexOf(trimmed, start);
        if (index == -1) break;
        matches.add(index);
        start = index + trimmed.length;
      }

      if (mounted) {
        setState(() {
          _searchMatchIndices = matches;
          _currentSearchMatchIndex = matches.isNotEmpty ? 0 : -1;
        });

        if (matches.isNotEmpty) {
          _jumpToSearchMatch(0, trimmed.length);
        } else {
          _textController.setSearchMatches(trimmed, const [], -1);
        }
      }
    });
  }

  /// Jumps editor view and scrolls to the N-th search match
  void _jumpToSearchMatch(int matchIdx, int matchLength) {
    if (matchIdx >= 0 && matchIdx < _searchMatchIndices.length) {
      final charIdx = _searchMatchIndices[matchIdx];
      setState(() {
        _currentSearchMatchIndex = matchIdx;
      });

      if (charIdx < _displayText.length) {
        final precedingText = _displayText.substring(0, charIdx);
        final lineIndex = precedingText.split('\n').length - 1;
        const double approxLineHeight = 18.85;
        final double targetOffset = lineIndex * approxLineHeight;

        if (_editorScrollController.hasClients) {
          final maxExtent = _editorScrollController.position.maxScrollExtent;
          _editorScrollController.animateTo(
            targetOffset.clamp(0.0, maxExtent),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }

        _textController.selection = TextSelection(
          baseOffset: charIdx,
          extentOffset: charIdx + matchLength,
        );

        _textController.setSearchMatches(
          _searchController.text.trim().toLowerCase(),
          _searchMatchIndices,
          charIdx,
        );
      }
    }
  }

  /// Selects all text in the display prompt editor
  void _selectAll() {
    _textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _displayText.length,
    );
    _editorFocusNode.requestFocus();
  }

  /// Copies 100% complete full prompt text to system clipboard
  Future<void> _handleCopy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: _fullPromptText));
      setState(() => _isCopied = true);
      if (context.mounted) {
        showSuccessSnackBar(
          context,
          'Full prompt context copied to clipboard!',
        );
      }
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isCopied = false);
      });
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, 'Failed to copy prompt to clipboard: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = math.min(screenSize.width * 0.95, 1100.0);
    final dialogHeight = math.min(screenSize.height * 0.9, 850.0);

    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Top IDE Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(180),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withAlpha(20)),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.code, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Prompt Context: ${widget.projectName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),

                  if (_isLoading)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withAlpha(200),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Building Prompt...',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_buildResult != null) ...[
                    _buildBadge(
                      Icons.auto_awesome,
                      '~${((_fullPromptText.length / 4) / 1000).toStringAsFixed(1)}k tokens',
                      Colors.amber.shade800,
                    ),
                    const SizedBox(width: 6),
                    _buildBadge(
                      Icons.notes,
                      '$_totalLines lines',
                      Colors.blue.shade800,
                    ),
                    const SizedBox(width: 6),
                    _buildBadge(
                      Icons.insert_drive_file,
                      '${_buildResult!.fileCount} files',
                      Colors.teal.shade800,
                    ),
                    const SizedBox(width: 6),
                    if (_buildResult!.skillCount > 0) ...[
                      _buildBadge(
                        Icons.psychology,
                        '${_buildResult!.skillCount} skills',
                        Colors.purple.shade800,
                      ),
                      const SizedBox(width: 6),
                    ],
                    _buildBadge(
                      Icons.data_usage,
                      '${(_fullPromptText.length / 1024).toStringAsFixed(1)} KB',
                      Colors.grey.shade800,
                    ),
                  ],

                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            if (_isLoading)
              Expanded(
                child: Container(
                  color: const Color(0xFF14141E),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Generating context prompt for "${widget.projectName}"...',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Reading project files and formatting agent skills in background isolate...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_errorMessage != null)
              Expanded(
                child: Container(
                  color: const Color(0xFF14141E),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else ...[
              // Toolbar: Search, Section Jumper, Select All, Copy Button
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: colorScheme.surface,
                child: Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search text...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    _performSearch('');
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: _performSearch,
                      ),
                    ),
                    if (_searchMatchIndices.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${_currentSearchMatchIndex + 1}/${_searchMatchIndices.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.amber,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                        onPressed: () {
                          if (_searchMatchIndices.isEmpty) return;
                          final newIdx =
                              (_currentSearchMatchIndex -
                                  1 +
                                  _searchMatchIndices.length) %
                              _searchMatchIndices.length;
                          _jumpToSearchMatch(
                            newIdx,
                            _searchController.text.trim().length,
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                        onPressed: () {
                          if (_searchMatchIndices.isEmpty) return;
                          final newIdx =
                              (_currentSearchMatchIndex + 1) %
                              _searchMatchIndices.length;
                          _jumpToSearchMatch(
                            newIdx,
                            _searchController.text.trim().length,
                          );
                        },
                      ),
                    ],

                    const SizedBox(width: 12),

                    if (_sections.isNotEmpty) ...[
                      DropdownButton<_PromptSection>(
                        value: _selectedSection,
                        hint: const Row(
                          children: [
                            Icon(Icons.list, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Jump to section...',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        underline: const SizedBox.shrink(),
                        onChanged: (sec) {
                          if (sec != null) _jumpToSection(sec);
                        },
                        items: _sections.map((sec) {
                          return DropdownMenuItem<_PromptSection>(
                            value: sec,
                            child: Row(
                              children: [
                                Icon(
                                  sec.icon,
                                  size: 16,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  sec.title,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const Spacer(),

                    OutlinedButton.icon(
                      icon: const Icon(Icons.select_all, size: 16),
                      label: const Text('Select All'),
                      onPressed: _selectAll,
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      icon: Icon(
                        _isCopied ? Icons.check : Icons.copy,
                        size: 18,
                      ),
                      label: Text(_isCopied ? 'Copied!' : 'Copy Full Prompt'),
                      onPressed: () => _handleCopy(context),
                    ),
                  ],
                ),
              ),

              if (_isTruncated)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  color: Colors.amber.shade900.withAlpha(180),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Preview truncated to $_maxDisplayLines of $_totalLines lines for 60 FPS rendering. "Copy Full Prompt" copies 100% of context.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const Divider(height: 1),

              // High Performance Text Editor Container
              Expanded(
                child: Container(
                  color: const Color(0xFF14141E),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: TextField(
                    controller: _textController,
                    scrollController: _editorScrollController,
                    focusNode: _editorFocusNode,
                    readOnly: true,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: [
                        'JetBrains Mono',
                        'Fira Code',
                        'Courier New',
                        'monospace',
                      ],
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFFD4D4D4),
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Helper builder for status pills in top header
  Widget _buildBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
