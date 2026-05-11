import 'dart:io';
import '../models/file_entry.dart';

class FileScannerService {
  static Future<List<FileEntry>> scanDirectories(List<String> rootPaths) async {
    final entries = <FileEntry>[];
    final seen = <String>{};

    for (final rootPath in rootPaths) {
      final dir = Directory(rootPath);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final ext = entity.path.split('.').last.toLowerCase();
            if (FileEntry.supportedExtensions.any((e) => e.contains(ext))) {
              if (seen.contains(entity.path)) continue;
              seen.add(entity.path);
              final stat = await entity.stat();
              entries.add(FileEntry(
                path: entity.path,
                name: entity.path.split(Platform.pathSeparator).last,
                extension: '.$ext',
                size: stat.size,
                lastModified: stat.modified,
              ));
            }
          }
        }
      } on PathAccessException {
        // skip inaccessible dirs
      }
    }

    // Restore favorites from cache
    try {
      final cached = await FileEntryBox.loadList();
      for (final entry in entries) {
        final match = cached.where((c) => c.path == entry.path).firstOrNull;
        if (match != null && match.isFavorite) {
          entry.isFavorite = true;
        }
      }
    } catch (_) {}

    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  static List<FileEntry> buildTree(List<FileEntry> entries) {
    return entries.where((e) => e.isSupported).toList();
  }
}
