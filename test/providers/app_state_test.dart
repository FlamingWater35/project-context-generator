import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_context_generator/models/agent_skill.dart';
import 'package:project_context_generator/models/project_config.dart';
import 'package:project_context_generator/models/tree_node.dart';
import 'package:project_context_generator/providers/app_state.dart';
import 'package:project_context_generator/services/config_service.dart';

import '../helpers/test_utils.dart';

void main() {
  group('selectedConfigProvider', () {
    test('is null when no configs exist', () async {
      final container = await createContainer(waitForLoad: false);
      await waitFor(
        () => container.read(configsProvider).isEmpty,
        description: 'empty config load',
      );

      expect(container.read(selectedConfigProvider), isNull);
    });

    test('selects the first loaded config by default', () async {
      final a = makeConfig(id: 'a', name: 'Alpha');
      final b = makeConfig(id: 'b', name: 'Beta');
      final container = await createContainer(configs: [a, b]);

      final selected = container.read(selectedConfigProvider);
      expect(selected, isNotNull);
      expect(selected!.id, isNotEmpty);
      expect(container.read(selectedConfigIdProvider), selected.id);
    });

    test('follows the explicitly selected id', () async {
      final a = makeConfig(id: 'a', name: 'Alpha');
      final b = makeConfig(id: 'b', name: 'Beta');
      final container = await createContainer(configs: [a, b]);

      container.read(selectedConfigIdProvider.notifier).state = 'b';

      expect(container.read(selectedConfigProvider)!.id, 'b');
    });

    test('falls back to the first config for an unknown id', () async {
      final a = makeConfig(id: 'a', name: 'Alpha');
      final b = makeConfig(id: 'b', name: 'Beta');
      final container = await createContainer(configs: [a, b]);

      container.read(selectedConfigIdProvider.notifier).state =
          'does-not-exist';

      final fallback = container.read(selectedConfigProvider);
      expect(fallback, isNotNull);
      await waitFor(
        () => container.read(selectedConfigIdProvider) == fallback!.id,
        description: 'selection microtask',
      );
      expect(container.read(selectedConfigIdProvider), fallback!.id);
    });
  });

  group('persisted window state', () {
    test('restores the last selected project and sort option', () async {
      final a = makeConfig(id: 'a', name: 'Alpha');
      final b = makeConfig(id: 'b', name: 'Beta');
      final container = await createContainer(
        configs: [a, b],
        windowState: {
          'lastSelectedProjectId': 'b',
          'projectSortOption': 'dateNewest',
        },
      );

      expect(container.read(selectedConfigIdProvider), 'b');
      expect(
        container.read(projectSortOptionProvider),
        ProjectSortOption.dateNewest,
      );
    });

    test('falls back to the first config for an unknown stored id', () async {
      final a = makeConfig(id: 'a', name: 'Alpha');
      final container = await createContainer(
        configs: [a],
        windowState: {'lastSelectedProjectId': 'missing'},
      );

      expect(container.read(selectedConfigIdProvider), 'a');
    });

    test('falls back to nameAsc for an unknown sort option', () async {
      final a = makeConfig(id: 'a', name: 'Alpha');
      final container = await createContainer(
        configs: [a],
        windowState: {'projectSortOption': 'unknown'},
      );

      expect(
        container.read(projectSortOptionProvider),
        ProjectSortOption.nameAsc,
      );
    });
  });

  group('ConfigsNotifier', () {
    test('addConfig adds and selects the new project', () async {
      final container = await createContainer();
      final notifier = container.read(configsProvider.notifier);

      await notifier.addConfig('  Gamma  ');

      expect(container.read(configsProvider), hasLength(1));
      final added = container.read(configsProvider).single;
      expect(added.name, '  Gamma  ');
      expect(container.read(selectedConfigIdProvider), added.id);
    });

    test('addConfig writes the config through the injected service', () async {
      final support = createTempDir('pcg_notifier_');
      final service = createTestConfigService(support);
      final container = await createContainer(
        supportDir: support,
        configService: service,
      );

      await container.read(configsProvider.notifier).addConfig('Persisted');

      final loaded = await service.loadConfigs();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'Persisted');
    });

    test(
      'updateConfig updates state immediately and flushes to disk',
      () async {
        final config = makeConfig(id: 'a', name: 'Alpha');
        final container = await createContainer(configs: [config]);
        final notifier = container.read(configsProvider.notifier);

        notifier.updateConfig(
          config.copyWith(name: 'Renamed'),
          oldName: 'Alpha',
        );

        expect(container.read(configsProvider).single.name, 'Renamed');

        await notifier.flush();

        final loaded = await container
            .read(configServiceProvider)
            .loadConfigs();
        expect(loaded.single.name, 'Renamed');
      },
    );

    test('updateConfig ignores unknown ids', () async {
      final config = makeConfig(id: 'a', name: 'Alpha');
      final container = await createContainer(configs: [config]);

      container
          .read(configsProvider.notifier)
          .updateConfig(makeConfig(id: 'ghost', name: 'Ghost'));

      expect(container.read(configsProvider).single.id, 'a');
    });

    test('deleteConfig removes the project and selects a fallback', () async {
      final a = makeConfig(id: 'a', name: 'Alpha');
      final b = makeConfig(id: 'b', name: 'Beta');
      final container = await createContainer(configs: [a, b]);
      container.read(selectedConfigIdProvider.notifier).state = 'a';

      await container.read(configsProvider.notifier).deleteConfig(a);

      expect(container.read(configsProvider).map((c) => c.id), ['b']);
      expect(container.read(selectedConfigIdProvider), 'b');
      expect(
        await container.read(configServiceProvider).loadConfigs(),
        hasLength(1),
      );
    });

    test(
      'deleteConfig keeps the selection when deleting another project',
      () async {
        final a = makeConfig(id: 'a', name: 'Alpha');
        final b = makeConfig(id: 'b', name: 'Beta');
        final container = await createContainer(configs: [a, b]);
        container.read(selectedConfigIdProvider.notifier).state = 'a';

        await container.read(configsProvider.notifier).deleteConfig(b);

        expect(container.read(selectedConfigIdProvider), 'a');
      },
    );

    test('deleting the last project clears the selection', () async {
      final a = makeConfig(id: 'a', name: 'Alpha');
      final container = await createContainer(configs: [a]);
      container.read(selectedConfigIdProvider.notifier).state = 'a';

      await container.read(configsProvider.notifier).deleteConfig(a);

      expect(container.read(configsProvider), isEmpty);
      expect(container.read(selectedConfigIdProvider), isNull);
    });

    test('deleteConfig also clears in-memory snapshots', () async {
      final a = makeConfig(id: 'a', name: 'Alpha');
      final container = await createContainer(configs: [a]);
      container.read(projectSnapshotsProvider.notifier).state = {
        'a': {'lib/main.dart'},
      };

      await container.read(configsProvider.notifier).deleteConfig(a);

      expect(container.read(projectSnapshotsProvider), isEmpty);
    });
  });

  group('derived file selection providers', () {
    final config = makeConfig(
      id: 'a',
      name: 'Alpha',
      includedFiles: const ['a/b/c.dart', 'a/d.dart', 'x/e/f.txt'],
    );

    ProviderContainer containerFor(ProjectConfig value) {
      final container = ProviderContainer(
        overrides: [selectedConfigProvider.overrideWith((ref) => value)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('selectedIncludedFilesSetProvider exposes a set', () {
      final container = containerFor(config);

      expect(container.read(selectedIncludedFilesSetProvider), {
        'a/b/c.dart',
        'a/d.dart',
        'x/e/f.txt',
      });
    });

    test('activeParentDirectoriesProvider computes every parent', () {
      final container = containerFor(config);

      expect(container.read(activeParentDirectoriesProvider), {
        'a',
        'a/b',
        'x',
        'x/e',
      });
    });

    test('both providers are empty when nothing is selected', () {
      final container = containerFor(makeConfig());

      expect(container.read(selectedIncludedFilesSetProvider), isEmpty);
      expect(container.read(activeParentDirectoriesProvider), isEmpty);
    });
  });

  group('allProjectSkillsProvider', () {
    test(
      'merges detected and custom skills, preferring custom duplicates',
      () async {
        const detected = AgentSkill(
          id: 'detected',
          name: 'Detected',
          description: 'From disk',
          content: 'detected content',
        );
        const duplicate = AgentSkill(
          id: 'shared',
          name: 'Detected Shared',
          description: 'detected',
          content: 'detected',
        );
        const custom = AgentSkill(
          id: 'shared',
          name: 'Custom Shared',
          description: 'custom',
          content: 'custom',
          isCustom: true,
        );
        final config = makeConfig(customSkills: const [custom]);
        final container = ProviderContainer(
          overrides: [
            selectedConfigProvider.overrideWith((ref) => config),
            detectedSkillsProvider.overrideWith(
              (ref) async => const [detected, duplicate],
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(detectedSkillsProvider.future);

        final skills = container.read(allProjectSkillsProvider);
        final byId = {for (final skill in skills) skill.id: skill};

        expect(byId.keys, containsAll(['detected', 'shared']));
        expect(byId['shared']!.name, 'Custom Shared');
        expect(byId['shared']!.isCustom, isTrue);
      },
    );

    test('returns only custom skills while detection is in flight', () async {
      const custom = AgentSkill(
        id: 'custom',
        name: 'Custom',
        description: '',
        content: '',
        isCustom: true,
      );
      final container = ProviderContainer(
        overrides: [
          selectedConfigProvider.overrideWith(
            (ref) => makeConfig(customSkills: const [custom]),
          ),
          detectedSkillsProvider.overrideWith(
            (ref) => Completer<List<AgentSkill>>().future,
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(allProjectSkillsProvider).single.id, 'custom');
    });

    test('is empty when no config is selected', () async {
      final container = await createContainer();

      expect(container.read(allProjectSkillsProvider), isEmpty);
    });
  });

  group('treeConfigProvider', () {
    test('is null when no root is configured', () {
      final container = ProviderContainer(
        overrides: [selectedConfigProvider.overrideWith((ref) => makeConfig())],
      );
      addTearDown(container.dispose);

      expect(container.read(treeConfigProvider), isNull);
    });

    test('is populated when a root and ignore patterns exist', () {
      final container = ProviderContainer(
        overrides: [
          selectedConfigProvider.overrideWith(
            (ref) => makeConfig(rootPath: '/repo', ignorePatterns: ['a/**']),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(treeConfigProvider), isNotNull);
    });
  });

  group('fileTreeProvider', () {
    late Directory support;
    late ConfigService configService;
    late FakeFsService fs;
    late TreeNode tree;

    setUp(() async {
      support = createTempDir('pcg_tree_');
      configService = createTestConfigService(support);
      tree = TreeNode(
        path: '/repo',
        relativePath: '',
        name: 'repo',
        isDirectory: true,
        children: [testFile('README.md')],
      );
      fs = FakeFsService(tree: tree);
    });

    ProviderContainer treeContainer() {
      final container = ProviderContainer(
        overrides: [
          configServiceProvider.overrideWithValue(configService),
          fsServiceProvider.overrideWithValue(fs),
          selectedConfigProvider.overrideWith(
            (ref) => makeConfig(
              id: 'cfg',
              rootPath: '/repo',
              ignorePatterns: const ['build/**'],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('builds the tree and persists a first snapshot', () async {
      final container = treeContainer();

      final result = await container.read(fileTreeProvider.future);

      expect(result, same(tree));
      expect(fs.buildTreeCalls, 1);
      expect(fs.knownPathsSeen.single, isNull);

      final snapshot = await configService.loadSnapshot('cfg');
      expect(snapshot, {'README.md'});
    });

    test('passes an existing snapshot to the filesystem service', () async {
      await configService.saveSnapshot('cfg', {'README.md'});
      final container = treeContainer();

      await container.read(fileTreeProvider.future);

      expect(fs.knownPathsSeen.single, {'README.md'});
      // An existing snapshot must not be overwritten by the scan.
      expect(await configService.loadSnapshot('cfg'), {'README.md'});
    });

    test('returns null when no root is configured', () async {
      final container = ProviderContainer(
        overrides: [
          configServiceProvider.overrideWithValue(configService),
          fsServiceProvider.overrideWithValue(fs),
          selectedConfigProvider.overrideWith((ref) => makeConfig()),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(fileTreeProvider.future), isNull);
      expect(fs.buildTreeCalls, 0);
    });

    test('swallows filesystem failures and returns null', () async {
      fs.buildTreeError = const FileSystemException('boom');
      final container = treeContainer();

      expect(await container.read(fileTreeProvider.future), isNull);
    });
  });

  group('promptStatsProvider', () {
    test('returns null without a configured root', () async {
      final container = ProviderContainer(
        overrides: [selectedConfigProvider.overrideWith((ref) => makeConfig())],
      );
      addTearDown(container.dispose);

      expect(await container.read(promptStatsProvider.future), isNull);
    });

    test('passes selected skills and files to the service', () async {
      final fs = FakeFsService(promptResult: samplePromptResult());
      final config = makeConfig(
        id: 'cfg',
        name: 'Stats',
        rootPath: '/repo',
        includedFiles: const ['lib/main.dart'],
        selectedSkillIds: const ['skill-a'],
        ignorePatterns: const ['build/**'],
      );
      const skill = AgentSkill(
        id: 'skill-a',
        name: 'Skill A',
        description: '',
        content: 'content',
      );
      const other = AgentSkill(
        id: 'skill-b',
        name: 'Skill B',
        description: '',
        content: 'content',
      );
      final container = ProviderContainer(
        overrides: [
          selectedConfigProvider.overrideWith((ref) => config),
          detectedSkillsProvider.overrideWith(
            (ref) async => const [skill, other],
          ),
          fsServiceProvider.overrideWithValue(fs),
        ],
      );
      addTearDown(container.dispose);
      await container.read(detectedSkillsProvider.future);

      final result = await container.read(promptStatsProvider.future);

      expect(result!.fileCount, 1);
      expect(fs.promptParams, hasLength(1));
      final params = fs.promptParams.single;
      expect(params.projectName, 'Stats');
      expect(params.rootPath, '/repo');
      expect(params.includedFiles, ['lib/main.dart']);
      expect(params.ignorePatterns, ['build/**']);
      expect(params.selectedSkills.map((s) => s.id), ['skill-a']);
    });

    test('propagates prompt construction errors', () async {
      final fs = FakeFsService(promptResult: samplePromptResult())
        ..promptError = StateError('prompt failed');
      final container = ProviderContainer(
        overrides: [
          selectedConfigProvider.overrideWith(
            (ref) => makeConfig(rootPath: '/repo', includedFiles: const ['a']),
          ),
          detectedSkillsProvider.overrideWith((ref) async => const []),
          fsServiceProvider.overrideWithValue(fs),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(promptStatsProvider.future),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AppStateController', () {
    late Directory support;
    late ConfigService configService;
    late FakeFsService fs;
    late ProviderContainer container;
    late ProjectConfig config;
    late TreeNode tree;

    TreeNode buildTree() {
      return testDir(
        'repo',
        children: [
          testDir(
            'lib',
            children: [
              testFile('lib/main.dart'),
              testDir('lib/sub', children: [testFile('lib/sub/util.dart')]),
            ],
          ),
          testFile('README.md'),
        ],
      );
    }

    Future<void> setUpWith({List<String> included = const []}) async {
      support = createTempDir('pcg_state_');
      configService = createTestConfigService(support);
      tree = buildTree();
      fs = FakeFsService(tree: tree, paths: {'README.md', 'lib/main.dart'});
      config = makeConfig(
        id: 'cfg',
        name: 'Project',
        rootPath: '/repo',
        includedFiles: included,
        selectedSkillIds: const ['skill-a'],
      );
      container = await createContainer(
        supportDir: support,
        configService: configService,
        fsService: fs,
        configs: [config],
        overrides: [fileTreeProvider.overrideWith((ref) async => tree)],
      );
      container.read(selectedConfigIdProvider.notifier).state = 'cfg';
      await container.read(fileTreeProvider.future);
    }

    Future<ProjectConfig> current() async {
      final value = container.read(selectedConfigProvider)!;
      return value;
    }

    Future<void> flush() => container.read(configsProvider.notifier).flush();

    test('checkFiles expands a directory into its files', () async {
      await setUpWith(included: ['README.md']);

      await container.read(appStateControllerProvider).checkFiles(['lib']);
      await flush();

      final updated = await current();
      expect(
        updated.includedFiles,
        containsAll(['lib/main.dart', 'lib/sub/util.dart', 'README.md']),
      );
      expect(container.read(selectedNodePathsProvider), isEmpty);
    });

    test('checkFiles keeps unknown paths verbatim', () async {
      await setUpWith();

      await container.read(appStateControllerProvider).checkFiles([
        'ghost.txt',
      ]);
      await flush();

      expect((await current()).includedFiles, ['ghost.txt']);
    });

    test('uncheckFiles removes every descendant', () async {
      await setUpWith(
        included: ['lib/main.dart', 'lib/sub/util.dart', 'README.md'],
      );

      await container.read(appStateControllerProvider).uncheckFiles(['lib']);
      await flush();

      expect((await current()).includedFiles, ['README.md']);
    });

    test('toggleFile adds and removes a single path', () async {
      await setUpWith();
      final controller = container.read(appStateControllerProvider);

      await controller.toggleFile('lib/main.dart', true);
      await flush();
      expect((await current()).includedFiles, contains('lib/main.dart'));

      await controller.toggleFile('lib/main.dart', false);
      await flush();
      expect((await current()).includedFiles, isNot(contains('lib/main.dart')));
    });

    test('selectAll adds all files under a directory', () async {
      await setUpWith();
      final lib = tree.children.first;

      await container.read(appStateControllerProvider).selectAll(lib);
      await flush();

      expect(
        (await current()).includedFiles,
        containsAll(['lib/main.dart', 'lib/sub/util.dart']),
      );
    });

    test('selectNone removes all files under a directory', () async {
      await setUpWith(included: ['lib/main.dart', 'lib/sub/util.dart']);
      final lib = tree.children.first;

      await container.read(appStateControllerProvider).selectNone(lib);
      await flush();

      expect((await current()).includedFiles, isEmpty);
    });

    test('invertSelection flips descendant states', () async {
      await setUpWith(included: ['lib/main.dart']);
      final lib = tree.children.first;

      await container.read(appStateControllerProvider).invertSelection(lib);
      await flush();

      final files = (await current()).includedFiles;
      expect(files, isNot(contains('lib/main.dart')));
      expect(files, contains('lib/sub/util.dart'));
    });

    test('addIgnorePattern appends and de-duplicates', () async {
      await setUpWith();
      final controller = container.read(appStateControllerProvider);

      await controller.addIgnorePattern('dist/**');
      await flush();
      expect((await current()).ignorePatterns, contains('dist/**'));

      final countBefore = (await current()).ignorePatterns.length;
      await controller.addIgnorePattern('dist/**');
      await flush();
      expect((await current()).ignorePatterns, hasLength(countBefore));
    });

    test(
      'addIgnorePatterns formats directories and escapes glob syntax',
      () async {
        await setUpWith();
        final controller = container.read(appStateControllerProvider);

        await controller.addIgnorePatterns(['lib', 'lib/[special].dart']);
        await flush();

        final ignores = (await current()).ignorePatterns;
        expect(ignores, contains('lib/**'));
        expect(ignores, contains(r'lib/\[special\].dart'));
        expect(container.read(selectedNodePathsProvider), isEmpty);
      },
    );

    test('skill selection toggles and bulk operations work', () async {
      await setUpWith();
      final controller = container.read(appStateControllerProvider);

      await controller.toggleSkillSelection('skill-b');
      await flush();
      expect((await current()).selectedSkillIds, contains('skill-b'));

      await controller.toggleSkillSelection('skill-a');
      await flush();
      expect((await current()).selectedSkillIds, isNot(contains('skill-a')));

      await controller.selectAllSkills(['a', 'b', 'c']);
      await flush();
      expect((await current()).selectedSkillIds, ['a', 'b', 'c']);

      await controller.deselectAllSkills();
      await flush();
      expect((await current()).selectedSkillIds, isEmpty);
    });

    test('custom skills can be added and deleted', () async {
      await setUpWith();
      final controller = container.read(appStateControllerProvider);
      const skill = AgentSkill(
        id: 'custom-1',
        name: 'Custom',
        description: 'desc',
        content: 'content',
        isCustom: true,
      );

      await controller.addCustomSkill(skill);
      await flush();
      var updated = await current();
      expect(updated.customSkills.single.id, 'custom-1');
      expect(updated.selectedSkillIds, contains('custom-1'));

      await controller.deleteCustomSkill('custom-1');
      await flush();
      updated = await current();
      expect(updated.customSkills, isEmpty);
      expect(updated.selectedSkillIds, isNot(contains('custom-1')));
    });

    test('toggleNodeExpanded flips the expansion map entry', () async {
      await setUpWith();
      final controller = container.read(appStateControllerProvider);

      controller.toggleNodeExpanded('lib');
      expect(container.read(expansionStateProvider)['lib'], isTrue);

      controller.toggleNodeExpanded('lib');
      expect(container.read(expansionStateProvider)['lib'], isFalse);
    });

    test(
      'selectConfig clears transient UI state and persists selection',
      () async {
        await setUpWith();
        container.read(expansionStateProvider.notifier).state = {'lib': true};
        container.read(selectedNodePathsProvider.notifier).state = {'lib'};

        container.read(appStateControllerProvider).selectConfig('cfg');

        expect(container.read(expansionStateProvider), isEmpty);
        expect(container.read(selectedNodePathsProvider), isEmpty);
        await waitForAsync(
          () async =>
              (await configService
                  .loadWindowState())?['lastSelectedProjectId'] ==
              'cfg',
          description: 'selection persistence',
        );
      },
    );

    test('setSortOption updates state and persists the option', () async {
      await setUpWith();

      container
          .read(appStateControllerProvider)
          .setSortOption(ProjectSortOption.dateOldest);

      expect(
        container.read(projectSortOptionProvider),
        ProjectSortOption.dateOldest,
      );
      await waitForAsync(
        () async =>
            (await configService.loadWindowState())?['projectSortOption'] ==
            'dateOldest',
        description: 'sort persistence',
      );
    });

    test(
      'updateCurrentConfig clears snapshots when the root changes',
      () async {
        await setUpWith();
        await configService.saveSnapshot('cfg', {'old'});
        container.read(projectSnapshotsProvider.notifier).state = {
          'cfg': {'old'},
        };

        await container
            .read(appStateControllerProvider)
            .updateCurrentConfig(rootPath: '/new-root');
        await flush();

        expect((await current()).rootPath, '/new-root');
        expect(await configService.loadSnapshot('cfg'), isNull);
        expect(container.read(projectSnapshotsProvider), isEmpty);
      },
    );

    test('updateCurrentConfig clears snapshots when ignores change', () async {
      await setUpWith();
      await configService.saveSnapshot('cfg', {'old'});
      container.read(projectSnapshotsProvider.notifier).state = {
        'cfg': {'old'},
      };

      await container
          .read(appStateControllerProvider)
          .updateCurrentConfig(ignorePatterns: const ['new/**']);
      await flush();

      expect(await configService.loadSnapshot('cfg'), isNull);
    });

    test(
      'rename persists the new name and removes the old legacy file',
      () async {
        await setUpWith();
        final legacy = File('${support.path}/configs/Project.json');
        legacy.writeAsStringSync('{}');

        await container
            .read(appStateControllerProvider)
            .updateCurrentConfig(name: 'Renamed');
        await flush();

        expect((await current()).name, 'Renamed');
        expect(legacy.existsSync(), isFalse);
        final loaded = await configService.loadConfigs();
        expect(loaded.single.name, 'Renamed');
      },
    );

    test(
      'acknowledgeChanges prunes missing files and saves a snapshot',
      () async {
        await setUpWith(included: ['README.md', 'missing.dart']);

        await container.read(appStateControllerProvider).acknowledgeChanges();
        await flush();

        expect((await current()).includedFiles, ['README.md']);
        expect(await configService.loadSnapshot('cfg'), {
          'README.md',
          'lib/main.dart',
        });
        expect(container.read(projectSnapshotsProvider)['cfg'], {
          'README.md',
          'lib/main.dart',
        });
      },
    );

    test('acknowledgeChanges is a no-op without a root', () async {
      await setUpWith();
      await container
          .read(appStateControllerProvider)
          .updateCurrentConfig(rootPath: '');
      await flush();
      final callsBefore = fs.scanPathsCalls;

      await container.read(appStateControllerProvider).acknowledgeChanges();

      expect(fs.scanPathsCalls, callsBefore);
    });

    test(
      'all mutating operations are safe without a selected config',
      () async {
        final empty = await createContainer();
        await waitFor(
          () => empty.read(configsProvider).isEmpty,
          description: 'empty load',
        );
        final controller = empty.read(appStateControllerProvider);

        await controller.checkFiles(['a']);
        await controller.uncheckFiles(['a']);
        await controller.toggleFile('a', true);
        await controller.toggleSkillSelection('a');
        await controller.selectAllSkills(['a']);
        await controller.deselectAllSkills();
        await controller.addIgnorePattern('a');
        await controller.addIgnorePatterns(['a']);
        await controller.updateCurrentConfig(name: 'x');
        await controller.addCustomSkill(
          const AgentSkill(id: 'a', name: 'a', description: '', content: ''),
        );
        await controller.deleteCustomSkill('a');
        await controller.acknowledgeChanges();

        expect(empty.read(configsProvider), isEmpty);
      },
    );
  });
}
