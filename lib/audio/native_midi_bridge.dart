import 'package:flutter/services.dart';

class NativeMidiBridge {
  static const _channel = MethodChannel('com.rgvieira63.guitarra/midi_audio');
  static bool _initialized = false;
  static bool _bridgeAvailable = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _channel.invokeMethod('ping');
      _bridgeAvailable = true;
    } catch (_) {
      _bridgeAvailable = false;
    }
  }

  static bool get isAvailable => _bridgeAvailable;

  static Future<void> sendNoteOn(int midiCode, int velocity) async {
    if (!_bridgeAvailable) return;
    try {
      await _channel.invokeMethod('sendNoteOn', {
        'note': midiCode,
        'velocity': velocity,
      });
    } catch (_) {}
  }

  static Future<void> sendNoteOff(int midiCode) async {
    if (!_bridgeAvailable) return;
    try {
      await _channel.invokeMethod('sendNoteOff', {
        'note': midiCode,
      });
    } catch (_) {}
  }

  static Future<void> allNotesOff() async {
    if (!_bridgeAvailable) return;
    try {
      await _channel.invokeMethod('allNotesOff');
    } catch (_) {}
  }
}
