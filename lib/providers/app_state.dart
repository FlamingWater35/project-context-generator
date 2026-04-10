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

final projectSnapshotsProvider = StateProvider<Map<String, Set<String>>>(
  (ref) => {},
);

final expansionStateProvider = StateProvider<Map<String, bool>>((ref) => {});

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
  if (selectedId == null) return configs.isNotEmpty ? configs.first : null;
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

  final snapshots = ref.watch(projectSnapshotsProvider);
  final config = ref.read(selectedConfigProvider);

  final knownPaths = config != null ? (snapshots[config.id] ?? {}) : null;

  final fsService = ref.watch(fsServiceProvider);
  return await fsService.buildTree(
    treeConfig.rootPath,
    treeConfig.ignorePatterns,
    knownPaths: knownPaths,
  );
});

final treeUpdateSignalProvider = StateProvider<int>((ref) => 0);
final appStateControllerProvider = Provider((ref) => AppStateController(ref));

class AppStateController {
  AppStateController(this._ref);

  final Ref _ref;

  void selectConfig(String? id) {
    _ref.read(selectedConfigIdProvider.notifier).state = id;
    _ref.read(expansionStateProvider.notifier).state = {};
    _loadPersistedSnapshot(id);
  }

  Future<void> refreshSnapshot({bool acknowledge = false}) async {
    final config = _ref.read(selectedConfigProvider);
    if (config == null || config.rootPath.isEmpty) return;

    final fs = _ref.read(fsServiceProvider);
    final currentPaths = await fs.scanPaths(
      config.rootPath,
      config.ignorePatterns,
    );

    final configService = _ref.read(configServiceProvider);
    await configService.saveSnapshot(config.id, currentPaths);

    if (acknowledge) {
      final snapshots = _ref.read(projectSnapshotsProvider.notifier);
      snapshots.state = {...snapshots.state, config.id: currentPaths};
    }
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

    if (rootPath != null || ignorePatterns != null) {
      await _resetSnapshotBaseline(current.id);
      _ref.invalidate(fileTreeProvider);
    }
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
    final files = _ref.read(fsServiceProvider).getRecursiveFiles(dirNode);
    final current = _ref.read(selectedConfigProvider);
    if (current == null) return;
    final set = current.includedFiles.toSet()..addAll(files);
    updateCurrentConfig(includedFiles: set.toList());
  }

  void selectNone(TreeNode dirNode) {
    final files = _ref
        .read(fsServiceProvider)
        .getRecursiveFiles(dirNode)
        .toSet();
    final current = _ref.read(selectedConfigProvider);
    if (current == null) return;
    final set = current.includedFiles.toSet()..removeAll(files);
    updateCurrentConfig(includedFiles: set.toList());
  }

  void invertSelection(TreeNode dirNode) {
    final files = _ref.read(fsServiceProvider).getRecursiveFiles(dirNode);
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

  void toggleNodeExpanded(String nodePath) {
    final currentState = _ref.read(expansionStateProvider);
    final isCurrentlyExpanded = currentState[nodePath] ?? false;
    _ref.read(expansionStateProvider.notifier).state = {
      ...currentState,
      nodePath: !isCurrentlyExpanded,
    };
    _ref.read(treeUpdateSignalProvider.notifier).state++;
  }

  Future<void> _loadPersistedSnapshot(String? id) async {
    if (id == null) return;
    final config = _ref.read(configsProvider).firstWhere((c) => c.id == id);
    if (config.rootPath.isEmpty) return;

    final configService = _ref.read(configServiceProvider);
    final persistedSnapshot = await configService.loadSnapshot(id);

    final snapshots = _ref.read(projectSnapshotsProvider.notifier);

    if (persistedSnapshot != null) {
      snapshots.state = {...snapshots.state, id: persistedSnapshot};
    } else {
      final fs = _ref.read(fsServiceProvider);
      final currentPaths = await fs.scanPaths(
        config.rootPath,
        config.ignorePatterns,
      );

      await configService.saveSnapshot(id, currentPaths);
      snapshots.state = {...snapshots.state, id: currentPaths};
    }
  }

  Future<void> _resetSnapshotBaseline(String configId) async {
    final config = _ref
        .read(configsProvider)
        .firstWhere((c) => c.id == configId);
    if (config.rootPath.isEmpty) return;

    final fs = _ref.read(fsServiceProvider);
    final currentPaths = await fs.scanPaths(
      config.rootPath,
      config.ignorePatterns,
    );

    final configService = _ref.read(configServiceProvider);
    await configService.saveSnapshot(configId, currentPaths);

    final snapshots = _ref.read(projectSnapshotsProvider.notifier);
    snapshots.state = {...snapshots.state, configId: currentPaths};
  }
}
