import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/project_config.dart';

// Service managing configuration storage serialization logic on physical disks
class ConfigService {
  // Scans configs folder pathways and decodes project profile records
  Future<List<ProjectConfig>> loadConfigs() async {
    try {
      final configDir = await _getConfigDir();
      final configs = <ProjectConfig>[];

      await for (final entity in configDir.list()) {
        if (entity is File &&
            entity.path.endsWith('.json') &&
            !entity.path.endsWith('.snap.json') &&
            !entity.path.endsWith('window_state.json')) {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content);
            final config = ProjectConfig.fromJson(json as Map<String, dynamic>);
            configs.add(config);

            final expectedFileName = '${config.id}.json';
            final actualFileName = p.basename(entity.path);
            if (actualFileName != expectedFileName) {
              final newFile = File(
                p.join(entity.parent.path, expectedFileName),
              );
              await entity.rename(newFile.path);
            }
          } catch (e) {
            debugPrint(
              'Failed to safely deserialize config entity matching path ${entity.path}: $e',
            );
          }
        }
      }
      return configs;
    } catch (e) {
      debugPrint(
        'Critical filesystem list scan failure within configs repository: $e',
      );
      return const [];
    }
  }

  // Persists configuration mappings inside local disk file tracks
  Future<void> saveConfig(ProjectConfig config, {String? oldName}) async {
    try {
      final configDir = await _getConfigDir();

      if (oldName != null && oldName != config.name) {
        final oldFile = File(
          p.join(configDir.path, '${_sanitize(oldName)}.json'),
        );
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
      }

      final legacyFile = File(
        p.join(configDir.path, '${_sanitize(config.name)}.json'),
      );
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }

      final file = File(p.join(configDir.path, '${config.id}.json'));
      final content = jsonEncode(config.toJson());
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Failure attempting to save project configuration schema: $e');
    }
  }

  // Deletes configuration profile documents and dynamic snapshots matching targets
  Future<void> deleteConfig(ProjectConfig config) async {
    try {
      final configDir = await _getConfigDir();

      final file = File(p.join(configDir.path, '${config.id}.json'));
      if (await file.exists()) {
        await file.delete();
      }

      final legacyFile = File(
        p.join(configDir.path, '${_sanitize(config.name)}.json'),
      );
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }

      await deleteSnapshot(config.id);
    } catch (e) {
      debugPrint(
        'Failure attempting to remove targeted metadata configurations: $e',
      );
    }
  }

  // Recovers stored target path selection snapshot records
  Future<Set<String>?> loadSnapshot(String configId) async {
    try {
      final configDir = await _getConfigDir();
      final file = File(p.join(configDir.path, '$configId.snap.json'));
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return Set<String>.from(json['paths'] as List<dynamic>? ?? const []);
    } catch (e) {
      debugPrint('Could not successfully resolve database path cache map: $e');
      return null;
    }
  }

  // Writes file structures lists down onto local systems
  Future<void> saveSnapshot(String configId, Set<String> paths) async {
    try {
      final configDir = await _getConfigDir();
      final file = File(p.join(configDir.path, '$configId.snap.json'));
      final content = jsonEncode({
        'paths': paths.toList(),
        'timestamp': DateTime.now().toIso8601String(),
      });
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Failed to save snapshot cache updates: $e');
    }
  }

  // Removes folder structure cached snapshots matching specific project identifiers
  Future<void> deleteSnapshot(String configId) async {
    try {
      final configDir = await _getConfigDir();
      final file = File(p.join(configDir.path, '$configId.snap.json'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to clean up configuration tree caches: $e');
    }
  }

  // Loads layout measurements, positions, and bounds of window containers
  Future<Map<String, dynamic>?> loadWindowState() async {
    try {
      final configDir = await _getConfigDir();
      final file = File(p.join(configDir.path, 'window_state.json'));
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint(
        'Unable to parse active window measurements state parameters: $e',
      );
      return null;
    }
  }

  // Saves global UI frame locations and window scale bounds onto local systems
  Future<void> saveWindowState(Map<String, dynamic> state) async {
    try {
      final configDir = await _getConfigDir();
      final file = File(p.join(configDir.path, 'window_state.json'));
      final content = jsonEncode(state);
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Unable to record active window scaling state parameters: $e');
    }
  }

  // Filters problematic characters from input string labels
  String _sanitize(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  // Retrieves application specific data documents directories
  Future<Directory> _getConfigDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final configDir = Directory(p.join(supportDir.path, 'configs'));
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }
    return configDir;
  }
}
