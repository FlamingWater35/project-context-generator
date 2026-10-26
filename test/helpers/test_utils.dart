import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:project_context_generator/models/agent_skill.dart';
import 'package:project_context_generator/models/project_config.dart';
import 'package:project_context_generator/models/tree_node.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/services/config_service.dart';
import 'package:project_context_generator/services/fs_service.dart';

/// Creates a temporary directory that is removed automatically at test teardown.
Directory createTempDir([String prefix = 'pcg_test_']) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup; never fail a test because of a locked temp file.
    }
  });
  return dir;
}

/// Writes [content] to [relativePath] under [root], creating parents as needed.
File writeFile(Directory root, String relativePath, String content) {
  final file = File(p.joinAll([root.path, ...relativePath.split('/')]));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return file;
}

/// Writes binary [bytes] to [relativePath] under [root].
File writeBytes(Directory root, String relativePath, List<int> bytes) {
  final file = File(p.joinAll([root.path, ...relativePath.split('/')]));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  return file;
}

/// Creates a [ConfigService] persisting into an isolated temporary directory.
ConfigService createTestConfigService(Directory supportDir) {
  return ConfigService(supportDirectoryProvider: () async => supportDir);
}

/// Builds a [ProjectConfig] with sensible defaults for tests.
ProjectConfig makeConfig({
  String id = 'config-1',
  String name = 'Test Project',
  String rootPath = '',
  List<String> includedFiles = const [],
  List<String> ignorePatterns = const [
    '.git/**',
    'node_modules/**',
    'build/**',
  ],
  List<String> selectedSkillIds = const [],
  List<AgentSkill> customSkills = const [],
  DateTime? createdAt,
}) {
  return ProjectConfig(
    id: id,
    name: name,
    rootPath: rootPath,
    includedFiles: includedFiles,
    ignorePatterns: ignorePatterns,
    selectedSkillIds: selectedSkillIds,
    customSkills: customSkills,
    createdAt: createdAt,
  );
}

/// Builds a directory [TreeNode] for provider/widget tests.
TreeNode testDir(
  String relativePath, {
  List<TreeNode> children = const [],
  bool isNew = false,
  String root = r'C:\root',
}) {
  final segments = relativePath.split('/');
  return TreeNode(
    path: p.joinAll([root, ...segments]),
    relativePath: relativePath,
    name: segments.last,
    isDirectory: true,
    children: children,
    isNew: isNew,
  );
}

/// Builds a file [TreeNode] for provider/widget tests.
TreeNode testFile(
  String relativePath, {
  bool isNew = false,
  String root = r'C:\root',
}) {
  final segments = relativePath.split('/');
  return TreeNode(
    path: p.joinAll([root, ...segments]),
    relativePath: relativePath,
    name: segments.last,
    isDirectory: false,
    isNew: isNew,
  );
}

/// A [PromptBuildResult] with no files, useful as a default fake response.
const PromptBuildResult emptyPromptResult = PromptBuildResult(
  promptText: '',
  displayText: '',
  fileCount: 0,
  skillCount: 0,
  totalLines: 1,
  sections: [],
  isTruncated: false,
);

/// A [PromptBuildResult] with representative metrics.
PromptBuildResult samplePromptResult({
  String promptText = '--- PROJECT CONTEXT: Test ---\nline\n',
  int fileCount = 1,
  int skillCount = 0,
  int totalLines = 2,
}) {
  return PromptBuildResult(
    promptText: promptText,
    displayText: promptText,
    fileCount: fileCount,
    skillCount: skillCount,
    totalLines: totalLines,
    sections: const [],
    isTruncated: false,
  );
}

/// Configurable in-memory [FsService] used to isolate UI/provider tests.
class FakeFsService extends FsService {
  FakeFsService({
    this.tree,
    Set<String>? paths,
    List<AgentSkill>? skills,
    PromptBuildResult? promptResult,
  }) : paths = paths ?? <String>{},
       skills = skills ?? const <AgentSkill>[],
       promptResult = promptResult ?? emptyPromptResult;

  TreeNode? tree;
  Set<String> paths;
  List<AgentSkill> skills;
  PromptBuildResult promptResult;

  /// Optional deferred responses for loading-state tests.
  Completer<TreeNode?>? treeCompleter;
  Completer<PromptBuildResult>? promptCompleter;
  Completer<List<AgentSkill>>? detectSkillsCompleter;

  /// Optional errors thrown by service methods.
  Object? scanPathsError;
  Object? buildTreeError;
  Object? promptError;

  /// Recorded invocations.
  int scanPathsCalls = 0;
  int buildTreeCalls = 0;
  int detectSkillsCalls = 0;
  final List<PromptBuildParams> promptParams = [];
  final List<Set<String>?> knownPathsSeen = [];
  final List<String> scannedRoots = [];

  @override
  Future<Set<String>> scanPaths(
    String rootPath,
    List<String> ignorePatterns,
  ) async {
    scanPathsCalls++;
    scannedRoots.add(rootPath);
    if (scanPathsError != null) throw scanPathsError!;
    return paths;
  }

  @override
  Future<TreeNode?> buildTree(
    String rootPath,
    List<String> ignorePatterns, {
    Set<String>? knownPaths,
  }) async {
    buildTreeCalls++;
    knownPathsSeen.add(knownPaths);
    if (buildTreeError != null) throw buildTreeError!;
    if (treeCompleter != null) return treeCompleter!.future;
    return tree;
  }

  @override
  Future<PromptBuildResult> buildPromptContext(PromptBuildParams params) async {
    promptParams.add(params);
    if (promptError != null) throw promptError!;
    if (promptCompleter != null) return promptCompleter!.future;
    return promptResult;
  }

  @override
  Future<List<AgentSkill>> detectSkills(String rootPath) async {
    detectSkillsCalls++;
    if (detectSkillsCompleter != null) return detectSkillsCompleter!.future;
    return skills;
  }
}

/// In-memory [ConfigService] for widget tests.
///
/// Real file I/O does not progress inside `testWidgets`' fake-async zone
/// without `tester.runAsync`, so widget tests use this synchronous stand-in.
class MemoryConfigService extends ConfigService {
  MemoryConfigService({
    List<ProjectConfig> configs = const [],
    Map<String, dynamic>? windowState,
    Map<String, Set<String>>? snapshots,
  }) : _configs = {for (final config in configs) config.id: config},
       _windowState = windowState == null ? null : Map.of(windowState),
       _snapshots = {
         for (final entry in (snapshots ?? const {}).entries)
           entry.key: Set.of(entry.value),
       };

  final Map<String, ProjectConfig> _configs;
  final Map<String, Set<String>> _snapshots;
  Map<String, dynamic>? _windowState;

  int saveConfigCalls = 0;
  int deleteConfigCalls = 0;

  @override
  Future<List<ProjectConfig>> loadConfigs() async =>
      _configs.values.toList(growable: false);

  @override
  Future<void> saveConfig(ProjectConfig config, {String? oldName}) async {
    saveConfigCalls++;
    _configs[config.id] = config;
  }

  @override
  Future<void> deleteConfig(ProjectConfig config) async {
    deleteConfigCalls++;
    _configs.remove(config.id);
    _snapshots.remove(config.id);
  }

  @override
  Future<Set<String>?> loadSnapshot(String configId) async {
    final snapshot = _snapshots[configId];
    return snapshot == null ? null : Set.of(snapshot);
  }

  @override
  Future<void> saveSnapshot(String configId, Set<String> paths) async {
    _snapshots[configId] = Set.of(paths);
  }

  @override
  Future<void> deleteSnapshot(String configId) async {
    _snapshots.remove(configId);
  }

  @override
  Future<Map<String, dynamic>?> loadWindowState() async =>
      _windowState == null ? null : Map.of(_windowState!);

  @override
  Future<void> saveWindowState(Map<String, dynamic> state) async {
    _windowState = Map.of(state);
  }

  /// Exposes the saved snapshot for assertions.
  Set<String>? snapshot(String configId) => _snapshots[configId];

  /// Exposes the saved window state for assertions.
  Map<String, dynamic>? get windowState =>
      _windowState == null ? null : Map.of(_windowState!);
}

/// Pumps a widget tree backed by an in-memory config service and waits for
/// the initial configuration load to complete.
Future<void> pumpWithConfigs(
  WidgetTester tester,
  Widget child, {
  List<ProjectConfig> configs = const [],
  Map<String, dynamic>? windowState,
  List<Override> overrides = const [],
  Size surfaceSize = const Size(1200, 800),
}) async {
  final service = MemoryConfigService(
    configs: configs,
    windowState: windowState,
  );
  await pumpApp(
    tester,
    child,
    overrides: [configServiceProvider.overrideWithValue(service), ...overrides],
    surfaceSize: surfaceSize,
  );
  await pumpUntil(
    tester,
    () => containerOf(tester).read(configsProvider).length == configs.length,
    description: 'initial configs to load',
  );
}

/// Waits until [condition] becomes true, yielding to the event loop in between.
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String description = 'condition',
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException('Timed out waiting for $description', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Like [waitFor], but supports asynchronous conditions (e.g. disk reads).
Future<void> waitForAsync(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String description = 'condition',
}) async {
  final stopwatch = Stopwatch()..start();
  while (!await condition()) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException('Timed out waiting for $description', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Creates a [ProviderContainer] wired to an isolated config service and
/// optional fake filesystem service.
Future<ProviderContainer> createContainer({
  Directory? supportDir,
  ConfigService? configService,
  FsService? fsService,
  List<ProjectConfig> configs = const [],
  Map<String, dynamic>? windowState,
  List<Override> overrides = const [],
  bool waitForLoad = true,
}) async {
  final dir = supportDir ?? createTempDir();
  final service = configService ?? createTestConfigService(dir);
  for (final config in configs) {
    await service.saveConfig(config);
  }
  if (windowState != null) {
    await service.saveWindowState(windowState);
  }

  final container = ProviderContainer(
    overrides: [
      configServiceProvider.overrideWithValue(service),
      if (fsService != null) fsServiceProvider.overrideWithValue(fsService),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  if (waitForLoad && configs.isNotEmpty) {
    await waitFor(
      () => container.read(configsProvider).length == configs.length,
      description: 'initial configs to load',
    );
    // Give the notifier a chance to apply persisted window state.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return container;
}

/// Pumps a widget inside a ProviderScope and dark MaterialApp.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size surfaceSize = const Size(1200, 800),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: child,
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
  await tester.pump();
}

/// Pumps frames until [condition] is true or [maxPumps] is exhausted.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 200,
  Duration step = const Duration(milliseconds: 20),
  String description = 'condition',
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) return;
    await tester.pump(step);
  }
  if (condition()) return;
  throw TestFailure('Timed out waiting for $description after $maxPumps pumps');
}

/// Flushes any debounced config persists scheduled by the active app.
Future<void> flushConfigs(WidgetTester tester) async {
  final host = find.byType(MaterialApp);
  if (host.evaluate().isEmpty) return;
  final container = ProviderScope.containerOf(tester.element(host.first));
  await container.read(configsProvider.notifier).flush();
  await tester.pump();
}

/// Reads the app's root provider container from a pumped widget tree.
ProviderContainer containerOf(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

/// Fake system clipboard which records writes and serves a configurable value.
class FakeClipboard {
  FakeClipboard([this.text]);

  String? text;
  int getDataCalls = 0;
  int setDataCalls = 0;

  void install(WidgetTester tester) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.getData':
          getDataCalls++;
          return text == null ? null : <String, dynamic>{'text': text};
        case 'Clipboard.setData':
          setDataCalls++;
          final arguments = call.arguments as Map<dynamic, dynamic>;
          text = arguments['text'] as String?;
          return null;
        case 'Clipboard.hasStrings':
          return <String, dynamic>{'value': text != null && text!.isNotEmpty};
        case 'SystemSound.play':
        case 'HapticFeedback.vibrate':
          return null;
        default:
          return null;
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }
}
