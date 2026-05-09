import 'package:flutter_test/flutter_test.dart';
import 'package:guitarra/models/file_entry.dart';
import 'package:guitarra/models/music_note.dart';
import 'package:guitarra/models/practice_session.dart';

void main() {
  test('FileEntry creates correctly', () {
    final entry = FileEntry(
      path: 'C:/music/test.musicxml',
      name: 'test.musicxml',
      extension: '.musicxml',
    );
    expect(entry.path, 'C:/music/test.musicxml');
    expect(entry.isSupported, true);
  });

  test('MusicNote computes correct note name', () {
    final note = MusicNote(midi: 60, step: 'C', octave: 4);
    expect(note.noteName, 'C');
    expect(note.octave, 4);
  });

  test('PracticeSession serializes to JSON', () {
    final session = PracticeSession(
      bpmStart: 60,
      bpmEnd: 120,
      bpmStep: 10,
      repetitions: 3,
      finalBPM: 120,
      musicTitle: 'Test Song',
    );
    final json = session.toJson();
    final restored = PracticeSession.fromJson(json);
    expect(restored.bpmStart, 60);
    expect(restored.bpmEnd, 120);
    expect(restored.musicTitle, 'Test Song');
  });
}
