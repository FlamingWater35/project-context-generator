import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../models/agent_skill.dart';
import '../models/project_config.dart';
import '../models/tree_node.dart';
import '../services/config_service.dart';
import '../services/fs_service.dart';

/// Available sorting modes for organizing project configurations in the sidebar.
enum ProjectSortOption { nameAsc, nameDesc, dateNewest, dateOldest }

/// Provider pointing to the configuration database service helper.
final configServiceProvider = Provider((ref) => ConfigService());

/// Provider pointing to the multi-isolate file parsing utility.
final fsServiceProvider = Provider((ref) => FsService());

/// Global state controller for tracking user adjustments to the sidebar layout.
final sidebarWidthProvider = StateProvider<double>((ref) => 250.0);

/// State provider tracking the active project sorting option.
final projectSortOptionProvider = StateProvider<ProjectSortOption>(
  (ref) => ProjectSortOption.nameAsc,
);

/// Tracks node paths currently highlighted/selected via multi-select gestures or button toggles.
final selectedNodePathsProvider = StateProvider<Set<String>>((ref) => const {});

/// Tracks identified disk snapshots per project ID to locate structural updates.
final projectSnapshotsProvider = StateProvider<Map<String, Set<String>>>(
  (ref) => const {},
);

/// Manages expansion triggers of nodes within the dynamic directory viewer.
final expansionStateProvider = StateProvider<Map<String, bool>>(
  (ref) => const {},
);

/// Application-wide listener monitoring and handling changes to project options.
final configsProvider =
    StateNotifierProvider<ConfigsNotifier, List<ProjectConfig>>((ref) {
      return ConfigsNotifier(ref, ref.watch(configServiceProvider));
    });

/// State notifier orchestrating background actions on system configurations.
class ConfigsNotifier extends StateNotifier<List<ProjectConfig>> {
  ConfigsNotifier(this._ref, this._configService) : super(const []) {
    _load();
  }

  final ConfigService _configService;
  final Ref _ref;
  ProjectConfig? _pendingConfig;
  String? _pendingOldName;
  Timer? _saveTimer;

  /// Stores and appends a fresh project record directly into persistent storage.
  Future<void> addConfig(String name) async {
    try {
      final newConfig = ProjectConfig(id: const Uuid().v4(), name: name);
      await _configService.saveConfig(newConfig);
      state = [...state, newConfig];

      _ref.read(appStateControllerProvider).selectConfig(newConfig.id);
    } catch (e) {
      debugPrint('Error creating new config configuration: $e');
    }
  }

  /// Defers and serializes target state parameters in intervals using a debounce window.
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

  /// Executes actual synchronous file writes for any configurations queued via the debounce window.
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

  /// Instantly commits and saves queued configurations on application shutdown.
  void flush() {
    _savePending();
  }

  /// Removes a configuration metadata record and cleans associated disk assets.
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
        final newSelected = state.isNotEmpty ? state.first.id : null;
        _ref.read(appStateControllerProvider).selectConfig(newSelected);
      }

      final snapshots = _ref.read(projectSnapshotsProvider.notifier);
      final newSnapshots = Map<String, Set<String>>.from(snapshots.state);
      newSnapshots.remove(config.id);
      snapshots.state = newSnapshots;
    } catch (e) {
      debugPrint('Error occurred trying to delete target configuration: $e');
    }
  }

  /// Asynchronously loads all previously stored project configs and restores the last opened project.
  Future<void> _load() async {
    try {
      state = await _configService.loadConfigs();

      final windowState = await _configService.loadWindowState();
      if (windowState != null) {
        final lastId = windowState['lastSelectedProjectId'] as String?;
        if (lastId != null && state.any((c) => c.id == lastId)) {
          _ref.read(selectedConfigIdProvider.notifier).state = lastId;
        } else if (state.isNotEmpty) {
          _ref.read(selectedConfigIdProvider.notifier).state = state.first.id;
        }

        final sortName = windowState['projectSortOption'] as String?;
        if (sortName != null) {
          final matchedOption = ProjectSortOption.values.firstWhere(
            (e) => e.name == sortName,
            orElse: () => ProjectSortOption.nameAsc,
          );
          _ref.read(projectSortOptionProvider.notifier).state = matchedOption;
        }
      } else if (state.isNotEmpty) {
        _ref.read(selectedConfigIdProvider.notifier).state = state.first.id;
      }
    } catch (e) {
      debugPrint('Failed loading saved configuration parameters: $e');
      state = const [];
    }
  }
}

/// State tracker focusing exclusively on the active config database selection identifier.
final selectedConfigIdProvider = StateProvider<String?>((ref) => null);

/// Exposes details regarding the currently highlighted active configuration structure cleanly without side-effects.
final selectedConfigProvider = Provider<ProjectConfig?>((ref) {
  final configs = ref.watch(configsProvider);
  final selectedId = ref.watch(selectedConfigIdProvider);
  if (configs.isEmpty) return null;

  final config = configs.where((c) => c.id == selectedId).firstOrNull;
  return config ?? configs.first;
});

/// Asynchronously scans project root to discover agent skills in the codebase.
final detectedSkillsProvider = FutureProvider<List<AgentSkill>>((ref) async {
  final config = ref.watch(selectedConfigProvider);
  if (config == null || config.rootPath.isEmpty) return const [];

  final fs = ref.read(fsServiceProvider);
  return await fs.detectSkills(config.rootPath);
});

/// Exposes the unified collection of detected and custom skills for the current project.
final allProjectSkillsProvider = Provider<List<AgentSkill>>((ref) {
  final config = ref.watch(selectedConfigProvider);
  if (config == null) return const [];

  final detected = ref.watch(detectedSkillsProvider).value ?? const [];
  final custom = config.customSkills;

  final Map<String, AgentSkill> map = {};
  for (final skill in detected) {
    map[skill.id] = skill;
  }
  for (final skill in custom) {
    map[skill.id] = skill;
  }
  return map.values.toList();
});

/// Caches and exposes checked paths as a Set to allow O(1) lookups during recursive rendering.
final selectedIncludedFilesSetProvider = Provider<Set<String>>((ref) {
  final config = ref.watch(selectedConfigProvider);
  if (config == null) return const <String>{};
  return config.includedFiles.toSet();
});

/// Private helper to capture identical properties and compare changes across scans.
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

/// Evaluates active directory roots and ignore settings configuration matches.
final treeConfigProvider = Provider<_TreeConfig?>((ref) {
  final config = ref.watch(selectedConfigProvider);
  if (config == null || config.rootPath.isEmpty) return null;
  return _TreeConfig(config.id, config.rootPath, config.ignorePatterns);
});

/// Emits loaded background directories mapped and structured dynamically as UI node trees.
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
    debugPrint('File parsing scan exception captured: $e');
    return null;
  }
});

/// Computes prompt statistics in background isolate for live display in bottom status bar.
final promptStatsProvider = FutureProvider<PromptBuildResult?>((ref) async {
  final config = ref.watch(selectedConfigProvider);
  if (config == null || config.rootPath.isEmpty) return null;

  final selectedSkillIds = config.selectedSkillIds.toSet();
  final allSkills = ref.watch(allProjectSkillsProvider);
  final selectedSkills = allSkills
      .where((s) => selectedSkillIds.contains(s.id))
      .toList();

  final fsService = ref.read(fsServiceProvider);

  final params = PromptBuildParams(
    projectName: config.name,
    rootPath: config.rootPath,
    includedFiles: config.includedFiles,
    selectedSkills: selectedSkills,
    ignorePatterns: config.ignorePatterns,
  );

  return await fsService.buildPromptContext(params);
});

/// App-wide provider containing high-level directory structural modifiers.
final appStateControllerProvider = Provider((ref) => AppStateController(ref));

/// Direct logic layer triggering disk state adjustments and directory manipulation actions.
class AppStateController {
  const AppStateController(this._ref);

  final Ref _ref;

  /// Recursively resolves input paths (files or directories) into individual relative file paths.
  List<String> _expandPathsToFiles(Iterable<String> paths) {
    final treeNode = _ref.read(fileTreeProvider).value;
    if (treeNode == null) return paths.toList();

    final Set<String> resultFiles = {};

    TreeNode? findNode(TreeNode current, String relPath) {
      if (current.relativePath == relPath) return current;
      for (final child in current.children) {
        final found = findNode(child, relPath);
        if (found != null) return found;
      }
      return null;
    }

    for (final path in paths) {
      final node = findNode(treeNode, path);
      if (node != null) {
        resultFiles.addAll(node.getAllFilePaths());
      } else {
        resultFiles.add(path);
      }
    }

    return resultFiles.toList();
  }

  /// Handles sidebar target config selection changes and persists the selected project ID.
  void selectConfig(String? id) {
    _ref.read(selectedConfigIdProvider.notifier).state = id;
    _ref.read(expansionStateProvider.notifier).state = const {};
    _ref.read(selectedNodePathsProvider.notifier).state = const {};

    if (id != null) {
      _saveLastSelectedProject(id);
    }
  }

  /// Updates and persists the current project list sorting option.
  void setSortOption(ProjectSortOption option) {
    _ref.read(projectSortOptionProvider.notifier).state = option;
    _saveSortOption(option);
  }

  /// Accepts and overrides directory metadata indicators to mark newly identified assets as loaded.
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

  /// Directly amends and commits alterations to physical attributes on the selected context.
  Future<void> updateCurrentConfig({
    String? name,
    String? rootPath,
    List<String>? ignorePatterns,
    List<String>? includedFiles,
    List<String>? selectedSkillIds,
    List<AgentSkill>? customSkills,
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
        selectedSkillIds: selectedSkillIds,
        customSkills: customSkills,
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

  /// Includes multiple file or directory relative paths at once, expanding directory paths recursively.
  Future<void> checkFiles(Iterable<String> paths) async {
    try {
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final expandedFilePaths = _expandPathsToFiles(paths);
      final set = current.includedFiles.toSet()..addAll(expandedFilePaths);
      await updateCurrentConfig(includedFiles: set.toList());
    } catch (e) {
      debugPrint('Failed to check files: $e');
    }
  }

  /// Unchecks multiple file or directory relative paths at once.
  Future<void> uncheckFiles(Iterable<String> paths) async {
    try {
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final expandedFilePaths = _expandPathsToFiles(paths);
      final set = current.includedFiles.toSet()..removeAll(expandedFilePaths);
      await updateCurrentConfig(includedFiles: set.toList());
    } catch (e) {
      debugPrint('Failed to uncheck files: $e');
    }
  }

  /// Toggles inclusion of a target agent skill for context prompt generation.
  Future<void> toggleSkillSelection(String skillId) async {
    try {
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final set = current.selectedSkillIds.toSet();
      if (set.contains(skillId)) {
        set.remove(skillId);
      } else {
        set.add(skillId);
      }
      await updateCurrentConfig(selectedSkillIds: set.toList());
    } catch (e) {
      debugPrint('Failed to toggle skill selection status: $e');
    }
  }

  /// Selects all available skills for context prompt inclusion.
  Future<void> selectAllSkills(List<String> skillIds) async {
    try {
      await updateCurrentConfig(selectedSkillIds: skillIds);
    } catch (e) {
      debugPrint('Failed to select all skills: $e');
    }
  }

  /// Deselects all skills for context prompt inclusion.
  Future<void> deselectAllSkills() async {
    try {
      await updateCurrentConfig(selectedSkillIds: const []);
    } catch (e) {
      debugPrint('Failed to deselect all skills: $e');
    }
  }

  /// Appends a custom user-created skill to the active project configuration.
  Future<void> addCustomSkill(AgentSkill skill) async {
    try {
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final updatedCustom = [...current.customSkills, skill];
      final updatedSelected = [...current.selectedSkillIds, skill.id];
      await updateCurrentConfig(
        customSkills: updatedCustom,
        selectedSkillIds: updatedSelected,
      );
    } catch (e) {
      debugPrint('Failed to add custom skill: $e');
    }
  }

  /// Removes a custom user-created skill from the active project configuration.
  Future<void> deleteCustomSkill(String skillId) async {
    try {
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final updatedCustom = current.customSkills
          .where((s) => s.id != skillId)
          .toList();
      final updatedSelected = current.selectedSkillIds
          .where((id) => id != skillId)
          .toList();
      await updateCurrentConfig(
        customSkills: updatedCustom,
        selectedSkillIds: updatedSelected,
      );
    } catch (e) {
      debugPrint('Failed to delete custom skill: $e');
    }
  }

  /// Adds or removes specific paths to the persistent selection configuration.
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

  /// Includes all target nodes belonging underneath a highlighted parent tree node.
  Future<void> selectAll(TreeNode dirNode) async {
    try {
      final files = dirNode.getAllFilePaths();
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final set = current.includedFiles.toSet()..addAll(files);
      await updateCurrentConfig(includedFiles: set.toList());
    } catch (e) {
      debugPrint('Failed to apply recursive directory item inclusions: $e');
    }
  }

  /// Purges all listed children nodes of a target folder node from selections.
  Future<void> selectNone(TreeNode dirNode) async {
    try {
      final files = dirNode.getAllFilePaths().toSet();
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final set = current.includedFiles.toSet()..removeAll(files);
      await updateCurrentConfig(includedFiles: set.toList());
    } catch (e) {
      debugPrint('Failed to exclude directory children items: $e');
    }
  }

  /// Flips file selection states across target children nested inside a folder node.
  Future<void> invertSelection(TreeNode dirNode) async {
    try {
      final files = dirNode.getAllFilePaths();
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

  /// Adds a global pattern definition to exclude matching paths.
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

  /// Appends multiple ignore rules to the configuration, automatically formatting directory paths.
  Future<void> addIgnorePatterns(List<String> paths) async {
    try {
      final current = _ref.read(selectedConfigProvider);
      if (current == null) return;
      final treeNode = _ref.read(fileTreeProvider).value;

      final Set<String> formattedPatterns = {};
      for (final p in paths) {
        bool isDir = false;
        if (treeNode != null) {
          TreeNode? find(TreeNode n) {
            if (n.relativePath == p) return n;
            for (final c in n.children) {
              final res = find(c);
              if (res != null) return res;
            }
            return null;
          }

          final match = find(treeNode);
          if (match != null && match.isDirectory) isDir = true;
        }

        if (isDir) {
          formattedPatterns.add('$p/**');
        } else {
          formattedPatterns.add(p);
        }
      }

      final set = current.ignorePatterns.toSet()..addAll(formattedPatterns);
      await updateCurrentConfig(ignorePatterns: set.toList());
    } catch (e) {
      debugPrint('Failed to add ignore patterns: $e');
    }
  }

  /// Toggles the local UI visual visibility status parameters of directory trees.
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

  /// Helper method persisting last selected project ID in window state file.
  Future<void> _saveLastSelectedProject(String projectId) async {
    try {
      final configService = _ref.read(configServiceProvider);
      final currentState = await configService.loadWindowState() ?? {};
      currentState['lastSelectedProjectId'] = projectId;
      await configService.saveWindowState(currentState);
    } catch (e) {
      debugPrint('Failed to save last selected project ID: $e');
    }
  }

  /// Helper method persisting chosen project sort option.
  Future<void> _saveSortOption(ProjectSortOption sortOption) async {
    try {
      final configService = _ref.read(configServiceProvider);
      final currentState = await configService.loadWindowState() ?? {};
      currentState['projectSortOption'] = sortOption.name;
      await configService.saveWindowState(currentState);
    } catch (e) {
      debugPrint('Failed to save project sort option: $e');
    }
  }

  /// Completely resets active cache snapshots matching selected identifier parameters.
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
