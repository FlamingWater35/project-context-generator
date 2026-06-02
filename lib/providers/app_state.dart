import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../models/project_config.dart';
import '../models/tree_node.dart';
import '../services/config_service.dart';
import '../services/fs_service.dart';

// Provider pointing to the configuration database service helper
final configServiceProvider = Provider((ref) => ConfigService());

// Provider pointing to the multi-isolate file parsing utility
final fsServiceProvider = Provider((ref) => FsService());

// Global state controller for tracking user adjustments to the sidebar layout
final sidebarWidthProvider = StateProvider<double>((ref) => 250.0);

// Tracks identified disk snapshots per project ID to locate structural updates
final projectSnapshotsProvider = StateProvider<Map<String, Set<String>>>(
  (ref) => const {},
);

// Manages expansion triggers of nodes within the dynamic directory viewer
final expansionStateProvider = StateProvider<Map<String, bool>>(
  (ref) => const {},
);

// Application-wide listener monitoring and handling changes to project options
final configsProvider =
    StateNotifierProvider<ConfigsNotifier, List<ProjectConfig>>((ref) {
      return ConfigsNotifier(ref, ref.watch(configServiceProvider));
    });

// State notifier orchestrating background actions on system configurations
class ConfigsNotifier extends StateNotifier<List<ProjectConfig>> {
  ConfigsNotifier(this._ref, this._configService) : super(const []) {
    _load();
  }

  final ConfigService _configService;
  final Ref _ref;
  Timer? _saveTimer;
  ProjectConfig? _pendingConfig;
  String? _pendingOldName;

  // Stores and appends a fresh project record directly into persistent storage
  Future<void> addConfig(String name) async {
    try {
      final newConfig = ProjectConfig(id: const Uuid().v4(), name: name);
      await _configService.saveConfig(newConfig);
      state = [...state, newConfig];
    } catch (e) {
      debugPrint('Error caught while creating new config configuration: $e');
    }
  }

  // Defers and serializes target state parameters in intervals using a debounce window
  void updateConfig(ProjectConfig config, {String? oldName}) {
    state = [
      for (final c in state)
        if (c.id == config.id) config else c,
    ];

    _pendingConfig = config;
    _pendingOldName = oldName;

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      _savePending();
    });
  }

  // Executes actual synchronous file writes for any configurations queued via the debounce window
  void _savePending() {
    if (_pendingConfig != null) {
      try {
        _configService.saveConfig(_pendingConfig!, oldName: _pendingOldName);
      } catch (e) {
        debugPrint('Failure flushing configs during periodic saving steps: $e');
      }
      _pendingConfig = null;
      _pendingOldName = null;
    }
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  // Instantly commits and saves queued configurations on application shutdown
  void flush() {
    _savePending();
  }

  // Removes a configuration metadata record and cleans associated disk assets
  Future<void> deleteConfig(ProjectConfig config) async {
    try {
      if (_pendingConfig?.id == config.id) {
        _pendingConfig = null;
        _pendingOldName = null;
        _saveTimer?.cancel();
      }
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
    } catch (e) {
      debugPrint('Error occurred trying to delete target configuration: $e');
    }
  }

  // Asynchronously loads all previously stored project configs from local disk
  Future<void> _load() async {
    try {
      state = await _configService.loadConfigs();
    } catch (e) {
      debugPrint('Failed loading saved configuration parameters: $e');
      state = const [];
    }
  }
}

// State tracker focusing exclusively on the active config database selection identifier
final selectedConfigIdProvider = StateProvider<String?>((ref) => null);

// Exposes details regarding the currently highlighted active configuration structure
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

// Caches and exposes checked paths as a Set to allow O(1) lookups during recursive rendering
final selectedIncludedFilesSetProvider = Provider<Set<String>>((ref) {
  final config = ref.watch(selectedConfigProvider);
  if (config == null) return const <String>{};
  return config.includedFiles.toSet();
});

// Private helper to capture identical properties and compare changes across scans
class _TreeConfig {
  const _TreeConfig(this.configId, this.rootPath, this.ignorePatterns);

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

// Evaluates active directory roots and ignore settings configuration matches
final treeConfigProvider = Provider<_TreeConfig?>((ref) {
  final config = ref.watch(selectedConfigProvider);
  if (config == null || config.rootPath.isEmpty) return null;
  return _TreeConfig(config.id, config.rootPath, config.ignorePatterns);
});

// Emits loaded background directories mapped and structured dynamically as UI node trees
final fileTreeProvider = FutureProvider<TreeNode?>((ref) async {
  bool mounted = true;
  ref.onDispose(() => mounted = false);

  final treeConfig = ref.watch(treeConfigProvider);
  if (treeConfig == null) return null;

  final snapshots = ref.read(projectSnapshotsProvider);
  Set<String>? knownPaths = snapshots[treeConfig.configId];

  try {
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
  } catch (e) {
    debugPrint('Critical file parsing scan exception captured: $e');
    return null;
  }
});

// App-wide provider containing high-level directory structural modifiers
final appStateControllerProvider = Provider((ref) => AppStateController(ref));

// Direct logic layer triggering disk state adjustments and directory manipulation actions
class AppStateController {
  const AppStateController(this._ref);

  final Ref _ref;

  // Handles sidebar target config selection changes and invalidates expansion state keys
  void selectConfig(String? id) {
    _ref.read(selectedConfigIdProvider.notifier).state = id;
    _ref.read(expansionStateProvider.notifier).state = const {};
  }

  // Accepts and overrides directory metadata indicators to mark newly identified assets as loaded
  Future<void> acknowledgeChanges() async {
    try {
      final config = _ref.read(selectedConfigProvider);
      if (config == null || config.rootPath.isEmpty) return;

      final fs = _ref.read(fsServiceProvider);
      final currentPaths = await fs.scanPaths(
        config.rootPath,
        config.ignorePatterns,
      );

      final effectiveIncluded = config.includedFiles
          .where((p) => currentPaths.contains(p))
          .toList();

      if (effectiveIncluded.length != config.includedFiles.length) {
        await updateCurrentConfig(includedFiles: effectiveIncluded);
      }

      final configService = _ref.read(configServiceProvider);
      await configService.saveSnapshot(config.id, currentPaths);

      final snapshots = _ref.read(projectSnapshotsProvider.notifier);
      snapshots.state = {...snapshots.state, config.id: currentPaths};
    } catch (e) {
      debugPrint(
        'Failure attempting to update database reference mappings: $e',
      );
    }
  }

  // Directly amends and commits alterations to physical attributes on the selected context
  Future<void> updateCurrentConfig({
    String? name,
    String? rootPath,
    List<String>? ignorePatterns,
    List<String>? includedFiles,
  }) async {
    try {
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

      _ref
          .read(configsProvider.notifier)
          .updateConfig(updated, oldName: oldName);
    } catch (e) {
      debugPrint('Failed to apply configuration variations: $e');
    }
  }

  // Adds or removes specific paths to the persistent selection configuration
  Future<void> toggleFile(String path, bool isIncluded) async {
    try {
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final set = current.includedFiles.toSet();
      if (isIncluded) {
        set.add(path);
      } else {
        set.remove(path);
      }
      await updateCurrentConfig(includedFiles: set.toList());
    } catch (e) {
      debugPrint('Failed to toggle individual file node status: $e');
    }
  }

  // Includes all target nodes belonging underneath a highlighted parent tree node
  Future<void> selectAll(TreeNode dirNode) async {
    try {
      final files = _ref.read(fsServiceProvider).getRecursiveFiles(dirNode);
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final set = current.includedFiles.toSet()..addAll(files);
      await updateCurrentConfig(includedFiles: set.toList());
    } catch (e) {
      debugPrint('Failed to apply recursive directory item inclusions: $e');
    }
  }

  // Purges all listed children nodes of a target folder node from selections
  Future<void> selectNone(TreeNode dirNode) async {
    try {
      final files = _ref
          .read(fsServiceProvider)
          .getRecursiveFiles(dirNode)
          .toSet();
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final set = current.includedFiles.toSet()..removeAll(files);
      await updateCurrentConfig(includedFiles: set.toList());
    } catch (e) {
      debugPrint('Failed to exclude directory children items: $e');
    }
  }

  // Flips file selection states across target children nested inside a folder node
  Future<void> invertSelection(TreeNode dirNode) async {
    try {
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
      await updateCurrentConfig(includedFiles: set.toList());
    } catch (e) {
      debugPrint('Failed to execute inverted state adjustment requests: $e');
    }
  }

  // Adds a global pattern definition to exclude matching paths
  Future<void> addIgnorePattern(String pattern) async {
    try {
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      if (current.ignorePatterns.contains(pattern)) return;
      final set = current.ignorePatterns.toSet()..add(pattern);
      await updateCurrentConfig(ignorePatterns: set.toList());
    } catch (e) {
      debugPrint('Failed to insert target ignore rules pattern parameter: $e');
    }
  }

  // Toggles the local UI visual visibility status parameters of directory trees
  void toggleNodeExpanded(String nodePath) {
    try {
      final currentState = _ref.read(expansionStateProvider);
      final isCurrentlyExpanded = currentState[nodePath] ?? false;
      _ref.read(expansionStateProvider.notifier).state = {
        ...currentState,
        nodePath: !isCurrentlyExpanded,
      };
    } catch (e) {
      debugPrint('Failed to alter tree layout expansion status data: $e');
    }
  }

  // Completely resets active cache snapshots matching selected identifier parameters
  Future<void> _clearSnapshot(String configId) async {
    try {
      final snapshots = _ref.read(projectSnapshotsProvider.notifier);
      final newSnaps = Map<String, Set<String>>.from(snapshots.state);
      newSnaps.remove(configId);
      snapshots.state = newSnaps;

      final configService = _ref.read(configServiceProvider);
      await configService.deleteSnapshot(configId);
    } catch (e) {
      debugPrint('Failure recorded when wiping database references: $e');
    }
  }
}
