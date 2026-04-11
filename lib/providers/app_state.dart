import 'dart:async';

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
      return ConfigsNotifier(ref, ref.watch(configServiceProvider));
    });

class ConfigsNotifier extends StateNotifier<List<ProjectConfig>> {
  ConfigsNotifier(this._ref, this._configService) : super([]) {
    _load();
  }

  final ConfigService _configService;
  final Ref _ref;
  Timer? _saveTimer;

  Future<void> addConfig(String name) async {
    final newConfig = ProjectConfig(id: const Uuid().v4(), name: name);
    await _configService.saveConfig(newConfig);
    state = [...state, newConfig];
  }

  void updateConfig(ProjectConfig config, {String? oldName}) {
    state = [
      for (final c in state)
        if (c.id == config.id) config else c,
    ];

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      _configService.saveConfig(config, oldName: oldName);
    });
  }

  Future<void> deleteConfig(ProjectConfig config) async {
    await _configService.deleteConfig(config);
    state = state.where((c) => c.id != config.id).toList();

    final currentSelectedId = _ref.read(selectedConfigIdProvider);
    if (currentSelectedId == config.id) {
      _ref.read(selectedConfigIdProvider.notifier).state = state.isNotEmpty
          ? state.first.id
          : null;
    }

    final snapshots = _ref.read(projectSnapshotsProvider.notifier);
    final newSnapshots = Map<String, Set<String>>.from(snapshots.state);
    newSnapshots.remove(config.id);
    snapshots.state = newSnapshots;
  }

  Future<void> _load() async {
    state = await _configService.loadConfigs();
  }
}

final selectedConfigIdProvider = StateProvider<String?>((ref) => null);

final selectedConfigProvider = Provider<ProjectConfig?>((ref) {
  final configs = ref.watch(configsProvider);
  final selectedId = ref.watch(selectedConfigIdProvider);
  if (configs.isEmpty) return null;

  final config = configs.where((c) => c.id == selectedId).firstOrNull;
  if (config != null) return config;

  Future.microtask(() {
    ref.read(selectedConfigIdProvider.notifier).state = configs.first.id;
  });

  return configs.first;
});

class _TreeConfig {
  _TreeConfig(this.configId, this.rootPath, this.ignorePatterns);

  final String configId;
  final List<String> ignorePatterns;
  final String rootPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TreeConfig &&
          configId == other.configId &&
          rootPath == other.rootPath &&
          listEquals(ignorePatterns, other.ignorePatterns);

  @override
  int get hashCode =>
      Object.hash(configId, rootPath, Object.hashAll(ignorePatterns));
}

final treeConfigProvider = Provider<_TreeConfig?>((ref) {
  final config = ref.watch(selectedConfigProvider);
  if (config == null || config.rootPath.isEmpty) return null;
  return _TreeConfig(config.id, config.rootPath, config.ignorePatterns);
});

final fileTreeProvider = FutureProvider<TreeNode?>((ref) async {
  bool mounted = true;
  ref.onDispose(() => mounted = false);

  final treeConfig = ref.watch(treeConfigProvider);
  if (treeConfig == null) return null;

  final snapshots = ref.read(projectSnapshotsProvider);
  Set<String>? knownPaths = snapshots[treeConfig.configId];

  if (knownPaths == null) {
    final configService = ref.read(configServiceProvider);
    knownPaths = await configService.loadSnapshot(treeConfig.configId);

    if (!mounted) return null;

    if (knownPaths == null) {
      final fs = ref.read(fsServiceProvider);
      knownPaths = await fs.scanPaths(
        treeConfig.rootPath,
        treeConfig.ignorePatterns,
      );

      if (!mounted) return null;

      await configService.saveSnapshot(treeConfig.configId, knownPaths);
    }

    if (mounted) {
      Future.microtask(() {
        if (mounted) {
          final notifier = ref.read(projectSnapshotsProvider.notifier);
          if (!notifier.state.containsKey(treeConfig.configId)) {
            notifier.state = {
              ...notifier.state,
              treeConfig.configId: knownPaths!,
            };
          }
        }
      });
    }
  }

  final fsService = ref.read(fsServiceProvider);
  return await fsService.buildTree(
    treeConfig.rootPath,
    treeConfig.ignorePatterns,
    knownPaths: knownPaths,
  );
});

final appStateControllerProvider = Provider((ref) => AppStateController(ref));

class AppStateController {
  AppStateController(this._ref);

  final Ref _ref;

  void selectConfig(String? id) {
    _ref.read(selectedConfigIdProvider.notifier).state = id;
    _ref.read(expansionStateProvider.notifier).state = {};
  }

  Future<void> acknowledgeChanges() async {
    final config = _ref.read(selectedConfigProvider);
    if (config == null || config.rootPath.isEmpty) return;

    final fs = _ref.read(fsServiceProvider);
    final currentPaths = await fs.scanPaths(
      config.rootPath,
      config.ignorePatterns,
    );

    final configService = _ref.read(configServiceProvider);
    await configService.saveSnapshot(config.id, currentPaths);

    final snapshots = _ref.read(projectSnapshotsProvider.notifier);
    snapshots.state = {...snapshots.state, config.id: currentPaths};
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

    if (rootPath != null || ignorePatterns != null) {
      await _clearSnapshot(current.id);
    }

    _ref.read(configsProvider.notifier).updateConfig(updated, oldName: oldName);
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
  }

  Future<void> _clearSnapshot(String configId) async {
    final snapshots = _ref.read(projectSnapshotsProvider.notifier);
    final newSnaps = Map<String, Set<String>>.from(snapshots.state);
    newSnaps.remove(configId);
    snapshots.state = newSnaps;

    final configService = _ref.read(configServiceProvider);
    await configService.deleteSnapshot(configId);
  }
}
