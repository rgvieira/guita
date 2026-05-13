import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class MidiVisualizer extends StatefulWidget {
  final bool isPlaying;
  final Set<int> activeMidiNotes;

  const MidiVisualizer({
    super.key,
    required this.isPlaying,
    required this.activeMidiNotes,
  });

  @override
  State<MidiVisualizer> createState() => _MidiVisualizerState();
}

class _MidiVisualizerState extends State<MidiVisualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  static const int barCount = 32;
  final List<double> _currentHeights = List.filled(barCount, 0);
  final List<double> _targetHeights = List.filled(barCount, 0);
  final List<double> _velocities = List.filled(barCount, 0);
  double _masterLevel = 0;
  double _masterTarget = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void didUpdateWidget(MidiVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying && !_ticker.isActive) {
        _ticker.start();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = 0.016; // ~60fps tick interval

    // Compute target heights from active notes
    for (int i = 0; i < barCount; i++) {
      _targetHeights[i] = 0;
    }

    if (widget.isPlaying && widget.activeMidiNotes.isNotEmpty) {
      _masterTarget = 1.0;
      for (final midi in widget.activeMidiNotes) {
        final bar = ((midi - 12) * barCount / 96).round().clamp(0, barCount - 1);
        final vel = 0.5 + (midi % 12) / 24.0;
        if (vel > _targetHeights[bar]) {
          _targetHeights[bar] = vel;
        }
      }
    } else {
      _masterTarget = 0;
    }

    // Smooth interpolation
    _masterLevel += (_masterTarget - _masterLevel) * dt * 8;
    _masterLevel = _masterLevel.clamp(0, 1);

    for (int i = 0; i < barCount; i++) {
      final target = _targetHeights[i] * _masterLevel;
      if (target > _currentHeights[i]) {
        _currentHeights[i] += (target - _currentHeights[i]) * dt * 20;
      } else {
        _currentHeights[i] += (target - _currentHeights[i]) * dt * 6;
      }
      _currentHeights[i] = _currentHeights[i].clamp(0, 1);
      _velocities[i] = _currentHeights[i];
    }

    if (_masterLevel < 0.001 && _currentHeights.every((h) => h < 0.001)) {
      if (_ticker.isActive) _ticker.stop();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: CustomPaint(
          size: const Size(double.infinity, 56),
          painter: _SpectrumPainter(_currentHeights, _masterLevel),
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> heights;
  final double masterLevel;

  _SpectrumPainter(this.heights, this.masterLevel);

  @override
  void paint(Canvas canvas, Size size) {
    if (masterLevel < 0.01) return;

    final barW = (size.width - (heights.length - 1) * 2) / heights.length;
    final maxH = size.height - 8;
    final baseY = size.height - 4;

    for (int i = 0; i < heights.length; i++) {
      final h = heights[i] * maxH;
      if (h < 1) continue;

      final x = i * (barW + 2);
      final y = baseY - h;
      final fraction = i / heights.length;

      final color = Color.lerp(
        const Color(0xFFD4A24E),
        const Color(0xFF8B4513),
        fraction,
      )!.withValues(alpha: 0.6 + 0.4 * heights[i]);

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) => true;
}
