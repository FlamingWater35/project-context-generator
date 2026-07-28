import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/agent_skill.dart';
import '../providers/app_state.dart';

/// Modal dialog enabling users to detect, review, select, and define custom agent skills for context prompt generation.
class SkillsDialog extends ConsumerStatefulWidget {
  const SkillsDialog({super.key});

  @override
  ConsumerState<SkillsDialog> createState() => _SkillsDialogState();
}

class _SkillsDialogState extends ConsumerState<SkillsDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Opens a sub-dialog to preview full skill content and instructions
  void _showPreviewDialog(BuildContext context, AgentSkill skill) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(skill.name),
        content: SizedBox(
          width: 600,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              skill.content.isEmpty
                  ? '(No instruction content provided)'
                  : skill.content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Opens an interactive creation dialog for adding custom user skills
  void _showAddCustomSkillDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Custom Skill'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Skill Name',
                  hintText: 'e.g. Code Reviewer',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g. Guidance on PR reviews and code quality',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Skill Instructions / Content',
                  hintText: 'Enter instructions for the AI agent...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final desc = descController.text.trim();
              final content = contentController.text.trim();

              if (name.isNotEmpty) {
                final skill = AgentSkill(
                  id: 'custom_${const Uuid().v4()}',
                  name: name,
                  description: desc.isEmpty
                      ? 'Custom user-defined skill'
                      : desc,
                  content: content,
                  isCustom: true,
                );
                await ref
                    .read(appStateControllerProvider)
                    .addCustomSkill(skill);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Add Skill'),
          ),
        ],
      ),
    ).then((_) {
      nameController.dispose();
      descController.dispose();
      contentController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = math.min(screenSize.width * 0.9, 850.0);
    final dialogHeight = math.min(screenSize.height * 0.85, 700.0);

    final config = ref.watch(selectedConfigProvider);
    final allSkills = ref.watch(allProjectSkillsProvider);
    final detectedSkillsAsync = ref.watch(detectedSkillsProvider);
    final selectedIds = config?.selectedSkillIds.toSet() ?? {};
    final controller = ref.read(appStateControllerProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.psychology, size: 26),
          const SizedBox(width: 12),
          const Text('Agent Skills'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Rescan Detected Skills',
            onPressed: () {
              ref.invalidate(detectedSkillsProvider);
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Custom Skill'),
            onPressed: () => _showAddCustomSkillDialog(context, ref),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selected skills will be included as structured guidelines in your generated context prompt.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: allSkills.isEmpty
                      ? null
                      : () => controller.selectAllSkills(
                          allSkills.map((s) => s.id).toList(),
                        ),
                  child: const Text('Select All'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () => controller.deselectAllSkills(),
                  child: const Text('Deselect All'),
                ),
                const Spacer(),
                Text(
                  '${selectedIds.length} of ${allSkills.length} skills selected',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: detectedSkillsAsync.when(
                data: (_) {
                  if (allSkills.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.extension_off,
                              size: 48,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No agent skills detected in this project.',
                              style: TextStyle(color: Colors.grey.shade400),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add skill files (e.g. SKILL.md, .github/skills/, .claude/skills/) or create a custom skill above.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withAlpha(20)),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.black.withAlpha(15),
                    ),
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _scrollController,
                        itemCount: allSkills.length,
                        separatorBuilder: (ctx, i) => Divider(
                          height: 1,
                          color: Colors.white.withAlpha(10),
                        ),
                        itemBuilder: (ctx, i) {
                          final skill = allSkills[i];
                          final isSelected = selectedIds.contains(skill.id);

                          return ListTile(
                            dense: true,
                            leading: Checkbox(
                              value: isSelected,
                              onChanged: (_) {
                                controller.toggleSkillSelection(skill.id);
                              },
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    skill.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: skill.isCustom
                                        ? Colors.purple.shade900
                                        : Colors.blue.shade900,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    skill.isCustom ? 'Custom' : 'Detected',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              skill.description.isNotEmpty
                                  ? skill.description
                                  : (skill.sourcePath ?? ''),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.visibility, size: 18),
                                  tooltip: 'Preview Skill Content',
                                  onPressed: () =>
                                      _showPreviewDialog(context, skill),
                                ),
                                if (skill.isCustom)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      size: 18,
                                      color: Colors.redAccent,
                                    ),
                                    tooltip: 'Delete Custom Skill',
                                    onPressed: () {
                                      controller.deleteCustomSkill(skill.id);
                                    },
                                  ),
                              ],
                            ),
                            onTap: () {
                              controller.toggleSkillSelection(skill.id);
                            },
                          );
                        },
                      ),
                    ),
                  );
                },
                loading: () => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Scanning for agent skills...'),
                    ],
                  ),
                ),
                error: (err, stack) =>
                    Center(child: Text('Failed to detect skills: $err')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
