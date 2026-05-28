import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'package:xml/xml.dart';
import '../models/music_note.dart';

class MusicParserService {
  static Future<ScoreData> parseFile(String path) async {
    final ext = path.split('.').last.toLowerCase();

    switch (ext) {
      case 'musicxml':
      case 'xml':
        return _parseMusicXml(path);
      case 'mid':
      case 'midi':
      case 'kar':
        return ScoreData(measures: []);
      default:
        if (path.contains('.gp')) return _parseGp(path);
        return ScoreData(measures: []);
    }
  }

  static Future<ScoreData> _parseMusicXml(String path) async {
    try {
      final content = await File(path).readAsString();
      final document = XmlDocument.parse(content);

      final title = document
          .findAllElements('movement-title')
          .firstOrNull
          ?.innerText ?? 'Unknown';

      final parts = document.findAllElements('part');
      final measures = <Measure>[];
      int measureNum = 0;

      for (final part in parts) {
        for (final measure in part.findElements('measure')) {
          measureNum++;
          final notes = <MusicNote>[];

          for (final note in measure.findElements('note')) {
            final rest = note.findElements('rest').isNotEmpty;
            if (rest) continue;

            final pitch = note.findElements('pitch').firstOrNull;
            final duration = note.findElements('duration').firstOrNull;
            final technical = note.findElements('technical').firstOrNull;

            if (pitch == null) continue;

            final step = pitch.findElements('step').firstOrNull?.innerText ?? 'C';
            final octave = int.tryParse(
              pitch.findElements('octave').firstOrNull?.innerText ?? '4',
            ) ?? 4;
            final alter = int.tryParse(
              pitch.findElements('alter').firstOrNull?.innerText ?? '0',
            ) ?? 0;

            final midi = _stepToMidi(step, octave) + alter;
            final dur = int.tryParse(duration?.innerText ?? '4') ?? 4;

            int fret = 0;
            int string = 0;
            if (technical != null) {
              fret = int.tryParse(
                technical.findElements('fret').firstOrNull?.innerText ?? '0',
              ) ?? 0;
              string = int.tryParse(
                technical.findElements('string').firstOrNull?.innerText ?? '0',
              ) ?? 0;
            }

            final chordNameEl = note.parent?.findElements('harmony').firstOrNull
                ?.findElements('root').firstOrNull
                ?.findElements('root-step').firstOrNull;

            notes.add(MusicNote(
              midi: midi,
              step: step,
              octave: octave,
              duration: dur,
              fret: fret,
              string: string,
              chordName: chordNameEl?.innerText,
            ));
          }

          if (notes.isNotEmpty) {
            measures.add(Measure(number: measureNum, notes: notes));
          }
        }
      }

      return ScoreData(title: title, measures: measures);
    } catch (e) {
      return ScoreData(measures: []);
    }
  }

  static Future<ScoreData> _parseGp(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final jsonString = await Isolate.run(() => _parseGpBytesToJson(bytes, path));
      return ScoreData.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
    } catch (e) {
      return ScoreData(measures: []);
    }
  }

  static String _parseGpBytesToJson(Uint8List bytes, String path) {
    final score = _parseGpBytes(bytes, path);
    return jsonEncode(score.toJson());
  }

  static ScoreData _parseGpBytes(Uint8List bytes, String path) {
    int offset = 0;

    String readStringSized() {
      final len = offset < bytes.length - 4
          ? _readInt(bytes, offset, 4)
          : 0;
      offset += 4;
      if (len == 0 || len > 255 || offset + len > bytes.length) return '';
      final str = String.fromCharCodes(bytes.sublist(offset, offset + len));
      offset += len;
      return str;
    }

    int readByte() => offset < bytes.length ? bytes[offset++].toInt() & 0xFF : 0;

    int readInt() {
      if (offset + 4 > bytes.length) return 0;
      final v = _readInt(bytes, offset, 4);
      offset += 4;
      return v;
    }

    final versionBytes = <int>[];
    while (offset < bytes.length && bytes[offset] != 0) {
      versionBytes.add(bytes[offset]);
      offset++;
    }
    offset++;

    final title = readStringSized();
    readStringSized();
    readStringSized();
    readStringSized();
    readStringSized();
    readStringSized();
    readStringSized();

    final noticeLines = readInt();
    for (int i = 0; i < noticeLines && offset < bytes.length; i++) { readStringSized(); }

    readByte();
    final bpm = readInt();
    final beatsPerMeasure = readInt();
    final beatUnit = readInt();

    final numMeasures = readInt();
    final numTracks = readInt();

    for (int t = 0; t < numTracks && offset < bytes.length; t++) {
      readStringSized();
      readInt(); readInt(); readInt(); readInt(); readInt();
      readInt(); readInt(); readInt();
      readInt();
      offset += isGp3(bytes) ? 4 : 44;
      final numStrings = readInt();
      for (int s = 0; s < 7; s++) { readInt(); }
      readInt(); readInt(); readInt();
      readByte();
      offset += isGp3(bytes) ? 15 : 19;
      if (!isGp3(bytes)) {
        for (int s = 0; s < numStrings; s++) { readInt(); }
      }
    }

    final measures = _parseGpMeasures(bytes, offset, numMeasures, numTracks, bpm);

    if (measures.isEmpty) {
      final midiNotes = _scanMidiEvents(bytes);
      if (midiNotes.isNotEmpty) {
        return ScoreData(
          title: title.isEmpty ? path.split('\\').last.split('/').last : title,
          bpm: bpm.toDouble(),
          measures: [Measure(number: 1, notes: midiNotes, bpm: bpm.toDouble())],
        );
      }
    }

    return ScoreData(
      title: title.isEmpty ? path.split('\\').last.split('/').last : title,
      bpm: bpm.toDouble(),
      beatsPerMeasure: beatsPerMeasure,
      beatUnit: beatUnit,
      measures: measures,
    );
  }

  static bool isGp3(Uint8List bytes) {
    final header = String.fromCharCodes(bytes.take(30));
    return header.contains('v3.');
  }

  static List<Measure> _parseGpMeasures(Uint8List bytes, int startOffset, int numMeasures, int numTracks, int bpm) {
    final measures = <Measure>[];
    int offset = startOffset;

    int readByte() => offset < bytes.length ? bytes[offset++].toInt() & 0xFF : 0;

    if (isGp3(bytes)) {
      for (int m = 0; m < numMeasures && offset < bytes.length - 10; m++) {
        readByte();
        readByte();
        readByte();
        readByte();
        readByte();
        final numBeats = readByte();

        final measureNotes = <MusicNote>[];
        for (int b = 0; b < numBeats && offset < bytes.length - 2; b++) {
          final bFlags = readByte();
          if (bFlags == 0) continue;
          final duration = readByte();
          int numNotes = readByte();
          if (numNotes == 0) continue;

          for (int n = 0; n < numNotes && n < 6 && offset < bytes.length - 2; n++) {
            final noteFlags = readByte();
            if ((noteFlags & 0x01) != 0) {
              final string = readByte();
              final fret = readByte();
              if (string > 0 && string <= 6) {
                const defaults = [64, 59, 55, 50, 45, 40];
                final midi = defaults[string - 1] + fret;
                measureNotes.add(MusicNote(
                  midi: midi,
                  step: _midiToStep(midi),
                  octave: _midiToOctave(midi),
                  duration: duration,
                  fret: fret,
                  string: string,
                ));
              }
            }
            if ((noteFlags & 0x02) != 0) readByte();
            if ((noteFlags & 0x04) != 0) readByte();
            if ((noteFlags & 0x08) != 0) readByte();
            if ((noteFlags & 0x10) != 0) readByte();
            if ((noteFlags & 0x20) != 0) readByte();
          }
        }

        if (measureNotes.isNotEmpty) {
          measures.add(Measure(number: m + 1, notes: measureNotes, bpm: bpm.toDouble()));
        }
      }
      return measures;
    }

    const tuning = [64, 59, 55, 50, 45, 40];

    for (int t = 0; t < numTracks && offset < bytes.length - 2; t++) {
      for (int m = 0; m < numMeasures && offset < bytes.length - 2; m++) {
        final measureFlags = readByte();
        final measureNotes = <MusicNote>[];

        int numBeats;
        if ((measureFlags & 0x40) != 0) {
          int voiceCount = readByte();
          numBeats = 0;
          for (int v = 0; v < voiceCount && offset < bytes.length - 2; v++) {
            if (offset >= bytes.length - 2) break;
            int vb = readByte();
            numBeats += vb;
            for (int b = 0; b < vb && offset < bytes.length - 2; b++) {
              _readGp4Beat(bytes, offset, tuning, measureNotes, (n) => offset = n);
            }
          }
        } else {
          numBeats = measureFlags & 0x1F;
          for (int b = 0; b < numBeats && offset < bytes.length - 2; b++) {
            _readGp4Beat(bytes, offset, tuning, measureNotes, (n) => offset = n);
          }
        }

        if (measureNotes.isNotEmpty) {
          measures.add(Measure(number: m + 1, notes: measureNotes, bpm: bpm.toDouble()));
        }
      }
    }

    return measures;
  }

  static void _readGp4Beat(Uint8List bytes, int startOffset, List<int> tuning,
      List<MusicNote> outNotes, void Function(int) setOffset) {
    int offset = startOffset;

    int readByte() => offset < bytes.length ? bytes[offset++].toInt() & 0xFF : 0;

    final beatFlags = readByte();

    if ((beatFlags & 0x01) != 0) {
      readByte();
      readByte();
    }
    if ((beatFlags & 0x02) != 0) readByte();
    if ((beatFlags & 0x04) != 0) { readByte(); readByte(); readByte(); readByte(); }
    if ((beatFlags & 0x08) != 0) {
      int len = readByte();
      for (int i = 0; i < len && offset < bytes.length; i++) { readByte(); }
      len = readByte();
      for (int i = 0; i < len && offset < bytes.length; i++) { readByte(); }
      for (int i = 0; i < 7 && offset < bytes.length; i++) { readByte(); }
      for (int i = 0; i < 6 && offset < bytes.length; i++) { readByte(); }
    }
    if ((beatFlags & 0x10) != 0) {
      int len = readByte();
      for (int i = 0; i < len && offset < bytes.length; i++) { readByte(); }
    }
    if ((beatFlags & 0x20) != 0) {
      int ef = readByte();
      if ((ef & 0x10) != 0) readByte();
      if ((ef & 0x02) != 0) { readByte(); readByte(); }
      if ((ef & 0x20) != 0) { readByte(); readByte(); readByte(); }
      if ((ef & 0x40) != 0) readByte();
    }
    if ((beatFlags & 0x40) != 0) {
      readByte();
      for (int i = 0; i < 4 && offset < bytes.length; i++) {
        int idx = readByte();
        if (idx != -1) {
          readByte();
          if (offset < bytes.length && (bytes[offset] & 0x80) != 0) readByte();
        }
      }
    }
    if ((beatFlags & 0x80) != 0) {
      final stringFlags = <int>[];
      for (int s = 0; s < 6 && offset < bytes.length; s++) {
        stringFlags.add(readByte());
      }

      for (int s = 0; s < 6 && offset < bytes.length - 1; s++) {
        if (stringFlags[s] == 0) continue;

        final noteFlags = readByte();
        int fret = -1;
        if ((noteFlags & 0x08) != 0) {
          fret = readByte();
        }
        if ((noteFlags & 0x10) != 0) readByte();

        if (fret >= 0 && fret <= 24) {
          final stringNum = s + 1;
          final midi = tuning[stringNum - 1] + fret;
          outNotes.add(MusicNote(
            midi: midi,
            step: _midiToStep(midi),
            octave: _midiToOctave(midi),
            duration: 4,
            fret: fret,
            string: stringNum,
          ));
        }

        if ((noteFlags & 0x20) != 0) readByte();
        if ((noteFlags & 0x40) != 0) readByte();
        if ((noteFlags & 0x80) != 0) {
          int ef = readByte();
          if ((ef & 0x01) != 0) { readByte(); readByte(); readByte(); }
          if ((ef & 0x02) != 0) { readByte(); }
          if ((ef & 0x04) != 0) { readByte(); readByte(); readByte(); }
          if ((ef & 0x08) != 0) { readByte(); readByte(); }
          if ((ef & 0x10) != 0) { readByte(); readByte(); }
          if ((ef & 0x20) != 0) { readByte(); readByte(); readByte(); }
          if ((ef & 0x40) != 0) { for (int i = 0; i < 4 && offset < bytes.length; i++) { readByte(); } }
          if ((ef & 0x80) != 0) { readByte(); readByte(); readByte(); readByte(); }
        }
      }
    }

    setOffset(offset);
  }

  static List<MusicNote> _scanMidiEvents(Uint8List bytes) {
    final notes = <MusicNote>[];

    for (int i = 0; i < bytes.length - 3; i++) {
      if ((bytes[i] & 0xF0) == 0x90 &&
          bytes[i + 2] > 0 && bytes[i + 2] < 127 &&
          bytes[i + 1] > 0 && bytes[i + 1] < 128) {
        final midi = bytes[i + 1];
        notes.add(MusicNote(
          midi: midi,
          step: _midiToStep(midi),
          octave: _midiToOctave(midi),
          duration: 4,
          fret: 0,
          string: 1,
        ));
      }
    }

    const tuning = [64, 59, 55, 50, 45, 40];
    for (int i = 0; i < bytes.length - 2; i++) {
      if (bytes[i] >= 1 && bytes[i] <= 6 &&
          bytes[i + 1] >= 0 && bytes[i + 1] <= 24 &&
          bytes[i + 2] >= 0 && bytes[i + 2] <= 127) {
        final string = bytes[i];
        final fret = bytes[i + 1];
        final midi = tuning[string - 1] + fret;
        if (notes.every((n) => n.midi != midi)) {
          notes.add(MusicNote(
            midi: midi,
            step: _midiToStep(midi),
            octave: _midiToOctave(midi),
            duration: 4,
            fret: fret,
            string: string,
          ));
        }
      }
    }

    return notes;
  }

  static int _readInt(Uint8List bytes, int offset, int length) {
    int value = 0;
    for (int i = 0; i < length; i++) {
      if (offset + i < bytes.length) {
        value = (value << 8) | (bytes[offset + i] & 0xFF);
      }
    }
    return value;
  }

  static int _stepToMidi(String step, int octave) {
    const map = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
    return (octave + 1) * 12 + (map[step] ?? 0);
  }

  static String _midiToStep(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return names[midi % 12];
  }

  static int _midiToOctave(int midi) => (midi ~/ 12) - 1;
}
