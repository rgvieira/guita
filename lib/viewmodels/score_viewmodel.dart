import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_note.dart';
import '../services/music_parser_service.dart';

final scoreProvider = StateNotifierProvider<ScoreNotifier, AsyncValue<ScoreData>>((ref) {
  return ScoreNotifier();
});

class ScoreNotifier extends StateNotifier<AsyncValue<ScoreData>> {
  ScoreNotifier() : super(AsyncValue.data(ScoreData(measures: [])));

  Future<void> loadFile(String path) async {
    state = const AsyncValue.loading();
    try {
      final score = await MusicParserService.parseFile(path);
      state = AsyncValue.data(score);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}
