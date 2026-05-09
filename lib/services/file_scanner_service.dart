import 'dart:io';
import '../models/file_entry.dart';

class FileScannerService {
  static Future<List<FileEntry>> scanDirectory(String rootPath) async {
    final entries = <FileEntry>[];
    final dir = Directory(rootPath);

    if (!await dir.exists()) {
      throw Exception('Directory not found: $rootPath');
    }

    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = entity.path.split('.').last.toLowerCase();
          if (FileEntry.supportedExtensions.any((e) => e.contains(ext))) {
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
      throw Exception(
        'Sem permissão para acessar $rootPath. Conceda permissão de armazenamento nas configurações do app.',
      );
    }

    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  static String getParentPath(String path) {
    final dir = Directory(path).parent;
    return dir.path;
  }

  static List<FileEntry> buildTree(List<FileEntry> entries) {
    return entries.where((e) => e.isSupported).toList();
  }
}
