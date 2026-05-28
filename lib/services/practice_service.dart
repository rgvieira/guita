import 'package:flutter/material.dart';
import '../models/practice_session.dart';

class PracticeService {
  bool _isRunning = false;
  int _currentBPM = 60;
  int _currentRepetition = 0;
  double _progress = 0;
  VoidCallback? onStateChanged;
  Function(double speed)? onSpeedChanged;
  Function()? onPlay;
  Function()? onStopPlayback;

  bool get isRunning => _isRunning;
  int get currentBPM => _currentBPM;
  int get currentRepetition => _currentRepetition;
  double get progress => _progress;

  Future<void> runPractice({
    required int bpmStart,
    required int bpmEnd,
    required int bpmStep,
    required int repetitions,
    required bool accelerate,
    required Function(int) onSpeedChange,
  }) async {
    _isRunning = true;
    _currentBPM = bpmStart;
    _currentRepetition = 0;
    _progress = 0;
    onStateChanged?.call();

    final speed = _bpmToSpeed(bpmStart);
    onSpeedChanged?.call(speed);
    onPlay?.call();

    for (int rep = 0; rep < repetitions; rep++) {
      if (!_isRunning) break;
      _currentRepetition = rep;
      onStateChanged?.call();

      int bpm = accelerate ? bpmStart : bpmEnd;

      while (_isRunning && (accelerate ? bpm <= bpmEnd : bpm >= bpmStart)) {
        _currentBPM = bpm;
        onSpeedChange(bpm);
        final speed = _bpmToSpeed(bpm);
        onSpeedChanged?.call(speed);
        onStateChanged?.call();

        // Wait for 4 beats at current BPM
        await Future.delayed(Duration(milliseconds: (60000 ~/ bpm) * 4));

        bpm += accelerate ? bpmStep : -bpmStep;
        final totalSteps = ((bpmEnd - bpmStart) / bpmStep).abs() + 1;
        final completed = (rep * totalSteps + (bpm - bpmStart).abs() / bpmStep);
        _progress = completed / (repetitions * totalSteps);
        onStateChanged?.call();
      }
    }

    // Save session
    final session = PracticeSession(
      bpmStart: bpmStart,
      bpmEnd: bpmEnd,
      bpmStep: bpmStep,
      repetitions: repetitions,
      finalBPM: accelerate ? bpmEnd : bpmStart,
      musicTitle: '',
    );
    await PracticeSessionBox.save(session);

    _isRunning = false;
    onStopPlayback?.call();
    onStateChanged?.call();
  }

  void stop() {
    _isRunning = false;
  }

  double _bpmToSpeed(int bpm) {
    // 120 BPM = 1.0 speed (normal)
    return (bpm / 120.0).clamp(0.125, 8.0);
  }
}
