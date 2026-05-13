import 'package:flutter/services.dart';

class AudioEffectsService {
  static const _channel = MethodChannel('audio_effects');

  int bandCount = 0;
  List<int> bandFreqs = [];
  int minLevel = -1500;
  int maxLevel = 1500;

  final List<int> _eqLevels = [];

  int reverbPreset = 0;
  int bassBoost = 0;
  double masterVolume = 1.0;
  int delayMs = 0;
  double delayFeedback = 0;
  int distortionDrive = 0;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final info = Map<String, dynamic>.from(
        await _channel.invokeMethod('init') as Map,
      );
      bandCount = info['bandCount'] as int? ?? 0;
      bandFreqs = List<int>.from(info['bandFreqs'] as List? ?? []);
      minLevel = info['minLevel'] as int? ?? -1500;
      maxLevel = info['maxLevel'] as int? ?? 1500;
      _eqLevels.clear();
      for (int i = 0; i < bandCount; i++) {
        _eqLevels.add(0);
      }
      _initialized = true;
    } catch (e) {
      bandCount = 0;
      _initialized = false;
    }
  }

  int get eqLevel => _eqLevels.isEmpty ? 0 : _eqLevels[0];

  Future<void> setEqBand(int band, int level) async {
    if (band < 0 || band >= _eqLevels.length) return;
    _eqLevels[band] = level;
    try {
      await _channel.invokeMethod('setEqBand', {
        'band': band,
        'level': level,
      });
    } catch (_) {}
  }

  Future<void> setAllEqBands(int level) async {
    for (int i = 0; i < _eqLevels.length; i++) {
      await setEqBand(i, level);
    }
  }

  Future<void> setReverbPreset(int preset) async {
    reverbPreset = preset;
    try {
      await _channel.invokeMethod('setReverbPreset', {'preset': preset});
    } catch (_) {}
  }

  Future<void> setBassBoost(int strength) async {
    bassBoost = strength;
    try {
      await _channel.invokeMethod('setBassBoost', {'strength': strength});
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    masterVolume = volume;
    try {
      await _channel.invokeMethod('setVolume', {'volume': volume.clamp(0.0, 1.0)});
    } catch (_) {}
  }

  Future<void> release() async {
    _initialized = false;
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
  }

  /// Apply distortion velocity compression: 0 = none, 100 = max
  int applyDistortion(int velocity) {
    if (distortionDrive <= 0) return velocity;
    final drive = distortionDrive / 100.0;
    final compressed = velocity * (1 - drive * 0.6) +
        (velocity > 64 ? 127.0 : 0.0) * drive * 0.3;
    return compressed.round().clamp(1, 127);
  }
}
