import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class FileEntry {
  final String id;
  final String path;
  final String name;
  final String extension;
  final bool isDirectory;
  final int size;
  final DateTime lastModified;
  bool isFavorite;

  FileEntry({
    String? id,
    required this.path,
    required this.name,
    required this.extension,
    this.isDirectory = false,
    this.size = 0,
    DateTime? lastModified,
    this.isFavorite = false,
  }) : id = id ?? const Uuid().v4(),
       lastModified = lastModified ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'name': name,
    'extension': extension,
    'isDirectory': isDirectory,
    'size': size,
    'lastModified': lastModified.toIso8601String(),
    'isFavorite': isFavorite,
  };

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
    id: json['id'] as String,
    path: json['path'] as String,
    name: json['name'] as String,
    extension: json['extension'] as String,
    isDirectory: json['isDirectory'] as bool,
    size: json['size'] as int,
    lastModified: DateTime.parse(json['lastModified'] as String),
    isFavorite: json['isFavorite'] as bool? ?? false,
  );

  static const supportedExtensions = [
    '.gp3', '.gp4', '.gp5', '.gpx', '.gp',
  ];

  bool get isSupported => supportedExtensions.contains(extension.toLowerCase());
}

class FileEntryBox {
  static const _boxName = 'files';
  static Box<String>? _box;

  static Future<Box<String>> get box async {
    _box ??= await Hive.openBox<String>(_boxName);
    return _box!;
  }

  static Future<void> saveList(List<FileEntry> entries) async {
    final b = await box;
    await b.clear();
    for (final entry in entries) {
      await b.put(entry.id, jsonEncode(entry.toJson()));
    }
  }

  static Future<void> updateEntry(FileEntry entry) async {
    final b = await box;
    await b.put(entry.id, jsonEncode(entry.toJson()));
  }

  static Future<List<FileEntry>> loadList() async {
    final b = await box;
    return b.values.map((v) => FileEntry.fromJson(jsonDecode(v) as Map<String, dynamic>)).toList();
  }
}
