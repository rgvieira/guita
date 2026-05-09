import 'package:hive_flutter/hive_flutter.dart';

class SettingsService {
  static const _boxName = 'app_settings';
  static late Box<String> _box;

  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  static String? get rootPath => _box.get('rootPath');
  static set rootPath(String? path) {
    if (path == null) {
      _box.delete('rootPath');
    } else {
      _box.put('rootPath', path);
    }
  }
}
