import 'dart:async';
import 'package:flutter/material.dart';
import '../models/music_note.dart';
import '../services/music_parser_service.dart';
import '../services/midi_player_service.dart';

class MidiScoreView extends StatefulWidget {
  final String filePath;
  final void Function(List<int> channels)? onChannelsLoaded;
  final void Function(int current, int total, String name)? onTrackChanged;
  final void Function(String error)? onError;
  final void Function(int state)? onPlayerStateChanged;

  const MidiScoreView({
    super.key,
    required this.filePath,
    this.onChannelsLoaded,
    this.onTrackChanged,
    this.onError,
    this.onPlayerStateChanged,
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
  final TransformationController _transformationController =
      TransformationController();

  Map<int, String> get channelNames => Map.unmodifiable(_channelNames);

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
      _currentNoteIndex = -1;
      _transformationController.value = Matrix4.identity();
      _load();
    }
  }

  @override
  void dispose() {
    _stop();
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
        final prog = data.channelPrograms[ch];
        if (prog != null) {
          _channelNames[ch] = data.instrumentName(prog);
        } else {
          _channelNames[ch] = 'Canal $ch';
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
    _playableNotes = _data!.allNotes
        .where((n) => n.channel == _selectedChannel && !n.isRest)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
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

    double noteX, noteY;
    if (_isHorizontal) {
      final staffY = sm + 20;
      noteX = 10 + leftMargin + clefSpace + measureIdx * mw + mw / 2;
      noteY = staffY + MidiScoreCanvas.staffHeight / 2;
    } else {
      final row = measureIdx ~/ barsPerRow;
      final col = measureIdx % barsPerRow;
      final rowWidth = barsPerRow * mw + leftMargin + 20;
      final offsetX = (screenWidth - rowWidth) / 2;
      noteX = offsetX + leftMargin + clefSpace + col * mw + mw / 2;
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
    if (_playableNotes.isEmpty) return;
    _stop();
    _isPlaying = true;
    widget.onPlayerStateChanged?.call(1);
    await _player.init();

    final bpm = _data?.bpm ?? 120;
    final beatMs = (60000 / bpm).round().clamp(50, 10000);

    for (int i = 0; i < _playableNotes.length && _isPlaying; i++) {
      final note = _playableNotes[i];
      setState(() => _currentNoteIndex = i);
      _scrollToNote(i);
      await _player.noteOn(note.midi);
      unawaited(Future.delayed(
          Duration(milliseconds: (beatMs * 0.8).round()),
          () => _player.noteOff(note.midi)));
      await Future.delayed(Duration(milliseconds: beatMs));
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

    return InteractiveViewer(
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
      ..strokeWidth = 0.8;

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
      Canvas canvas, double x, double y, MusicNote note, int idx, {bool isHighlight = false}) {
    const noteHeadW = 7.0;
    const noteHeadH = 5.0;

    // Ledger lines
    final pos = _notePosition(note);
    if (pos < 0) {
      for (int l = 0; l >= pos; l -= 2) {
        final ly = _noteY(y, l);
        canvas.drawLine(
          Offset(x - noteHeadW - 2, ly),
          Offset(x + noteHeadW + 2, ly),
          Paint()..color = const Color(0xFF5D4037)..strokeWidth = 0.6,
        );
      }
    } else if (pos > 8) {
      for (int l = 8; l <= pos; l += 2) {
        final ly = _noteY(y, l);
        canvas.drawLine(
          Offset(x - noteHeadW - 2, ly),
          Offset(x + noteHeadW + 2, ly),
          Paint()..color = const Color(0xFF5D4037)..strokeWidth = 0.6,
        );
      }
    }

    // Accidental
    if (note.step.length > 1) {
      final acc = note.step[1];
      if (acc == '#') {
        final tp = TextPainter(
          text: const TextSpan(
              text: '\u{266F}',
              style: TextStyle(fontSize: 9, color: Color(0xFF5D4037))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - noteHeadW - tp.width - 2, _noteY(y, pos) - tp.height / 2));
      } else if (acc == 'b') {
        final tp = TextPainter(
          text: const TextSpan(
              text: '\u{266D}',
              style: TextStyle(fontSize: 9, color: Color(0xFF5D4037))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - noteHeadW - tp.width - 2, _noteY(y, pos) - tp.height / 2));
      }
    }

    // Note head
    final ny = _noteY(y, pos);
    if (isHighlight) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, ny), width: noteHeadW * 1.5, height: noteHeadH * 1.5),
        Paint()..color = Colors.orange,
      );
    }
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, ny), width: noteHeadW, height: noteHeadH),
      Paint()..color = Colors.black,
    );

    // Stem
    final stemUp = pos < 4;
    final stemLen = lineSpacing * 3.5;
    if (stemUp) {
      canvas.drawLine(
        Offset(x + noteHeadW / 2, ny),
        Offset(x + noteHeadW / 2, ny - stemLen),
        Paint()..color = const Color(0xFF5D4037)..strokeWidth = 1.0,
      );
    } else {
      canvas.drawLine(
        Offset(x - noteHeadW / 2, ny),
        Offset(x - noteHeadW / 2, ny + stemLen),
        Paint()..color = const Color(0xFF5D4037)..strokeWidth = 1.0,
      );
    }

    // Flag for eighth notes
    if (note.duration >= 8 && note.duration < 16) {
      final flagX = stemUp ? x + noteHeadW / 2 : x - noteHeadW / 2;
      final flagTop = stemUp ? ny - stemLen : ny + stemLen;
      final flagPath = Path()
        ..moveTo(flagX, flagTop)
        ..quadraticBezierTo(
          stemUp ? flagX + 7 : flagX - 7,
          stemUp ? flagTop + lineSpacing : flagTop - lineSpacing,
          stemUp ? flagX + 2 : flagX - 2,
          stemUp ? flagTop + lineSpacing * 1.5 : flagTop - lineSpacing * 1.5,
        );
      canvas.drawPath(flagPath, Paint()
        ..color = const Color(0xFF5D4037)
        ..style = PaintingStyle.fill);
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

        if (measureIdx % 5 == 0) {
          final tp = TextPainter(
            text: TextSpan(
              text: '${measure.number}',
              style: const TextStyle(fontSize: 8, color: Color(0xFF5D4037)),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x, systemY - 14));
        }

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

      if (i % 5 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${measure.number}',
            style: const TextStyle(fontSize: 8, color: Color(0xFF5D4037)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x, staffY - 14));
      }

      x += measureWidth;
    }
    _drawFinalBar(canvas, x, staffY, paint);
  }

  void _drawMeasureNotes(Canvas canvas, double mx, double sy, Measure measure, Paint paint) {
    final notes = measure.notes.where(_noteMatches).toList();
    if (notes.isEmpty) return;
    notes.sort((a, b) => a.startTime.compareTo(b.startTime));

    final groups = <List<MusicNote>>[];
    for (final n in notes) {
      if (groups.isEmpty || (n.startTime - groups.last.first.startTime).abs() > 30) {
        groups.add([n]);
      } else {
        groups.last.add(n);
      }
    }

    if (groups.length == 1) {
      for (final n in groups.first) {
        final isHl = _isHighlighted(n);
        _drawNote(canvas, mx + measureWidth / 2, sy, n, 0, isHighlight: isHl);
      }
      return;
    }

    final spacing = (measureWidth - 8) / groups.length;
    for (int gi = 0; gi < groups.length; gi++) {
      final gx = mx + 4 + gi * spacing;
      for (final n in groups[gi]) {
        final isHl = _isHighlighted(n);
        _drawNote(canvas, gx, sy, n, 0, isHighlight: isHl);
      }
    }
  }

  bool _isHighlighted(MusicNote note) {
    if (highlightNoteIndex < 0 || highlightNoteIndex >= playableNotes.length) return false;
    return identical(playableNotes[highlightNoteIndex], note) ||
        (playableNotes[highlightNoteIndex].midi == note.midi &&
         playableNotes[highlightNoteIndex].startTime == note.startTime);
  }

  bool _noteMatches(MusicNote n) {
    if (n.isRest) return false;
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
