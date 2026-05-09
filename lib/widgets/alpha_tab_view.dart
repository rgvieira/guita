import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AlphaTabView extends StatefulWidget {
  final String filePath;
  final void Function(int playerState)? onPlayerStateChanged;
  final void Function()? onSoundFontLoaded;
  final void Function()? onScoreLoaded;

  const AlphaTabView({
    super.key,
    required this.filePath,
    this.onPlayerStateChanged,
    this.onSoundFontLoaded,
    this.onScoreLoaded,
  });

  @override
  State<AlphaTabView> createState() => AlphaTabViewState();
}

class AlphaTabViewState extends State<AlphaTabView> {
  MethodChannel? _channel;
  bool _initialised = false;

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

  Future<void> _onPlatformViewCreated(int id) async {
    _channel = MethodChannel('alphatab_$id');
    _channel!.setMethodCallHandler(_handleNativeMessage);
    if (!_initialised) {
      _initialised = true;
      await _channel!.invokeMethod('loadScore', widget.filePath);
    }
  }

  Future<dynamic> _handleNativeMessage(MethodCall call) async {
    switch (call.method) {
      case 'onScoreLoaded':
        widget.onScoreLoaded?.call();
        break;
      case 'onSoundFontLoaded':
        widget.onSoundFontLoaded?.call();
        break;
      case 'onPlayerStateChanged':
        widget.onPlayerStateChanged?.call(call.arguments as int);
        break;
      case 'onError':
        debugPrint('alphaTab error: ${call.arguments}');
        break;
      case 'onRenderFinished':
        break;
    }
  }

  Future<void> play() => _channel?.invokeMethod('play') ?? Future.value();
  Future<void> pause() => _channel?.invokeMethod('pause') ?? Future.value();
  Future<void> stop() => _channel?.invokeMethod('stop') ?? Future.value();
}
