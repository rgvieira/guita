import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_entry.dart';
import '../viewmodels/file_tree_viewmodel.dart';

class FileTreeWidget extends ConsumerWidget {
  final List<FileEntry> files;
  final void Function(FileEntry file)? onFileTap;

  const FileTreeWidget({super.key, required this.files, this.onFileTap});

  IconData _iconForExt(String ext) {
    switch (ext) {
      case '.gp3':
      case '.gp4':
      case '.gp5':
      case '.gpx':
      case '.gp':
        return Icons.music_note;
      case '.mid':
      case '.midi':
      case '.kar':
        return Icons.piano;
      case '.musicxml':
      case '.xml':
        return Icons.description;
      case '.pdf':
        return Icons.picture_as_pdf;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Nenhum arquivo encontrado',
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return ListTile(
          leading: Icon(_iconForExt(file.extension), color: Colors.brown),
          title: Text(file.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            '${file.size ~/ 1024} KB',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          trailing: IconButton(
            icon: Icon(
              file.isFavorite ? Icons.star : Icons.star_border,
              color: file.isFavorite ? Colors.amber : Colors.grey,
            ),
            onPressed: () =>
                ref.read(fileListProvider.notifier).toggleFavorite(file),
          ),
          onTap: () => onFileTap?.call(file),
        );
      },
    );
  }
}
