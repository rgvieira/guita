import 'dart:math';

class EngraverEngine {
  static const double scalingFactor = 1.618;
  static const double minNoteSpace = 18.0;

  double calculateNoteWidth(double beatDuration) {
    if (beatDuration <= 0) return minNoteSpace;
    return minNoteSpace * pow(beatDuration, log(scalingFactor) / log(2));
  }

  MeasureLayout layoutMeasure(
    List<MeasureNote> notes,
    double beatsPerMeasure,
    double measureX,
  ) {
    if (notes.isEmpty) return MeasureLayout(measureX: measureX, totalWidth: minNoteSpace, positions: [], durations: []);

    final sorted = List<MeasureNote>.from(notes)
      ..sort((a, b) => a.startBeat.compareTo(b.startBeat));

    double cx = 0;
    final positions = <double>[];
    final durations = <double>[];

    for (int i = 0; i < sorted.length; i++) {
      final note = sorted[i];
      positions.add(cx);

      double beatDuration;
      if (i < sorted.length - 1) {
        beatDuration = sorted[i + 1].startBeat - note.startBeat;
        if (beatDuration <= 0) beatDuration = 0.25;
      } else {
        beatDuration = beatsPerMeasure - note.startBeat;
        if (beatDuration <= 0) beatDuration = 0.25;
      }
      durations.add(beatDuration);

      cx += calculateNoteWidth(beatDuration);
    }

    final totalWidth = cx + minNoteSpace * 0.5;

    return MeasureLayout(
      measureX: measureX,
      totalWidth: totalWidth,
      positions: positions,
      durations: durations,
    );
  }

  static double systemLineSpacing = 8.0;
  static double systemStaffTop = 40.0;
  static double systemLeftMargin = 30.0;
  static double systemClefSpace = 20.0;
  static double systemMargin = 24.0;

  static double get staffBottom => systemStaffTop + 4 * systemLineSpacing;
  static double get staffHeight => 4 * systemLineSpacing;
  static double get systemHeight => staffBottom + 16;
}

class MeasureLayout {
  final double measureX;
  final double totalWidth;
  final List<double> positions;
  final List<double> durations;

  const MeasureLayout({
    required this.measureX,
    required this.totalWidth,
    required this.positions,
    required this.durations,
  });
}

class MeasureNote {
  final double startBeat;
  final int midi;
  final int duration;
  final int channel;
  final int velocity;
  final bool isRest;
  final String step;
  final int octave;

  const MeasureNote({
    required this.startBeat,
    required this.midi,
    required this.duration,
    this.channel = 0,
    this.velocity = 100,
    this.isRest = false,
    required this.step,
    required this.octave,
  });
}
