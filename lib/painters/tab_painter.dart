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

  static const double lineSpacing = 16.0;
  static const double noteSpacing = 35.0;
  static const double leftMargin = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    const stringNames = ['e', 'B', 'G', 'D', 'A', 'E'];
    final startY = 20.0;
    final effectiveWidth = size.width;

    // String lines
    for (int i = 0; i < 6; i++) {
      final y = startY + i * lineSpacing;
      final isThick = i == 5;
      canvas.drawLine(
        Offset(0, y),
        Offset(effectiveWidth, y),
        Paint()
          ..color = Colors.brown.withValues(alpha: isThick ? 0.7 : 0.4)
          ..strokeWidth = isThick ? 2.0 : 1.0,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: stringNames[i],
          style: TextStyle(fontSize: 9, color: Colors.brown[700], fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - 7));
    }

    // Bar lines
    const beatsPerBar = 4;
    if (notes.isNotEmpty) {
      for (int i = 0; i < notes.length; i += beatsPerBar) {
        final x = leftMargin + i * noteSpacing;
        canvas.drawLine(
          Offset(x, startY - 4),
          Offset(x, startY + 5 * lineSpacing + 4),
          Paint()..color = Colors.brown..strokeWidth = 1.0,
        );
      }
    }

    // Fret numbers
    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      if (note.isRest || note.string == 0) continue;

      final x = leftMargin + i * noteSpacing;
      if (x > effectiveWidth) break;

      final stringIndex = 6 - note.string;
      final y = startY + stringIndex * lineSpacing;

      final isHighlight = i == currentNoteIndex;

      if (isHighlight) {
        canvas.drawCircle(Offset(x, y), 9, Paint()..color = Colors.orange);
      }

      final tp = TextPainter(
        text: TextSpan(
          text: '${note.fret}',
          style: TextStyle(
            fontSize: isHighlight ? 13 : 10,
            color: isHighlight ? Colors.white : Colors.black87,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    // Cursor
    if (cursorX > 0) {
      canvas.drawLine(
        Offset(cursorX, 0),
        Offset(cursorX, size.height),
        Paint()..color = Colors.red..strokeWidth = 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TabPainter oldDelegate) =>
    oldDelegate.notes != notes ||
    oldDelegate.cursorX != cursorX ||
    oldDelegate.currentNoteIndex != currentNoteIndex;
}
