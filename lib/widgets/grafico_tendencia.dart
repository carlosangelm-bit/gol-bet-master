// ─────────────────────────────────────────────────────────────────────────────
// EL GRÁFICO DE TENDENCIA — dibujado a mano, y por qué
//
// ── Por qué no una librería ─────────────────────────────────────────────────
//
// El proyecto no tiene ninguna, y añadir una dependencia aquí se decidió en vez
// de darse por hecho. Tres motivos, en orden de peso:
//
//   1 · El sistema manda sobre el gráfico. El encargo pide que salga de los
//       tokens —acento, escalera, tipografía—, no de la paleta de la librería.
//       Con una librería el trabajo no desaparece: se convierte en pelearse con
//       sus defaults, que es peor porque no se ve en el código de aquí.
//
//   2 · Es UN tipo de gráfico. Una línea con su relleno. Lo que una librería
//       aporta —doce tipos, interacción, animación— aquí no se usa.
//
//   3 · Y el proyecto ya pinta a mano en tres sitios: el cuadro de eliminación,
//       el fondo de la pantalla de entrada y el tablero de Inicio. Esto no
//       introduce una técnica nueva.
//
// ── EL COLOR: ni verde ni rojo, y no es una preferencia ─────────────────────
//
// Lo natural sería pintar de verde la mejora y de rojo el empeoramiento. Sería
// un error, y de los que este proyecto ya tiene fijado por escrito: el verde y
// el rojo saturados son el CANAL DEL DINERO —cobras, pagas— y hay un test que
// impide que otra cosa los reutilice. "Un canal, un significado".
//
// Un handicap bajando no es dinero cobrado. Es jugar mejor, que es exactamente
// lo que dice el CANAL DEL SCORE: `scoreUnder` para bajo par, `scoreOver` para
// sobre par. Baja saturación a propósito, porque el significado lo lleva la
// forma —la línea que baja— y el tono solo acompaña.
//
// Así que la tendencia usa el canal del score. Es el mismo idioma que ya habla
// la tarjeta hoyo a hoyo.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/tendencia.dart';

class GraficoTendencia extends StatelessWidget {
  final SerieDeTendencia serie;
  final GolfTheme t;
  final double alto;

  const GraficoTendencia({
    super.key,
    required this.serie,
    required this.t,
    this.alto = 64,
  });

  /// El color del rumbo. Ver la cabecera: canal del SCORE, nunca el del dinero.
  static Color colorDe(RumboDeTendencia rumbo, GolfTheme t) =>
      switch (rumbo) {
        RumboDeTendencia.mejora => t.scoreUnder,
        RumboDeTendencia.empeora => t.scoreOver,
        RumboDeTendencia.plana => t.sub,
      };

  @override
  Widget build(BuildContext context) {
    if (!serie.suficiente) return _Faltan(serie: serie, t: t);

    final color = colorDe(serie.rumbo, t);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(
            serie.rumbo == RumboDeTendencia.mejora
                ? Icons.trending_down
                : serie.rumbo == RumboDeTendencia.empeora
                    ? Icons.trending_up
                    : Icons.trending_flat,
            size: 15,
            color: color),
        const SizedBox(width: 6),
        // La frase lleva la CIFRA, no solo la dirección: "ha bajado" sin cuánto
        // deja al jugador mirando el gráfico para adivinarlo.
        Expanded(child: Text(serie.frase, style: GolfType.label(t.sub))),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: alto,
        width: double.infinity,
        child: CustomPaint(
          painter: _PintorDeTendencia(
            serie: serie,
            linea: color,
            reja: t.divider,
            fondo: t.card,
          ),
        ),
      ),
      const SizedBox(height: 5),
      // Los extremos, rotulados. Un gráfico sin escala es una forma bonita:
      // hay que poder leer de cuánto a cuánto.
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(serie.primero.toStringAsFixed(1), style: GolfType.label(t.sub)),
        Text('${serie.puntos.length} puntos', style: GolfType.label(t.sub)),
        Text(serie.ultimo.toStringAsFixed(1), style: GolfType.value(color, size: 15)),
      ]),
    ]);
  }
}

/// Lo que se ve mientras no hay suficientes rondas.
///
/// Es el criterio que más importa de este encargo: el estado NORMAL de una
/// cuenta nueva es no tener datos. Una línea de dos puntos presentada como
/// tendencia dice algo falso, y decir algo falso es peor que no decir nada.
class _Faltan extends StatelessWidget {
  final SerieDeTendencia serie;
  final GolfTheme t;
  const _Faltan({required this.serie, required this.t});

  @override
  Widget build(BuildContext context) {
    final f = serie.faltan;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.show_chart, size: 15, color: t.sub),
          const SizedBox(width: 6),
          Text('TENDENCIA', style: GolfType.label(t.sub)),
        ]),
        const SizedBox(height: 6),
        Text(
            f > 0
                // Con la cifra exacta: "faltan datos" no le dice a nadie
                // cuándo va a dejar de faltar.
                ? 'Te faltan $f ronda${f == 1 ? '' : 's'} para ver si tu '
                    'índice sube o baja.'
                : 'Con ${serie.rondas} rondas todavía no hay línea que contar.',
            style: TextStyle(color: t.text, fontSize: 12.5, height: 1.35)),
        const SizedBox(height: 4),
        Text(
            'Hacen falta ${SerieDeTendencia.minimoRondas}: con menos, una sola '
            'ronda mala manda sobre la pendiente y la línea diría algo que no '
            'es.',
            style: TextStyle(color: t.sub, fontSize: 11, height: 1.35)),
      ]),
    );
  }
}

/// Dónde cae cada punto dentro del lienzo.
///
/// Fuera del pintor y público a propósito: la geometría es lo único de este
/// archivo que se puede comprobar en un test, y es donde vive el error que no se
/// ve. Una serie plana dividiendo por cero, o el eje sin invertir —que se vería
/// perfectamente bien y diría lo contrario de lo que pasa— no los caza mirar la
/// pantalla.
List<Offset> posicionesDeTendencia(SerieDeTendencia s, Size size) {
  final n = s.puntos.length;
  if (n == 0) return const [];

  // Un margen arriba y abajo para que la línea no se pegue al borde.
  const margen = 6.0;
  final alto = size.height - margen * 2;

  // OJO: rango cero. Una serie perfectamente plana —que pasa: cinco rondas
  // clavadas en 10,4— daría una división por cero y la línea saldría fuera del
  // lienzo o no saldría. Se centra, que es lo que significa "plana".
  final rango = s.maximo - s.minimo;
  double y(double v) => rango < 0.0001
      ? margen + alto / 2
      // Invertido: en golf, MENOS es mejor, así que el índice más bajo va
      // ARRIBA. Sin esto la línea diría lo contrario de lo que pasa.
      : margen + alto * ((v - s.minimo) / rango);

  // Con un solo punto no hay ancho que repartir: va al centro.
  double x(int i) => n == 1 ? size.width / 2 : size.width * (i / (n - 1));

  return [
    for (var i = 0; i < n; i++) Offset(x(i), y(s.puntos[i].indice)),
  ];
}

class _PintorDeTendencia extends CustomPainter {
  final SerieDeTendencia serie;
  final Color linea;
  final Color reja;
  final Color fondo;

  const _PintorDeTendencia({
    required this.serie,
    required this.linea,
    required this.reja,
    required this.fondo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pts = posicionesDeTendencia(serie, size);
    if (pts.isEmpty) return;

    // La reja: una línea a media altura. Referencia, no decoración — sin ella
    // no se sabe si la curva se mueve mucho o poco.
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = reja
        ..strokeWidth = 1,
    );

    final trazo = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      trazo.lineTo(p.dx, p.dy);
    }

    // El relleno bajo la línea, muy tenue. Da cuerpo sin competir con el trazo.
    final relleno = Path.from(trazo)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
        relleno, Paint()..color = linea.withValues(alpha: 0.12));

    canvas.drawPath(
      trazo,
      Paint()
        ..color = linea
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    // El último punto, marcado. Es el valor de hoy: el que se busca al mirar.
    canvas.drawCircle(pts.last, 3.5, Paint()..color = fondo);
    canvas.drawCircle(
      pts.last,
      3.5,
      Paint()
        ..color = linea
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_PintorDeTendencia v) =>
      v.serie.puntos.length != serie.puntos.length ||
      v.serie.ultimo != serie.ultimo ||
      v.linea != linea;
}
