class SmuflGlyphs {
  SmuflGlyphs._();

  // Clefs
  static const String gClef = '\u{E050}';
  static const String fClef = '\u{E062}';
  static const String cClef = '\u{E05C}';

  // Noteheads
  static const String noteheadBlack = '\u{E0A4}';
  static const String noteheadHalf = '\u{E0A3}';
  static const String noteheadWhole = '\u{E0A2}';
  static const String noteheadDoubleWhole = '\u{E0A1}';
  static const String noteheadX = '\u{E0A7}';
  static const String noteheadDiamond = '\u{E0A9}';
  static const String noteheadTriangle = '\u{E0AF}';

  // Accidentals
  static const String sharp = '\u{E262}';
  static const String flat = '\u{E260}';
  static const String natural = '\u{E261}';
  static const String doubleSharp = '\u{E263}';
  static const String doubleFlat = '\u{E264}';

  // Rests
  static const String restWhole = '\u{E4E3}';
  static const String restHalf = '\u{E4E4}';
  static const String restQuarter = '\u{E4E5}';
  static const String restEighth = '\u{E4E6}';
  static const String restSixteenth = '\u{E4E7}';
  static const String restThirtySecond = '\u{E4E8}';

  // Flags
  static const String flagEighthUp = '\u{E240}';
  static const String flagEighthDown = '\u{E241}';
  static const String flagSixteenthUp = '\u{E242}';
  static const String flagSixteenthDown = '\u{E243}';
  static const String flagThirtySecondUp = '\u{E244}';
  static const String flagThirtySecondDown = '\u{E245}';

  // Time signatures
  static const String timeSig4over4 = '\u{E08A}';
  static const String timeSigCommon = '\u{E08A}';
  static const String timeSigCut = '\u{E08B}';

  // Dynamics
  static const String dynamicPP = '\u{E52A}';
  static const String dynamicP = '\u{E520}';
  static const String dynamicMP = '\u{E52B}';
  static const String dynamicMF = '\u{E52C}';
  static const String dynamicF = '\u{E522}';
  static const String dynamicFF = '\u{E532}';

  // Articulations
  static const String accent = '\u{E4A0}';
  static const String staccato = '\u{E4A2}';
  static const String tenuto = '\u{E4A4}';
  static const String marcato = '\u{E4AC}';

  // Ornaments
  static const String trill = '\u{E566}';
  static const String turn = '\u{E567}';
  static const String mordent = '\u{E568}';
  static const String tremolo = '\u{E568}';

  // Barlines
  static const String barlineSingle = '\u{E030}';
  static const String barlineDouble = '\u{E031}';
  static const String barlineFinal = '\u{E032}';
  static const String barlineRepeatLeft = '\u{E040}';
  static const String barlineRepeatRight = '\u{E041}';

  // Ottava
  static const String ottavaAlta = '\u{E510}';
  static const String ottavaBassa = '\u{E512}';
  static const String quindicesimaAlta = '\u{E511}';
  static const String quindicesimaBassa = '\u{E513}';

  // Pedal
  static const String pedalMark = '\u{E500}';
  static const String pedalUp = '\u{E501}';

  // String numbers
  static const String string0 = '\u{E610}';
  static const String string1 = '\u{E611}';
  static const String string2 = '\u{E612}';
  static const String string3 = '\u{E613}';
  static const String string4 = '\u{E614}';
  static const String string5 = '\u{E615}';
  static const String string6 = '\u{E616}';
  static const String string7 = '\u{E617}';
  static const String string8 = '\u{E618}';
  static const String string9 = '\u{E619}';

  // Fretboard
  static const String guitarFretboard = '\u{E850}';
  static const String guitarString = '\u{E851}';

  // Noteheads by duration
  static String noteheadForDuration(int quarters) {
    if (quarters >= 16) return noteheadWhole;
    if (quarters >= 8) return noteheadHalf;
    return noteheadBlack;
  }

  static String restForDuration(int quarters) {
    if (quarters >= 16) return restWhole;
    if (quarters >= 8) return restHalf;
    if (quarters >= 4) return restQuarter;
    if (quarters >= 2) return restEighth;
    return restSixteenth;
  }

  static String flagForDuration(int quarters, bool up) {
    if (quarters <= 1) {
      return up ? flagSixteenthUp : flagSixteenthDown;
    }
    return up ? flagEighthUp : flagEighthDown;
  }
}
