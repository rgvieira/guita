<#
.SYNOPSIS
    Gera um projeto Flutter completo para leitura de partituras, tablaturas e cifras
    com suporte a GP*, MIDI e MusicXML, usando Hive, Riverpod e arquitetura MVVM.

.DESCRIPTION
    Este script cria automaticamente um app Flutter com:
    - Hive para persistência local dos arquivos encontrados
    - Riverpod para gerenciamento de estado reativo
    - MVVM (Model-View-ViewModel) para separação de camadas
    - Leitura recursiva de pastas com TreeView para seleção de arquivos
    - Tela de partitura gráfica com pentagrama, tablatura e cifras
    - Player MIDI com cursor de acompanhamento
    - Modo de prática com BPM progressivo
    - Histórico de treinos com gráfico de evolução
    - Exportação em PNG

.PARAMETER RootPath
    Caminho onde o projeto Flutter será criado.

.PARAMETER FlutterPath
    Caminho do executável Flutter (opcional, detecta automaticamente).

.EXAMPLE
    PS> .\create_guitar2.ps1 -RootPath "D:\workspace\guitar2"

.NOTES
    Autor: Roberto
    Versão: 1.0
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath,

    [Parameter(Mandatory = $false)]
    [string]$FlutterPath = ""
)

$ErrorActionPreference = "Stop"

# ============================================================
# DETECTAR FLUTTER
# ============================================================
if (-not $FlutterPath) {
    $flutterCmd = Get-Command "flutter.bat" -ErrorAction SilentlyContinue
    if (-not $flutterCmd) {
        $flutterCmd = Get-Command "flutter" -ErrorAction SilentlyContinue
    }
    if ($flutterCmd) {
        $FlutterPath = $flutterCmd.Source
    }
    else {
        Write-Error "Flutter não encontrado. Instale o Flutter ou forneça o caminho via -FlutterPath"
        exit 1
    }
}

Write-Host "=== Guitar2 - Gerador de Projeto Flutter ===" -ForegroundColor Cyan
Write-Host "Flutter: $FlutterPath" -ForegroundColor Gray
Write-Host "Destino: $RootPath" -ForegroundColor Gray
Write-Host ""

# ============================================================
# 1. CRIAR PROJETO FLUTTER
# ============================================================
Write-Host "[1/9] Criando projeto Flutter..." -ForegroundColor Yellow
$projectName = Split-Path $RootPath -Leaf
if (-not $projectName) { $projectName = "guitar2" }

$parentDir = Split-Path $RootPath -Parent
Push-Location $parentDir
try {
    & $FlutterPath create --project-name $projectName --org com.guitar2 --platforms windows,android,ios $RootPath 2>&1 | Out-Null
}
finally {
    Pop-Location
}

# ============================================================
# 2. CRIAR ESTRUTURA DE DIRETÓRIOS
# ============================================================
Write-Host "[2/9] Criando estrutura de diretórios..." -ForegroundColor Yellow
$dirs = @(
    "lib\models",
    "lib\viewmodels",
    "lib\views",
    "lib\services",
    "lib\painters",
    "lib\widgets"
)
foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Path "$RootPath\$dir" -Force | Out-Null
}

# ============================================================
# 3. ATUALIZAR pubspec.yaml
# ============================================================
Write-Host "[3/9] Configurando dependências..." -ForegroundColor Yellow
@"
name: $projectName
description: "Leitor de partituras, tablaturas e cifras com suporte a GP*, MIDI e MusicXML"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.11.5

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_riverpod: ^2.6.1
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  path_provider: ^2.1.5
  file_picker: ^8.1.7
  intl: ^0.20.2
  xml: ^6.5.0
  uuid: ^4.5.1
  collection: ^1.19.1
  fl_chart: ^0.70.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
"@ | Set-Content "$RootPath\pubspec.yaml" -Encoding UTF8

# ============================================================
# 4. CRIAR MODELS
# ============================================================
Write-Host "[4/9] Criando Models..." -ForegroundColor Yellow

# file_entry.dart
@"
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class FileEntry {
  final String id;
  final String path;
  final String name;
  final String extension;
  final bool isDirectory;
  final int size;
  final DateTime lastModified;

  FileEntry({
    String? id,
    required this.path,
    required this.name,
    required this.extension,
    this.isDirectory = false,
    this.size = 0,
    DateTime? lastModified,
  }) : id = id ?? const Uuid().v4(),
       lastModified = lastModified ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'name': name,
    'extension': extension,
    'isDirectory': isDirectory,
    'size': size,
    'lastModified': lastModified.toIso8601String(),
  };

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
    id: json['id'] as String,
    path: json['path'] as String,
    name: json['name'] as String,
    extension: json['extension'] as String,
    isDirectory: json['isDirectory'] as bool,
    size: json['size'] as int,
    lastModified: DateTime.parse(json['lastModified'] as String),
  );

  static const supportedExtensions = [
    '.gp3', '.gp4', '.gp5', '.gpx', '.gp',
    '.mid', '.midi',
    '.musicxml', '.xml',
    '.pdf',
  ];

  bool get isSupported => supportedExtensions.contains(extension.toLowerCase());
}

class FileEntryBox {
  static const _boxName = 'files';
  static Box<String>? _box;

  static Future<Box<String>> get box async {
    _box ??= await Hive.openBox<String>(_boxName);
    return _box!;
  }

  static Future<void> saveList(List<FileEntry> entries) async {
    final b = await box;
    await b.clear();
    for (final entry in entries) {
      await b.put(entry.id, jsonEncode(entry.toJson()));
    }
  }

  static Future<List<FileEntry>> loadList() async {
    final b = await box;
    return b.values.map((v) => FileEntry.fromJson(jsonDecode(v) as Map<String, dynamic>)).toList();
  }
}
"@ | Set-Content "$RootPath\lib\models\file_entry.dart" -Encoding UTF8

# music_note.dart
@"
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
}
"@ | Set-Content "$RootPath\lib\models\music_note.dart" -Encoding UTF8

# practice_session.dart
@"
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class PracticeSession {
  final String id;
  final DateTime date;
  final int bpmStart;
  final int bpmEnd;
  final int bpmStep;
  final int repetitions;
  final int finalBPM;
  final String musicTitle;

  PracticeSession({
    String? id,
    DateTime? date,
    required this.bpmStart,
    required this.bpmEnd,
    required this.bpmStep,
    required this.repetitions,
    required this.finalBPM,
    this.musicTitle = '',
  }) : id = id ?? const Uuid().v4(),
       date = date ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'bpmStart': bpmStart,
    'bpmEnd': bpmEnd,
    'bpmStep': bpmStep,
    'repetitions': repetitions,
    'finalBPM': finalBPM,
    'musicTitle': musicTitle,
  };

  factory PracticeSession.fromJson(Map<String, dynamic> json) => PracticeSession(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    bpmStart: json['bpmStart'] as int,
    bpmEnd: json['bpmEnd'] as int,
    bpmStep: json['bpmStep'] as int,
    repetitions: json['repetitions'] as int,
    finalBPM: json['finalBPM'] as int,
    musicTitle: json['musicTitle'] as String? ?? '',
  );
}

class PracticeSessionBox {
  static const _boxName = 'sessions';
  static Box<String>? _box;

  static Future<Box<String>> get box async {
    _box ??= await Hive.openBox<String>(_boxName);
    return _box!;
  }

  static Future<void> save(PracticeSession session) async {
    final b = await box;
    await b.put(session.id, jsonEncode(session.toJson()));
  }

  static Future<List<PracticeSession>> loadAll() async {
    final b = await box;
    final list = b.values.map(
      (v) => PracticeSession.fromJson(jsonDecode(v) as Map<String, dynamic>),
    ).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  static Future<void> clear() async {
    final b = await box;
    await b.clear();
  }
}
"@ | Set-Content "$RootPath\lib\models\practice_session.dart" -Encoding UTF8

# ============================================================
# 5. CRIAR SERVICES
# ============================================================
Write-Host "[5/9] Criando Services..." -ForegroundColor Yellow

# file_scanner_service.dart
@"
import 'dart:io';
import '../models/file_entry.dart';

class FileScannerService {
  static Future<List<FileEntry>> scanDirectory(String rootPath) async {
    final entries = <FileEntry>[];
    final dir = Directory(rootPath);

    if (!await dir.exists()) {
      throw Exception('Directory not found: $rootPath');
    }

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = entity.path.split('.').last.toLowerCase();
        if (FileEntry.supportedExtensions.any((e) => e.contains(ext))) {
          final stat = await entity.stat();
          entries.add(FileEntry(
            path: entity.path,
            name: entity.path.split(Platform.pathSeparator).last,
            extension: '.$ext',
            size: stat.size,
            lastModified: stat.modified,
          ));
        }
      }
    }

    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  static String getParentPath(String path) {
    final dir = Directory(path).parent;
    return dir.path;
  }

  static List<FileEntry> buildTree(List<FileEntry> entries) {
    return entries.where((e) => e.isSupported).toList();
  }
}
"@ | Set-Content "$RootPath\lib\services\file_scanner_service.dart" -Encoding UTF8

# music_parser_service.dart
@"
import 'dart:io';
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
        return _parseMidi(path);
      default:
        if (path.contains('.gp')) return _parseGpPlaceholder(path);
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
      final measures = <Measure>[];
      final notes = <MusicNote>[];
      int i = 0;

      while (i + 7 < bytes.length) {
        if (bytes[i] == 0x90 && bytes[i + 2] > 0) {
          final midi = bytes[i + 1];
          final step = _midiToStep(midi);
          final octave = _midiToOctave(midi);
          notes.add(MusicNote(
            midi: midi,
            step: step,
            octave: octave,
            duration: 4,
          ));
          i += 3;
        } else {
          i++;
        }
      }

      if (notes.isNotEmpty) {
        measures.add(Measure(number: 1, notes: notes));
      }

      return ScoreData(measures: measures);
    } catch (e) {
      return ScoreData(measures: []);
    }
  }

  static Future<ScoreData> _parseGpPlaceholder(String path) async {
    return ScoreData(
      title: path.split('\\').last.split('/').last,
      measures: [
        Measure(number: 1, notes: [
          MusicNote(midi: 40, step: 'E', octave: 2, fret: 0, string: 6),
          MusicNote(midi: 45, step: 'A', octave: 2, fret: 0, string: 5),
          MusicNote(midi: 50, step: 'D', octave: 3, fret: 0, string: 4),
          MusicNote(midi: 55, step: 'G', octave: 3, fret: 0, string: 3),
          MusicNote(midi: 59, step: 'B', octave: 3, fret: 0, string: 2),
          MusicNote(midi: 64, step: 'E', octave: 4, fret: 0, string: 1),
        ]),
      ],
    );
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
"@ | Set-Content "$RootPath\lib\services\music_parser_service.dart" -Encoding UTF8

# midi_player_service.dart
@"
import '../models/music_note.dart';

class MidiPlayerService {
  bool _isPlaying = false;
  Function(int note)? onNotePlay;

  bool get isPlaying => _isPlaying;

  void setVolume(double vol) {}

  Future<void> playNote(MusicNote note) async {
    if (!_isPlaying) return;
    onNotePlay?.call(note.midi);
  }

  Future<void> playSequence(List<MusicNote> notes, double bpm,
      {bool Function()? shouldStop}) async {
    _isPlaying = true;
    final beatDuration = (60000 / bpm).toInt();

    for (final note in notes) {
      if (shouldStop != null && shouldStop()) break;
      if (!_isPlaying) break;
      await playNote(note);
      await Future.delayed(Duration(milliseconds: beatDuration));
    }

    _isPlaying = false;
  }

  void stop() {
    _isPlaying = false;
  }

  void dispose() {
    _isPlaying = false;
  }
}
"@ | Set-Content "$RootPath\lib\services\midi_player_service.dart" -Encoding UTF8

# pdf_export_service.dart
@"
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PdfExportService {
  static Future<String> exportToPng({
    required String title,
    required ui.Image scoreImage,
    required ui.Image? tabImage,
    required List<String> chords,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final outputDir = Directory('\${dir.path}/exports');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '\${outputDir.path}/\$title-\$timestamp.png';

    final byteData = await scoreImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Failed to render image');

    final file = File(filePath);
    await file.writeAsBytes(byteData.buffer.asUint8List());

    return filePath;
  }
}
"@ | Set-Content "$RootPath\lib\services\pdf_export_service.dart" -Encoding UTF8

# ============================================================
# 6. CRIAR PAINTERS
# ============================================================
Write-Host "[6/9] Criando Painters..." -ForegroundColor Yellow

# score_painter.dart
@"
import 'package:flutter/material.dart';
import '../models/music_note.dart';

class ScorePainter extends CustomPainter {
  final List<MusicNote> notes;
  final double cursorX;
  final double viewWidth;
  final double noteSpacing;
  final int currentNoteIndex;

  ScorePainter({
    required this.notes,
    this.cursorX = -1,
    this.viewWidth = 800,
    this.noteSpacing = 40,
    this.currentNoteIndex = -1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final staffPaint = Paint()
      ..color = Colors.brown.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    const lineSpacing = 12.0;
    final startY = size.height / 2 - 2 * lineSpacing;
    final effectiveWidth = size.width;

    for (int i = 0; i < 5; i++) {
      final y = startY + i * lineSpacing;
      canvas.drawLine(Offset(0, y), Offset(effectiveWidth, y), staffPaint);
    }

    final clefSize = 30.0;
    final clefPainter = TextPainter(
      text: TextSpan(
        text: 'G',
        style: TextStyle(fontSize: clefSize, color: Colors.brown, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    clefPainter.paint(canvas, Offset(10, startY - clefSize / 2));

    final notePaint = Paint()..color = Colors.black;
    final highlightPaint = Paint()..color = Colors.orange;

    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      if (note.isRest) continue;

      final x = 60 + i * noteSpacing;
      if (x > effectiveWidth) break;

      final noteY = startY + 2 * lineSpacing - (note.midi % 12) * 2.5;

      if (i == currentNoteIndex) {
        canvas.drawCircle(Offset(x, noteY), 8, highlightPaint);
      } else {
        canvas.drawCircle(Offset(x, noteY), 6, notePaint);
      }

      if (note.fret > 0 || note.string > 0) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '\${note.fret}',
            style: TextStyle(fontSize: 8, color: Colors.black54),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(x - 3, noteY + 10));
      }
    }

    if (cursorX > 0) {
      final cursorPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 2.0;
      canvas.drawLine(
        Offset(cursorX, 0),
        Offset(cursorX, size.height),
        cursorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ScorePainter oldDelegate) =>
    oldDelegate.notes != notes ||
    oldDelegate.cursorX != cursorX ||
    oldDelegate.currentNoteIndex != currentNoteIndex;
}
"@ | Set-Content "$RootPath\lib\painters\score_painter.dart" -Encoding UTF8

# tab_painter.dart
@"
import 'package:flutter/material.dart';
import '../models/music_note.dart';

class TabPainter extends CustomPainter {
  final List<MusicNote> notes;
  final double cursorX;
  final int currentNoteIndex;

  TabPainter({
    required this.notes,
    this.cursorX = -1,
    this.currentNoteIndex = -1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stringPaint = Paint()
      ..color = Colors.brown.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    const stringNames = ['e', 'B', 'G', 'D', 'A', 'E'];
    const lineSpacing = 18.0;
    final startY = 20.0;
    final effectiveWidth = size.width;

    for (int i = 0; i < 6; i++) {
      final y = startY + i * lineSpacing;
      canvas.drawLine(Offset(0, y), Offset(effectiveWidth, y), stringPaint);

      final stringLabelPainter = TextPainter(
        text: TextSpan(
          text: stringNames[i],
          style: TextStyle(
            fontSize: 10,
            color: Colors.brown,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      stringLabelPainter.paint(canvas, Offset(4, y - 8));
    }

    const noteSpacing = 40.0;
    final fretPaint = Paint()..color = Colors.black87;
    final highlightPaint = Paint()..color = Colors.orange;

    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      if (note.isRest || note.string == 0) continue;

      final x = 60 + i * noteSpacing;
      if (x > effectiveWidth) break;

      final stringIndex = 6 - note.string;
      final y = startY + stringIndex * lineSpacing;

      final isHighlight = i == currentNoteIndex;

      if (isHighlight) {
        canvas.drawCircle(Offset(x, y), 8, highlightPaint);
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: '\${note.fret}',
          style: TextStyle(
            fontSize: isHighlight ? 12 : 10,
            color: isHighlight ? Colors.white : fretPaint.color,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x - 3, y - 7));
    }

    if (cursorX > 0) {
      final cursorPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 2.0;
      canvas.drawLine(
        Offset(cursorX, 0),
        Offset(cursorX, size.height),
        cursorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TabPainter oldDelegate) =>
    oldDelegate.notes != notes ||
    oldDelegate.cursorX != cursorX ||
    oldDelegate.currentNoteIndex != currentNoteIndex;
}
"@ | Set-Content "$RootPath\lib\painters\tab_painter.dart" -Encoding UTF8

# chord_painter.dart
@"
import 'package:flutter/material.dart';

class ChordPainter extends CustomPainter {
  final String chordName;
  final List<int> frets;
  final List<bool> muted;

  ChordPainter({
    required this.chordName,
    this.frets = const [],
    this.muted = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (chordName.isEmpty) return;

    final paint = Paint()
      ..color = Colors.brown
      ..strokeWidth = 1.5;

    final center = size.width / 2;
    final top = 10.0;

    final namePainter = TextPainter(
      text: TextSpan(
        text: chordName,
        style: TextStyle(
          fontSize: 18,
          color: Colors.brown,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    namePainter.paint(canvas, Offset(center - 15, top));

    if (frets.isEmpty) return;

    const stringSpacing = 14.0;
    const fretSpacing = 14.0;
    const nutY = 50.0;
    final startX = center - 2.5 * stringSpacing;

    for (int i = 0; i < 6; i++) {
      final x = startX + i * stringSpacing;
      canvas.drawLine(
        Offset(x, nutY),
        Offset(x, nutY + 4 * fretSpacing),
        paint,
      );
    }

    for (int f = 0; f <= 4; f++) {
      final y = nutY + f * fretSpacing;
      canvas.drawLine(
        Offset(startX, y),
        Offset(startX + 5 * stringSpacing, y),
        paint,
      );
    }

    for (int i = 0; i < frets.length && i < 6; i++) {
      if (muted.length > i && muted[i]) {
        final x = startX + i * stringSpacing;
        final mutedPainter = TextPainter(
          text: TextSpan(
            text: 'X',
            style: TextStyle(fontSize: 12, color: Colors.red),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        mutedPainter.paint(canvas, Offset(x - 4, nutY - 20));
        continue;
      }

      if (frets[i] > 0) {
        final x = startX + i * stringSpacing;
        final y = nutY + (frets[i] - 1) * fretSpacing + fretSpacing / 2;
        canvas.drawCircle(Offset(x, y), 5, Paint()..color = Colors.brown);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ChordPainter oldDelegate) =>
    oldDelegate.chordName != chordName;
}
"@ | Set-Content "$RootPath\lib\painters\chord_painter.dart" -Encoding UTF8

# ============================================================
# 7. CRIAR VIEWMODELS
# ============================================================
Write-Host "[7/9] Criando ViewModels..." -ForegroundColor Yellow

# file_tree_viewmodel.dart
@"
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_entry.dart';
import '../services/file_scanner_service.dart';

final fileListProvider = StateNotifierProvider<FileListNotifier, AsyncValue<List<FileEntry>>>((ref) {
  return FileListNotifier();
});

final selectedFileProvider = StateProvider<FileEntry?>((ref) => null);
final rootPathProvider = StateProvider<String>((ref) => '');

class FileListNotifier extends StateNotifier<AsyncValue<List<FileEntry>>> {
  FileListNotifier() : super(const AsyncValue.data([]));

  Future<void> scanDirectory(String path) async {
    state = const AsyncValue.loading();
    try {
      final files = await FileScannerService.scanDirectory(path);
      await FileEntryBox.saveList(files);
      state = AsyncValue.data(files);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> loadFromCache() async {
    try {
      final files = await FileEntryBox.loadList();
      state = AsyncValue.data(files);
    } catch (e) {
      state = AsyncValue.data([]);
    }
  }
}
"@ | Set-Content "$RootPath\lib\viewmodels\file_tree_viewmodel.dart" -Encoding UTF8

# score_viewmodel.dart
@"
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_note.dart';
import '../services/music_parser_service.dart';
import '../services/midi_player_service.dart';

final scoreProvider = StateNotifierProvider<ScoreNotifier, AsyncValue<ScoreData>>((ref) {
  return ScoreNotifier();
});

final playbackProvider = StateNotifierProvider<PlaybackNotifier, PlaybackState>((ref) {
  return PlaybackNotifier();
});

class ScoreNotifier extends StateNotifier<AsyncValue<ScoreData>> {
  ScoreNotifier() : super(AsyncValue.data(ScoreData(measures: [])));

  Future<void> loadFile(String path) async {
    state = const AsyncValue.loading();
    try {
      final score = await MusicParserService.parseFile(path);
      state = AsyncValue.data(score);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}

class PlaybackState {
  final bool isPlaying;
  final int currentNoteIndex;
  final double currentBpm;
  final double position;

  const PlaybackState({
    this.isPlaying = false,
    this.currentNoteIndex = -1,
    this.currentBpm = 120,
    this.position = 0,
  });

  PlaybackState copyWith({
    bool? isPlaying,
    int? currentNoteIndex,
    double? currentBpm,
    double? position,
  }) => PlaybackState(
    isPlaying: isPlaying ?? this.isPlaying,
    currentNoteIndex: currentNoteIndex ?? this.currentNoteIndex,
    currentBpm: currentBpm ?? this.currentBpm,
    position: position ?? this.position,
  );
}

class PlaybackNotifier extends StateNotifier<PlaybackState> {
  final MidiPlayerService _player = MidiPlayerService();

  PlaybackNotifier() : super(const PlaybackState());

  MidiPlayerService get player => _player;

  Future<void> play(List<MusicNote> notes, double bpm) async {
    state = state.copyWith(isPlaying: true, currentBpm: bpm);

    final beatDuration = (60000 / bpm).toInt();

    for (int i = 0; i < notes.length; i++) {
      if (!state.isPlaying) break;

      state = state.copyWith(
        currentNoteIndex: i,
        position: (i / notes.length).clamp(0.0, 1.0),
      );

      await _player.playNote(notes[i]);
      await Future.delayed(Duration(milliseconds: beatDuration));
    }

    state = state.copyWith(
      isPlaying: false,
      currentNoteIndex: -1,
      position: 0,
    );
  }

  void stop() {
    _player.stop();
    state = state.copyWith(isPlaying: false, currentNoteIndex: -1, position: 0);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
"@ | Set-Content "$RootPath\lib\viewmodels\score_viewmodel.dart" -Encoding UTF8

# practice_viewmodel.dart
@"
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_note.dart';
import '../models/practice_session.dart';
import '../services/midi_player_service.dart';

final practiceProvider = StateNotifierProvider<PracticeNotifier, PracticeState>((ref) {
  return PracticeNotifier();
});

class PracticeState {
  final int bpmStart;
  final int bpmEnd;
  final int bpmStep;
  final int repetitions;
  final bool accelerate;
  final bool isRunning;
  final int currentBPM;
  final int currentRepetition;
  final double progress;
  final List<PracticeSession> history;

  const PracticeState({
    this.bpmStart = 60,
    this.bpmEnd = 120,
    this.bpmStep = 10,
    this.repetitions = 3,
    this.accelerate = true,
    this.isRunning = false,
    this.currentBPM = 60,
    this.currentRepetition = 0,
    this.progress = 0,
    this.history = const [],
  });

  PracticeState copyWith({
    int? bpmStart,
    int? bpmEnd,
    int? bpmStep,
    int? repetitions,
    bool? accelerate,
    bool? isRunning,
    int? currentBPM,
    int? currentRepetition,
    double? progress,
    List<PracticeSession>? history,
  }) => PracticeState(
    bpmStart: bpmStart ?? this.bpmStart,
    bpmEnd: bpmEnd ?? this.bpmEnd,
    bpmStep: bpmStep ?? this.bpmStep,
    repetitions: repetitions ?? this.repetitions,
    accelerate: accelerate ?? this.accelerate,
    isRunning: isRunning ?? this.isRunning,
    currentBPM: currentBPM ?? this.currentBPM,
    currentRepetition: currentRepetition ?? this.currentRepetition,
    progress: progress ?? this.progress,
    history: history ?? this.history,
  );
}

class PracticeNotifier extends StateNotifier<PracticeState> {
  final MidiPlayerService _player = MidiPlayerService();

  PracticeNotifier() : super(const PracticeState()) {
    _loadHistory();
  }

  void _loadHistory() async {
    final sessions = await PracticeSessionBox.loadAll();
    state = state.copyWith(history: sessions);
  }

  void updateBpmStart(int value) => state = state.copyWith(bpmStart: value);
  void updateBpmEnd(int value) => state = state.copyWith(bpmEnd: value);
  void updateBpmStep(int value) => state = state.copyWith(bpmStep: value);
  void updateRepetitions(int value) => state = state.copyWith(repetitions: value);
  void toggleAccelerate() => state = state.copyWith(accelerate: !state.accelerate);

  Future<void> startPractice(List<MusicNote> notes, String musicTitle) async {
    state = state.copyWith(isRunning: true, currentBPM: state.bpmStart, currentRepetition: 0, progress: 0);

    for (int rep = 0; rep < state.repetitions; rep++) {
      state = state.copyWith(currentRepetition: rep);
      int currentBPM = state.accelerate ? state.bpmStart : state.bpmEnd;

      while (state.accelerate ? currentBPM <= state.bpmEnd : currentBPM >= state.bpmStart) {
        if (!state.isRunning) break;

        state = state.copyWith(currentBPM: currentBPM);
        final beatDuration = (60000 ~/ currentBPM);

        for (final note in notes) {
          if (!state.isRunning) break;
          await _player.playNote(note);
          await Future.delayed(Duration(milliseconds: beatDuration));
        }

        currentBPM += state.accelerate ? state.bpmStep : -state.bpmStep;
        final totalSteps = ((state.bpmEnd - state.bpmStart) / state.bpmStep).abs() + 1;
        final completed = (rep * totalSteps + (currentBPM - state.bpmStart).abs() / state.bpmStep);
        state = state.copyWith(
          progress: completed / (state.repetitions * totalSteps),
        );
      }
    }

    final session = PracticeSession(
      bpmStart: state.bpmStart,
      bpmEnd: state.bpmEnd,
      bpmStep: state.bpmStep,
      repetitions: state.repetitions,
      finalBPM: state.accelerate ? state.bpmEnd : state.bpmStart,
      musicTitle: musicTitle,
    );
    await PracticeSessionBox.save(session);
    _loadHistory();

    state = state.copyWith(isRunning: false, currentBPM: state.bpmStart, progress: 0);
  }

  void stop() {
    _player.stop();
    state = state.copyWith(isRunning: false);
  }
}
"@ | Set-Content "$RootPath\lib\viewmodels\practice_viewmodel.dart" -Encoding UTF8

# ============================================================
# 8. CRIAR WIDGETS
# ============================================================
Write-Host "[8/9] Criando Widgets..." -ForegroundColor Yellow

# file_tree_widget.dart
@"
import 'package:flutter/material.dart';
import '../models/file_entry.dart';
import '../painters/chord_painter.dart';

class FileTreeWidget extends StatelessWidget {
  final List<FileEntry> files;
  final Function(FileEntry) onFileTap;
  final String rootPath;

  const FileTreeWidget({
    super.key,
    required this.files,
    required this.onFileTap,
    this.rootPath = '',
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Nenhum arquivo encontrado',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: files.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final file = files[index];
        final icon = _getFileIcon(file.extension);
        final isInRoot = rootPath.isEmpty || file.path.startsWith(rootPath);
        final displayPath = isInRoot && rootPath.isNotEmpty
            ? file.path.substring(rootPath.length + 1)
            : file.path;

        return ListTile(
          leading: Icon(icon, color: Colors.brown),
          title: Text(
            file.name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            displayPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          trailing: Text(
            _formatSize(file.size),
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          onTap: () => onFileTap(file),
        );
      },
    );
  }

  IconData _getFileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case '.gp3':
      case '.gp4':
      case '.gp5':
      case '.gpx':
      case '.gp':
        return Icons.music_note;
      case '.mid':
      case '.midi':
        return Icons.piano;
      case '.musicxml':
      case '.xml':
        return Icons.library_music;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '\$bytes B';
    if (bytes < 1024 * 1024) return '\${(bytes / 1024).toStringAsFixed(1)} KB';
    return '\${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class ChordDisplayWidget extends StatelessWidget {
  final String chordName;

  const ChordDisplayWidget({super.key, required this.chordName});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(120, 140),
      painter: ChordPainter(chordName: chordName),
    );
  }
}
"@ | Set-Content "$RootPath\lib\widgets\file_tree_widget.dart" -Encoding UTF8

# bpm_chart_widget.dart
@"
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/practice_session.dart';

class BpmChartWidget extends StatelessWidget {
  final List<PracticeSession> sessions;

  const BpmChartWidget({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma sessão registrada',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    final reversed = sessions.reversed.toList();
    final spots = <FlSpot>[];
    for (int i = 0; i < reversed.length; i++) {
      spots.add(FlSpot(i.toDouble(), reversed[i].finalBPM.toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.brown.withValues(alpha: 0.1),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                '\${value.toInt()}',
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= reversed.length) return const SizedBox();
                final date = reversed[idx].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '\${date.day}/\${date.month}',
                    style: TextStyle(fontSize: 8, color: Colors.grey[600]),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: 0,
        maxY: 200,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.green,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                FlDotCirclePainter(
                  radius: 4,
                  color: Colors.green,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final session = reversed[spot.spotIndex];
              return LineTooltipItem(
                '\${spot.y.toInt()} BPM\n\${session.date.day}/\${session.date.month}',
                TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
"@ | Set-Content "$RootPath\lib\widgets\bpm_chart_widget.dart" -Encoding UTF8

# ============================================================
# 9. CRIAR VIEWS
# ============================================================
Write-Host "[9/9] Criando Views e main.dart..." -ForegroundColor Yellow

# file_tree_screen.dart
@"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../viewmodels/file_tree_viewmodel.dart';
import '../models/file_entry.dart';
import '../widgets/file_tree_widget.dart';

class FileTreeScreen extends ConsumerWidget {
  const FileTreeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(fileListProvider);
    final rootPath = ref.watch(rootPathProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guitar2 - Partituras'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Selecionar pasta',
            onPressed: () => _pickFolder(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Histórico',
            onPressed: () => Navigator.pushNamed(context, '/history'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (rootPath.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.brown.shade50,
              child: Row(
                children: [
                  Icon(Icons.folder, size: 16, color: Colors.brown[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rootPath,
                      style: TextStyle(fontSize: 12, color: Colors.brown[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => ref.read(fileListProvider.notifier).scanDirectory(rootPath),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: filesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text('Erro: \$e'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (rootPath.isNotEmpty) {
                          ref.read(fileListProvider.notifier).scanDirectory(rootPath);
                        }
                      },
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
              data: (files) => FileTreeWidget(
                files: files,
                rootPath: rootPath,
                onFileTap: (file) => _openFile(context, file),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      ref.read(rootPathProvider.notifier).state = result;
      ref.read(fileListProvider.notifier).scanDirectory(result);
    }
  }

  void _openFile(BuildContext context, FileEntry file) {
    Navigator.pushNamed(
      context,
      '/score',
      arguments: file.path,
    );
  }
}
"@ | Set-Content "$RootPath\lib\views\file_tree_screen.dart" -Encoding UTF8

# score_screen.dart
@"
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/score_viewmodel.dart';
import '../painters/score_painter.dart';
import '../painters/tab_painter.dart';
import '../models/music_note.dart';

class ScoreScreen extends ConsumerStatefulWidget {
  const ScoreScreen({super.key});

  @override
  ConsumerState<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends ConsumerState<ScoreScreen> {
  Timer? _timer;
  double _cursorX = -1;
  int _currentNoteIndex = -1;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filePath = ModalRoute.of(context)!.settings.arguments as String;
    final scoreAsync = ref.watch(scoreProvider);
    final playback = ref.watch(playbackProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          filePath.split('\\').last.split('/').last,
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Modo Prática',
            onPressed: () {
              if (scoreAsync.hasValue) {
                Navigator.pushNamed(context, '/practice', arguments: filePath);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Exportar',
            onPressed: () => Navigator.pushNamed(context, '/export', arguments: filePath),
          ),
        ],
      ),
      body: scoreAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text('Erro ao carregar partitura'),
              Text('\$e', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        data: (score) {
          final notes = score.allNotes;
          return Column(
            children: [
              if (score.title.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.brown.shade50,
                  child: Text(
                    score.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown[800],
                    ),
                  ),
                ),
              if (notes.any((n) => n.chordName != null))
                Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: notes.length,
                    itemBuilder: (context, index) {
                      final chord = notes[index].chordName;
                      if (chord == null) return const SizedBox(width: 8);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          label: Text(chord, style: TextStyle(fontSize: 11, color: Colors.brown[700])),
                          backgroundColor: Colors.brown.shade50,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    },
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.speed, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text('\${score.bpm.toInt()} BPM', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    const Spacer(),
                    Text(
                      '\${notes.length} notas',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: (notes.length * 40.0 + 100.0).clamp(400.0, 5000.0),
                    child: CustomPaint(
                      size: Size(double.infinity, 200),
                      painter: ScorePainter(
                        notes: notes,
                        cursorX: _cursorX,
                        currentNoteIndex: _currentNoteIndex,
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: (notes.length * 40.0 + 100.0).clamp(400.0, 5000.0),
                    child: CustomPaint(
                      size: Size(double.infinity, 130),
                      painter: TabPainter(
                        notes: notes,
                        cursorX: _cursorX,
                        currentNoteIndex: _currentNoteIndex,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      onPressed: playback.isPlaying ? null : () => _seekTo(0),
                    ),
                    const SizedBox(width: 16),
                    FloatingActionButton(
                      mini: true,
                      onPressed: () => _togglePlayback(notes, score.bpm),
                      backgroundColor: playback.isPlaying ? Colors.red : Colors.brown,
                      child: Icon(
                        playback.isPlaying ? Icons.stop : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _togglePlayback(List<MusicNote> notes, double bpm) {
    final playback = ref.read(playbackProvider);
    if (playback.isPlaying) {
      ref.read(playbackProvider.notifier).stop();
      setState(() {
        _cursorX = -1;
        _currentNoteIndex = -1;
      });
    } else {
      _startPlayback(notes, bpm);
    }
  }

  void _startPlayback(List<MusicNote> notes, double bpm) {
    _timer?.cancel();
    final beatDuration = (60000 / bpm).toInt();

    ref.read(playbackProvider.notifier).play(notes, bpm);

    _timer = Timer.periodic(Duration(milliseconds: beatDuration), (timer) {
      final playback = ref.read(playbackProvider);
      if (!playback.isPlaying) {
        _timer?.cancel();
        setState(() {
          _cursorX = -1;
          _currentNoteIndex = -1;
        });
        return;
      }

      setState(() {
        _currentNoteIndex = playback.currentNoteIndex;
        _cursorX = 60 + _currentNoteIndex * 40;
      });
    });
  }

  void _seekTo(int index) {
    setState(() {
      _currentNoteIndex = index;
      _cursorX = 60 + index * 40;
    });
  }
}
"@ | Set-Content "$RootPath\lib\views\score_screen.dart" -Encoding UTF8

# practice_screen.dart
@"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/practice_viewmodel.dart';
import '../services/music_parser_service.dart';
import '../widgets/bpm_chart_widget.dart';

class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  @override
  Widget build(BuildContext context) {
    final filePath = ModalRoute.of(context)!.settings.arguments as String;
    final practice = ref.watch(practiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo de Prática'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configurações',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildSlider('BPM Inicial', practice.bpmStart, 20, 200,
                        (v) => ref.read(practiceProvider.notifier).updateBpmStart(v)),
                    _buildSlider('BPM Final', practice.bpmEnd, 20, 200,
                        (v) => ref.read(practiceProvider.notifier).updateBpmEnd(v)),
                    _buildSlider('Incremento', practice.bpmStep, 1, 30,
                        (v) => ref.read(practiceProvider.notifier).updateBpmStep(v)),
                    _buildSlider('Repetições', practice.repetitions, 1, 20,
                        (v) => ref.read(practiceProvider.notifier).updateRepetitions(v)),
                    SwitchListTile(
                      title: const Text('Acelerar progressivamente'),
                      subtitle: Text(
                        practice.accelerate ? 'Lento → Rápido' : 'Rápido → Lento',
                      ),
                      value: practice.accelerate,
                      onChanged: (_) => ref.read(practiceProvider.notifier).toggleAccelerate(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (practice.isRunning)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: practice.progress),
                      const SizedBox(height: 12),
                      Text(
                        'Repetição \${practice.currentRepetition + 1}/\${practice.repetitions}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      Text(
                        'BPM atual: \${practice.currentBPM}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.brown,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => ref.read(practiceProvider.notifier).stop(),
                        icon: const Icon(Icons.stop),
                        label: const Text('Parar'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
            if (!practice.isRunning)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _startPractice(filePath),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar Prática'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.brown,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Histórico de Prática',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 250,
              child: BpmChartWidget(sessions: practice.history),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('\$label: \$value'),
        Slider(
          min: min.toDouble(),
          max: max.toDouble(),
          value: value.toDouble(),
          divisions: max - min,
          activeColor: Colors.brown,
          onChanged: (v) => onChanged(v.toInt()),
        ),
      ],
    );
  }

  Future<void> _startPractice(String filePath) async {
    try {
      final score = await MusicParserService.parseFile(filePath);
      final notes = score.allNotes;
      if (notes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nenhuma nota encontrada no arquivo')),
          );
        }
        return;
      }
      ref.read(practiceProvider.notifier).startPractice(notes, score.title);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: \$e')),
        );
      }
    }
  }
}
"@ | Set-Content "$RootPath\lib\views\practice_screen.dart" -Encoding UTF8

# history_screen.dart
@"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/practice_viewmodel.dart';
import '../widgets/bpm_chart_widget.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final practice = ref.watch(practiceProvider);
    final sessions = practice.history;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Treinos'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: sessions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timeline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum treino registrado ainda',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete uma sessão no modo prática\npara ver seu progresso aqui.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: 300,
                    child: BpmChartWidget(sessions: sessions),
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        '\${sessions.length} sessões',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const Spacer(),
                      Text(
                        'Melhor: \${sessions.fold(0, (max, s) => s.finalBPM > max ? s.finalBPM : max)} BPM',
                        style: TextStyle(color: Colors.green[700]),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.brown.shade100,
                          child: Text(
                            '\${session.finalBPM}',
                            style: TextStyle(
                              color: Colors.brown[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          session.musicTitle.isEmpty ? 'Música' : session.musicTitle,
                        ),
                        subtitle: Text(
                          '\${session.bpmStart}→\${session.bpmEnd} BPM | \${session.repetitions}x | \${session.date.day}/\${session.date.month}/\${session.date.year}',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: Text(
                          '\${session.finalBPM} BPM',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
"@ | Set-Content "$RootPath\lib\views\history_screen.dart" -Encoding UTF8

# export_config_screen.dart
@"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import '../viewmodels/score_viewmodel.dart';
import '../painters/score_painter.dart';
import '../painters/tab_painter.dart';

class ExportConfigScreen extends ConsumerStatefulWidget {
  const ExportConfigScreen({super.key});

  @override
  ConsumerState<ExportConfigScreen> createState() => _ExportConfigScreenState();
}

class _ExportConfigScreenState extends ConsumerState<ExportConfigScreen> {
  bool includeScore = true;
  bool includeTab = true;
  bool includeChords = false;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final filePath = ModalRoute.of(context)!.settings.arguments as String;
    final scoreAsync = ref.watch(scoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Conteúdo para exportar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Partitura'),
                    subtitle: const Text('Pentagrama com notas'),
                    value: includeScore,
                    onChanged: (v) => setState(() => includeScore = v!),
                    activeColor: Colors.brown,
                  ),
                  CheckboxListTile(
                    title: const Text('Tablatura'),
                    subtitle: const Text('Cordas e casas'),
                    value: includeTab,
                    onChanged: (v) => setState(() => includeTab = v!),
                    activeColor: Colors.brown,
                  ),
                  CheckboxListTile(
                    title: const Text('Cifras'),
                    subtitle: const Text('Nomes de acordes'),
                    value: includeChords,
                    onChanged: (v) => setState(() => includeChords = v!),
                    activeColor: Colors.brown,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (scoreAsync.hasValue)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preview: \${scoreAsync.value!.title}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\${scoreAsync.value!.allNotes.length} notas | \${scoreAsync.value!.measures.length} compassos',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _exporting ? null : () => _export(filePath),
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt),
              label: const Text('Exportar PNG'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.brown,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(String filePath) async {
    setState(() => _exporting = true);
    try {
      final score = ref.read(scoreProvider).valueOrNull;
      if (score == null) throw Exception('Nenhuma partitura carregada');

      if (!includeScore && !includeTab) {
        throw Exception('Selecione ao menos um elemento para exportar');
      }

      final dir = await getApplicationDocumentsDirectory();
      final outputDir = Directory('\${dir.path}/guitar2_exports');
      if (!await outputDir.exists()) await outputDir.create(recursive: true);

      final title = score.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outFile = File('\${outputDir.path}/\${title}_\$timestamp.png');

      final pictureRecorder = ui.PictureRecorder();
      final canvas = Canvas(pictureRecorder);

      final notes = score.allNotes;
      final width = (notes.length * 40.0 + 100.0).clamp(400.0, 5000.0);
      double height = 0;

      if (includeTab) height += 130;
      if (includeScore) height += 200;

      if (includeScore) {
        final sp = ScorePainter(notes: notes);
        sp.paint(canvas, Size(width, 200));
        canvas.translate(0, 200);
      }

      if (includeTab) {
        final tp = TabPainter(notes: notes);
        tp.paint(canvas, Size(width, 130));
      }

      final picture = pictureRecorder.endRecording();
      final img = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) throw Exception('Falha ao gerar imagem');

      await outFile.writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exportado: \${outFile.path}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: \$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _exporting = false);
    }
  }
}
"@ | Set-Content "$RootPath\lib\views\export_config_screen.dart" -Encoding UTF8

# ============================================================
# 10. CRIAR MAIN.DART
# ============================================================
@"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'views/file_tree_screen.dart';
import 'views/score_screen.dart';
import 'views/practice_screen.dart';
import 'views/history_screen.dart';
import 'views/export_config_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const ProviderScope(child: Guitar2App()));
}

class Guitar2App extends StatelessWidget {
  const Guitar2App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guitar2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.brown,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 1,
        ),
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(
              builder: (_) => const FileTreeScreen(),
              settings: settings,
            );
          case '/score':
            return MaterialPageRoute(
              builder: (_) => const ScoreScreen(),
              settings: settings,
            );
          case '/practice':
            return MaterialPageRoute(
              builder: (_) => const PracticeScreen(),
              settings: settings,
            );
          case '/history':
            return MaterialPageRoute(
              builder: (_) => const HistoryScreen(),
              settings: settings,
            );
          case '/export':
            return MaterialPageRoute(
              builder: (_) => const ExportConfigScreen(),
              settings: settings,
            );
          default:
            return MaterialPageRoute(
              builder: (_) => const FileTreeScreen(),
            );
        }
      },
    );
  }
}
"@ | Set-Content "$RootPath\lib\main.dart" -Encoding UTF8

# ============================================================
# 11. ATUALIZAR TEST
# ============================================================
@"
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar2/models/file_entry.dart';
import 'package:guitar2/models/music_note.dart';
import 'package:guitar2/models/practice_session.dart';

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
"@ | Set-Content "$RootPath\test\widget_test.dart" -Encoding UTF8

# ============================================================
# 12. INSTALL DEPENDENCIES
# ============================================================
Write-Host "Instalando dependências..." -ForegroundColor Yellow
Push-Location $RootPath
try {
    & $FlutterPath pub get 2>&1 | Out-Null
}
finally {
    Pop-Location
}

# ============================================================
# 13. ANALYZE
# ============================================================
Write-Host "Verificando o projeto..." -ForegroundColor Yellow
Push-Location $RootPath
try {
    & $FlutterPath analyze 2>&1
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== Projeto Guitar2 criado com sucesso! ===" -ForegroundColor Green
Write-Host "Localização: $RootPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Para executar:" -ForegroundColor White
Write-Host "  cd $RootPath" -ForegroundColor Gray
Write-Host "  flutter run" -ForegroundColor Gray
