// ─────────────────────────────────────────────────────────────────────────────
// EL BALANCE EN EL TIEMPO
//
// En Inicio hay una cifra: "+$500". Y con muchas rondas, CUÁNDO se ganó y
// cuándo se perdió dice más que el total: +500 puede ser una racha buena de
// hace un año que se está deshaciendo, o una subida constante. El número no
// distingue esas dos cosas y la línea sí.
//
// ── ACUMULADO, y por qué no el resultado por ronda ──────────────────────────
//
// Parecían dos opciones y no lo son: una línea ACUMULADA lleva las dos dentro.
// La ALTURA de cada punto es el saldo de entonces; el ESCALÓN entre dos puntos
// es lo que se ganó o perdió esa ronda. Se leen las dos preguntas del mismo
// trazo.
//
// Y resuelve sola lo de las rondas sin dinero. Una ronda sin apuestas, o que
// acabó en ceros, no mueve el saldo: en un acumulado es un tramo PLANO, que es
// exactamente lo que pasó. En un gráfico por ronda sería un cero ocupando el
// mismo ancho que un ±$500 — el mismo espacio para "no pasó nada" y para "me
// llevé quinientos".
//
// ── Lo que NO hace falta aquí, al revés que en el handicap ──────────────────
//
// Ninguna guarda. El handicap necesitaba descartar diferenciales imposibles
// porque eran un cálculo roto sobre rondas a medias. Aquí no hay cálculo que
// romper: el balance de una ronda incompleta es dinero REAL, liquidado sobre
// los hoyos que se jugaron. Una ronda de nueve paga lo que pactaron nueve.
// ─────────────────────────────────────────────────────────────────────────────
import 'round_result.dart';

/// Un punto: cuánto llevabas acumulado después de esa ronda.
class PuntoDeBalance {
  final DateTime cuando;

  /// El saldo acumulado hasta aquí incluido.
  final double acumulado;

  /// Lo que se movió en ESTA ronda. Es el escalón.
  final double delaRonda;

  final String nombreDeLaRonda;

  const PuntoDeBalance({
    required this.cuando,
    required this.acumulado,
    required this.delaRonda,
    required this.nombreDeLaRonda,
  });

  /// La ronda no movió el saldo: sin apuestas, o todo en tablas.
  bool get plana => delaRonda.abs() < 0.005;
}

class SerieDeBalance {
  final List<PuntoDeBalance> puntos;

  const SerieDeBalance(this.puntos);

  /// Cuántas rondas hacen falta para dibujar.
  ///
  /// ── Cuatro, y por su propia razón ─────────────────────────────────────────
  ///
  /// En el handicap son once, y el motivo era muy concreto: hasta la séptima
  /// ronda el índice lleva un ajuste de la tabla WHS que se retira solo, así
  /// que los primeros puntos se movían por el andamiaje y no por el juego.
  ///
  /// Aquí no hay andamiaje. Cada punto es un HECHO: "después de la tercera
  /// ronda llevaba +150" es exactamente cierto desde la primera. Copiar el once
  /// habría escondido un gráfico correcto durante ocho rondas por un motivo que
  /// no aplica.
  ///
  /// Lo que sí sigue siendo verdad es que una línea de dos puntos siempre sube
  /// o baja, y con tres una sola ronda es un tercio de la forma. Cuatro es
  /// donde el trazo empieza a describir un camino en vez de un segmento.
  static const minimoRondas = 4;

  bool get suficiente => puntos.length >= minimoRondas;

  int get faltan => (minimoRondas - puntos.length).clamp(0, minimoRondas);

  /// El saldo de hoy. Es la cifra que la tarjeta ya enseñaba.
  double get total => puntos.isEmpty ? 0 : puntos.last.acumulado;

  double get maximo =>
      puntos.map((p) => p.acumulado).reduce((a, b) => a > b ? a : b);
  double get minimo =>
      puntos.map((p) => p.acumulado).reduce((a, b) => a < b ? a : b);

  /// La mejor ronda y la peor. Es lo que se busca al mirar la forma.
  PuntoDeBalance get mejor =>
      puntos.reduce((a, b) => b.delaRonda > a.delaRonda ? b : a);
  PuntoDeBalance get peor =>
      puntos.reduce((a, b) => b.delaRonda < a.delaRonda ? b : a);

  /// Cuántas rondas no movieron el saldo.
  int get planas => puntos.where((p) => p.plana).length;

  /// Si el saldo estuvo alguna vez en el otro lado del cero.
  ///
  /// Es lo que hace interesante la línea: un +500 que nunca bajó de cero cuenta
  /// algo muy distinto de un +500 que estuvo en −800.
  bool get cruzoElCero =>
      puntos.any((p) => p.acumulado > 0) && puntos.any((p) => p.acumulado < 0);
}

/// La serie acumulada de [resultados] para el jugador [miId].
///
/// El orden de entrada da igual: aquí se ordena por fecha, porque de eso depende
/// todo lo demás y confiar en el orden de quien llama es pedir un fallo
/// silencioso.
SerieDeBalance serieDeBalance(List<RoundResult> resultados, String miId) {
  final orden = [...resultados]
    ..sort((a, b) => a.playedAt.compareTo(b.playedAt));

  var acumulado = 0.0;
  final puntos = <PuntoDeBalance>[];
  for (final r in orden) {
    final n = r.netoDe(miId);
    acumulado += n;
    puntos.add(PuntoDeBalance(
      cuando: r.playedAt,
      acumulado: acumulado,
      delaRonda: n,
      nombreDeLaRonda: r.roundName,
    ));
  }
  return SerieDeBalance(puntos);
}
