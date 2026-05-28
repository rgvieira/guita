import 'package:flutter/services.dart';

class AudioEffectsService {
  static const _channel = MethodChannel('audio_effects');

  double masterVolume = 1.0;
  bool _initialized = false;

  int bandCount = 0;
  List<int> bandFreqs = [];
  int minLevel = 0;
  int maxLevel = 0;

  int reverbPreset = 0;
  int bassBoost = 0;
  int delayMs = 0;
  double delayFeedback = 0;
  int distortionDrive = 0;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final info = Map<String, dynamic>.from(
        await _channel.invokeMethod('init') as Map,
      );
      bandCount = info['bandCount'] as int? ?? 0;
      bandFreqs = List<int>.from(info['bandFreqs'] as List? ?? []);
      minLevel = info['minLevel'] as int? ?? 0;
      maxLevel = info['maxLevel'] as int? ?? 0;
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  Future<void> setVolume(double volume) async {
    masterVolume = volume.clamp(0.0, 1.0);
  }

  Future<void> release() async {
    _initialized = false;
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
  }
}
