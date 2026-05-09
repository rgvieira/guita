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
