// ─────────────────────────────────────────────────────────────────────────────
// SCORE SHAPE — el score se codifica por FORMA, no por color
//
// Es la convención de la tarjeta de papel, y la app ya la insinuaba con el
// círculo de los birdies:
//
//     ◎  eagle o mejor   doble círculo
//     ○  birdie          círculo
//        par             sin adorno
//     □  bogey           cuadro
//     ▣  doble o peor    doble cuadro
//
// Por qué importa más allá del gusto: hasta ahora no se podía quitarle el rojo
// al bogey porque lo dejaría indistinguible de un par. El color era el único
// canal, así que estaba obligado a llevar información. Con la forma cargando el
// significado, el rojo saturado queda libre para el DINERO, que es el único sitio
// donde debe estar.
//
// Token y forma tenían que cambiar juntos, y por eso la fase 2 los dejó fuera.
//
// Consecuencia verificable: el score se distingue en escala de grises.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/app_theme.dart';

/// Forma del score respecto al par.
enum ScoreShape {
  /// Eagle o mejor: dos círculos.
  doubleCircle,

  /// Birdie: un círculo.
  circle,

  /// Par: nada. La ausencia de adorno ES la información.
  none,

  /// Bogey: un cuadro.
  square,

  /// Doble bogey o peor: dos cuadros.
  doubleSquare,
}

/// Qué forma le toca a un score.
///
/// [gross] puede ser 0 o negativo si el hoyo no se ha jugado; en ese caso no hay
/// forma que dibujar.
ScoreShape scoreShapeFor(int gross, int par) {
  if (gross <= 0) return ScoreShape.none;
  final delta = gross - par;
  if (delta <= -2) return ScoreShape.doubleCircle;
  if (delta == -1) return ScoreShape.circle;
  if (delta == 0) return ScoreShape.none;
  if (delta == 1) return ScoreShape.square;
  return ScoreShape.doubleSquare;
}

extension ScoreShapeInfo on ScoreShape {
  bool get esCirculo =>
      this == ScoreShape.circle || this == ScoreShape.doubleCircle;

  bool get esCuadro =>
      this == ScoreShape.square || this == ScoreShape.doubleSquare;

  bool get esDoble =>
      this == ScoreShape.doubleCircle || this == ScoreShape.doubleSquare;

  /// Nombre en golf, para lectores de pantalla y para tests.
  String get label => switch (this) {
        ScoreShape.doubleCircle => 'Eagle o mejor',
        ScoreShape.circle => 'Birdie',
        ScoreShape.none => 'Par',
        ScoreShape.square => 'Bogey',
        ScoreShape.doubleSquare => 'Doble bogey o peor',
      };
}

/// Un score con su forma.
///
/// El color del trazo TIÑE, no informa: quitarlo entero dejaría el score
/// igual de legible. Eso es lo que hace que el canal del color quede libre.
class GScoreShape extends StatelessWidget {
  final int gross;
  final int par;
  final GolfTheme t;

  /// Tamaño del número. La forma se dimensiona a partir de él.
  final double fontSize;

  /// Color del número. Por defecto el texto normal.
  final Color? color;

  const GScoreShape({
    super.key,
    required this.gross,
    required this.par,
    required this.t,
    this.fontSize = 15,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final forma = scoreShapeFor(gross, par);
    final tinte = color ??
        (forma.esCirculo
            ? t.scoreUnder
            : forma.esCuadro
                ? t.scoreOver
                : t.text);

    final numero = Text(
      gross <= 0 ? '–' : '$gross',
      style: TextStyle(
        color: gross <= 0 ? t.sub : tinte,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    if (forma == ScoreShape.none) {
      // El par no lleva adorno, pero SÍ ocupa lo mismo: sin este relleno la
      // columna baila entre hoyos y la tabla deja de leerse en vertical.
      return SizedBox(
        width: fontSize * 2.0,
        height: fontSize * 2.0,
        child: Center(child: numero),
      );
    }

    final lado = fontSize * 2.0;

    Widget capa(double tamano, double grosor) => Container(
          width: tamano,
          height: tamano,
          decoration: BoxDecoration(
            border: Border.all(color: tinte, width: grosor),
            borderRadius: BorderRadius.circular(
                forma.esCirculo ? tamano : fontSize * 0.28),
          ),
        );

    return SizedBox(
      width: lado,
      height: lado,
      child: Stack(alignment: Alignment.center, children: [
        capa(lado - 1, 1.4),
        // La segunda capa es lo que distingue eagle de birdie y doble de bogey
        // sin recurrir a otro color.
        if (forma.esDoble) capa(lado - 7, 1.1),
        Center(child: numero),
      ]),
    );
  }

  /// Radio de la forma, expuesto para que otras superficies la reproduzcan.
  static double radiusFor(ScoreShape forma, double fontSize) =>
      forma.esCirculo ? fontSize * 2.0 : fontSize * 0.28;
}
