// ─────────────────────────────────────────────────────────────────────────────
// EL BALANCE, DIBUJADO
//
// ── EL COLOR: aquí SÍ el verde y el rojo, y es la excepción que confirma ────
//
// La regla del sistema es "un canal, un significado", y el verde y el rojo
// saturados están RESERVADOS al dinero: cobras y pagas. Hay un test que impide
// que otra cosa los use, y por eso la tendencia del handicap usa el canal del
// score — un índice bajando no es dinero cobrado.
//
// Esto sí es dinero. Es literalmente el canal para el que se reservaron, así
// que aquí usarlos no es una excepción a la regla: es la regla.
//
// Merece quedar escrito porque las dos decisiones se parecen y son contrarias:
// el mismo par de tonos, prohibido en un gráfico y obligatorio en el de al
// lado, por lo que MIDEN y no por cómo se ven.
//
// ── Y el pintor es el mismo ─────────────────────────────────────────────────
//
// Un segundo pintor con su propia geometría habría dado dos sitios donde
// arreglar el mismo eje invertido. Lo que cambia entre los dos gráficos es una
// bandera: en el handicap menos es mejor; aquí, más.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/serie_balance.dart';
import 'grafico_tendencia.dart';

class GraficoBalance extends StatelessWidget {
  final SerieDeBalance serie;
  final GolfTheme t;
  final double alto;

  /// Cómo se escribe el dinero. Viene de fuera porque el formato ya está
  /// decidido en otro sitio y no puede haber dos.
  final String Function(double) importe;

  const GraficoBalance({
    super.key,
    required this.serie,
    required this.t,
    required this.importe,
    this.alto = 56,
  });

  /// El color de la línea: el del dinero, según dónde acabe el saldo.
  static Color colorDe(SerieDeBalance s, GolfTheme t) {
    if (s.puntos.isEmpty) return t.sub;
    final v = s.total;
    // `even` para el cero: es un resultado, no un dato ausente. Mismo token que
    // usa el balance del duelo.
    if (v.abs() < 0.005) return t.even;
    return v > 0 ? t.profit : t.loss;
  }

  @override
  Widget build(BuildContext context) {
    if (!serie.suficiente) return _Faltan(serie: serie, t: t);

    final color = colorDe(serie, t);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: alto,
        width: double.infinity,
        child: CustomPaint(
          painter: PintorDeSerie(
            valores: serie.puntos.map((p) => p.acumulado).toList(),
            // Con dinero, MÁS es mejor: al revés que el handicap.
            menosEsMejor: false,
            // La reja en el CERO, no a media altura: por encima ganas, por
            // debajo pagas. Es lo que hace que la forma se lea de un vistazo.
            referencia: 0,
            linea: color,
            reja: t.divider,
            fondo: t.card,
          ),
        ),
      ),
      const SizedBox(height: 6),
      // Lo que la línea enseña y la cifra no: dónde estuvo lo mejor y lo peor.
      Row(children: [
        Expanded(
          child: Text(
              'Mejor ${importe(serie.mejor.delaRonda)} · '
              'Peor ${importe(serie.peor.delaRonda)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GolfType.label(t.sub)),
        ),
        Text('${serie.puntos.length} rondas', style: GolfType.label(t.sub)),
      ]),
      if (serie.cruzoElCero) ...[
        const SizedBox(height: 2),
        // Un +500 que nunca bajó de cero cuenta algo muy distinto de un +500
        // que estuvo en −800. La cifra sola no distingue esas dos historias.
        Text('El saldo cruzó el cero en algún momento',
            style: TextStyle(color: t.sub, fontSize: 10.5)),
      ],
    ]);
  }
}

/// Lo que se ve mientras no hay suficientes rondas.
class _Faltan extends StatelessWidget {
  final SerieDeBalance serie;
  final GolfTheme t;
  const _Faltan({required this.serie, required this.t});

  @override
  Widget build(BuildContext context) {
    final f = serie.faltan;
    return Text(
        f == SerieDeBalance.minimoRondas
            ? 'Cuando lleves ${SerieDeBalance.minimoRondas} rondas, aquí se '
                'verá cómo ha ido subiendo o bajando.'
            // Con la cifra exacta: "faltan datos" no dice cuándo dejan de
            // faltar.
            : 'Te falta${f == 1 ? '' : 'n'} $f ronda${f == 1 ? '' : 's'} para '
                'ver la forma de tu saldo, no solo el total.',
        style: TextStyle(color: t.sub, fontSize: 11, height: 1.35));
  }
}
