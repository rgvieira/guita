import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/music_note.dart';
import '../services/audio_effects_service.dart';
import '../services/music_parser_service.dart';
import '../services/midi_player_service.dart';
import '../rendering/engraver_engine.dart';
import 'midi_visualizer.dart';

class MidiScoreView extends StatefulWidget {
  final String filePath;
  final void Function(List<int> channels)? onChannelsLoaded;
  final void Function(int current, int total, String name)? onTrackChanged;
  final void Function(String error)? onError;
  final void Function(int state)? onPlayerStateChanged;
  final AudioEffectsService? effectsService;

  const MidiScoreView({
    super.key,
    required this.filePath,
    this.onChannelsLoaded,
    this.onTrackChanged,
    this.onError,
    this.onPlayerStateChanged,
    this.effectsService,
  });

  @override
  State<MidiScoreView> createState() => MidiScoreViewState();
}

class MidiScoreViewState extends State<MidiScoreView> {
  ScoreData? _data;
  List<int> _channels = [];
  final Map<int, String> _channelNames = {};
  int _selectedChannel = 0;
  bool _isHorizontal = false;
  double _scale = 1.0;
  String? _error;
  final MidiPlayerService _player = MidiPlayerService();
  bool _isPlaying = false;
  int _currentNoteIndex = -1;
  Timer? _playTimer;
  List<MusicNote> _playableNotes = [];
  List<MusicNote> _allPlayableNotes = [];
  final TransformationController _transformationController =
      TransformationController();
  final Set<int> _activeMidiNotes = {};

  Map<int, String> get channelNames => Map.unmodifiable(_channelNames);
  Set<int> get activeMidiNotes => _activeMidiNotes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MidiScoreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filePath != oldWidget.filePath) {
      _stop();
      _data = null;
      _channels = [];
      _selectedChannel = 0;
      _error = null;
      _playableNotes = [];
      _allPlayableNotes = [];
      _currentNoteIndex = -1;
      _transformationController.value = Matrix4.identity();
      _load();
    }
  }

  @override
  void dispose() {
    _isPlaying = false;
    _playTimer?.cancel();
    _playTimer = null;
    _player.allNotesOff();
    _currentNoteIndex = -1;
    _activeMidiNotes.clear();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await MusicParserService.parseFile(widget.filePath);
      if (!mounted) return;
      if (data.measures.isEmpty) {
        setState(() => _error = 'Nenhuma nota encontrada');
        return;
      }
      _data = data;
      final channels = data.allNotes
          .map((n) => n.channel)
          .toSet()
          .toList()
        ..sort();
      _channels = channels;
      _channelNames.clear();
      for (final ch in channels) {
        if (data.channelNames.containsKey(ch) && data.channelNames[ch]!.isNotEmpty) {
          _channelNames[ch] = data.channelNames[ch]!;
        } else {
          final prog = data.channelPrograms[ch];
          if (prog != null) {
            _channelNames[ch] = data.instrumentName(prog);
          } else {
            _channelNames[ch] = 'Canal $ch';
          }
        }
      }
      _selectedChannel = channels.isNotEmpty ? channels.first : 0;
      _updatePlayableNotes();
      setState(() {});
      widget.onChannelsLoaded?.call(channels);
      if (channels.isNotEmpty) {
        widget.onTrackChanged?.call(
          0, channels.length, _channelNames[channels.first] ?? 'Canal ${channels.first}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Erro ao processar: $e');
        widget.onError?.call('Erro ao processar: $e');
      }
    }
  }

  void _updatePlayableNotes() {
    if (_data == null) return;
    // All channels for playback
    _allPlayableNotes = _data!.allNotes
        .where((n) => !n.isRest)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    // Selected channel for display
    _playableNotes = _allPlayableNotes
        .where((n) => n.channel == _selectedChannel)
        .toList();
  }

  void setChannel(int channel) {
    setState(() {
      _selectedChannel = channel;
      _updatePlayableNotes();
      _currentNoteIndex = -1;
      _transformationController.value = Matrix4.identity();
    });
  }

  void nextChannel() {
    final idx = _channels.indexOf(_selectedChannel);
    if (idx < _channels.length - 1) {
      final next = _channels[idx + 1];
      setChannel(next);
    }
  }

  void prevChannel() {
    final idx = _channels.indexOf(_selectedChannel);
    if (idx > 0) {
      final prev = _channels[idx - 1];
      setChannel(prev);
    }
  }

  void toggleLayout() {
    setState(() {
      _isHorizontal = !_isHorizontal;
      _transformationController.value = Matrix4.identity();
    });
  }

  Future<Uint8List> printScore() async {
    if (_data == null || _data!.measures.isEmpty) return Uint8List(0);
    final doc = pw.Document();
    // Only include measures that have notes from the selected channel
    final filteredMeasures = _data!.measures
        .where((m) => m.notes.any((n) => n.channel == _selectedChannel))
        .toList();
    if (filteredMeasures.isEmpty) return Uint8List(0);
    // Renumber sequentially for clean output
    for (int i = 0; i < filteredMeasures.length; i++) {
      filteredMeasures[i] = Measure(
        number: i + 1,
        notes: filteredMeasures[i].notes,
        bpm: filteredMeasures[i].bpm,
      );
    }

    final pageFormat = PdfPageFormat.a4;
    const mw = MidiScoreCanvas.measureWidth;
    final sh = MidiScoreCanvas.systemHeight;
    const sm = MidiScoreCanvas.systemMargin;
    const leftMargin = MidiScoreCanvas.leftMargin;
    const clefSpace = MidiScoreCanvas.clefSpace;

    final pageW = pageFormat.width - 40;
    final pageH = pageFormat.height - 40;
    final barsPerRow = ((pageW - leftMargin - clefSpace - 20) / mw).floor().clamp(1, 16).toInt();
    final rowsPerPage = (pageH / (sh + sm)).floor().clamp(1, 99).toInt();
    final measuresPerPage = barsPerRow * rowsPerPage;
    final totalPages = (filteredMeasures.length / measuresPerPage).ceil().clamp(1, 999);

    for (int p = 0; p < totalPages; p++) {
      final start = p * measuresPerPage;
      final end = (start + measuresPerPage).clamp(0, filteredMeasures.length).toInt();
      final pageMeasures = filteredMeasures.sublist(start, end);
      final rows = (pageMeasures.length / barsPerRow).ceil().clamp(1, rowsPerPage).toInt();
      final size = Size(pageW, rows * (sh + sm) + sm);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = MidiScoreCanvas(
        measures: pageMeasures,
        beatsPerMeasure: _data!.beatsPerMeasure,
        beatUnit: _data!.beatUnit,
        channelFilter: _selectedChannel,
        isHorizontal: false,
        scale: 1.0,
        highlightNoteIndex: -1,
        playableNotes: const [],
      );
      painter.paint(canvas, size);
      final picture = recorder.endRecording();
      final w = size.width.toInt().clamp(1, 10000);
      final h = size.height.toInt().clamp(1, 10000);
      final image = await picture.toImage(w, h);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        doc.addPage(pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) => pw.Image(
            pw.MemoryImage(byteData.buffer.asUint8List()),
            fit: pw.BoxFit.contain,
          ),
        ));
      }
      picture.dispose();
    }
    return doc.save();
  }

  Widget _scrollButton(IconData icon, double delta) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: Colors.brown.shade100.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            final matrix = _transformationController.value;
            final tx = matrix.entry(0, 3);
            final ty = matrix.entry(1, 3);
            final m = Matrix4.identity();
            m.setEntry(0, 0, matrix.entry(0, 0));
            m.setEntry(1, 1, matrix.entry(1, 1));
            m.setTranslationRaw(tx, ty + delta, 0);
            _transformationController.value = m;
          },
          child: Icon(icon, size: 20, color: Colors.brown[700]),
        ),
      ),
    );
  }

  void _scrollToNote(int noteIndex) {
    if (_data == null ||
        noteIndex < 0 ||
        noteIndex >= _playableNotes.length) {
      return;
    }
    final note = _playableNotes[noteIndex];
    final measures = _data!.measures;

    int measureIdx = 0;
    for (int i = 0; i < measures.length; i++) {
      if (measures[i].notes.contains(note)) {
        measureIdx = i;
        break;
      }
    }

    final leftMargin = MidiScoreCanvas.leftMargin;
    final clefSpace = MidiScoreCanvas.clefSpace;
    final mw = MidiScoreCanvas.measureWidth;
    final sh = MidiScoreCanvas.systemHeight;
    final sm = MidiScoreCanvas.systemMargin;

    final screenWidth = MediaQuery.of(context).size.width;
    final barsPerRow = ((screenWidth - 60) / mw).floor().clamp(1, 16);

    double noteFrac = 0.5;
    final measure = measures[measureIdx];
    final measureNotes = measure.notes
        .where((n) => n.channel == _selectedChannel && !n.isRest)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (measureNotes.length > 1) {
      final bpm = measure.bpm > 0 ? measure.bpm : 120.0;
      final beatMs = 60000 / bpm;
      final firstTime = measureNotes.first.startTime;
      final beatsFromStart = (note.startTime - firstTime) / beatMs;
      noteFrac = (beatsFromStart / _data!.beatsPerMeasure).clamp(0.0, 1.0);
    }
    final noteOffsetInMeasure = 4 + noteFrac * (mw - 8);

    double noteX, noteY;
    if (_isHorizontal) {
      final staffY = sm + 20;
      noteX = 10 + leftMargin + clefSpace + measureIdx * mw + noteOffsetInMeasure;
      noteY = staffY + MidiScoreCanvas.staffHeight / 2;
    } else {
      final row = measureIdx ~/ barsPerRow;
      final col = measureIdx % barsPerRow;
      final rowWidth = barsPerRow * mw + leftMargin + 20;
      final offsetX = (screenWidth - rowWidth) / 2;
      noteX = offsetX + leftMargin + clefSpace + col * mw + noteOffsetInMeasure;
      noteY = sm + row * (sh + sm) + MidiScoreCanvas.staffHeight / 2;
    }

    final viewSize = context.size ?? Size(400, 400);
    final current = _transformationController.value;
    final sx = current.entry(0, 0);

    final tx = viewSize.width / 2 - noteX * sx;
    final ty = viewSize.height / 2 - noteY * sx;

    final matrix = Matrix4.identity();
    matrix.setEntry(0, 0, sx);
    matrix.setEntry(1, 1, sx);
    matrix.setTranslationRaw(tx, ty, 0);
    _transformationController.value = matrix;
  }

  void zoomIn() => setState(() => _scale = (_scale * 1.2).clamp(0.5, 4.0));
  void zoomOut() => setState(() => _scale = (_scale / 1.2).clamp(0.5, 4.0));

  Future<void> play() async {
    if (_allPlayableNotes.isEmpty) return;
    _stop();
    _isPlaying = true;
    _currentNoteIndex = -1;
    widget.onPlayerStateChanged?.call(1);
    await _player.init();

    // Group ALL notes by startTime (chords across all channels)
    final groups = <List<MusicNote>>[];
    for (final n in _allPlayableNotes) {
      if (groups.isEmpty || (n.startTime - groups.last.first.startTime) > 5.0) {
        groups.add([n]);
      } else {
        groups.last.add(n);
      }
    }

    // Pre-roll: small delay to ensure UI updates before audio starts
    await Future.delayed(const Duration(milliseconds: 50));

    DateTime prevTime = DateTime.now();
    double prevStartTime = groups.first.first.startTime;

    for (int gi = 0; gi < groups.length && _isPlaying; gi++) {
      final group = groups[gi];
      final currentTime = group.first.startTime;

      // Compute wait based on real elapsed time (drift-proof)
      if (gi > 0) {
        final expectedDelta = currentTime - prevStartTime;
        final actualElapsed = DateTime.now().difference(prevTime).inMilliseconds.toDouble();
        final remaining = (expectedDelta - actualElapsed).round().clamp(1, 300000);
        await Future.delayed(Duration(milliseconds: remaining));
        if (!_isPlaying) break;
      }

      // Fire all noteOns concurrently for simultaneous chord playback
      final now = DateTime.now();
      final effects = widget.effectsService;
      final noteMidis = group.map((n) => n.midi).toList();

      // Apply distortion via velocity clamping
      final velocities = group.map((n) {
        if (effects != null && effects.distortionDrive > 0) {
          return effects.applyDistortion(n.velocity);
        }
        return n.velocity;
      }).toList();

      await Future.wait(List.generate(noteMidis.length,
        (i) => _player.noteOn(noteMidis[i], velocity: velocities[i])));

      // Track active notes for visualizer
      setState(() => _activeMidiNotes.addAll(noteMidis));

      // Schedule note-off per note
      for (int ni = 0; ni < group.length; ni++) {
        final note = group[ni];
        final m = noteMidis[ni];
        final dur = (note.endTime - note.startTime).round().clamp(30, 60000);
        unawaited(Future.delayed(
          Duration(milliseconds: dur),
          () {
            if (_isPlaying) {
              _player.noteOff(m);
              setState(() => _activeMidiNotes.remove(m));
            }
          },
        ));
      }

      // Delay effect: schedule delayed copies with feedback
      if (effects != null && effects.delayMs > 0 && effects.delayFeedback > 0) {
        for (int rep = 1; rep <= 3; rep++) {
          final delay = effects.delayMs * rep;
          final fbVel = (100 * effects.delayFeedback * (1 - rep * 0.25)).round().clamp(1, 100);
          unawaited(Future.delayed(Duration(milliseconds: delay), () {
            if (!_isPlaying) return;
            for (int ni = 0; ni < noteMidis.length; ni++) {
              _player.noteOn(noteMidis[ni], velocity: fbVel);
              _player.noteOff(noteMidis[ni]);
            }
          }));
        }
      }

      // Update highlight - find matching note in selected channel
      final matching = _playableNotes.cast<MusicNote?>().firstWhere(
        (n) => n!.startTime == currentTime,
        orElse: () => null,
      );
      if (matching != null) {
        final idx = _playableNotes.indexOf(matching);
        setState(() => _currentNoteIndex = idx);
        _scrollToNote(idx);
      }

      prevTime = now;
      prevStartTime = currentTime;
    }

    _isPlaying = false;
    _currentNoteIndex = -1;
    await _player.allNotesOff();
    if (mounted) {
      setState(() {});
      widget.onPlayerStateChanged?.call(0);
    }
  }

  void _stop() {
    _isPlaying = false;
    _playTimer?.cancel();
    _playTimer = null;
    _player.allNotesOff();
    _currentNoteIndex = -1;
    _activeMidiNotes.clear();
    if (mounted) setState(() {});
  }

  void pause() {
    _stop();
    widget.onPlayerStateChanged?.call(0);
  }

  bool get isPlaying => _isPlaying;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final measures = _data!.measures;
    if (measures.isEmpty) {
      return const Center(child: Text('Nenhum compasso para exibir'));
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    const step = 100.0;
                    final matrix = _transformationController.value;
                    final tx = matrix.entry(0, 3);
                    final ty = matrix.entry(1, 3);
                    double dx = 0, dy = 0;
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) { dy = step; }
                    else if (event.logicalKey == LogicalKeyboardKey.arrowDown) { dy = -step; }
                    else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) { dx = step; }
                    else if (event.logicalKey == LogicalKeyboardKey.arrowRight) { dx = -step; }
                    else if (event.logicalKey == LogicalKeyboardKey.pageUp) { dy = step * 4; }
                    else if (event.logicalKey == LogicalKeyboardKey.pageDown) { dy = -step * 4; }
                    if (dx != 0 || dy != 0) {
                      final m = Matrix4.identity();
                      m.setEntry(0, 0, matrix.entry(0, 0));
                      m.setEntry(1, 1, matrix.entry(1, 1));
                      m.setTranslationRaw(tx + dx, ty + dy, 0);
                      _transformationController.value = m;
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  constrained: !_isHorizontal,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: CustomPaint(
                    size: _computeCanvasSize(measures),
                    painter: MidiScoreCanvas(
                      measures: measures,
                      beatsPerMeasure: _data!.beatsPerMeasure,
                      beatUnit: _data!.beatUnit,
                      channelFilter: _selectedChannel,
                      isHorizontal: _isHorizontal,
                      scale: _scale,
                      highlightNoteIndex: _currentNoteIndex,
                      playableNotes: _playableNotes,
                    ),
                  ),
                ),
              ),
              // Scroll buttons overlay
              Positioned(
                right: 8,
                bottom: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _scrollButton(Icons.keyboard_arrow_up, 150),
                    const SizedBox(height: 4),
                    _scrollButton(Icons.keyboard_arrow_down, -150),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_isPlaying)
          MidiVisualizer(
            key: ValueKey('visualizer_$_isPlaying'),
            isPlaying: _isPlaying,
            activeMidiNotes: _activeMidiNotes,
          ),
      ],
    );
  }

  Size _computeCanvasSize(List<Measure> measures) {
    const mw = MidiScoreCanvas.measureWidth;
    final sh = MidiScoreCanvas.systemHeight;
    const sm = MidiScoreCanvas.systemMargin;
    if (_isHorizontal) {
      return Size(measures.length * mw + 80, sh + sm);
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final barsPerRow = ((screenWidth - 60) / mw).floor().clamp(1, 16);
    final rows = (measures.length / barsPerRow).ceil().clamp(1, 999);
    return Size(screenWidth - 4, rows * (sh + sm) + sm);
  }
}

class MidiScoreCanvas extends CustomPainter {
  final List<Measure> measures;
  final int beatsPerMeasure;
  final int beatUnit;
  final int channelFilter;
  final bool isHorizontal;
  final double scale;
  final int highlightNoteIndex;
  final List<MusicNote> playableNotes;

  static const double lineSpacing = 8;
  static const double measureWidth = 120;
  static const double staffTop = 40;
  static const double leftMargin = 30;
  static const double systemMargin = 24;
  static const double clefSpace = 20;

  static double get staffBottom => staffTop + 4 * lineSpacing;
  static double get staffHeight => 4 * lineSpacing;
  static double get systemHeight => staffBottom + 16;

  MidiScoreCanvas({
    required this.measures,
    this.beatsPerMeasure = 4,
    this.beatUnit = 4,
    this.channelFilter = -1,
    this.isHorizontal = false,
    this.scale = 1.0,
    this.highlightNoteIndex = -1,
    this.playableNotes = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    final paint = Paint()
      ..color = const Color(0xFF5D4037)
      ..strokeWidth = 1.0;

    if (isHorizontal) {
      _drawHorizontalLayout(canvas, size, paint);
    } else {
      _drawVerticalLayout(canvas, size, paint);
    }

    canvas.restore();
  }

  void _drawStaff(Canvas canvas, double x, double y, double width, Paint paint) {
    for (int i = 0; i < 5; i++) {
      final ly = y + i * lineSpacing;
      canvas.drawLine(Offset(x, ly), Offset(x + width, ly), paint);
    }
  }

  void _drawClef(Canvas canvas, double x, double y) {
    final tp = TextPainter(
      text: const TextSpan(
        text: '\u{1D11E}', // treble clef
        style: TextStyle(fontSize: 28, color: Color(0xFF5D4037)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x + 2, y - 6));
  }

  void _drawTimeSignature(Canvas canvas, double x, double y) {
    final tp = TextPainter(
      text: TextSpan(
        text: '$beatsPerMeasure\n$beatUnit',
        style: const TextStyle(fontSize: 11, color: Color(0xFF5D4037), height: 1.1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y + 4));
  }

  void _drawMeasureBar(Canvas canvas, double x, double y, Paint paint) {
    canvas.drawLine(
      Offset(x, y - 4),
      Offset(x, y + 4 * lineSpacing + 4),
      paint..strokeWidth = 1.2,
    );
  }

  void _drawFinalBar(Canvas canvas, double x, double y, Paint paint) {
    canvas.drawLine(
      Offset(x - 2, y - 4),
      Offset(x - 2, y + 4 * lineSpacing + 4),
      paint..strokeWidth = 2.0,
    );
    canvas.drawLine(
      Offset(x + 1, y - 4),
      Offset(x + 1, y + 4 * lineSpacing + 4),
      paint..strokeWidth = 1.0,
    );
  }

  void _drawNote(
      Canvas canvas, double x, double y, MusicNote note, int idx,
      {bool isHighlight = false, double accidentalOffset = 0, bool drawAccidental = true, bool suppressFlag = false}) {
    const noteHeadW = 9.0;
    const noteHeadH = 6.5;

    final pos = _notePosition(note);
    final ny = _noteY(y, pos);
    final isHalf = note.duration >= 8 && note.duration < 16;
    final isShort = note.duration <= 2;
    final isWhole = note.duration >= 16;
    final stemUp = pos > 4;
    final stemLen = lineSpacing * 3.5;

    // Ledger lines
    if (pos <= 0) {
      for (int l = (pos <= -2 ? 0 : 0); l >= pos; l -= 2) {
        final ly = _noteY(y, l);
        canvas.drawLine(
          Offset(x - noteHeadW - 2, ly),
          Offset(x + noteHeadW + 2, ly),
          Paint()..color = const Color(0xFF5D4037)..strokeWidth = 0.8,
        );
      }
    } else if (pos >= 8) {
      for (int l = 8; l <= pos; l += 2) {
        final ly = _noteY(y, l);
        canvas.drawLine(
          Offset(x - noteHeadW - 2, ly),
          Offset(x + noteHeadW + 2, ly),
          Paint()..color = const Color(0xFF5D4037)..strokeWidth = 0.8,
        );
      }
    }

    // Accidental (only if drawAccidental is true)
    if (drawAccidental && note.step.length > 1) {
      final acc = note.step[1];
      if (acc == '#') {
        final tp = TextPainter(
          text: const TextSpan(
              text: '\u{266F}',
              style: TextStyle(fontSize: 10, color: Color(0xFF5D4037))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - noteHeadW - tp.width - 3 + accidentalOffset, ny - tp.height / 2));
      } else if (acc == 'b') {
        final tp = TextPainter(
          text: const TextSpan(
              text: '\u{266D}',
              style: TextStyle(fontSize: 10, color: Color(0xFF5D4037))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - noteHeadW - tp.width - 3 + accidentalOffset, ny - tp.height / 2));
      }
    }

    // Highlight background
    if (isHighlight) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, ny), width: noteHeadW * 1.6, height: noteHeadH * 1.6),
        Paint()..color = Colors.orange,
      );
    }

    // Whole note: hollow oval, no stem
    if (isWhole) {
      _drawNoteHead(canvas, x, ny, noteHeadW, noteHeadH, isFilled: false);
      return;
    }

    // Note head
    _drawNoteHead(canvas, x, ny, noteHeadW, noteHeadH, isFilled: !isHalf);

    // Stem
    if (!isWhole) {
      final stemX = stemUp ? x + noteHeadW / 2 : x - noteHeadW / 2;
      final stemTop = stemUp ? ny - stemLen : ny + stemLen;
      canvas.drawLine(
        Offset(stemX, ny),
        Offset(stemX, stemTop),
        Paint()..color = const Color(0xFF5D4037)..strokeWidth = 1.2,
      );

      // Flag only for non-beamed short notes
      if (!suppressFlag && isShort) {
        final flagDir = stemUp ? 1.0 : -1.0;
        _drawFlag(canvas, stemX, stemTop, flagDir);
        if (note.duration <= 1) {
          _drawFlag(canvas, stemX, stemTop + lineSpacing * 1.4 * flagDir, flagDir);
        }
      }
    }
  }

  void _drawNoteHead(Canvas canvas, double x, double y, double w, double h, {bool isFilled = true}) {
    final path = Path()
      ..moveTo(x, y - h / 2)
      ..cubicTo(x + w * 0.3, y - h / 2, x + w * 0.5, y - h * 0.15, x + w * 0.5, y)
      ..cubicTo(x + w * 0.5, y + h * 0.15, x + w * 0.3, y + h / 2, x, y + h / 2)
      ..cubicTo(x - w * 0.15, y + h / 2, x - w * 0.5, y + h * 0.1, x - w * 0.5, y)
      ..cubicTo(x - w * 0.5, y - h * 0.1, x - w * 0.15, y - h / 2, x, y - h / 2)
      ..close();
    canvas.drawPath(path, Paint()
      ..color = Colors.black
      ..style = isFilled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = isFilled ? 0 : 1.5);
  }

  void _drawFlag(Canvas canvas, double x, double y, double dir) {
    final fh = lineSpacing * 1.8;
    final fx = x;
    final flagPath = Path()
      ..moveTo(fx, y)
      ..cubicTo(
        fx + 10 * dir, y + 3,
        fx + 12 * dir, y + fh * 0.6,
        fx + 3 * dir, y + fh,
      )
      ..cubicTo(
        fx + 5 * dir, y + fh * 0.7,
        fx + 4 * dir, y + fh * 0.35,
        fx, y + fh * 0.25,
      )
      ..close();
    canvas.drawPath(flagPath, Paint()
      ..color = const Color(0xFF5D4037)
      ..style = PaintingStyle.fill);
  }

  void _drawRest(Canvas canvas, double x, double y, int duration) {
    final fill = Paint()
      ..color = const Color(0xFF5D4037)
      ..style = PaintingStyle.fill;

    if (duration >= 16) {
      // Whole rest: rectangle below 4th line
      final ry = y + 4 * lineSpacing - 2;
      canvas.drawRect(Rect.fromLTWH(x - 5, ry, 10, lineSpacing * 0.6), fill);
    } else if (duration >= 8) {
      // Half rest: rectangle on 3rd line
      final ry = y + 2 * lineSpacing - 2;
      canvas.drawRect(Rect.fromLTWH(x - 5, ry, 10, lineSpacing * 0.6), fill);
    } else if (duration >= 4) {
      // Quarter rest: hand-drawn zigzag path
      final r = lineSpacing * 0.5;
      final cx = x;
      final cy = y + 2 * lineSpacing;
      final path = Path()
        ..moveTo(cx - r, cy - r * 2.5)
        ..cubicTo(cx + r * 1.5, cy - r * 2, cx + r * 1.2, cy - r * 0.5, cx, cy - r * 0.3)
        ..cubicTo(cx - r, cy - r * 0.1, cx - r * 1.3, cy + r * 0.3, cx - r * 0.5, cy + r * 1.2)
        ..cubicTo(cx, cy + r * 1.8, cx + r * 0.5, cy + r * 2.2, cx + r * 0.8, cy + r * 2.5)
        ..cubicTo(cx + r * 0.2, cy + r * 2.0, cx - r * 0.3, cy + r * 1.5, cx - r * 0.1, cy + r * 1.0)
        ..cubicTo(cx + r * 0.1, cy + r * 0.5, cx + r * 0.3, cy + r * 0.0, cx, cy - r * 0.2)
        ..cubicTo(cx - r * 0.3, cy - r * 0.4, cx - r * 0.5, cy - r * 1.0, cx, cy - r * 1.5)
        ..close();
      canvas.drawPath(path, fill);
    } else {
      // Eighth rest
      final r = lineSpacing * 0.5;
      final cx = x;
      final cy = y + 3 * lineSpacing;
      final path = Path()
        ..moveTo(cx + r * 0.8, cy - r * 2.5)
        ..cubicTo(cx + r * 2.0, cy - r * 1.5, cx + r * 1.8, cy - r * 0.2, cx + r * 0.5, cy + r * 0.5)
        ..cubicTo(cx - r * 0.8, cy + r * 1.2, cx - r * 1.5, cy + r * 1.8, cx - r * 1.2, cy + r * 2.8)
        ..lineTo(cx + r * 1.2, cy + r * 0.5)
        ..close();
      canvas.drawPath(path, fill);
    }
  }

  int _notePosition(MusicNote note) {
    const map = {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6};
    final di = map[note.step[0]] ?? 0;
    return (note.octave * 7 + di) - 30; // 0 = E4 bottom line
  }

  double _noteY(double staffY, int pos) {
    return staffY + 4 * lineSpacing - pos * lineSpacing / 2;
  }

  void _drawVerticalLayout(Canvas canvas, Size size, Paint paint) {
    final screenWidth = size.width / scale;
    final barsPerRow = ((screenWidth - 60) / measureWidth).floor().clamp(1, 16);

    double systemY = systemMargin;
    int measureIdx = 0;

    while (measureIdx < measures.length) {
      final remaining = measures.length - measureIdx;
      final barsThisRow = remaining < barsPerRow ? remaining : barsPerRow;

      final rowWidth = barsThisRow * measureWidth + leftMargin + 20;
      final offsetX = (screenWidth - rowWidth) / 2;

      _drawStaff(canvas, offsetX, systemY, rowWidth, paint);
      _drawClef(canvas, offsetX, systemY);
      _drawTimeSignature(canvas, offsetX + clefSpace + 6, systemY);

      double x = offsetX + leftMargin + clefSpace;

      for (int b = 0; b < barsThisRow && measureIdx < measures.length; b++) {
        final measure = measures[measureIdx];
        _drawMeasureBar(canvas, x - 3, systemY, paint);

        _drawMeasureNotes(canvas, x, systemY, measure, paint);

        x += measureWidth;
        measureIdx++;
      }
      _drawFinalBar(canvas, x, systemY, paint);
      systemY += systemHeight + systemMargin;
    }
  }

  void _drawHorizontalLayout(Canvas canvas, Size size, Paint paint) {
    const staffY = systemMargin + 20;
    final totalWidth = measures.length * measureWidth + leftMargin + clefSpace + 40;
    final offsetX = 10.0;

    _drawStaff(canvas, offsetX, staffY, totalWidth, paint);
    _drawClef(canvas, offsetX, staffY);
    _drawTimeSignature(canvas, offsetX + clefSpace + 6, staffY);

    double x = offsetX + leftMargin + clefSpace;

    for (int i = 0; i < measures.length; i++) {
      final measure = measures[i];
      _drawMeasureBar(canvas, x - 3, staffY, paint);
      _drawMeasureNotes(canvas, x, staffY, measure, paint);

      x += measureWidth;
    }
    _drawFinalBar(canvas, x, staffY, paint);
  }

  void _drawMeasureNotes(Canvas canvas, double mx, double sy, Measure measure, Paint paint) {
    final notes = measure.notes.where(_noteMatches).toList();
    if (notes.isEmpty) return;
    notes.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Group by startTime for chords
    final groups = <List<MusicNote>>[];
    for (final n in notes) {
      if (n.isRest) {
        groups.add([n]);
      } else if (groups.isEmpty || (n.startTime - groups.last.first.startTime).abs() > 30) {
        groups.add([n]);
      } else {
        groups.last.add(n);
      }
    }

    final bpm = measure.bpm > 0 ? measure.bpm : 120.0;
    final beatMs = 60000 / bpm;
    final measureStart = measure.startMs > 0 ? measure.startMs : notes.first.startTime;
    final forceSingle = groups.length == 1;

    // Compute timing fractions (linear beats)
    final timingFractions = <double>[];
    for (int gi = 0; gi < groups.length; gi++) {
      final gStart = groups[gi].first.startTime;
      final beatsFromStart = (gStart - measureStart) / beatMs;
      timingFractions.add(forceSingle ? 0.5 : (beatsFromStart / beatsPerMeasure).clamp(0.0, 1.0));
    }

    // === BEAMING DETECTION ===
    final beamThreshold = 0.6 / beatsPerMeasure;
    final beamedSet = <int>{};
    {
      int gi = 0;
      while (gi < groups.length) {
        if (groups[gi].first.isRest) { gi++; continue; }
        int gj = gi + 1;
        while (gj < groups.length && !groups[gj].first.isRest) {
          final gap = timingFractions[gj] - timingFractions[gj - 1];
          if (gap > beamThreshold) break;
          gj++;
        }
        if (gj - gi >= 2) {
          for (int k = gi; k < gj; k++) { beamedSet.add(k); }
        }
        gi = gj;
      }
    }

    // Golden-ratio proportional spacing (EngraverEngine)
    final positions = <double>[];
    if (forceSingle) {
      positions.add(mx + 4 + 0.5 * (measureWidth - 8));
    } else {
      final k = log(EngraverEngine.scalingFactor) / log(2);
      double totalWeight = 0;
      final weights = <double>[];
      for (int gi = 0; gi < groups.length; gi++) {
        final gStart = groups[gi].first.startTime;
        double beatDuration;
        if (gi < groups.length - 1) {
          final nextStart = groups[gi + 1].first.startTime;
          beatDuration = ((nextStart - gStart) / beatMs).clamp(0.125, beatsPerMeasure.toDouble());
        } else {
          final beatsFromStart = (gStart - measureStart) / beatMs;
          beatDuration = (beatsPerMeasure - beatsFromStart).clamp(0.125, beatsPerMeasure.toDouble());
        }
        final w = pow(beatDuration, k).toDouble();
        weights.add(w);
        totalWeight += w;
      }
      double cum = 0;
      for (int gi = 0; gi < groups.length; gi++) {
        positions.add(mx + 4 + (cum / totalWeight) * (measureWidth - 8));
        cum += weights[gi];
      }
    }

    // Track accidentals seen in this measure
    final accidentalsSeen = <String>{};

    for (int gi = 0; gi < groups.length; gi++) {
      final group = groups[gi];
      final gx = positions[gi];
      final isBeamed = beamedSet.contains(gi);

      final hasAccidentals = group.any((n) => n.step.length > 1 && !n.isRest);

      for (final n in group) {
        if (n.isRest) {
          _drawRest(canvas, gx, sy, n.duration);
        } else {
          bool drawAcc = false;
          if (n.step.length > 1) {
            final accKey = '${n.step}${n.octave}';
            if (!accidentalsSeen.contains(accKey)) {
              drawAcc = true;
              accidentalsSeen.add(accKey);
            }
          }

          double accOffset = 0;
          if (hasAccidentals && group.length > 1) {
            accOffset = -group.indexOf(n) * 5.0;
          }

          _drawNote(canvas, gx, sy, n, 0,
              isHighlight: _isHighlighted(n),
              accidentalOffset: accOffset,
              drawAccidental: drawAcc,
              suppressFlag: isBeamed);
        }
      }

      if (gi == 0 && measure.number % 5 == 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${measure.number}',
            style: const TextStyle(fontSize: 8, color: Color(0xFF5D4037)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(gx, sy - 14));
      }
    }

    // Draw beams on top
    _drawBeams(canvas, groups, positions, sy, timingFractions, beamedSet);
  }

  void _drawBeams(Canvas canvas, List<List<MusicNote>> groups, List<double> positions, double sy,
      List<double> fractions, Set<int> beamedSet) {
    if (beamedSet.length < 2) return;

    const noteHeadW = 9.0;
    final beamPaint = Paint()
      ..color = const Color(0xFF5D4037)
      ..style = PaintingStyle.fill;

    int i = 0;
    while (i < groups.length) {
      if (!beamedSet.contains(i)) { i++; continue; }
      int j = i + 1;
      while (j < groups.length && beamedSet.contains(j)) { j++; }

      final stemUp = _groupStemUp(groups, i, j);
      final firstBeamY = _groupBeamY(groups[i], positions[i], sy, stemUp);
      final lastBeamY = _groupBeamY(groups[j - 1], positions[j - 1], sy, stemUp);
      final firstX = positions[i];
      final lastX = positions[j - 1];
      final beamThick = lineSpacing * 0.55;
      final beamDir = stemUp ? 1.0 : -1.0;

      bool hasSixteenth = false;
      for (int k = i; k < j - 1; k++) {
        if ((fractions[k + 1] - fractions[k]) <= 0.5 / beatsPerMeasure) {
          hasSixteenth = true;
          break;
        }
      }

      // Primary beam
      final beamPath = Path()
        ..moveTo(firstX - 1, firstBeamY)
        ..lineTo(lastX + 1, lastBeamY)
        ..lineTo(lastX + 1, lastBeamY + beamThick * beamDir)
        ..lineTo(firstX - 1, firstBeamY + beamThick * beamDir)
        ..close();
      canvas.drawPath(beamPath, beamPaint);

      // Redraw stems for all groups in beam
      for (int k = i; k < j; k++) {
        final beamY = _groupBeamY(groups[k], positions[k], sy, stemUp);
        for (final n in groups[k]) {
          if (n.isRest) continue;
          final pos = _notePosition(n);
          final ny = _noteY(sy, pos);
          final stemX = stemUp ? positions[k] + noteHeadW / 2 : positions[k] - noteHeadW / 2;
          final beamEdge = stemUp ? beamY : beamY + beamThick * beamDir;
          canvas.drawLine(
            Offset(stemX, ny),
            Offset(stemX, beamEdge),
            Paint()..color = const Color(0xFF5D4037)..strokeWidth = 1.5,
          );
        }
      }

      // Second beam for sixteenth notes
      if (hasSixteenth) {
        final beamGap = lineSpacing * 0.6 * beamDir;
        final beam2Path = Path()
          ..moveTo(firstX - 1, firstBeamY - beamGap)
          ..lineTo(lastX + 1, lastBeamY - beamGap)
          ..lineTo(lastX + 1, lastBeamY - beamGap + beamThick * beamDir)
          ..lineTo(firstX - 1, firstBeamY - beamGap + beamThick * beamDir)
          ..close();
        canvas.drawPath(beam2Path, beamPaint);
      }

      // Edge markers
      final edgeLen = beamThick * 1.5 * beamDir;
      canvas.drawLine(
        Offset(firstX, firstBeamY),
        Offset(firstX, firstBeamY + edgeLen),
        Paint()..color = const Color(0xFF5D4037)..strokeWidth = 1.5,
      );
      canvas.drawLine(
        Offset(lastX, lastBeamY),
        Offset(lastX, lastBeamY + edgeLen),
        Paint()..color = const Color(0xFF5D4037)..strokeWidth = 1.5,
      );

      i = j;
    }
  }

  bool _groupStemUp(List<List<MusicNote>> groups, int start, int end) {
    int upCount = 0, downCount = 0;
    for (int k = start; k < end; k++) {
      for (final n in groups[k]) {
        if (n.isRest) continue;
        if (_notePosition(n) > 4) { upCount++; } else { downCount++; }
      }
    }
    return upCount >= downCount;
  }

  double _groupBeamY(List<MusicNote> group, double x, double sy, bool stemUp) {
    double ySum = 0;
    int count = 0;
    for (final n in group) {
      if (n.isRest) continue;
      final pos = _notePosition(n);
      final ny = _noteY(sy, pos);
      final stemLen = lineSpacing * 3.5;
      final stemEnd = stemUp ? ny - stemLen : ny + stemLen;
      ySum += stemEnd;
      count++;
    }
    return count > 0 ? ySum / count : sy;
  }

  bool _isHighlighted(MusicNote note) {
    if (highlightNoteIndex < 0 || highlightNoteIndex >= playableNotes.length) return false;
    return identical(playableNotes[highlightNoteIndex], note) ||
        (playableNotes[highlightNoteIndex].midi == note.midi &&
         playableNotes[highlightNoteIndex].startTime == note.startTime);
  }

  bool _noteMatches(MusicNote n) {
    if (channelFilter < 0) return true;
    return n.channel == channelFilter;
  }

  @override
  bool shouldRepaint(covariant MidiScoreCanvas oldDelegate) =>
      oldDelegate.measures != measures ||
      oldDelegate.channelFilter != channelFilter ||
      oldDelegate.isHorizontal != isHorizontal ||
      oldDelegate.scale != scale ||
      oldDelegate.highlightNoteIndex != highlightNoteIndex;
}
