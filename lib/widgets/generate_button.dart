import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state.dart';
import '../services/fs_service.dart';
import 'snackbar.dart';

/// Button that compiles context prompt in background isolate and copies it directly to system clipboard.
class GenerateButton extends ConsumerStatefulWidget {
  const GenerateButton({super.key});

  @override
  ConsumerState<GenerateButton> createState() => _GenerateButtonState();
}

class _GenerateButtonState extends ConsumerState<GenerateButton> {
  bool _isLoading = false;

  /// Verifies disk snapshot changes and presents options to review project changes or confirm generation.
  Future<void> _handleGenerate() async {
    setState(() => _isLoading = true);

    try {
      final config = ref.read(selectedConfigProvider);
      if (config == null || config.rootPath.isEmpty) {
        if (mounted) {
          showErrorSnackBar(
            context,
            'Please select a valid root folder first.',
          );
        }
        return;
      }

      if (config.includedFiles.isEmpty) {
        if (mounted) {
          showErrorSnackBar(
            context,
            'No files selected to include in prompt context.',
          );
        }
        return;
      }

      final fs = ref.read(fsServiceProvider);
      final snapshots = ref.read(projectSnapshotsProvider);
      final knownPaths = snapshots[config.id] ?? {};

      final currentPaths = await fs.scanPaths(
        config.rootPath,
        config.ignorePatterns,
      );

      final bool hasChanged =
          currentPaths.length != knownPaths.length ||
          !currentPaths.containsAll(knownPaths);

      if (hasChanged) {
        if (mounted) {
          final String? actionChoice = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Project State Changed'),
              content: const Text(
                'The physical files on disk have changed since the last check. Would you like to review the updated project structure or confirm generation?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'review'),
                  child: const Text('Review Project'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'confirm'),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          );

          if (actionChoice == 'review') {
            await ref.read(appStateControllerProvider).acknowledgeChanges();
            ref.invalidate(fileTreeProvider);
            if (mounted) {
              showInfoSnackBar(
                context,
                'Project structure updated. Please review your file selections.',
              );
            }
          } else if (actionChoice == 'confirm') {
            await ref.read(appStateControllerProvider).acknowledgeChanges();
            ref.invalidate(fileTreeProvider);
            if (mounted) await _performGenerateAndCopyPrompt();
          }
        }
      } else {
        if (mounted) {
          await _performGenerateAndCopyPrompt();
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Generation process failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Compiles full prompt context in background isolate and copies directly to clipboard.
  Future<void> _performGenerateAndCopyPrompt() async {
    final config = ref.read(selectedConfigProvider);
    if (config == null) return;

    try {
      final fsService = ref.read(fsServiceProvider);

      final selectedSkillIds = config.selectedSkillIds.toSet();
      final allSkills = ref.read(allProjectSkillsProvider);
      final selectedSkills = allSkills
          .where((s) => selectedSkillIds.contains(s.id))
          .toList();

      final params = PromptBuildParams(
        projectName: config.name,
        rootPath: config.rootPath,
        includedFiles: config.includedFiles,
        selectedSkills: selectedSkills,
        ignorePatterns: config.ignorePatterns,
      );

      final result = await fsService.buildPromptContext(params);

      if (result.fileCount == 0) {
        if (mounted) {
          showErrorSnackBar(
            context,
            'No files selected or all selected files are ignored.',
          );
        }
        return;
      }

      await Clipboard.setData(ClipboardData(text: result.promptText));

      if (mounted) {
        showSuccessSnackBar(
          context,
          'Prompt generated and copied to clipboard! (${result.fileCount} files, ${result.totalLines} lines)',
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Failed to copy prompt to clipboard: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Generate & Copy Prompt (Ctrl+G / Cmd+G)',
      child: FilledButton.icon(
        icon: _isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.copy),
        label: Text(_isLoading ? 'Generating...' : 'Generate & Copy'),
        onPressed: _isLoading ? null : _handleGenerate,
      ),
    );
  }
}
