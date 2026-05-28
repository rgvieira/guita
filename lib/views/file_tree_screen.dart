import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../viewmodels/file_tree_viewmodel.dart';
import '../models/file_entry.dart';
import '../services/settings_service.dart';
import '../widgets/file_tree_widget.dart';

class FileTreeScreen extends ConsumerStatefulWidget {
  const FileTreeScreen({super.key});

  @override
  ConsumerState<FileTreeScreen> createState() => _FileTreeScreenState();
}

class _FileTreeScreenState extends ConsumerState<FileTreeScreen>
    with SingleTickerProviderStateMixin {
  bool _initialized = false;
  late TabController _tabController;
  final _searchController = TextEditingController();
  String? _unsupportedFileMsg;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(searchQueryProvider.notifier).state = '';
      ref.read(showFavoritesOnlyProvider.notifier).state = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.storage.isGranted) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.photos.isGranted && await Permission.audio.isGranted) {
      return true;
    }

    if (await Permission.storage.request().isGranted) return true;
    if (await Permission.manageExternalStorage.request().isGranted) return true;
    if (await Permission.photos.request().isGranted &&
        await Permission.audio.request().isGranted) {
      return true;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Permissão de armazenamento necessária'),
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
    final filesAsync = ref.watch(filteredFilesProvider);
    final rootPaths = ref.watch(rootPathsProvider);
    final showFavs = ref.watch(showFavoritesOnlyProvider);
    final query = ref.watch(searchQueryProvider);

    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final saved = SettingsService.rootPaths;
        if (saved.isNotEmpty) {
          ref.read(fileListProvider.notifier).scanDirectories(saved);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/icon/icon.png',
            errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 28),
          ),
        ),
        title: const Text('Guitarra - Partituras'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.black,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black45,
          tabs: const [
            Tab(text: 'Arquivos', icon: Icon(Icons.library_music)),
            Tab(text: 'Pastas', icon: Icon(Icons.folder)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              showFavs ? Icons.star : Icons.star_border,
              color: showFavs ? Colors.amber : null,
            ),
            tooltip: 'Favoritos',
            onPressed: () {
              ref.read(showFavoritesOnlyProvider.notifier).state = !showFavs;
            },
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'Adicionar pasta',
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
          if (_unsupportedFileMsg != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _unsupportedFileMsg!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _unsupportedFileMsg = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFilesTab(filesAsync, showFavs, query),
                _buildFoldersTab(rootPaths, ref),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesTab(
      AsyncValue<List<FileEntry>> filesAsync, bool showFavs, String query) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar arquivo...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(searchQueryProvider.notifier).state = '';
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (v) =>
                ref.read(searchQueryProvider.notifier).state = v,
          ),
        ),
        if (showFavs)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.amber.shade50,
            child: Text(
              'Mostrando apenas favoritos',
              style: TextStyle(fontSize: 12, color: Colors.amber[900]),
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
                  TextButton(
                    onPressed: () => ref
                        .read(fileListProvider.notifier)
                        .scanDirectories(ref.read(rootPathsProvider)),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
            data: (files) => FileTreeWidget(
              files: files,
              onFileTap: (file) => _openFile(context, file),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFoldersTab(List<String> rootPaths, WidgetRef ref) {
    if (rootPaths.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Nenhuma pasta adicionada',
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.create_new_folder),
              label: const Text('Adicionar pasta'),
              onPressed: () => _pickFolder(context, ref),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        for (final path in rootPaths) _buildDirectoryNode(path, 0, ref),
      ],
    );
  }

  Widget _buildDirectoryNode(String path, int depth, WidgetRef ref) {
    final name = path.split(Platform.pathSeparator).last;
    return _DirectoryTile(
      path: path,
      name: name,
      depth: depth,
      onFileTap: (file) => _openFile(context, file),
    );
  }

  Future<void> _pickFolder(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final granted = await _requestStoragePermission();
    if (!granted) return;

    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null && mounted) {
        ref.read(searchQueryProvider.notifier).state = '';
        _searchController.clear();
        ref.read(showFavoritesOnlyProvider.notifier).state = false;
        ref.read(rootPathsProvider.notifier).addPath(result);
        await ref
            .read(fileListProvider.notifier)
            .scanDirectories(ref.read(rootPathsProvider));
        _tabController.animateTo(0);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openFile(BuildContext context, FileEntry file) {
    final ext = file.path.split('.').last.toLowerCase();
    if (!ext.startsWith('gp')) {
      setState(() {
        _unsupportedFileMsg = 'Arquivo não compatível';
      });
      return;
    }
    setState(() => _unsupportedFileMsg = null);
    Navigator.pushNamed(context, '/score', arguments: file.path);
  }
}

class _DirectoryTile extends ConsumerStatefulWidget {
  final String path;
  final String name;
  final int depth;
  final void Function(FileEntry file)? onFileTap;

  const _DirectoryTile({
    required this.path,
    required this.name,
    required this.depth,
    this.onFileTap,
  });

  @override
  ConsumerState<_DirectoryTile> createState() => _DirectoryTileState();
}

class _DirectoryTileState extends ConsumerState<_DirectoryTile> {
  bool _expanded = false;
  Future<List<FileSystemEntity>>? _childrenFuture;

  Future<List<FileSystemEntity>> _loadChildren() async {
    final dir = Directory(widget.path);
    if (!await dir.exists()) return [];
    return dir.list().toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _expanded = !_expanded;
              if (_expanded && _childrenFuture == null) {
                _childrenFuture = _loadChildren();
              }
            });
          },
          child: Padding(
            padding: EdgeInsets.only(left: widget.depth * 16.0),
            child: ListTile(
              dense: true,
              leading: Icon(
                _expanded ? Icons.folder_open : Icons.folder,
                color: Colors.black,
              ),
              title: Text(
                widget.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        if (_expanded)
          FutureBuilder<List<FileSystemEntity>>(
            future: _childrenFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: EdgeInsets.only(left: (widget.depth + 1) * 16.0),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: LinearProgressIndicator(),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: EdgeInsets.only(left: (widget.depth + 1) * 16.0),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      'Erro: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                );
              }
              final entities = snapshot.data ?? [];
              final dirs = <Directory>[];
              final files = <File>[];
              for (final e in entities) {
                if (e is Directory) {
                  dirs.add(e);
                } else if (e is File) {
                  files.add(e);
                }
              }
              dirs.sort((a, b) => a.path.compareTo(b.path));
              files.sort((a, b) => a.path.compareTo(b.path));

              final children = <Widget>[];
              for (final d in dirs) {
                final childName = d.path.split(Platform.pathSeparator).last;
                if (childName.isEmpty || childName.startsWith('.')) continue;
                children.add(_DirectoryTile(
                  path: d.path,
                  name: childName,
                  depth: widget.depth + 1,
                  onFileTap: widget.onFileTap,
                ));
              }
              for (final f in files) {
                final ext = f.path.split('.').last.toLowerCase();
                if (!FileEntry.supportedExtensions
                    .any((e) => e.contains(ext))) {
                  continue;
                }
                final childName = f.path.split(Platform.pathSeparator).last;
                children.add(_FileTile(
                  path: f.path,
                  name: childName,
                  extension: '.$ext',
                  depth: widget.depth + 1,
                  onTap: widget.onFileTap,
                ));
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              );
            },
          ),
      ],
    );
  }
}

class _FileTile extends ConsumerWidget {
  final String path;
  final String name;
  final String extension;
  final int depth;
  final void Function(FileEntry file)? onTap;

  const _FileTile({
    required this.path,
    required this.name,
    required this.extension,
    required this.depth,
    this.onTap,
  });

  IconData _iconForExt() {
    switch (extension) {
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
    final files = ref.watch(fileListProvider).valueOrNull ?? [];
    final match = files.where((f) => f.path == path).firstOrNull;
    final isFavorite = match?.isFavorite ?? false;

    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: ListTile(
        dense: true,
        leading: Icon(_iconForExt(), color: Colors.black),
        title: Text(
          name,
          style: const TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: Icon(
            isFavorite ? Icons.star : Icons.star_border,
            color: isFavorite ? Colors.amber : Colors.grey,
            size: 18,
          ),
          onPressed: () {
            final entry = match ??
                FileEntry(
                  path: path,
                  name: name,
                  extension: extension,
                );
            ref.read(fileListProvider.notifier).toggleFavorite(entry);
          },
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
        onTap: () {
          final entry = match ??
              FileEntry(
                path: path,
                name: name,
                extension: extension,
              );
          onTap?.call(entry);
        },
      ),
    );
  }
}
