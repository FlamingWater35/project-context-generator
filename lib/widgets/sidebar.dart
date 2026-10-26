import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:silky_scroll/silky_scroll.dart';

import '../models/project_config.dart';
import '../providers/app_state.dart';

/// Sidebar panel presenting lists of configured projects, project sorting, active project switching, and configuration creations.
class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key});

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Opens a pop-up dialog to capture names for new configuration files.
  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _ProjectNameDialog(
        title: 'New Project',
        confirmLabel: 'Create',
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      await ref.read(configsProvider.notifier).addConfig(name);
    } catch (e) {
      debugPrint('Could not create new project config: $e');
    }
  }

  /// Launches target input dialogs enabling name overrides of configurations.
  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    ProjectConfig config,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _ProjectNameDialog(
        title: 'Rename Project',
        confirmLabel: 'Rename',
        initialValue: config.name,
      ),
    );

    if (name == null || name.isEmpty || name == config.name) return;

    try {
      ref
          .read(configsProvider.notifier)
          .updateConfig(config.copyWith(name: name), oldName: config.name);
    } catch (e) {
      debugPrint('Could not apply target layout rename operations: $e');
    }
  }

  /// Requests deletion verification before wiping files.
  void _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    ProjectConfig config,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text(
          'Are you sure you want to delete "${config.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await ref.read(configsProvider.notifier).deleteConfig(config);
              } catch (e) {
                debugPrint('Configuration deletion operation failed: $e');
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allConfigs = ref.watch(configsProvider);
    final sortOption = ref.watch(projectSortOptionProvider);
    var configs = allConfigs.toList();

    // Sort projects dynamically based on the active ProjectSortOption
    configs.sort((a, b) {
      switch (sortOption) {
        case ProjectSortOption.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case ProjectSortOption.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case ProjectSortOption.dateNewest:
          return b.createdAt.compareTo(a.createdAt);
        case ProjectSortOption.dateOldest:
          return a.createdAt.compareTo(b.createdAt);
      }
    });

    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.trim().toLowerCase();
      configs = configs
          .where((c) => c.name.toLowerCase().contains(query))
          .toList();
    }

    final selectedId =
        ref.watch(selectedConfigIdProvider) ??
        (allConfigs.isNotEmpty ? allConfigs.first.id : null);

    return Material(
      elevation: 2,
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Projects',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<ProjectSortOption>(
                    icon: const Icon(Icons.sort, size: 20),
                    tooltip: 'Sort Projects',
                    onSelected: (option) {
                      ref
                          .read(appStateControllerProvider)
                          .setSortOption(option);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: ProjectSortOption.nameAsc,
                        child: const Row(
                          children: [
                            Icon(Icons.sort_by_alpha, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Name (A to Z)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: ProjectSortOption.nameDesc,
                        child: const Row(
                          children: [
                            Icon(Icons.sort_by_alpha, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Name (Z to A)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: ProjectSortOption.dateNewest,
                        child: const Row(
                          children: [
                            Icon(Icons.calendar_today, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Date (Newest First)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: ProjectSortOption.dateOldest,
                        child: const Row(
                          children: [
                            Icon(Icons.calendar_today, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Date (Oldest First)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'New Project',
                    onPressed: () {
                      _showCreateDialog(context, ref);
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
              ).copyWith(bottom: 8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search projects...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.all(8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SilkyListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(
                    top: 8,
                    bottom: 8,
                    left: 12,
                    right: 18,
                  ),
                  itemCount: configs.length,
                  itemBuilder: (context, index) {
                    final config = configs[index];
                    final isSelected = config.id == selectedId;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 4,
                      ),
                      child: Material(
                        color: isSelected
                            ? Theme.of(
                                context,
                              ).colorScheme.primaryContainer.withAlpha(102)
                            : Colors.white.withAlpha(8),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primary.withAlpha(128)
                                  : Colors.transparent,
                            ),
                          ),
                          child: ListTile(
                            title: Text(
                              config.name,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.grey.shade400,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                            selected: isSelected,
                            onTap: () {
                              ref
                                  .read(appStateControllerProvider)
                                  .selectConfig(config.id);
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 16),
                                  onPressed: () =>
                                      _showRenameDialog(context, ref, config),
                                  color: Colors.grey.shade500,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 16),
                                  onPressed: () => _showDeleteConfirmation(
                                    context,
                                    ref,
                                    config,
                                  ),
                                  color: Colors.grey.shade500,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal dialog capturing a project name.
///
/// A dedicated stateful widget owns the [TextEditingController] so it is
/// disposed only after the route (and its closing animation) is gone. Disposing
/// from `showDialog(...).then(...)` can race with the exit transition and throw
/// "A TextEditingController was used after being disposed".
class _ProjectNameDialog extends StatefulWidget {
  const _ProjectNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialValue = '',
  });

  final String confirmLabel;
  final String initialValue;
  final String title;

  @override
  State<_ProjectNameDialog> createState() => _ProjectNameDialogState();
}

class _ProjectNameDialogState extends State<_ProjectNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Project Name'),
        autofocus: true,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
