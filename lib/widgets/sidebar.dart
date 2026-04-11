import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project_config.dart';
import '../providers/app_state.dart';
import 'smooth_scroll.dart';

class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key});

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final SmoothScrollController _scrollController = SmoothScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Project'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Project Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref
                    .read(configsProvider.notifier)
                    .addConfig(controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    ProjectConfig config,
  ) {
    final controller = TextEditingController(text: config.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Project'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Project Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref
                    .read(configsProvider.notifier)
                    .updateConfig(
                      config.copyWith(name: controller.text.trim()),
                      oldName: config.name,
                    );
              }
              Navigator.pop(context);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

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
            onPressed: () {
              ref.read(configsProvider.notifier).deleteConfig(config);
              Navigator.pop(context);
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
    var configs = allConfigs.toList();

    configs.sort((a, b) {
      int cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
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
        width: 250,
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Text(
                    'Projects',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
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
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: configs.length,
                itemBuilder: (context, index) {
                  final config = configs[index];
                  final isSelected = config.id == selectedId;

                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(
                              context,
                            ).colorScheme.primaryContainer.withAlpha(102)
                          : Colors.white.withAlpha(8),
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
                            onPressed: () =>
                                _showDeleteConfirmation(context, ref, config),
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
