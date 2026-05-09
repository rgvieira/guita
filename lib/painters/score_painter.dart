import 'package:flutter/material.dart';
import '../models/music_note.dart';

class ScorePainter extends CustomPainter {
  final List<MusicNote> notes;
  final double cursorX;
  final int currentNoteIndex;

  ScorePainter({
    required this.notes,
    this.cursorX = -1,
    this.currentNoteIndex = -1,
  });

  static const double lineSpacing = 10.0;
  static const double noteSpacing = 35.0;
  static const double leftMargin = 50.0;

  int _diatonicIndex(String step) {
    const map = {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6};
    return map[step[0]] ?? 0;
  }

  double _noteY(double staffBottom, int pos) {
    return staffBottom - pos * lineSpacing / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF5D4037);
    final staffTop = 30.0;
    final staffBottom = staffTop + 4 * lineSpacing;
    final effectiveWidth = size.width;

    // Staff lines
    for (int i = 0; i < 5; i++) {
      final y = staffTop + i * lineSpacing;
      canvas.drawLine(Offset(0, y), Offset(effectiveWidth, y), paint..strokeWidth = 0.8);
    }

    // Bar lines (every 4 "beats" visually — approximate)
    const beatsPerBar = 4;
    if (notes.isNotEmpty) {
      for (int i = 0; i < notes.length; i += beatsPerBar) {
        final x = leftMargin + i * noteSpacing;
        canvas.drawLine(Offset(x, staffTop - 5), Offset(x, staffBottom + 5), paint..strokeWidth = 1.0);
      }
    }

    // Notes
    const noteHeadW = 8.0;
    const noteHeadH = 6.0;

    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      if (note.isRest) continue;

      final x = leftMargin + i * noteSpacing;
      if (x > effectiveWidth) break;

      final di = _diatonicIndex(note.step);
      final pos = (note.octave * 7 + di) - 30; // 0 = E4 bottom line
      final y = _noteY(staffBottom, pos);
      final isHighlight = i == currentNoteIndex;

      // Ledger lines
      if (pos < 0) {
        for (int l = pos; l <= 0; l += 2) {
          if (l % 2 == 0) {
            final ly = _noteY(staffBottom, l);
            canvas.drawLine(Offset(x - noteHeadW - 2, ly), Offset(x + noteHeadW + 2, ly), paint..strokeWidth = 0.8);
          }
        }
      } else if (pos > 8) {
        for (int l = 8; l <= pos; l += 2) {
          if (l % 2 == 0) {
            final ly = _noteY(staffBottom, l);
            canvas.drawLine(Offset(x - noteHeadW - 2, ly), Offset(x + noteHeadW + 2, ly), paint..strokeWidth = 0.8);
          }
        }
      }

      // Accidental
      if (note.step.length > 1) {
        final acc = note.step[1];
        if (acc == '#') {
          final tp = TextPainter(
            text: TextSpan(text: '♯', style: TextStyle(fontSize: 10, color: Colors.black)),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x - noteHeadW - tp.width - 3, y - tp.height / 2));
        } else if (acc == 'b') {
          final tp = TextPainter(
            text: TextSpan(text: '♭', style: TextStyle(fontSize: 10, color: Colors.black)),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x - noteHeadW - tp.width - 3, y - tp.height / 2));
        }
      }

      // Note head
      if (isHighlight) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: noteHeadW * 1.3, height: noteHeadH * 1.3),
          Paint()..color = Colors.orange,
        );
      }

      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: noteHeadW, height: noteHeadH),
        Paint()..color = Colors.black,
      );

      // Stem
      final stemUp = pos < 4;
      final stemLen = lineSpacing * 3.5;
      if (stemUp) {
        canvas.drawLine(Offset(x + noteHeadW / 2, y), Offset(x + noteHeadW / 2, y - stemLen), paint..strokeWidth = 1.2);
      } else {
        canvas.drawLine(Offset(x - noteHeadW / 2, y), Offset(x - noteHeadW / 2, y + stemLen), paint..strokeWidth = 1.2);
      }

      // Flag for quarter note / beaming indicator (simple flag shape for 8th notes)
      if (note.duration >= 8 && note.duration < 16) {
        final flagX = stemUp ? x + noteHeadW / 2 : x - noteHeadW / 2;
        final flagTop = stemUp ? y - stemLen : y + stemLen;
        final flagPath = Path()
          ..moveTo(flagX, flagTop)
          ..quadraticBezierTo(
            stemUp ? flagX + 8 : flagX - 8,
            stemUp ? flagTop + lineSpacing : flagTop - lineSpacing,
            stemUp ? flagX + 2 : flagX - 2,
            stemUp ? flagTop + lineSpacing * 1.5 : flagTop - lineSpacing * 1.5,
          );
        canvas.drawPath(flagPath, paint..strokeWidth = 1.5..style = PaintingStyle.fill);
      }

      // Fret number below (small)
      if (note.fret > 0 || note.string > 0) {
        final fretTp = TextPainter(
          text: TextSpan(
            text: '${note.fret}',
            style: TextStyle(fontSize: 7, color: Colors.grey[600]),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        fretTp.paint(canvas, Offset(x - fretTp.width / 2, staffBottom + 10));
      }
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
  bool shouldRepaint(covariant ScorePainter oldDelegate) =>
    oldDelegate.notes != notes ||
    oldDelegate.cursorX != cursorX ||
    oldDelegate.currentNoteIndex != currentNoteIndex;
}
