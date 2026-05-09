class MusicNote {
  final int midi;
  final String step;
  final int octave;
  final int duration;
  final int fret;
  final int string;
  final double startTime;
  final double endTime;
  final String? chordName;
  final bool isRest;

  MusicNote({
    required this.midi,
    required this.step,
    required this.octave,
    this.duration = 4,
    this.fret = 0,
    this.string = 0,
    this.startTime = 0,
    this.endTime = 0,
    this.chordName,
    this.isRest = false,
  });

  Map<String, dynamic> toJson() => {
    'midi': midi,
    'step': step,
    'octave': octave,
    'duration': duration,
    'fret': fret,
    'string': string,
    'startTime': startTime,
    'endTime': endTime,
    'chordName': chordName,
    'isRest': isRest,
  };

  factory MusicNote.fromJson(Map<String, dynamic> json) => MusicNote(
    midi: json['midi'] as int,
    step: json['step'] as String,
    octave: json['octave'] as int,
    duration: json['duration'] as int? ?? 4,
    fret: json['fret'] as int? ?? 0,
    string: json['string'] as int? ?? 0,
    startTime: (json['startTime'] as num?)?.toDouble() ?? 0,
    endTime: (json['endTime'] as num?)?.toDouble() ?? 0,
    chordName: json['chordName'] as String?,
    isRest: json['isRest'] as bool? ?? false,
  );

  String get noteName {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return names[midi % 12];
  }

  double get frequency => 440 * _pow(2, (midi - 69) / 12);

  static double _pow(double base, double exp) {
    double result = 1;
    for (int i = 0; i < exp.abs().toInt(); i++) {
      result *= base;
    }
    return exp < 0 ? 1 / result : result;
  }
}

class Measure {
  final int number;
  final List<MusicNote> notes;
  final double bpm;

  Measure({required this.number, required this.notes, this.bpm = 120});

  Map<String, dynamic> toJson() => {
    'number': number,
    'notes': notes.map((n) => n.toJson()).toList(),
    'bpm': bpm,
  };

  factory Measure.fromJson(Map<String, dynamic> json) => Measure(
    number: json['number'] as int,
    notes: (json['notes'] as List).map((n) => MusicNote.fromJson(n as Map<String, dynamic>)).toList(),
    bpm: (json['bpm'] as num?)?.toDouble() ?? 120,
  );
}

class ScoreData {
  final String title;
  final String artist;
  final double bpm;
  final int beatsPerMeasure;
  final int beatUnit;
  final List<Measure> measures;

  ScoreData({
    this.title = 'Unknown',
    this.artist = '',
    this.bpm = 120,
    this.beatsPerMeasure = 4,
    this.beatUnit = 4,
    required this.measures,
  });

  List<MusicNote> get allNotes =>
    measures.expand((m) => m.notes).toList();

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'bpm': bpm,
    'beatsPerMeasure': beatsPerMeasure,
    'beatUnit': beatUnit,
    'measures': measures.map((m) => m.toJson()).toList(),
  };

  factory ScoreData.fromJson(Map<String, dynamic> json) => ScoreData(
    title: json['title'] as String? ?? 'Unknown',
    artist: json['artist'] as String? ?? '',
    bpm: (json['bpm'] as num?)?.toDouble() ?? 120,
    beatsPerMeasure: json['beatsPerMeasure'] as int? ?? 4,
    beatUnit: json['beatUnit'] as int? ?? 4,
    measures: (json['measures'] as List?)?.map((m) => Measure.fromJson(m as Map<String, dynamic>)).toList() ?? [],
  );
}
