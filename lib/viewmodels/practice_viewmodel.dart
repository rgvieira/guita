import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_note.dart';
import '../models/practice_session.dart';
import '../services/midi_player_service.dart';

final practiceProvider = StateNotifierProvider<PracticeNotifier, PracticeState>((ref) {
  return PracticeNotifier();
});

class PracticeState {
  final int bpmStart;
  final int bpmEnd;
  final int bpmStep;
  final int repetitions;
  final bool accelerate;
  final bool isRunning;
  final int currentBPM;
  final int currentRepetition;
  final double progress;
  final List<PracticeSession> history;

  const PracticeState({
    this.bpmStart = 60,
    this.bpmEnd = 120,
    this.bpmStep = 10,
    this.repetitions = 3,
    this.accelerate = true,
    this.isRunning = false,
    this.currentBPM = 60,
    this.currentRepetition = 0,
    this.progress = 0,
    this.history = const [],
  });

  PracticeState copyWith({
    int? bpmStart,
    int? bpmEnd,
    int? bpmStep,
    int? repetitions,
    bool? accelerate,
    bool? isRunning,
    int? currentBPM,
    int? currentRepetition,
    double? progress,
    List<PracticeSession>? history,
  }) => PracticeState(
    bpmStart: bpmStart ?? this.bpmStart,
    bpmEnd: bpmEnd ?? this.bpmEnd,
    bpmStep: bpmStep ?? this.bpmStep,
    repetitions: repetitions ?? this.repetitions,
    accelerate: accelerate ?? this.accelerate,
    isRunning: isRunning ?? this.isRunning,
    currentBPM: currentBPM ?? this.currentBPM,
    currentRepetition: currentRepetition ?? this.currentRepetition,
    progress: progress ?? this.progress,
    history: history ?? this.history,
  );
}

class PracticeNotifier extends StateNotifier<PracticeState> {
  final MidiPlayerService _player = MidiPlayerService();

  PracticeNotifier() : super(const PracticeState()) {
    _loadHistory();
  }

  void _loadHistory() async {
    final sessions = await PracticeSessionBox.loadAll();
    state = state.copyWith(history: sessions);
  }

  void updateBpmStart(int value) => state = state.copyWith(bpmStart: value);
  void updateBpmEnd(int value) => state = state.copyWith(bpmEnd: value);
  void updateBpmStep(int value) => state = state.copyWith(bpmStep: value);
  void updateRepetitions(int value) => state = state.copyWith(repetitions: value);
  void toggleAccelerate() => state = state.copyWith(accelerate: !state.accelerate);

  Future<void> startPractice(List<MusicNote> notes, String musicTitle) async {
    state = state.copyWith(isRunning: true, currentBPM: state.bpmStart, currentRepetition: 0, progress: 0);

    for (int rep = 0; rep < state.repetitions; rep++) {
      state = state.copyWith(currentRepetition: rep);
      int currentBPM = state.accelerate ? state.bpmStart : state.bpmEnd;

      while (state.accelerate ? currentBPM <= state.bpmEnd : currentBPM >= state.bpmStart) {
        if (!state.isRunning) break;

        state = state.copyWith(currentBPM: currentBPM);
        final beatDuration = (60000 ~/ currentBPM);

        for (final note in notes) {
          if (!state.isRunning) break;
          await _player.playNote(note);
          await Future.delayed(Duration(milliseconds: beatDuration));
        }

        currentBPM += state.accelerate ? state.bpmStep : -state.bpmStep;
        final totalSteps = ((state.bpmEnd - state.bpmStart) / state.bpmStep).abs() + 1;
        final completed = (rep * totalSteps + (currentBPM - state.bpmStart).abs() / state.bpmStep);
        state = state.copyWith(
          progress: completed / (state.repetitions * totalSteps),
        );
      }
    }

    final session = PracticeSession(
      bpmStart: state.bpmStart,
      bpmEnd: state.bpmEnd,
      bpmStep: state.bpmStep,
      repetitions: state.repetitions,
      finalBPM: state.accelerate ? state.bpmEnd : state.bpmStart,
      musicTitle: musicTitle,
    );
    await PracticeSessionBox.save(session);
    _loadHistory();

    state = state.copyWith(isRunning: false, currentBPM: state.bpmStart, progress: 0);
  }

  void stop() {
    _player.stop();
    state = state.copyWith(isRunning: false);
  }
}
