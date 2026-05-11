import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

class SettingsService {
  static const _boxName = 'app_settings';
  static late Box<String> _box;

  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  static List<String> get rootPaths {
    final raw = _box.get('rootPaths');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.cast<String>();
    } catch (_) {
      // fallback: legado rootPath único
      final legacy = _box.get('rootPath');
      if (legacy != null && legacy.isNotEmpty) return [legacy];
      return [];
    }
  }

  static set rootPaths(List<String> paths) {
    _box.put('rootPaths', jsonEncode(paths));
  }

  static Future<void> addRootPath(String path) async {
    final list = rootPaths;
    if (!list.contains(path)) {
      list.add(path);
      rootPaths = list;
    }
  }

  static Future<void> removeRootPath(String path) async {
    final list = rootPaths;
    list.remove(path);
    rootPaths = list;
  }
}
