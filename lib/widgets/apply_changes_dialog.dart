import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:silky_scroll/silky_scroll.dart';

import '../models/code_change.dart';
import '../models/project_config.dart';
import '../providers/app_state.dart';
import '../services/code_parser_service.dart';
import 'snackbar.dart';

/// Modal dialog that listens to system clipboard for LLM response blocks and applies file changes safely.
class ApplyChangesDialog extends ConsumerStatefulWidget {
  const ApplyChangesDialog({super.key, required this.config});

  final ProjectConfig config;

  @override
  ConsumerState<ApplyChangesDialog> createState() => _ApplyChangesDialogState();
}

class _ApplyChangesDialogState extends ConsumerState<ApplyChangesDialog> {
  Timer? _clipboardTimer;
  List<FileCodeChange> _detectedChanges = [];
  bool _isApplying = false;
  bool _isListening = false;
  String _lastClipboardText = '';

  final ScrollController _previewScrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _clipboardTimer?.cancel();
    _sidebarScrollController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  /// Starts polling system clipboard for new LLM changes, seeding initial clipboard text to ignore pre-existing content.
  Future<void> _startListening() async {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;

    if (mounted) {
      setState(() => _isListening = true);
    }

    // Capture current clipboard content as baseline so pre-existing text is not immediately processed
    try {
      final initialData = await Clipboard.getData(Clipboard.kTextPlain);
      if (initialData?.text != null) {
        _lastClipboardText = initialData!.text!;
      }
    } catch (e) {
      debugPrint('Error capturing initial clipboard state: $e');
    }

    if (!mounted || !_isListening) return;

    _clipboardTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _checkClipboard(),
    );
  }

  /// Stops clipboard polling listener.
  void _stopListening() {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
    if (mounted) {
      setState(() => _isListening = false);
    }
  }

  /// Checks system clipboard text and parses detected file code blocks if content has changed.
  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        if (data.text != _lastClipboardText) {
          _lastClipboardText = data.text!;
          _processText(_lastClipboardText);
        }
      }
    } catch (e) {
      debugPrint('Error polling clipboard: $e');
    }
  }

  /// Manually reads content from system clipboard and parses immediately.
  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;

      if (data != null && data.text != null && data.text!.isNotEmpty) {
        _lastClipboardText = data.text!;
        _processText(_lastClipboardText);
      } else {
        showInfoSnackBar(context, 'Clipboard is empty.');
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Failed to read clipboard: $e');
      }
    }
  }

  /// Parses text content and updates dialog UI state when valid changes are found.
  void _processText(String text) {
    final parsed = CodeParserService.parseCodeChanges(
      text,
      widget.config.rootPath,
    );

    if (parsed.isNotEmpty && mounted) {
      setState(() {
        _detectedChanges = parsed;
        _selectedIndex = 0;
        _isListening = false;
      });
      _stopListening();
      showSuccessSnackBar(
        context,
        'Detected ${parsed.length} file change(s) from clipboard!',
      );
    }
  }

  /// Overwrites modified files and creates new files on disk safely.
  Future<void> _applyChanges() async {
    final selectedChanges = _detectedChanges
        .where((c) => c.isSelected)
        .toList();

    if (selectedChanges.isEmpty) {
      showErrorSnackBar(context, 'No file changes selected to apply.');
      return;
    }

    setState(() => _isApplying = true);

    int successCount = 0;
    final List<String> errors = [];

    final canonicalRoot = p.normalize(p.absolute(widget.config.rootPath));

    for (final change in selectedChanges) {
      try {
        if (!CodeParserService.isPathSafe(
          widget.config.rootPath,
          change.relativePath,
        )) {
          errors.add(
            '${change.relativePath}: Path safety violation (outside project root)',
          );
          continue;
        }

        final fullPath = p.normalize(
          p.join(canonicalRoot, change.relativePath),
        );
        final file = File(fullPath);

        // Ensure parent directory structure exists
        file.parent.createSync(recursive: true);

        // Overwrite or create file
        file.writeAsStringSync(change.newContent);
        successCount++;
      } catch (e) {
        errors.add('${change.relativePath}: $e');
      }
    }

    if (!mounted) return;

    setState(() => _isApplying = false);

    if (successCount > 0) {
      // Refresh project tree state & acknowledge filesystem updates
      await ref.read(appStateControllerProvider).acknowledgeChanges();
      ref.invalidate(fileTreeProvider);

      if (!mounted) return;

      showSuccessSnackBar(
        context,
        'Successfully applied changes to $successCount file(s)!',
      );
      Navigator.pop(context);
    } else if (errors.isNotEmpty) {
      showErrorSnackBar(
        context,
        'Failed to apply ${errors.length} file(s): ${errors.first}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = math.min(screenSize.width * 0.92, 950.0);
    final dialogHeight = math.min(screenSize.height * 0.88, 750.0);

    final selectedCount = _detectedChanges.where((c) => c.isSelected).length;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.build_circle_outlined, size: 26),
          const SizedBox(width: 12),
          const Text('Apply Code Changes'),
          const Spacer(),
          if (_isListening)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade900.withAlpha(180),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.greenAccent,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Listening to clipboard...',
                    style: TextStyle(fontSize: 12, color: Colors.greenAccent),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            icon: Icon(_isListening ? Icons.pause : Icons.radar, size: 18),
            label: Text(_isListening ? 'Stop Listening' : 'Start Listening'),
            onPressed: _isListening ? _stopListening : _startListening,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.content_paste, size: 18),
            label: const Text('Paste Manual'),
            onPressed: _pasteFromClipboard,
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: _detectedChanges.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.integration_instructions_outlined,
                        size: 64,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No code changes detected yet.',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Turn on clipboard listening and copy an LLM response containing file code blocks,\nor click "Paste Manual" to parse code changes.',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : Row(
                children: [
                  // Sidebar showing changed and new files
                  SizedBox(
                    width: 320,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Changed Files (${_detectedChanges.length})',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  final allSelected = _detectedChanges.every(
                                    (c) => c.isSelected,
                                  );
                                  for (var c in _detectedChanges) {
                                    c.isSelected = !allSelected;
                                  }
                                });
                              },
                              child: Text(
                                _detectedChanges.every((c) => c.isSelected)
                                    ? 'Deselect All'
                                    : 'Select All',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Material(
                            color: Colors.black.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            child: Scrollbar(
                              controller: _sidebarScrollController,
                              thumbVisibility: true,
                              child: SilkyListView.separated(
                                controller: _sidebarScrollController,
                                itemCount: _detectedChanges.length,
                                separatorBuilder: (ctx, i) => Divider(
                                  height: 1,
                                  color: Colors.white.withAlpha(10),
                                ),
                                itemBuilder: (ctx, index) {
                                  final change = _detectedChanges[index];
                                  final isFocused = index == _selectedIndex;

                                  return ListTile(
                                    dense: true,
                                    selected: isFocused,
                                    leading: Checkbox(
                                      value: change.isSelected,
                                      onChanged: (val) {
                                        setState(() {
                                          change.isSelected = val ?? false;
                                        });
                                      },
                                    ),
                                    title: Text(
                                      p.basename(change.relativePath),
                                      style: TextStyle(
                                        fontWeight: isFocused
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      p.dirname(change.relativePath),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: change.isNewFile
                                            ? Colors.green.shade900
                                            : Colors.blue.shade900,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        change.isNewFile ? 'NEW' : 'MODIFIED',
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() => _selectedIndex = index);
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const VerticalDivider(width: 24, indent: 8, endIndent: 8),

                  // Main Content Code Block Preview Panel
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_detectedChanges.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(
                                _detectedChanges[_selectedIndex].isNewFile
                                    ? Icons.note_add_outlined
                                    : Icons.edit_note,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _detectedChanges[_selectedIndex].relativePath,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(40),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withAlpha(20),
                                ),
                              ),
                              child: Scrollbar(
                                controller: _previewScrollController,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _previewScrollController,
                                  child: SelectableText(
                                    _detectedChanges[_selectedIndex].newContent,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (_detectedChanges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Text(
              '$selectedCount of ${_detectedChanges.length} changes selected',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: _isApplying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check),
          label: Text(_isApplying ? 'Applying...' : 'Apply Changes'),
          onPressed: (_isApplying || selectedCount == 0) ? null : _applyChanges,
        ),
      ],
    );
  }
}
