// ─────────────────────────────────────────────────────────────────────────────
// LA TENDENCIA DEL HANDICAP — el cálculo, aparte del dibujo
//
// El índice se ve hoy como un número suelto: "10,4 · 8 rondas". Y el número no
// contesta la pregunta que el jugador se hace, que no es cuánto tiene sino si
// está bajando.
//
// ── El dato existe, la serie no ─────────────────────────────────────────────
//
// `HandicapProvider` guarda los diferenciales de las últimas veinte rondas y el
// índice de HOY. El índice de ayer no lo guarda nadie: se recalcula entero cada
// vez con la tabla WHS.
//
// Así que la serie se DERIVA, y sale gratis porque `calculateIndex` es pura:
// para cada ronda k, el índice que había entonces es el que sale de darle las
// rondas 1..k. Es lo mismo que hace la app hoy, veinte veces.
//
// Derivarla en vez de guardarla es además lo correcto por otro motivo, y es el
// mismo que rige las tablas de torneo: una serie guardada se queda vieja en
// silencio cuando se corrige una ronda vieja.
// ─────────────────────────────────────────────────────────────────────────────
import '../services/handicap_service.dart';

/// Un punto de la serie: qué índice tenías después de esa ronda.
class PuntoDeTendencia {
  final DateTime cuando;
  final double indice;

  /// Cuántas rondas había contadas en ese momento.
  final int rondas;

  const PuntoDeTendencia({
    required this.cuando,
    required this.indice,
    required this.rondas,
  });
}

/// Hacia dónde va.
///
/// ── OJO CON EL SIGNO ────────────────────────────────────────────────────────
///
/// En golf, BAJAR es mejorar. Un gráfico que pinte la subida de verde porque
/// "sube" estaría diciendo lo contrario de lo que pasa, y es el mismo error que
/// el "AS" que significaba tres cosas: un símbolo con el significado invertido
/// es peor que ningún símbolo.
enum RumboDeTendencia { mejora, empeora, plana }

class SerieDeTendencia {
  final List<PuntoDeTendencia> puntos;

  /// Cuántas rondas hay en total, aunque no lleguen para la serie.
  final int rondas;

  const SerieDeTendencia({required this.puntos, required this.rondas});

  /// Cuántos PUNTOS hacen falta para llamar a esto una tendencia.
  ///
  /// Una línea de dos puntos siempre "sube" o "baja": no describe nada, decora
  /// una coincidencia. Con cuatro, una sola ronda mala manda sobre la
  /// pendiente. Cinco es donde empieza a decir algo que el número no dice.
  static const minimoPuntos = 5;

  /// La ronda en la que nace el primer punto. **No es la tercera.**
  ///
  /// ── Lo que apareció al probarlo, y cambió el diseño ───────────────────────
  ///
  /// WHS da índice desde la tercera ronda, así que lo natural era empezar ahí.
  /// Un test con doce rondas de diferencial IDÉNTICO —el jugador que no cambia
  /// nada— lo desmintió: el índice subía 2,0 puntos.
  ///
  /// No era un fallo del cálculo. Es la tabla WHS, que mientras hay pocas
  /// rondas aplica una reducción que después retira:
  ///
  ///     3 rondas  →  −2,0        6 rondas  →  −1,0
  ///     4 rondas  →  −1,0        7 en adelante  →  0
  ///     5 rondas  →   0
  ///
  /// O sea que los primeros puntos se mueven por el ANDAMIAJE, no por cómo se
  /// juega. Un jugador que mejora de verdad vería su línea subir, y la pantalla
  /// le diría "has subido 2,0" atribuyéndoselo a él.
  ///
  /// Es la misma familia que el "AS" con tres significados: una cifra correcta
  /// presentada como algo que no es. Así que la serie empieza donde el ajuste
  /// ya es cero y todo movimiento posterior es real.
  ///
  /// El coste, dicho: hacen falta ONCE rondas para ver la línea. Es mucho, y es
  /// preferible a enseñarla antes diciendo algo falso.
  static const primeraRondaComparable = 7;

  /// Cuántas rondas hacen falta en total. Ver [primeraRondaComparable].
  static const minimoRondas = primeraRondaComparable + minimoPuntos - 1;

  bool get suficiente => puntos.length >= minimoPuntos;

  /// Cuántas rondas faltan para poder dibujarla.
  int get faltan => (minimoRondas - rondas).clamp(0, minimoRondas);

  double get primero => puntos.first.indice;
  double get ultimo => puntos.last.indice;

  /// Lo que ha cambiado. Negativo = ha bajado = ha mejorado.
  double get delta => ultimo - primero;

  double get minimo =>
      puntos.map((p) => p.indice).reduce((a, b) => a < b ? a : b);
  double get maximo =>
      puntos.map((p) => p.indice).reduce((a, b) => a > b ? a : b);

  /// El rumbo, con una zona muerta.
  ///
  /// Sin la zona muerta, una diferencia de 0,05 se anunciaría como "mejorando"
  /// y sería ruido presentado como noticia. Dos décimas es lo que el propio
  /// índice distingue: se muestra con un decimal.
  RumboDeTendencia get rumbo {
    if (delta <= -0.2) return RumboDeTendencia.mejora;
    if (delta >= 0.2) return RumboDeTendencia.empeora;
    return RumboDeTendencia.plana;
  }

  /// La frase que acompaña al gráfico. Con la cifra, no solo la dirección.
  String get frase => switch (rumbo) {
        RumboDeTendencia.mejora =>
          'Has bajado ${delta.abs().toStringAsFixed(1)} en '
              '${puntos.length} rondas',
        RumboDeTendencia.empeora =>
          'Has subido ${delta.abs().toStringAsFixed(1)} en '
              '${puntos.length} rondas',
        RumboDeTendencia.plana => 'Estable en las últimas ${puntos.length} rondas',
      };
}

/// La serie del índice a lo largo del histórico.
///
/// [diffs] son los diferenciales tal como los da HandicapProvider. El orden de
/// entrada da igual: aquí se ordena por fecha, porque de eso depende todo lo
/// demás y confiar en el orden de quien llama es pedir un fallo silencioso.
SerieDeTendencia tendenciaDeHandicap(List<ScoreDifferential> diffs) {
  final orden = [...diffs]..sort((a, b) => a.playedAt.compareTo(b.playedAt));
  final puntos = <PuntoDeTendencia>[];

  for (var k = 1; k <= orden.length; k++) {
    // El índice que había ENTONCES: las rondas hasta esa, y ninguna posterior.
    final hasta = orden.sublist(0, k);
    final r = HandicapService.calculateIndex(hasta);
    final i = r.index;
    if (i == null) continue;
    // Y antes de la séptima ronda tampoco, aunque HAYA índice: ahí el número
    // lleva el ajuste de la tabla WHS, que se retira solo. Ver
    // [primeraRondaComparable] — comparar esos puntos con los de después es
    // mezclar el andamiaje con el juego.
    if (k < SerieDeTendencia.primeraRondaComparable) continue;
    puntos.add(PuntoDeTendencia(
        cuando: orden[k - 1].playedAt, indice: i, rondas: k));
  }

  return SerieDeTendencia(puntos: puntos, rondas: orden.length);
}
