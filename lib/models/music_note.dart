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
  final int channel;
  final int velocity;

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
    this.channel = 0,
    this.velocity = 100,
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
    'channel': channel,
    'velocity': velocity,
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
    channel: json['channel'] as int? ?? 0,
    velocity: json['velocity'] as int? ?? 100,
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
  final Map<int, int> channelPrograms;

  ScoreData({
    this.title = 'Unknown',
    this.artist = '',
    this.bpm = 120,
    this.beatsPerMeasure = 4,
    this.beatUnit = 4,
    required this.measures,
    this.channelPrograms = const {},
  });

  List<MusicNote> get allNotes =>
    measures.expand((m) => m.notes).toList();

  static const List<String> gmInstrumentNames = [
    'Acoustic Grand Piano', 'Bright Acoustic Piano', 'Electric Grand Piano', 'Honky-tonk Piano',
    'Electric Piano 1', 'Electric Piano 2', 'Harpsichord', 'Clavinet',
    'Celesta', 'Glockenspiel', 'Music Box', 'Vibraphone',
    'Marimba', 'Xylophone', 'Tubular Bells', 'Dulcimer',
    'Drawbar Organ', 'Percussive Organ', 'Rock Organ', 'Church Organ',
    'Reed Organ', 'Accordion', 'Harmonica', 'Tango Accordion',
    'Acoustic Guitar (nylon)', 'Acoustic Guitar (steel)', 'Electric Guitar (jazz)', 'Electric Guitar (clean)',
    'Electric Guitar (muted)', 'Overdriven Guitar', 'Distortion Guitar', 'Guitar Harmonics',
    'Acoustic Bass', 'Electric Bass (finger)', 'Electric Bass (pick)', 'Fretless Bass',
    'Slap Bass 1', 'Slap Bass 2', 'Synth Bass 1', 'Synth Bass 2',
    'Violin', 'Viola', 'Cello', 'Contrabass',
    'Tremolo Strings', 'Pizzicato Strings', 'Orchestral Harp', 'Timpani',
    'String Ensemble 1', 'String Ensemble 2', 'Synth Strings 1', 'Synth Strings 2',
    'Choir Aahs', 'Voice Oohs', 'Synth Voice', 'Orchestra Hit',
    'Trumpet', 'Trombone', 'Tuba', 'Muted Trumpet',
    'French Horn', 'Brass Section', 'Synth Brass 1', 'Synth Brass 2',
    'Soprano Sax', 'Alto Sax', 'Tenor Sax', 'Baritone Sax',
    'Oboe', 'English Horn', 'Bassoon', 'Clarinet',
    'Piccolo', 'Flute', 'Recorder', 'Pan Flute',
    'Blown Bottle', 'Shakuhachi', 'Whistle', 'Ocarina',
    'Lead 1 (square)', 'Lead 2 (sawtooth)', 'Lead 3 (calliope)', 'Lead 4 (chiff)',
    'Lead 5 (charang)', 'Lead 6 (voice)', 'Lead 7 (fifths)', 'Lead 8 (bass + lead)',
    'Pad 1 (new age)', 'Pad 2 (warm)', 'Pad 3 (polysynth)', 'Pad 4 (choir)',
    'Pad 5 (bowed)', 'Pad 6 (metallic)', 'Pad 7 (halo)', 'Pad 8 (sweep)',
    'FX 1 (rain)', 'FX 2 (soundtrack)', 'FX 3 (crystal)', 'FX 4 (atmosphere)',
    'FX 5 (brightness)', 'FX 6 (goblins)', 'FX 7 (echoes)', 'FX 8 (sci-fi)',
    'Sitar', 'Banjo', 'Shamisen', 'Koto',
    'Kalimba', 'Bagpipe', 'Fiddle', 'Shanai',
    'Tinkle Bell', 'Agogo', 'Steel Drums', 'Woodblock',
    'Taiko Drum', 'Melodic Tom', 'Synth Drum', 'Reverse Cymbal',
    'Guitar Fret Noise', 'Breath Noise', 'Seashore', 'Bird Tweet',
    'Telephone Ring', 'Helicopter', 'Applause', 'Gunshot',
  ];

  String instrumentName(int program) =>
      program >= 0 && program < gmInstrumentNames.length
          ? gmInstrumentNames[program]
          : 'Unknown';

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
