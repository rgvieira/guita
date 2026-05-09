import 'dart:async';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import '../models/music_note.dart';

class MidiPlayerService {
  bool _isPlaying = false;
  int? _sfId;
  bool _initialized = false;
  final Set<int> _activeNotes = {};

  bool get isPlaying => _isPlaying;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _sfId = await MidiPro().loadSoundfontAsset(
      assetPath: 'assets/soundfonts/TimGM6mb.sf2',
      bank: 0,
      program: 0,
    );
  }

  Future<void> noteOn(int midi, {int velocity = 100}) async {
    if (_sfId == null) return;
    await MidiPro().playNote(key: midi, velocity: velocity, sfId: _sfId!);
    _activeNotes.add(midi);
  }

  Future<void> noteOff(int midi) async {
    if (_sfId == null) return;
    await MidiPro().stopNote(key: midi, sfId: _sfId!);
    _activeNotes.remove(midi);
  }

  Future<void> allNotesOff() async {
    if (_sfId == null) return;
    await MidiPro().stopAllNotes(sfId: _sfId!);
    _activeNotes.clear();
  }

  /// Play a single note (used by practice mode).
  Future<void> playNote(MusicNote note) async {
    await init();
    await noteOn(note.midi);
    Future.delayed(const Duration(milliseconds: 300), () => noteOff(note.midi));
  }

  /// Play all notes sequentially. [onNote] fires for each note for cursor tracking.
  Future<void> playSongOnce(
    List<MusicNote> notes,
    double bpm, {
    void Function(int index)? onNote,
    void Function()? onComplete,
  }) async {
    if (notes.isEmpty) return;
    await init();

    _isPlaying = true;
    final beatMs = (60000 / bpm).round().clamp(50, 10000);
    final noteDuration = (beatMs * 0.8).round();

    for (int i = 0; i < notes.length && _isPlaying; i++) {
      await noteOn(notes[i].midi);
      onNote?.call(i);
      Future.delayed(Duration(milliseconds: noteDuration), () {
        noteOff(notes[i].midi);
      });
      await Future.delayed(Duration(milliseconds: beatMs));
    }

    _isPlaying = false;
    await allNotesOff();
    onComplete?.call();
  }

  void stop() {
    _isPlaying = false;
    allNotesOff();
  }

  void dispose() {
    _isPlaying = false;
    allNotesOff();
  }
}
