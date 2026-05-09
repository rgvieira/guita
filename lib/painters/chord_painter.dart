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
