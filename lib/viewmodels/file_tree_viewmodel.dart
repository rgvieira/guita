import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_entry.dart';
import '../services/file_scanner_service.dart';
import '../services/settings_service.dart';

final fileListProvider = StateNotifierProvider<FileListNotifier, AsyncValue<List<FileEntry>>>((ref) {
  return FileListNotifier();
});

final selectedFileProvider = StateProvider<FileEntry?>((ref) => null);

final rootPathsProvider = StateNotifierProvider<RootPathsNotifier, List<String>>((ref) {
  return RootPathsNotifier();
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final showFavoritesOnlyProvider = StateProvider<bool>((ref) => false);

final filteredFilesProvider = Provider<AsyncValue<List<FileEntry>>>((ref) {
  final filesAsync = ref.watch(fileListProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final favoritesOnly = ref.watch(showFavoritesOnlyProvider);

  return filesAsync.whenData((files) {
    var result = files;

    if (favoritesOnly) {
      result = result.where((f) => f.isFavorite).toList();
    }

    if (query.isNotEmpty) {
      result = result.where((f) {
        final name = f.name.toLowerCase();
        return name.startsWith(query);
      }).toList();
    }

    return result;
  });
});

class RootPathsNotifier extends StateNotifier<List<String>> {
  RootPathsNotifier() : super(SettingsService.rootPaths);

  void addPath(String path) {
    if (!state.contains(path)) {
      state = [...state, path];
      SettingsService.rootPaths = state;
    }
  }

  void removePath(String path) {
    state = state.where((p) => p != path).toList();
    SettingsService.rootPaths = state;
  }
}

class FileListNotifier extends StateNotifier<AsyncValue<List<FileEntry>>> {
  FileListNotifier() : super(const AsyncValue.data([]));

  Future<void> scanDirectories(List<String> paths) async {
    state = const AsyncValue.loading();
    try {
      final files = await FileScannerService.scanDirectories(paths);
      await FileEntryBox.saveList(files);
      state = AsyncValue.data(files);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> toggleFavorite(FileEntry entry) async {
    entry.isFavorite = !entry.isFavorite;
    await FileEntryBox.updateEntry(entry);
    state = state.whenData((files) => files.map((f) {
      if (f.id == entry.id) return entry;
      return f;
    }).toList());
  }

  Future<void> loadFromCache() async {
    try {
      final files = await FileEntryBox.loadList();
      state = AsyncValue.data(files);
    } catch (e) {
      state = AsyncValue.data([]);
    }
  }
}
