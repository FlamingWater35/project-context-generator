import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../models/project_config.dart';
import '../models/tree_node.dart';
import '../services/config_service.dart';
import '../services/fs_service.dart';

final configServiceProvider = Provider((ref) => ConfigService());
final fsServiceProvider = Provider((ref) => FsService());

final configsProvider =
    StateNotifierProvider<ConfigsNotifier, List<ProjectConfig>>((ref) {
      return ConfigsNotifier(ref.watch(configServiceProvider));
    });

class ConfigsNotifier extends StateNotifier<List<ProjectConfig>> {
  ConfigsNotifier(this._configService) : super([]) {
    _load();
  }

  final ConfigService _configService;

  Future<void> addConfig(String name) async {
    final newConfig = ProjectConfig(id: const Uuid().v4(), name: name);
    await _configService.saveConfig(newConfig);
    state = [...state, newConfig];
  }

  Future<void> updateConfig(ProjectConfig config, {String? oldName}) async {
    await _configService.saveConfig(config, oldName: oldName);
    state = [
      for (final c in state)
        if (c.id == config.id) config else c,
    ];
  }

  Future<void> deleteConfig(ProjectConfig config) async {
    await _configService.deleteConfig(config.name);
    state = state.where((c) => c.id != config.id).toList();
  }

  Future<void> _load() async {
    state = await _configService.loadConfigs();
  }
}

final selectedConfigIdProvider = StateProvider<String?>((ref) => null);

final selectedConfigProvider = Provider<ProjectConfig?>((ref) {
  final configs = ref.watch(configsProvider);
  final selectedId = ref.watch(selectedConfigIdProvider);
  if (selectedId == null) {
    return configs.isNotEmpty ? configs.first : null;
  }
  try {
    return configs.firstWhere((c) => c.id == selectedId);
  } catch (_) {
    return configs.isNotEmpty ? configs.first : null;
  }
});

class _TreeConfig {
  _TreeConfig(this.rootPath, this.ignorePatterns);

  final List<String> ignorePatterns;
  final String rootPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TreeConfig &&
          rootPath == other.rootPath &&
          listEquals(ignorePatterns, other.ignorePatterns);

  @override
  int get hashCode => rootPath.hashCode ^ Object.hashAll(ignorePatterns);
}

final treeConfigProvider = Provider<_TreeConfig?>((ref) {
  final config = ref.watch(selectedConfigProvider);
  if (config == null || config.rootPath.isEmpty) return null;
  return _TreeConfig(config.rootPath, config.ignorePatterns);
});

final fileTreeProvider = FutureProvider<TreeNode?>((ref) async {
  final treeConfig = ref.watch(treeConfigProvider);
  if (treeConfig == null) return null;

  final fsService = ref.watch(fsServiceProvider);
  return await fsService.buildTree(
    treeConfig.rootPath,
    treeConfig.ignorePatterns,
  );
});

final treeUpdateSignalProvider = StateProvider<int>((ref) => 0);

final appStateControllerProvider = Provider((ref) => AppStateController(ref));

class AppStateController {
  AppStateController(this._ref);

  final Ref _ref;

  void selectConfig(String? id) {
    _ref.read(selectedConfigIdProvider.notifier).state = id;
  }

  Future<void> updateCurrentConfig({
    String? name,
    String? rootPath,
    List<String>? ignorePatterns,
    List<String>? includedFiles,
  }) async {
    final current = _ref.read(selectedConfigProvider);
    if (current == null) return;

    final oldName = (name != null && name != current.name)
        ? current.name
        : null;

    final updated = current.copyWith(
      name: name,
      rootPath: rootPath,
      ignorePatterns: ignorePatterns,
      includedFiles: includedFiles,
    );
    await _ref
        .read(configsProvider.notifier)
        .updateConfig(updated, oldName: oldName);
  }

  void toggleFile(String path, bool isIncluded) {
    final current = _ref.read(selectedConfigProvider);
    if (current == null) return;

    final set = current.includedFiles.toSet();
    if (isIncluded) {
      set.add(path);
    } else {
      set.remove(path);
    }
    updateCurrentConfig(includedFiles: set.toList());
  }

  void selectAll(TreeNode dirNode) {
    final fs = _ref.read(fsServiceProvider);
    final files = fs.getRecursiveFiles(dirNode);
    final current = _ref.read(selectedConfigProvider);
    if (current == null) return;
    final set = current.includedFiles.toSet()..addAll(files);
    updateCurrentConfig(includedFiles: set.toList());
  }

  void selectNone(TreeNode dirNode) {
    final fs = _ref.read(fsServiceProvider);
    final files = fs.getRecursiveFiles(dirNode).toSet();
    final current = _ref.read(selectedConfigProvider);
    if (current == null) return;
    final set = current.includedFiles.toSet()..removeAll(files);
    updateCurrentConfig(includedFiles: set.toList());
  }

  void invertSelection(TreeNode dirNode) {
    final fs = _ref.read(fsServiceProvider);
    final files = fs.getRecursiveFiles(dirNode);
    final current = _ref.read(selectedConfigProvider);
    if (current == null) return;

    final set = current.includedFiles.toSet();
    for (final file in files) {
      if (set.contains(file)) {
        set.remove(file);
      } else {
        set.add(file);
      }
    }
    updateCurrentConfig(includedFiles: set.toList());
  }

  void addIgnorePattern(String pattern) {
    final current = _ref.read(selectedConfigProvider);
    if (current == null) return;
    if (current.ignorePatterns.contains(pattern)) return;

    final set = current.ignorePatterns.toSet()..add(pattern);
    updateCurrentConfig(ignorePatterns: set.toList());
  }

  void toggleNodeExpanded(TreeNode node) {
    node.isExpanded = !node.isExpanded;
    _ref.read(treeUpdateSignalProvider.notifier).state++;
  }
}
