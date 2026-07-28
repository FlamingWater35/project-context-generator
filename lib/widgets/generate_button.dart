import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state.dart';
import '../services/fs_service.dart';
import 'prompt_viewer_dialog.dart';
import 'snackbar.dart';

// Button that triggers background isolate prompt compilation and opens the prompt viewing menu immediately
class GenerateButton extends ConsumerStatefulWidget {
  const GenerateButton({super.key});

  @override
  ConsumerState<GenerateButton> createState() => _GenerateButtonState();
}

class _GenerateButtonState extends ConsumerState<GenerateButton> {
  bool _isLoading = false;

  // Verifies disk configurations and processes text extraction with user decision options
  Future<void> _handleGenerate() async {
    setState(() => _isLoading = true);

    try {
      final config = ref.read(selectedConfigProvider);
      if (config == null || config.rootPath.isEmpty) return;

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
                'The physical files on disk have changed since the last check. Would you like to refresh your project snapshot or generate using the existing configuration?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'copy_anyway'),
                  child: const Text('View Anyway'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'refresh'),
                  child: const Text('Refresh & View'),
                ),
              ],
            ),
          );

          if (actionChoice == 'refresh') {
            await ref.read(appStateControllerProvider).acknowledgeChanges();
            ref.invalidate(fileTreeProvider);
            if (mounted) _performGeneratePrompt();
          } else if (actionChoice == 'copy_anyway') {
            if (mounted) _performGeneratePrompt();
          }
        }
      } else {
        if (mounted) {
          _performGeneratePrompt();
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

  // Immediately launches PromptViewerDialog with a background future task
  void _performGeneratePrompt() {
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

      // Create future for background isolate prompt compilation
      final promptFuture = fsService.buildPromptContext(params);

      // Open the preview dialog IMMEDIATELY
      showDialog(
        context: context,
        builder: (_) => PromptViewerDialog(
          projectName: config.name,
          promptFuture: promptFuture,
        ),
      );
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Failed to launch prompt preview: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.visibility),
      label: Text(_isLoading ? 'Generating...' : 'Generate Prompt'),
      onPressed: _isLoading ? null : _handleGenerate,
    );
  }
}
