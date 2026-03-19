import 'package:flutter/material.dart';

enum AppThemeMode { light, dark, classic }

// ─── Paletas ──────────────────────────────────────────────────────────────────
class _P {
  // Light
  static const lBg      = Color(0xFFFFFFFF);
  static const lSurface = Color(0xFFF5F5F5);
  static const lCard    = Color(0xFFFFFFFF);
  static const lPrimary = Color(0xFF2E7D32);
  static const lOnPrim  = Color(0xFFFFFFFF);
  static const lText    = Color(0xFF1A1A1A);
  static const lSub     = Color(0xFF757575);
  static const lDiv     = Color(0xFFE0E0E0);
  static const lProfit  = Color(0xFF2E7D32);
  static const lLoss    = Color(0xFFC62828);
  static const lAccent  = Color(0xFF43A047);
  static const lUnder   = Color(0xFF1565C0);
  static const lOver    = Color(0xFFC62828);

  // Dark
  static const dBg      = Color(0xFF111111);
  static const dSurface = Color(0xFF1E1E1E);
  static const dCard    = Color(0xFF282828);
  static const dPrimary = Color(0xFF4CAF50);
  static const dOnPrim  = Color(0xFF000000);
  static const dText    = Color(0xFFEEEEEE);
  static const dSub     = Color(0xFF9E9E9E);
  static const dDiv     = Color(0xFF333333);
  static const dProfit  = Color(0xFF66BB6A);
  static const dLoss    = Color(0xFFEF5350);
  static const dAccent  = Color(0xFF81C784);
  static const dUnder   = Color(0xFF64B5F6);
  static const dOver    = Color(0xFFEF9A9A);

  // Classic (Verde fairway · Crema · Oro)
  static const cBg      = Color(0xFF1B5E20);
  static const cSurface = Color(0xFF194F1C);
  static const cCard    = Color(0xFF1E6125);
  static const cPrimary = Color(0xFFF9A825);
  static const cOnPrim  = Color(0xFF1B5E20);
  static const cText    = Color(0xFFFFF8E7);
  static const cSub     = Color(0xFFD4C89A);
  static const cDiv     = Color(0xFF2E7D32);
  static const cProfit  = Color(0xFFF9A825);
  static const cLoss    = Color(0xFFFFCDD2);
  static const cAccent  = Color(0xFFFBC02D);
  static const cUnder   = Color(0xFFF9A825);
  static const cOver    = Color(0xFFFFCDD2);
}

class GolfTheme {
  final Color bg, surface, card, primary, onPrimary;
  final Color text, sub, divider, profit, loss, accent;
  final Color scoreUnder, scoreOver;
  final Brightness brightness;

  const GolfTheme._({
    required this.bg, required this.surface, required this.card,
    required this.primary, required this.onPrimary,
    required this.text, required this.sub, required this.divider,
    required this.profit, required this.loss, required this.accent,
    required this.scoreUnder, required this.scoreOver,
    required this.brightness,
  });

  static const light = GolfTheme._(
    bg: _P.lBg, surface: _P.lSurface, card: _P.lCard,
    primary: _P.lPrimary, onPrimary: _P.lOnPrim,
    text: _P.lText, sub: _P.lSub, divider: _P.lDiv,
    profit: _P.lProfit, loss: _P.lLoss, accent: _P.lAccent,
    scoreUnder: _P.lUnder, scoreOver: _P.lOver,
    brightness: Brightness.light,
  );

  static const dark = GolfTheme._(
    bg: _P.dBg, surface: _P.dSurface, card: _P.dCard,
    primary: _P.dPrimary, onPrimary: _P.dOnPrim,
    text: _P.dText, sub: _P.dSub, divider: _P.dDiv,
    profit: _P.dProfit, loss: _P.dLoss, accent: _P.dAccent,
    scoreUnder: _P.dUnder, scoreOver: _P.dOver,
    brightness: Brightness.dark,
  );

  static const classic = GolfTheme._(
    bg: _P.cBg, surface: _P.cSurface, card: _P.cCard,
    primary: _P.cPrimary, onPrimary: _P.cOnPrim,
    text: _P.cText, sub: _P.cSub, divider: _P.cDiv,
    profit: _P.cProfit, loss: _P.cLoss, accent: _P.cAccent,
    scoreUnder: _P.cUnder, scoreOver: _P.cOver,
    brightness: Brightness.dark,
  );

  ThemeData toMaterial() => ThemeData(
    brightness: brightness,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: primary, onPrimary: onPrimary,
      secondary: accent, onSecondary: onPrimary,
      error: loss, onError: onPrimary,
      surface: surface, onSurface: text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg, foregroundColor: text, elevation: 0, centerTitle: false,
      titleTextStyle: TextStyle(color: text, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      iconTheme: IconThemeData(color: text),
    ),
    cardTheme: CardThemeData(
      color: card, elevation: brightness == Brightness.light ? 0.5 : 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
    textTheme: TextTheme(
      headlineLarge: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -0.5),
      headlineMedium: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 22),
      titleLarge: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 18),
      titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 16),
      titleSmall: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 14),
      bodyLarge: TextStyle(color: text, fontSize: 16),
      bodyMedium: TextStyle(color: text, fontSize: 14),
      bodySmall: TextStyle(color: sub, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: surface,
      labelStyle: TextStyle(color: sub),
      hintStyle: TextStyle(color: sub),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: divider)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: primary, width: 2)),
    ),
  );
}

// ── Global theme holder ────────────────────────────────────────────────────────
class GolfThemeExt {
  static GolfTheme _currentTheme = GolfTheme.light;
  static GolfTheme get current => _currentTheme;
  static void setCurrent(GolfTheme t) => _currentTheme = t;
}

// Extension para acceder al tema desde context
extension GolfThemeContext on BuildContext {
  GolfTheme get gt => GolfThemeExt.current;
}
