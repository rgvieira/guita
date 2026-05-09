import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_entry.dart';
import '../services/file_scanner_service.dart';

final fileListProvider = StateNotifierProvider<FileListNotifier, AsyncValue<List<FileEntry>>>((ref) {
  return FileListNotifier();
});

final selectedFileProvider = StateProvider<FileEntry?>((ref) => null);
final rootPathProvider = StateProvider<String>((ref) => '');

class FileListNotifier extends StateNotifier<AsyncValue<List<FileEntry>>> {
  FileListNotifier() : super(const AsyncValue.data([]));

  Future<void> scanDirectory(String path) async {
    state = const AsyncValue.loading();
    try {
      final files = await FileScannerService.scanDirectory(path);
      await FileEntryBox.saveList(files);
      state = AsyncValue.data(files);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
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
