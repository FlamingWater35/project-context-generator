import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_config.dart';
import '../providers/app_state.dart';
import 'smooth_scroll.dart';

class IgnoreListDialog extends ConsumerStatefulWidget {
  final ProjectConfig config;
  const IgnoreListDialog({super.key, required this.config});

  @override
  ConsumerState<IgnoreListDialog> createState() => _IgnoreListDialogState();
}

class _IgnoreListDialogState extends ConsumerState<IgnoreListDialog> {
  late List<String> ignores;
  final TextEditingController _controller = TextEditingController();
  final SmoothScrollController _scrollController = SmoothScrollController();
  final SmoothScrollController _presetScrollController = SmoothScrollController();

  bool _showPresets = true;

  final List<String> commonPresets = const [
    '.git/**',
    'node_modules/**',
    'build/**',
    '.dart_tool/**',
    '**/*.lock',
    '**/*.g.dart',
    '.idea/**',
    '.vscode/**',
    'dist/**',
    'target/**',
    'vendor/**',
    '**/.DS_Store',
  ];

  @override
  void initState() {
    super.initState();
    ignores = List.from(widget.config.ignorePatterns);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _presetScrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _addIgnore(String val) {
    final trimmed = val.trim();
    if (trimmed.isNotEmpty && !ignores.contains(trimmed)) {
      setState(() {
        ignores.add(trimmed);
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    final dialogWidth = (screenSize.width * 0.7).clamp(600.0, 1000.0);
    final dialogHeight = (screenSize.height * 0.7).clamp(400.0, 800.0);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.blur_off, size: 24),
          const SizedBox(width: 12),
          const Text('Ignore Patterns'),
          const Spacer(),
          IconButton(
            icon: Icon(_showPresets ? Icons.view_sidebar : Icons.view_sidebar_outlined),
            tooltip: _showPresets ? 'Hide Presets' : 'Show Presets',
            onPressed: () => setState(() => _showPresets = !_showPresets),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Files matching these patterns will be excluded from the generated context.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: 'Add custom pattern (e.g. **/temp/*)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onSubmitted: _addIgnore,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.add),
                        onPressed: () => _addIgnore(_controller.text),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white.withAlpha(20)),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.black.withAlpha(10),
                      ),
                      child: ignores.isEmpty
                          ? Center(
                              child: Text('No active ignore patterns.',
                              style: TextStyle(color: Colors.grey.shade600)))
                          : Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              child: ListView.separated(
                                controller: _scrollController,
                                padding: EdgeInsets.zero,
                                itemCount: ignores.length,
                                separatorBuilder: (ctx, i) => Divider(height: 1, color: Colors.white.withAlpha(10)),
                                itemBuilder: (ctx, i) => ListTile(
                                  dense: true,
                                  title: Text(ignores[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () => setState(() => ignores.removeAt(i)),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            if (_showPresets) ...[
              const VerticalDivider(width: 32, indent: 10, endIndent: 10),
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Common Presets', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Scrollbar(
                        controller: _presetScrollController,
                        thumbVisibility: true,
                        child: ListView(
                          controller: _presetScrollController,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: commonPresets.map((preset) {
                                final isAdded = ignores.contains(preset);
                                return FilterChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(preset, style: const TextStyle(fontSize: 11)),
                                  selected: isAdded,
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) {
                                        ignores.add(preset);
                                      } else {
                                        ignores.remove(preset);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            ref.read(appStateControllerProvider).updateCurrentConfig(ignorePatterns: ignores);
            Navigator.pop(context);
          },
          child: const Text('Apply Changes'),
        ),
      ],
    );
  }
}
