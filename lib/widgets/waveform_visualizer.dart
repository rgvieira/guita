import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class WaveformVisualizer extends StatefulWidget {
  final bool isPlaying;

  const WaveformVisualizer({super.key, required this.isPlaying});

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('audio_visualizer');
  late final Ticker _ticker;
  final List<double> _bars = List.filled(32, 0);
  final List<double> _targets = List.filled(32, 0);
  final List<Color> _barColors = [];
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
    _generateGradient();
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  void _generateGradient() {
    _barColors.clear();
    for (int i = 0; i < 32; i++) {
      final t = i / 31;
      _barColors.add(Color.lerp(
        const Color(0xFF00F5FF),
        const Color(0xFF8B5CF6),
        t,
      )!);
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAudioData':
        if (call.arguments is List) {
          final levels = (call.arguments as List).map((e) => (e as num).toDouble()).toList();
          if (levels.length == 32) {
            setState(() {
              for (int i = 0; i < 32; i++) {
                _targets[i] = levels[i];
              }
            });
          }
        }
        break;
    }
  }

  @override
  void didUpdateWidget(WaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _startVisualizer();
      } else {
        _stopVisualizer();
      }
    }
  }

  Future<void> _startVisualizer() async {
    if (_started) return;
    try {
      final ok = await _channel.invokeMethod<bool>('start');
      if (ok == true) {
        _started = true;
      }
    } catch (e) {
      debugPrint('Visualizer start failed: $e');
    }
  }

  Future<void> _stopVisualizer() async {
    if (!_started) return;
    try {
      await _channel.invokeMethod('stop');
      _started = false;
    } catch (e) {
      debugPrint('Visualizer stop failed: $e');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _stopVisualizer();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    bool allZero = true;
    for (int i = 0; i < 32; i++) {
      _bars[i] += (_targets[i] - _bars[i]) * 0.2;
      _bars[i] = _bars[i].clamp(0.0, 1.0);
      if (_bars[i] > 0.01) allZero = false;
    }

    if (!widget.isPlaying && allZero) {
      _ticker.stop();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            const Color(0xFF0A0A1A),
          ],
        ),
      ),
      child: CustomPaint(
        size: const Size(double.infinity, double.infinity),
        painter: _WaveformPainter(_bars, _barColors, widget.isPlaying),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final List<Color> barColors;
  final bool isPlaying;

  _WaveformPainter(this.bars, this.barColors, this.isPlaying);

  @override
  void paint(Canvas canvas, Size size) {
    if (!isPlaying && bars.every((b) => b < 0.01)) return;

    final barCount = bars.length;
    final barWidth = (size.width - (barCount - 1) * 2) / barCount;
    final maxBarHeight = size.height * 0.85;
    final centerY = size.height / 2;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      final h = bars[i] * maxBarHeight;
      if (h < 1) continue;

      final x = i * (barWidth + 2);
      final radius = barWidth / 2;

      final color = Color.lerp(
        barColors[i],
        const Color(0xFFFF006E),
        bars[i] * 0.3,
      )!;

      paint.color = color.withValues(alpha: 0.7 + bars[i] * 0.3);

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, centerY - h / 2, barWidth, h),
        Radius.circular(radius),
      );

      canvas.drawRRect(rect, paint);

      if (bars[i] > 0.5) {
        paint.color = color.withValues(alpha: (bars[i] - 0.5) * 0.4);
        final glowRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 1, centerY - h / 2 - 2, barWidth + 2, h + 4),
          Radius.circular(radius + 1),
        );
        canvas.drawRRect(glowRect, paint);
      }
    }

    final linePaint = Paint()
      ..color = const Color(0xFF00F5FF).withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) => true;
}
