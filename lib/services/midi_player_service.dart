import 'dart:async';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import '../models/music_note.dart';
import '../audio/native_midi_bridge.dart';

class MidiPlayerService {
  bool _isPlaying = false;
  int? _sfId;
  bool _initialized = false;
  final Set<int> _activeNotes = {};
  Timer? _sequencerTimer;
  int _currentTick = 0;
  int _totalTicks = 0;
  double _msPerTick = 1;
  List<_ScheduledEvent> _events = [];
  int _eventIndex = 0;
  final _playheadController = StreamController<double>.broadcast();
  final _stateController = StreamController<bool>.broadcast();

  bool get isPlaying => _isPlaying;
  int get currentTick => _currentTick;
  Stream<double> get playheadStream => _playheadController.stream;
  Stream<bool> get stateStream => _stateController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await NativeMidiBridge.init();
    try {
      _sfId = await MidiPro().loadSoundfontAsset(
        assetPath: 'assets/soundfonts/TimGM6mb.sf2',
        bank: 0,
        program: 0,
      );
    } catch (_) {
      _sfId = null;
    }
  }

  Future<void> noteOn(int midi, {int velocity = 100}) async {
    _activeNotes.add(midi);
    if (_sfId != null) {
      await MidiPro().playNote(key: midi, velocity: velocity, sfId: _sfId!);
      return;
    }
    if (NativeMidiBridge.isAvailable) {
      await NativeMidiBridge.sendNoteOn(midi, velocity);
    }
  }

  Future<void> noteOff(int midi) async {
    _activeNotes.remove(midi);
    if (_sfId != null) {
      await MidiPro().stopNote(key: midi, sfId: _sfId!);
      return;
    }
    if (NativeMidiBridge.isAvailable) {
      await NativeMidiBridge.sendNoteOff(midi);
    }
  }

  Future<void> allNotesOff() async {
    if (_sfId != null) {
      await MidiPro().stopAllNotes(sfId: _sfId!);
    } else if (NativeMidiBridge.isAvailable) {
      await NativeMidiBridge.allNotesOff();
    }
    _activeNotes.clear();
  }

  /// Play a single note (used by practice mode).
  Future<void> playNote(MusicNote note) async {
    await init();
    await noteOn(note.midi);
    Future.delayed(const Duration(milliseconds: 300), () => noteOff(note.midi));
  }

  void schedule(List<MusicNote> notes, double bpm, {double startTime = 0}) {
    _events = _buildEvents(notes, bpm, startTime);
    _events.sort((a, b) => a.tick.compareTo(b.tick));
    _totalTicks = _events.isNotEmpty ? _events.last.tick : 0;
    _msPerTick = 60000.0 / bpm / 480.0;
  }

  void play({
    void Function(int index)? onNote,
    void Function()? onComplete,
  }) {
    if (_events.isEmpty || _isPlaying) return;
    _isPlaying = true;
    _eventIndex = 0;
    _currentTick = 0;
    _stateController.add(true);

    _sequencerTimer = Timer.periodic(Duration(milliseconds: _msPerTick.ceil().clamp(1, 100)), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      _currentTick++;
      final progress = _totalTicks > 0 ? _currentTick / _totalTicks : 0.0;
      _playheadController.add(progress);

      while (_eventIndex < _events.length && _events[_eventIndex].tick <= _currentTick) {
        final ev = _events[_eventIndex];
        if (ev.isNoteOn) {
          noteOn(ev.midi, velocity: ev.velocity);
          onNote?.call(ev.noteIndex);
        } else {
          noteOff(ev.midi);
        }
        _eventIndex++;
      }

      if (_currentTick >= _totalTicks || _eventIndex >= _events.length) {
        _isPlaying = false;
        _sequencerTimer?.cancel();
        _sequencerTimer = null;
        allNotesOff();
        _stateController.add(false);
        onComplete?.call();
      }
    });
  }

  void pause() {
    _isPlaying = false;
    _sequencerTimer?.cancel();
    _sequencerTimer = null;
    allNotesOff();
    _stateController.add(false);
  }

  void stop() {
    _isPlaying = false;
    _sequencerTimer?.cancel();
    _sequencerTimer = null;
    _currentTick = 0;
    _eventIndex = 0;
    allNotesOff();
    _playheadController.add(0.0);
    _stateController.add(false);
  }

  void seek(double progress) {
    if (_events.isEmpty) return;
    _currentTick = (progress * _totalTicks).round();
    _eventIndex = _events.lastIndexWhere((e) => e.tick <= _currentTick) + 1;
    _eventIndex = _eventIndex.clamp(0, _events.length);
  }

  List<_ScheduledEvent> _buildEvents(List<MusicNote> notes, double bpm, double startTime) {
    final events = <_ScheduledEvent>[];
    final tickPerMs = 480.0 / (60000.0 / bpm);
    final startTick = (startTime * tickPerMs).round();

    // Group notes by startTime for chord detection
    final grouped = <int, List<MusicNote>>{};
    for (int i = 0; i < notes.length; i++) {
      final key = notes[i].startTime.round();
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(notes[i]);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    int tickOffset = startTick;
    int prevTime = 0;

    for (final time in sortedKeys) {
      final group = grouped[time]!;
      if (time > prevTime) {
        tickOffset += ((time - prevTime) * tickPerMs).round();
      }
      for (final note in group) {
        events.add(_ScheduledEvent(
          tick: tickOffset,
          midi: note.midi,
          velocity: note.velocity > 0 ? note.velocity : 100,
          isNoteOn: true,
          noteIndex: notes.indexOf(note),
        ));
        final endMs = (note.endTime > note.startTime ? note.endTime - time : 200).round();
        events.add(_ScheduledEvent(
          tick: tickOffset + (endMs * tickPerMs).round(),
          midi: note.midi,
          velocity: 0,
          isNoteOn: false,
          noteIndex: notes.indexOf(note),
        ));
      }
      prevTime = time;
    }
    return events;
  }

  void dispose() {
    _isPlaying = false;
    _sequencerTimer?.cancel();
    allNotesOff();
    _playheadController.close();
    _stateController.close();
  }
}

class _ScheduledEvent {
  final int tick;
  final int midi;
  final int velocity;
  final bool isNoteOn;
  final int noteIndex;

  const _ScheduledEvent({
    required this.tick,
    required this.midi,
    required this.velocity,
    required this.isNoteOn,
    required this.noteIndex,
  });
}
