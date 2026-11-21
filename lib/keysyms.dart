import 'package:flutter/services.dart';

/// X11 keysym değerleri (VNC'nin kullandığı tuş kodları).
class Ks {
  static const shiftL = 0xffe1;
  static const ctrlL = 0xffe3;
  static const altL = 0xffe9;
  static const superL = 0xffeb;
  static const esc = 0xff1b;
  static const tab = 0xff09;
  static const enter = 0xff0d;
  static const backspace = 0xff08;
  static const del = 0xffff;
  static const left = 0xff51;
  static const up = 0xff52;
  static const right = 0xff53;
  static const down = 0xff54;
  static const home = 0xff50;
  static const end = 0xff57;
  static const pgUp = 0xff55;
  static const pgDn = 0xff56;
  static const ins = 0xff63;
  static const f1 = 0xffbe;
  static const printScreen = 0xff61;

  static final Map<LogicalKeyboardKey, int> _special = {
    LogicalKeyboardKey.enter: enter,
    LogicalKeyboardKey.numpadEnter: 0xff8d,
    LogicalKeyboardKey.backspace: backspace,
    LogicalKeyboardKey.delete: del,
    LogicalKeyboardKey.tab: tab,
    LogicalKeyboardKey.escape: esc,
    LogicalKeyboardKey.arrowLeft: left,
    LogicalKeyboardKey.arrowUp: up,
    LogicalKeyboardKey.arrowRight: right,
    LogicalKeyboardKey.arrowDown: down,
    LogicalKeyboardKey.home: home,
    LogicalKeyboardKey.end: end,
    LogicalKeyboardKey.pageUp: pgUp,
    LogicalKeyboardKey.pageDown: pgDn,
    LogicalKeyboardKey.insert: ins,
    LogicalKeyboardKey.shiftLeft: shiftL,
    LogicalKeyboardKey.shiftRight: 0xffe2,
    LogicalKeyboardKey.controlLeft: ctrlL,
    LogicalKeyboardKey.controlRight: 0xffe4,
    LogicalKeyboardKey.altLeft: altL,
    LogicalKeyboardKey.altRight: 0xfe03,
    LogicalKeyboardKey.metaLeft: superL,
    LogicalKeyboardKey.metaRight: 0xffec,
    LogicalKeyboardKey.capsLock: 0xffe5,
    LogicalKeyboardKey.numLock: 0xff7f,
    LogicalKeyboardKey.scrollLock: 0xff14,
    LogicalKeyboardKey.printScreen: printScreen,
    LogicalKeyboardKey.pause: 0xff13,
    LogicalKeyboardKey.f1: f1,
    LogicalKeyboardKey.f2: f1 + 1,
    LogicalKeyboardKey.f3: f1 + 2,
    LogicalKeyboardKey.f4: f1 + 3,
    LogicalKeyboardKey.f5: f1 + 4,
    LogicalKeyboardKey.f6: f1 + 5,
    LogicalKeyboardKey.f7: f1 + 6,
    LogicalKeyboardKey.f8: f1 + 7,
    LogicalKeyboardKey.f9: f1 + 8,
    LogicalKeyboardKey.f10: f1 + 9,
    LogicalKeyboardKey.f11: f1 + 10,
    LogicalKeyboardKey.f12: f1 + 11,
  };

  static int? forLogical(LogicalKeyboardKey k) => _special[k];

  static int forChar(String c) {
    final code = c.runes.first;
    if (c == '\n' || c == '\r') return enter;
    if (c == '\t') return tab;
    if ((code >= 0x20 && code <= 0x7e) || (code >= 0xa0 && code <= 0xff)) return code;
    return 0x01000000 | code; // Unicode keysym (ş, ğ, ı ...)
  }

  /// ABD klavyesinde Shift gerektiren karakterler.
  static bool needsShift(String c) {
    if (c.toUpperCase() == c && c.toLowerCase() != c) return true;
    return '~!@#\$%^&*()_+{}|:"<>?'.contains(c);
  }

  static bool isModifier(int ks) => (ks >= 0xffe1 && ks <= 0xffee) || ks == 0xfe03;
}
