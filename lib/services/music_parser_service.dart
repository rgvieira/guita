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
        return _parseMidi(path);
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

  static Future<ScoreData> _parseMidi(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return _parseMidiBytes(bytes, path);
    } catch (e) {
      return ScoreData(measures: []);
    }
  }

  // --- Internal MIDI helpers ---
  static int _read32BE(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return ((bytes[offset] & 0xFF) << 24) |
           ((bytes[offset + 1] & 0xFF) << 16) |
           ((bytes[offset + 2] & 0xFF) << 8) |
           (bytes[offset + 3] & 0xFF);
  }

  static int _read16BE(Uint8List bytes, int offset) {
    if (offset + 2 > bytes.length) return 0;
    return ((bytes[offset] & 0xFF) << 8) | (bytes[offset + 1] & 0xFF);
  }

  static ScoreData _parseMidiBytes(Uint8List bytes, String path) {
    int offset = 0;

    // Validate MIDI header
    if (offset + 14 > bytes.length) return ScoreData(measures: []);
    if (bytes[0] != 0x4D || bytes[1] != 0x54 || bytes[2] != 0x68 || bytes[3] != 0x64) {
      return ScoreData(measures: []); // not "MThd"
    }

    final headerLen = _read32BE(bytes, 4);
    offset = 8;
    if (headerLen < 6) return ScoreData(measures: []);

    // format (ignored), numTracks, division
    _read16BE(bytes, offset); offset += 2; // format
    final numTracks = _read16BE(bytes, offset); offset += 2;
    final rawDivision = _read16BE(bytes, offset); offset += 2;
    offset += (headerLen - 6); // skip extra header bytes

    final int ticksPerQuarterNote;
    if ((rawDivision & 0x8000) != 0) {
      ticksPerQuarterNote = 480; // SMPTE fallback
    } else {
      ticksPerQuarterNote = rawDivision & 0x7FFF;
    }

    // Defaults
    int microPerQuarter = 500000;
    int numerator = 4;
    int denominator = 4;
    // Track data
    final allNotes = <_RawNote>[];
    final lyrics = <StringBuffer>[];
    final tempoEvents = <_TempoEvent>[];
    final timeSigEvents = <_TimeSigEvent>[];
    final channelPrograms = <int, int>{};
    tempoEvents.add(_TempoEvent(0, microPerQuarter));
    timeSigEvents.add(_TimeSigEvent(0, numerator, denominator));
    String title = path.split('\\').last.split('/').last.replaceAll(RegExp(r'\.(mid|midi|kar)$', caseSensitive: false), '');

    // Parse each track
    for (int t = 0; t < numTracks && offset + 8 <= bytes.length; t++) {
      // Track header
      if (bytes[offset] != 0x4D || bytes[offset + 1] != 0x54 ||
          bytes[offset + 2] != 0x72 || bytes[offset + 3] != 0x6B) {
        break; // not "MTrk"
      }
      offset += 4;
      final trackLen = _read32BE(bytes, offset); offset += 4;
      final trackEnd = (offset + trackLen).clamp(0, bytes.length);

      int currentTick = 0;
      int runningStatus = 0;

      while (offset < trackEnd) {
        if (offset >= bytes.length) break;

        // Read delta-time VLQ
        int delta = 0;
        {
          int shift = 0;
          while (offset < bytes.length) {
            final b = bytes[offset++];
            delta = (delta << 7) | (b & 0x7F);
            shift += 7;
            if ((b & 0x80) == 0) break;
            if (shift > 28) { delta = 0; break; }
          }
        }
        currentTick += delta;

        if (offset >= trackEnd) break;

        int status = bytes[offset];

        // --- Meta event (FF xx) ---
        if (status == 0xFF) {
          offset++;
          if (offset >= trackEnd) break;
          final metaType = bytes[offset++];
          // Read VLQ for meta data length (manually, tracking offset)
          int metaLen = 0;
          {
            int shift = 0;
            while (offset < trackEnd) {
              final b = bytes[offset++];
              metaLen = (metaLen << 7) | (b & 0x7F);
              shift += 7;
              if ((b & 0x80) == 0) break;
              if (shift > 28) { metaLen = 0; break; }
            }
          }
          if (metaLen < 0 || offset + metaLen > trackEnd) { offset = trackEnd; continue; }
          final metaStart = offset;
          offset += metaLen;

          switch (metaType) {
            case 0x00: break; // Sequence Number
            case 0x01: // Text
              break;
            case 0x02: break; // Copyright
            case 0x03: // Track Name
              if (metaLen > 0 && t == 0) {
                final name = String.fromCharCodes(bytes.sublist(metaStart, metaStart + metaLen)).trim();
                if (name.isNotEmpty) title = name;
              }
              break;
            case 0x04: break; // Instrument
            case 0x05: // Lyric (KAR)
              if (metaLen > 0) {
                final line = String.fromCharCodes(bytes.sublist(metaStart, metaStart + metaLen)).trim();
                if (line.isNotEmpty) {
                  if (lyrics.length <= t) lyrics.add(StringBuffer());
                  if (t < lyrics.length) {
                    if (lyrics[t].isNotEmpty) lyrics[t].write(' ');
                    lyrics[t].write(line);
                  }
                }
              }
              break;
            case 0x51: // Tempo (FF 51 03 tt tt tt)
              if (metaLen >= 3) {
                microPerQuarter = (bytes[metaStart] << 16) |
                                  (bytes[metaStart + 1] << 8) |
                                  bytes[metaStart + 2];
                tempoEvents.add(_TempoEvent(currentTick, microPerQuarter));
              }
              break;
            case 0x58: // Time Signature (FF 58 04 nn dd cc bb)
              if (metaLen >= 4) {
                numerator = bytes[metaStart];
                denominator = 1 << bytes[metaStart + 1];
                timeSigEvents.add(_TimeSigEvent(currentTick, numerator, denominator));
              }
              break;
            case 0x59: break; // Key Signature
            case 0x2F: break; // End of Track
            default: break;
          }
          continue;
        }

        // --- Running status ---
        if (status < 0x80) {
          offset--;
          status = runningStatus;
        } else {
          offset++;
          runningStatus = status;
        }

        if ((status & 0xF0) == 0x90) {
          // Note On
          if (offset + 1 >= trackEnd) break;
          final note = bytes[offset++];
          final velocity = bytes[offset++];
          if (velocity > 0 && note < 128) {
            allNotes.add(_RawNote(
              midi: note,
              tickStart: currentTick,
              tickEnd: -1,
              channel: status & 0x0F,
              velocity: velocity,
            ));
          }
        } else if ((status & 0xF0) == 0x80) {
          // Note Off - match with note-on to set end tick
          if (offset + 1 >= trackEnd) break;
          final note = bytes[offset++];
          offset++; // skip velocity
          if (note < 128) {
            for (int i = allNotes.length - 1; i >= 0; i--) {
              if (allNotes[i].midi == note &&
                  allNotes[i].channel == (status & 0x0F) &&
                  allNotes[i].tickEnd < 0) {
                allNotes[i].tickEnd = currentTick;
                break;
              }
            }
          }
        } else if ((status & 0xF0) == 0xA0) {
          // Polyphonic Aftertouch
          if (offset + 1 < trackEnd) offset += 2;
        } else if ((status & 0xF0) == 0xB0) {
          // Control Change
          if (offset + 1 < trackEnd) offset += 2;
        } else if ((status & 0xF0) == 0xC0) {
          // Program Change
          if (offset < trackEnd) {
            final program = bytes[offset++];
            channelPrograms[status & 0x0F] = program;
          }
        } else if ((status & 0xF0) == 0xD0) {
          // Channel Aftertouch
          if (offset < trackEnd) offset++;
        } else if ((status & 0xF0) == 0xE0) {
          // Pitch Bend
          if (offset + 1 < trackEnd) offset += 2;
        } else if (status == 0xF0 || status == 0xF7) {
          // System Exclusive - skip until 0xF7
          offset = _skipSysEx(bytes, offset, trackEnd);
        } else {
          if (offset < trackEnd) offset++;
        }
      }

      offset = trackEnd;
    }

    // Sort all notes by tick
    allNotes.sort((a, b) => a.tickStart.compareTo(b.tickStart));

    // Sort event lists by tick (should already be in order, but ensure it)
    tempoEvents.sort((a, b) => a.tick.compareTo(b.tick));
    timeSigEvents.sort((a, b) => a.tick.compareTo(b.tick));

    // Helper: compute elapsed ms at given tick using tempo map
    double computeMsAtTick(int tick) {
      if (ticksPerQuarterNote <= 0) return tick * 0.5;
      double elapsedMs = 0;
      int prevTick = 0;
      int prevMicroPQ = 500000;
      for (final ev in tempoEvents) {
        if (ev.tick >= tick) break;
        if (ev.tick > prevTick) {
          final ticks = ev.tick - prevTick;
          elapsedMs += ticks * (prevMicroPQ / ticksPerQuarterNote / 1000.0);
        }
        prevTick = ev.tick;
        prevMicroPQ = ev.microPerQuarter;
      }
      if (tick > prevTick) {
        final ticks = tick - prevTick;
        elapsedMs += ticks * (prevMicroPQ / ticksPerQuarterNote / 1000.0);
      }
      return elapsedMs;
    }

    // Helper: find the time sig values active at a given tick
    _TimeSigEvent timeSigAt(int tick) {
      _TimeSigEvent? sig;
      for (final s in timeSigEvents) {
        if (s.tick <= tick) sig = s;
      }
      return sig ?? timeSigEvents.first;
    }

    // Group notes into measures using per-note tempo & time sig
    final Map<int, List<MusicNote>> measureMap = {};

    for (final raw in allNotes) {
      final startMs = computeMsAtTick(raw.tickStart);
      final endMs = raw.tickEnd >= 0 && raw.tickEnd > raw.tickStart
          ? computeMsAtTick(raw.tickEnd)
          : startMs + 200.0;

      final sig = timeSigAt(raw.tickStart);
      final ticksPerMeasure = ticksPerQuarterNote * sig.numerator;
      final measureNum = ticksPerMeasure > 0
          ? (raw.tickStart ~/ ticksPerMeasure) + 1
          : 1;

      final durBeats = ticksPerQuarterNote > 0
          ? ((raw.tickEnd - raw.tickStart) / ticksPerQuarterNote)
          : 0.25;
      final duration = (durBeats * 4).round().clamp(1, 16);

      measureMap.putIfAbsent(measureNum, () => []);
      measureMap[measureNum]!.add(MusicNote(
        midi: raw.midi,
        step: _midiToStep(raw.midi),
        octave: _midiToOctave(raw.midi),
        duration: duration,
        startTime: startMs,
        endTime: endMs,
        channel: raw.channel,
      ));
    }

    final sortedKeys = measureMap.keys.toList()..sort();
    final firstSig = timeSigEvents.isNotEmpty ? timeSigEvents.first : _TimeSigEvent(0, 4, 4);
    final firstTempo = tempoEvents.isNotEmpty ? tempoEvents.first : _TempoEvent(0, 500000);
    final initialBpm = 60000000.0 / firstTempo.microPerQuarter;

    final measures = sortedKeys.map((k) =>
      Measure(number: k, notes: measureMap[k]!, bpm: initialBpm)
    ).toList();

    return ScoreData(
      title: title,
      bpm: initialBpm,
      beatsPerMeasure: firstSig.numerator,
      beatUnit: firstSig.denominator,
      measures: measures,
      channelPrograms: channelPrograms,
    );
  }

  static int _skipSysEx(Uint8List bytes, int start, int trackEnd) {
    int offset = start;
    while (offset < trackEnd) {
      if (bytes[offset] == 0xF7) return offset + 1;
      offset++;
    }
    return offset;
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

    // --- Header ---
    final versionBytes = <int>[];
    while (offset < bytes.length && bytes[offset] != 0) {
      versionBytes.add(bytes[offset]);
      offset++;
    }
    offset++;
    // ignore: unused_local_variable
    final version = String.fromCharCodes(versionBytes);

    // --- Song info ---
    final title = readStringSized();
    readStringSized(); // artist
    readStringSized(); // album
    readStringSized(); // author
    readStringSized(); // copyright
    readStringSized(); // tab author
    readStringSized(); // instructions

    final noticeLines = readInt();
    for (int i = 0; i < noticeLines && offset < bytes.length; i++) { readStringSized(); }

    readByte(); // triplet feel
    final bpm = readInt();
    readInt(); // beats per measure
    readInt(); // beat unit

    final numMeasures = readInt();
    final numTracks = readInt();

    // Skip track definitions (we only need MIDI data)
    for (int t = 0; t < numTracks && offset < bytes.length; t++) {
      readStringSized(); // name
      readInt(); readInt(); readInt(); readInt(); readInt();
      readInt(); readInt(); readInt();
      readInt(); // instrument
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

    // --- Try to parse measures ---
    final measures = _parseGpMeasures(bytes, offset, numMeasures, numTracks, bpm);

    // --- If no measures found, scan raw bytes aggressively ---
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
      // GP3: flat measure-by-measure format
      for (int m = 0; m < numMeasures && offset < bytes.length - 10; m++) {
        readByte(); // flags
        readByte(); // numerator
        readByte(); // denominator
        readByte(); // begin repeat
        readByte(); // end repeat
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

    // ---- GP4/5 ----
    // Step 1: Skip all measure headers (flags-based variable structure)
    for (int m = 0; m < numMeasures && offset < bytes.length - 1; m++) {
      final flags = readByte();
      if ((flags & 0x01) != 0) readByte(); // numerator
      if ((flags & 0x02) != 0) readByte(); // denominator
      if ((flags & 0x04) != 0) readByte(); // begin repeat
      if ((flags & 0x08) != 0) readByte(); // end repeat
      if ((flags & 0x10) != 0) readByte(); // repeat count
      if ((flags & 0x20) != 0) readByte(); // alternate ending
      if ((flags & 0x40) != 0) {
        // marker
        int len = readByte();
        for (int i = 0; i < len && offset < bytes.length; i++) { readByte(); }
        len = readByte();
        for (int i = 0; i < len && offset < bytes.length; i++) { readByte(); }
      }
      if ((flags & 0x80) != 0) {
        readByte(); // key signature
        readByte(); // tonality
      }
    }

    // Step 2: Read per-track, per-measure beat/note data
    const tuning = [64, 59, 55, 50, 45, 40]; // E4 B3 G3 D3 A2 E2 (standard)

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
      readByte(); // duration value
      readByte(); // dotted/tuplet flags
    }
    if ((beatFlags & 0x02) != 0) readByte(); // dynamic
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
      // Match any MIDI note-on (channel 0-15)
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

    // Also scan for potential GP-encoded string+fret pairs
    const tuning = [64, 59, 55, 50, 45, 40];
    for (int i = 0; i < bytes.length - 2; i++) {
      // Look for consecutive (string, fret) bytes
      if (bytes[i] >= 1 && bytes[i] <= 6 &&
          bytes[i + 1] >= 0 && bytes[i + 1] <= 24 &&
          bytes[i + 2] >= 0 && bytes[i + 2] <= 127) {
        final string = bytes[i];
        final fret = bytes[i + 1];
        final midi = tuning[string - 1] + fret;
        // Avoid duplicates from the MIDI scan
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

class _RawNote {
  final int midi;
  final int tickStart;
  int tickEnd;
  final int channel;
  final int velocity;

  _RawNote({
    required this.midi,
    required this.tickStart,
    required this.tickEnd,
    required this.channel,
    required this.velocity,
  });
}

class _TempoEvent {
  final int tick;
  final int microPerQuarter;

  _TempoEvent(this.tick, this.microPerQuarter);
}

class _TimeSigEvent {
  final int tick;
  final int numerator;
  final int denominator;

  _TimeSigEvent(this.tick, this.numerator, this.denominator);
}
