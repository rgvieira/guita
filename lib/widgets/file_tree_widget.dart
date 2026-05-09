import 'package:flutter/material.dart';
import '../models/file_entry.dart';
import '../painters/chord_painter.dart';

class FileTreeWidget extends StatelessWidget {
  final List<FileEntry> files;
  final Function(FileEntry) onFileTap;
  final String rootPath;

  const FileTreeWidget({
    super.key,
    required this.files,
    required this.onFileTap,
    this.rootPath = '',
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Nenhum arquivo encontrado',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: files.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final file = files[index];
        final icon = _getFileIcon(file.extension);
        final isInRoot = rootPath.isEmpty || file.path.startsWith(rootPath);
        final displayPath = isInRoot && rootPath.isNotEmpty
            ? file.path.substring(rootPath.length + 1)
            : file.path;

        return ListTile(
          leading: Icon(icon, color: Colors.brown),
          title: Text(
            file.name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            displayPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          trailing: Text(
            _formatSize(file.size),
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          onTap: () => onFileTap(file),
        );
      },
    );
  }

  IconData _getFileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case '.gp3':
      case '.gp4':
      case '.gp5':
      case '.gpx':
      case '.gp':
        return Icons.music_note;
      case '.mid':
      case '.midi':
        return Icons.piano;
      case '.musicxml':
      case '.xml':
        return Icons.library_music;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class ChordDisplayWidget extends StatelessWidget {
  final String chordName;

  const ChordDisplayWidget({super.key, required this.chordName});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(120, 140),
      painter: ChordPainter(chordName: chordName),
    );
  }
}
