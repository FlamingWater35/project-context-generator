import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/project_config.dart';

class ConfigService {
  Future<List<ProjectConfig>> loadConfigs() async {
    final configDir = await _getConfigDir();
    final configs = <ProjectConfig>[];

    await for (final entity in configDir.list()) {
      if (entity is File &&
          entity.path.endsWith('.json') &&
          !entity.path.endsWith('.snap.json')) {
        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content);
          configs.add(ProjectConfig.fromJson(json));
        } catch (e) {
          // Ignore invalid files gracefully
        }
      }
    }
    return configs;
  }

  Future<void> saveConfig(ProjectConfig config, {String? oldName}) async {
    final configDir = await _getConfigDir();
    if (oldName != null && oldName != config.name) {
      final oldFile = File(
        p.join(configDir.path, '${_sanitize(oldName)}.json'),
      );
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
      final oldSnap = File(
        p.join(configDir.path, '${_sanitize(oldName)}.snap.json'),
      );
      if (await oldSnap.exists()) {
        await oldSnap.delete();
      }
    }
    final safeName = _sanitize(config.name);
    final file = File(p.join(configDir.path, '$safeName.json'));
    final content = jsonEncode(config.toJson());
    await file.writeAsString(content);
  }

  Future<void> deleteConfig(String name) async {
    final configDir = await _getConfigDir();
    final safeName = _sanitize(name);
    final file = File(p.join(configDir.path, '$safeName.json'));
    if (await file.exists()) {
      await file.delete();
    }
    final snapFile = File(p.join(configDir.path, '$safeName.snap.json'));
    if (await snapFile.exists()) {
      await snapFile.delete();
    }
  }

  Future<Set<String>?> loadSnapshot(String configId) async {
    try {
      final configDir = await _getConfigDir();
      final file = File(p.join(configDir.path, '$configId.snap.json'));
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final json = jsonDecode(content);
      return Set<String>.from(json['paths'] ?? []);
    } catch (e) {
      return null;
    }
  }

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
      debugPrint('Failed to save snapshot: $e');
    }
  }

  String _sanitize(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Future<Directory> _getConfigDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final configDir = Directory(p.join(supportDir.path, 'configs'));
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }
    return configDir;
  }
}
