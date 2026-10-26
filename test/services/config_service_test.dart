import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:project_context_generator/services/config_service.dart';

import '../helpers/test_utils.dart';

void main() {
  late Directory supportDir;
  late ConfigService service;

  Directory configsDir() => Directory(p.join(supportDir.path, 'configs'));

  setUp(() {
    supportDir = createTempDir('pcg_config_');
    service = createTestConfigService(supportDir);
  });

  group('initialization', () {
    test('creates the configs directory on first use', () async {
      expect(configsDir().existsSync(), isFalse);

      await service.loadConfigs();

      expect(configsDir().existsSync(), isTrue);
    });

    test('loadConfigs returns an empty list when no configs exist', () async {
      expect(await service.loadConfigs(), isEmpty);
    });
  });

  group('saveConfig / loadConfigs', () {
    test('round-trips a configuration', () async {
      final config = makeConfig(
        id: 'abc-123',
        name: 'Alpha',
        rootPath: r'C:\repo',
        includedFiles: const ['lib/main.dart'],
        ignorePatterns: const ['build/**'],
        selectedSkillIds: const ['skill-1'],
      );

      await service.saveConfig(config);

      expect(
        File(p.join(configsDir().path, 'abc-123.json')).existsSync(),
        isTrue,
      );

      final loaded = await service.loadConfigs();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'abc-123');
      expect(loaded.single.name, 'Alpha');
      expect(loaded.single.rootPath, r'C:\repo');
      expect(loaded.single.includedFiles, ['lib/main.dart']);
      expect(loaded.single.ignorePatterns, ['build/**']);
      expect(loaded.single.selectedSkillIds, ['skill-1']);
    });

    test('persists multiple configurations', () async {
      await service.saveConfig(makeConfig(id: 'one', name: 'One'));
      await service.saveConfig(makeConfig(id: 'two', name: 'Two'));

      final loaded = await service.loadConfigs();

      expect(loaded.map((c) => c.id), containsAll(['one', 'two']));
    });

    test('overwrites the file when saving the same id again', () async {
      await service.saveConfig(makeConfig(id: 'one', name: 'First'));
      await service.saveConfig(makeConfig(id: 'one', name: 'Second'));

      final loaded = await service.loadConfigs();

      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'Second');
    });

    test('renames legacy files to match the configuration id', () async {
      final config = makeConfig(id: 'real-id', name: 'Legacy');
      final legacy = File(p.join(configsDir().path, 'legacy-name.json'));
      configsDir().createSync(recursive: true);
      legacy.writeAsStringSync(jsonEncode(config.toJson()));

      final loaded = await service.loadConfigs();

      expect(loaded.single.id, 'real-id');
      expect(legacy.existsSync(), isFalse);
      expect(
        File(p.join(configsDir().path, 'real-id.json')).existsSync(),
        isTrue,
      );
    });

    test('skips files with malformed JSON', () async {
      configsDir().createSync(recursive: true);
      File(p.join(configsDir().path, 'broken.json')).writeAsStringSync('{oops');
      await service.saveConfig(makeConfig(id: 'good', name: 'Good'));

      final loaded = await service.loadConfigs();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'good');
    });

    test(
      'uses the defensive fallback for structurally invalid records',
      () async {
        configsDir().createSync(recursive: true);
        File(
          p.join(configsDir().path, 'bad-shape.json'),
        ).writeAsStringSync(jsonEncode({'name': 'Name only'}));

        final loaded = await service.loadConfigs();

        expect(loaded, hasLength(1));
        expect(loaded.single.id, 'corrupted_fallback');
        expect(loaded.single.name, 'Name only');
      },
    );

    test('ignores snapshot and window-state files', () async {
      await service.saveConfig(makeConfig(id: 'one', name: 'One'));
      await service.saveSnapshot('one', {'lib/main.dart'});
      await service.saveWindowState({'width': 1000.0});

      final loaded = await service.loadConfigs();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'one');
    });
  });

  group('saveConfig with legacy cleanup', () {
    test('removes the legacy file matching the old name', () async {
      final oldLegacy = File(p.join(configsDir().path, 'Old_Name_.json'));
      configsDir().createSync(recursive: true);
      oldLegacy.writeAsStringSync('{}');

      await service.saveConfig(
        makeConfig(id: 'one', name: 'New Name'),
        oldName: 'Old:Name?',
      );

      expect(oldLegacy.existsSync(), isFalse);
      expect(
        File(p.join(configsDir().path, 'New_Name_.json')).existsSync(),
        isFalse,
      );
      expect(File(p.join(configsDir().path, 'one.json')).existsSync(), isTrue);
    });

    test('removes a legacy file matching the new sanitized name', () async {
      final legacy = File(p.join(configsDir().path, 'My_Project_.json'));
      configsDir().createSync(recursive: true);
      legacy.writeAsStringSync('{}');

      await service.saveConfig(makeConfig(id: 'one', name: 'My:Project?'));

      expect(legacy.existsSync(), isFalse);
      expect(File(p.join(configsDir().path, 'one.json')).existsSync(), isTrue);
    });
  });

  group('deleteConfig', () {
    test('removes the config, legacy name file, and snapshot', () async {
      final config = makeConfig(id: 'one', name: 'One');
      await service.saveConfig(config);
      await service.saveSnapshot('one', {'a'});
      final legacy = File(p.join(configsDir().path, 'One.json'));
      legacy.writeAsStringSync('{}');

      await service.deleteConfig(config);

      expect(File(p.join(configsDir().path, 'one.json')).existsSync(), isFalse);
      expect(legacy.existsSync(), isFalse);
      expect(
        File(p.join(configsDir().path, 'one.snap.json')).existsSync(),
        isFalse,
      );
      expect(await service.loadSnapshot('one'), isNull);
    });

    test('is a no-op for a missing configuration', () async {
      await service.deleteConfig(makeConfig(id: 'missing', name: 'Missing'));

      expect(await service.loadConfigs(), isEmpty);
    });
  });

  group('snapshots', () {
    test('round-trips a set of paths', () async {
      await service.saveSnapshot('one', {'lib/main.dart', 'README.md'});

      final loaded = await service.loadSnapshot('one');

      expect(loaded, {'lib/main.dart', 'README.md'});
    });

    test('returns null when no snapshot exists', () async {
      expect(await service.loadSnapshot('missing'), isNull);
    });

    test('returns null for corrupt snapshot JSON', () async {
      configsDir().createSync(recursive: true);
      File(
        p.join(configsDir().path, 'bad.snap.json'),
      ).writeAsStringSync('not json');

      expect(await service.loadSnapshot('bad'), isNull);
    });

    test('defaults a snapshot without paths to an empty set', () async {
      configsDir().createSync(recursive: true);
      File(
        p.join(configsDir().path, 'empty.snap.json'),
      ).writeAsStringSync(jsonEncode({'timestamp': 'now'}));

      expect(await service.loadSnapshot('empty'), isEmpty);
    });

    test('deleteSnapshot is safe when the file is absent', () async {
      await service.deleteSnapshot('missing');

      expect(
        File(p.join(configsDir().path, 'missing.snap.json')).existsSync(),
        isFalse,
      );
    });
  });

  group('window state', () {
    test('round-trips arbitrary state', () async {
      await service.saveWindowState({
        'width': 1280.0,
        'height': 720.0,
        'x': 10.0,
        'y': 20.0,
        'isMaximized': false,
        'sidebarWidth': 300.0,
        'lastSelectedProjectId': 'one',
        'projectSortOption': 'nameDesc',
      });

      final state = await service.loadWindowState();

      expect(state, isNotNull);
      expect(state!['width'], 1280.0);
      expect(state['sidebarWidth'], 300.0);
      expect(state['lastSelectedProjectId'], 'one');
      expect(state['projectSortOption'], 'nameDesc');
    });

    test('returns null when no state exists', () async {
      expect(await service.loadWindowState(), isNull);
    });

    test('returns null for malformed state', () async {
      configsDir().createSync(recursive: true);
      File(
        p.join(configsDir().path, 'window_state.json'),
      ).writeAsStringSync('{broken');

      expect(await service.loadWindowState(), isNull);
    });

    test('overwrites previously saved state', () async {
      await service.saveWindowState({'width': 1.0});
      await service.saveWindowState({'width': 2.0});

      expect((await service.loadWindowState())!['width'], 2.0);
    });
  });
}
