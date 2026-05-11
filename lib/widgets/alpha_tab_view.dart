import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AlphaTabView extends StatefulWidget {
  final String filePath;
  final void Function(int playerState)? onPlayerStateChanged;
  final void Function()? onSoundFontLoaded;
  final void Function()? onScoreLoaded;
  final void Function(String message)? onError;
  final void Function(String? trackInfo)? onTrackChanged;

  const AlphaTabView({
    super.key,
    required this.filePath,
    this.onPlayerStateChanged,
    this.onSoundFontLoaded,
    this.onScoreLoaded,
    this.onError,
    this.onTrackChanged,
  });

  @override
  State<AlphaTabView> createState() => AlphaTabViewState();
}

class AlphaTabViewState extends State<AlphaTabView> {
  MethodChannel? _channel;
  int trackCount = 1;
  int currentTrack = 0;
  List<String>? _trackNames;

  @override
  void didUpdateWidget(AlphaTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filePath != oldWidget.filePath) {
      trackCount = 1;
      currentTrack = 0;
      if (_channel != null) {
        _loadFile();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Center(child: Text('Only supported on Android'));
    }
    return AndroidView(
      viewType: 'alphatab_view',
      onPlatformViewCreated: _onPlatformViewCreated,
      layoutDirection: TextDirection.ltr,
    );
  }

  Future<void> _loadFile() async {
    await _channel!.invokeMethod('loadScore', widget.filePath);
  }

  Future<void> _onPlatformViewCreated(int id) async {
    _channel = MethodChannel('alphatab_$id');
    _channel!.setMethodCallHandler(_handleNativeMessage);
    await _sendSoundFont();
    await _loadFile();
  }

  Future<void> _sendSoundFont() async {
    try {
      final sfDir = Directory('${(await getTemporaryDirectory()).path}/soundfonts');
      if (!await sfDir.exists()) await sfDir.create(recursive: true);
      final sfFile = File('${sfDir.path}/TimGM6mb.sf2');
      if (!await sfFile.exists()) {
        final data = await rootBundle.load('assets/soundfonts/TimGM6mb.sf2');
        await sfFile.writeAsBytes(data.buffer.asUint8List());
      }
      await _channel?.invokeMethod('setSoundFontPath', sfFile.path);
    } catch (e) {
      debugPrint('Failed to send SoundFont: $e');
    }
  }

  List<String>? get trackNames => _trackNames;

  Future<dynamic> _handleNativeMessage(MethodCall call) async {
    switch (call.method) {
      case 'onScoreLoaded':
        widget.onScoreLoaded?.call();
        break;
      case 'onTrackNames':
        final namesStr = call.arguments as String?;
        if (namesStr != null && namesStr.isNotEmpty) {
          setState(() {
            _trackNames = namesStr.split('|');
          });
        }
        break;
      case 'onSoundFontLoaded':
        widget.onSoundFontLoaded?.call();
        break;
      case 'onPlayerStateChanged':
        widget.onPlayerStateChanged?.call(call.arguments as int);
        break;
      case 'onTrackChanged':
        final info = call.arguments as String?;
        if (info != null) {
          final parts = info.split('/');
          if (parts.length == 2) {
            currentTrack = int.tryParse(parts[0]) ?? 0;
            trackCount = int.tryParse(parts[1]) ?? 1;
          }
        }
        widget.onTrackChanged?.call(info);
        break;
      case 'onError':
        debugPrint('alphaTab error: ${call.arguments}');
        widget.onError?.call(call.arguments as String);
        break;
      case 'onRenderFinished':
        break;
    }
  }

  Future<void> play() => _channel?.invokeMethod('play') ?? Future.value();
  Future<void> pause() => _channel?.invokeMethod('pause') ?? Future.value();
  Future<void> stop() => _channel?.invokeMethod('stop') ?? Future.value();
  Future<void> nextTrack() => _channel?.invokeMethod('nextTrack') ?? Future.value();
  Future<void> prevTrack() => _channel?.invokeMethod('prevTrack') ?? Future.value();
  Future<void> setTrack(int index) => _channel?.invokeMethod('setTrack', index) ?? Future.value();
  Future<bool> toggleLayout() async {
    final result = await _channel?.invokeMethod<bool>('toggleLayout');
    return result ?? false;
  }
}
