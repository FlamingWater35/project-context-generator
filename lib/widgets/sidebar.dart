import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(configsProvider);
    final selectedId = ref.watch(selectedConfigIdProvider) ?? (configs.isNotEmpty ? configs.first.id : null);

    return Material(
      elevation: 2,
      child: Container(
        width: 250,
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children:[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children:[
                  const Text('Projects', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      _showCreateDialog(context, ref);
                    },
                  )
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: configs.length,
                itemBuilder: (context, index) {
                  final config = configs[index];
                  final isSelected = config.id == selectedId;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4)
                          : Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                            : Colors.transparent,
                      ),
                    ),
                    child: ListTile(
                      title: Text(
                        config.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Theme.of(context).colorScheme.onSurface : Colors.grey.shade400,
                        ),
                      ),
                      selected: isSelected,
                      onTap: () {
                        ref.read(appStateControllerProvider).selectConfig(config.id);
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children:[
                          IconButton(
                            icon: const Icon(Icons.edit, size: 16),
                            onPressed: () => _showRenameDialog(context, ref, config),
                            color: Colors.grey.shade500,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 16),
                            onPressed: () {
                              ref.read(configsProvider.notifier).deleteConfig(config);
                            },
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
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
        actions:[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref.read(configsProvider.notifier).addConfig(controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, config) {
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
        actions:[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref.read(configsProvider.notifier).updateConfig(
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
    );
  }
}
