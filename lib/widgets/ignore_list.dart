import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_config.dart';
import '../providers/app_state.dart';

class IgnoreListDialog extends ConsumerStatefulWidget {
  final ProjectConfig config;
  const IgnoreListDialog({super.key, required this.config});

  @override
  ConsumerState<IgnoreListDialog> createState() => _IgnoreListDialogState();
}

class _IgnoreListDialogState extends ConsumerState<IgnoreListDialog> {
  late List<String> ignores;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    ignores = List.from(widget.config.ignorePatterns);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom Ignores'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: Column(
          children:[
            Row(
              children:[
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'Add ignore pattern (e.g. node_modules/**)',
                    ),
                    onSubmitted: _addIgnore,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _addIgnore(_controller.text),
                )
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: ignores.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(ignores[index]),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        setState(() {
                          ignores.removeAt(index);
                        });
                      },
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
      actions:[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            ref.read(appStateControllerProvider).updateCurrentConfig(ignorePatterns: ignores);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _addIgnore(String val) {
    if (val.trim().isNotEmpty) {
      setState(() {
        ignores.add(val.trim());
        _controller.clear();
      });
    }
  }
}
