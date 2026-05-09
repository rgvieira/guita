import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../viewmodels/file_tree_viewmodel.dart';
import '../models/file_entry.dart';
import '../widgets/file_tree_widget.dart';
import '../services/settings_service.dart';

class FileTreeScreen extends ConsumerStatefulWidget {
  const FileTreeScreen({super.key});

  @override
  ConsumerState<FileTreeScreen> createState() => _FileTreeScreenState();
}

class _FileTreeScreenState extends ConsumerState<FileTreeScreen> {
  bool _initialized = false;

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.storage.isGranted) return true;

    if (await Permission.manageExternalStorage.isGranted) return true;

    if (await Permission.photos.isGranted && await Permission.audio.isGranted) return true;

    if (await Permission.storage.request().isGranted) return true;

    if (await Permission.manageExternalStorage.request().isGranted) return true;

    if (await Permission.photos.request().isGranted && await Permission.audio.request().isGranted) {
      return true;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Permissão de armazenamento necessária para acessar arquivos'),
          action: SnackBarAction(
            label: 'Configurações',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final filesAsync = ref.watch(fileListProvider);
    final rootPath = ref.watch(rootPathProvider);

    // Load cached folder on first build
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final saved = SettingsService.rootPath;
        if (saved != null && saved.isNotEmpty) {
          ref.read(rootPathProvider.notifier).state = saved;
          ref.read(fileListProvider.notifier).scanDirectory(saved);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guitarra - Partituras'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Selecionar pasta',
            onPressed: () => _pickFolder(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Histórico',
            onPressed: () => Navigator.pushNamed(context, '/history'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (rootPath.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Icon(Icons.folder, size: 16, color: Colors.brown[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rootPath,
                      style: TextStyle(fontSize: 12, color: Colors.brown[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => ref.read(fileListProvider.notifier).scanDirectory(rootPath),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: filesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    const Text(
                      'Erro ao acessar arquivos',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        '$e',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _requestStoragePermission().then((granted) {
                        if (granted && rootPath.isNotEmpty) {
                          ref.read(fileListProvider.notifier).scanDirectory(rootPath);
                        }
                      }),
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Conceder permissão'),
                    ),
                    const SizedBox(height: 8),
                    if (rootPath.isNotEmpty)
                      TextButton(
                        onPressed: () => ref.read(fileListProvider.notifier).scanDirectory(rootPath),
                        child: const Text('Tentar novamente'),
                      ),
                  ],
                ),
              ),
              data: (files) => FileTreeWidget(
                files: files,
                rootPath: rootPath,
                onFileTap: (file) => _openFile(context, file),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final granted = await _requestStoragePermission();
    if (!granted) return;

    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null && mounted) {
        SettingsService.rootPath = result;
        ref.read(rootPathProvider.notifier).state = result;
        ref.read(fileListProvider.notifier).scanDirectory(result);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao selecionar pasta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openFile(BuildContext context, FileEntry file) {
    Navigator.pushNamed(
      context,
      '/score',
      arguments: file.path,
    );
  }
}
