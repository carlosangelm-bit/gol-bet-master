// ─────────────────────────────────────────────────────────────────────────────
// SIXES / HOLLYWOOD — tres bloques, y las parejas rotan para que todos jueguen
// con todos
//
// El precedente es Wolf: los lados cambian DURANTE la ronda y BetSide es de la
// ronda entera, así que ninguno de los ejes de composición existentes sirve. Por
// eso este motor arma el enfrentamiento por su cuenta.
//
// Y la diferencia que lo hace más barato que Wolf: la composición se DERIVA del
// bloque y del orden de salida, no se captura. Así que no hay ninguna pregunta
// nueva en el campo —como Snake y Rabbit—, solo un encabezado que dice con quién
// vas. Que sí hace falta: en el hoyo 7 alguien va a preguntarlo, y contar
// bloques mentalmente es justo lo que la app está para evitar.
//
// CÓMO ROTAN, con los jugadores en orden de salida [p0, p1, p2, p3]:
//
//   bloque 1 → p0+p1  vs  p2+p3
//   bloque 2 → p0+p2  vs  p1+p3
//   bloque 3 → p0+p3  vs  p1+p2
//
// Son las tres únicas particiones de cuatro en dos parejas, así que con cuatro
// jugadores y tres bloques la rotación CIERRA: cada uno juega exactamente un
// bloque con cada uno de los otros tres. Es lo que hace que el formato exista con
// cuatro y no con cinco.
//
// El cálculo de cada bloque NO es nuevo: es el mismo best ball entre dos lados
// que ya usa el Nassau por equipos, así que se llama a GameEngine.holeDeltaVs en
// vez de reimplementarlo. Un segundo best ball habría podido discrepar del
// primero, y el jugador vería dos marcadores del mismo golf.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';
import 'bet_engine.dart';
import 'game_engine.dart';

/// Por qué un bloque no liquidó.
enum SixesSinLiquidar {
  /// El bloque no tiene ni un hoyo con las dos bolas anotadas.
  sinJugar,

  /// Se jugó y quedó empatado.
  empatado,

  /// La ronda es más corta que el bloque: esos hoyos no existen.
  fueraDeLaRonda,
}

/// Un bloque de Sixes: dos parejas, un tramo de hoyos, un resultado.
class BloqueDeSixes {
  /// 1, 2 o 3.
  final int numero;

  /// El tramo, inclusive.
  final int desde;
  final int hasta;

  /// Las dos parejas de ESTE bloque.
  final List<String> parejaA;
  final List<String> parejaB;

  /// Hoyos ganados por cada lado dentro del bloque.
  final int ganadosA;
  final int ganadosB;

  /// Hoyos empatados y hoyos con score de los dos lados.
  final int empatados;
  final int jugados;

  /// Quién se llevó el bloque: los ids del lado ganador, o vacío si nadie.
  final List<String> ganadores;

  /// Por qué no hubo ganador. null si sí lo hubo.
  final SixesSinLiquidar? sinLiquidar;

  const BloqueDeSixes({
    required this.numero,
    required this.desde,
    required this.hasta,
    required this.parejaA,
    required this.parejaB,
    this.ganadosA = 0,
    this.ganadosB = 0,
    this.empatados = 0,
    this.jugados = 0,
    this.ganadores = const [],
    this.sinLiquidar,
  });

  bool get resuelto => ganadores.isNotEmpty;

  /// El marcador del bloque, para pantalla: "3–2" o "sin jugar".
  String get marcador => jugados == 0 ? '—' : '$ganadosA–$ganadosB';
}

class SixesEngine {
  const SixesEngine._();

  /// Las tres parejas del bloque [numero] (1..3) con los jugadores en orden.
  ///
  /// Devuelve (parejaA, parejaB). Es pura y separada del resto para que la
  /// pantalla pueda decir con quién vas sin calcular la ronda entera.
  static (List<String>, List<String>) parejasDelBloque(
      List<String> pids, int numero) {
    // Con menos de cuatro no hay rotación que cerrar; el tipo ya se atenúa
    // antes de llegar aquí, pero devolver algo coherente evita un crash si un
    // dato guardado viene raro.
    if (pids.length < 4) {
      return (pids.take(1).toList(), pids.skip(1).take(1).toList());
    }
    final p = pids.take(4).toList();
    return switch (numero) {
      1 => ([p[0], p[1]], [p[2], p[3]]),
      2 => ([p[0], p[2]], [p[1], p[3]]),
      _ => ([p[0], p[3]], [p[1], p[2]]),
    };
  }

  /// Cuántos hoyos tiene cada bloque en una ronda de [holesInRound].
  ///
  /// El estándar con cuatro jugadores es 6 —tres bloques de seis en 18— y el
  /// fivesome usa 3. Se DERIVA de la longitud en vez de fijarse, así que una
  /// ronda de 9 sale con bloques de 3 y sigue siendo el mismo formato a mitad de
  /// largo, en vez de atenuarse.
  static int bloqueSugerido(int holesInRound) =>
      holesInRound < 3 ? 1 : holesInRound ~/ 3;

  /// En qué bloque cae [hoyo], o null si queda fuera de los tres.
  ///
  /// Los hoyos que sobran cuando la ronda no es múltiplo de tres bloques NO
  /// entran: repartirlos en el último bloque lo alargaría en silencio.
  static int? bloqueDelHoyo(int hoyo, int hoyosPorBloque) {
    if (hoyosPorBloque <= 0 || hoyo < 1) return null;
    final b = ((hoyo - 1) ~/ hoyosPorBloque) + 1;
    return b >= 1 && b <= 3 ? b : null;
  }

  /// Los tres bloques con su resultado.
  ///
  /// [pids] en orden de salida. La misma fuente que consume la pantalla y el
  /// ledger, para que el marcador que se ve y el dinero que se cobra no puedan
  /// desincronizarse.
  static List<BloqueDeSixes> bloques(
      Round round, List<String> pids, BetModuleInstance mod) {
    final cfg = mod.sixes;
    final n = cfg.hoyosPorBloque;
    final salida = <BloqueDeSixes>[];

    for (var b = 1; b <= 3; b++) {
      final (a, bb) = parejasDelBloque(pids, b);
      final desde = (b - 1) * n + 1;
      final hasta = b * n;

      if (desde > round.totalHoles) {
        salida.add(BloqueDeSixes(
          numero: b,
          desde: desde,
          hasta: hasta,
          parejaA: a,
          parejaB: bb,
          sinLiquidar: SixesSinLiquidar.fueraDeLaRonda,
        ));
        continue;
      }

      final sideA = BetSide(id: 'sixes_${b}_a', name: 'A', playerIds: a);
      final sideB = BetSide(id: 'sixes_${b}_b', name: 'B', playerIds: bb);
      // El mismo mapa de handicap que el best ball por equipos: strokes
      // relativos al más bajo del enfrentamiento. Construirlo aquí a mano habría
      // sido una segunda forma de repartir golpes.
      final hcpMap = mod.useHandicap
          ? GameEngine.buildTeamHcpMap(round, [...a, ...bb],
              cfg: mod.teamHandicap)
          : {for (final p in [...a, ...bb]) p: 0.0};

      var ga = 0, gb = 0, eq = 0, jug = 0;
      for (var h = desde; h <= hasta && h <= round.totalHoles; h++) {
        final d = GameEngine.holeDeltaVs(
          round: round,
          sideA: sideA,
          sideB: sideB,
          holeNum: h,
          useHandicap: mod.useHandicap,
          hcpMap: hcpMap,
        );
        if (d == null) continue; // un lado sin ninguna bola: el hoyo no cuenta
        jug++;
        if (d > 0) {
          ga++;
        } else if (d < 0) {
          gb++;
        } else {
          eq++;
        }
      }

      final ganadores = jug == 0
          ? const <String>[]
          : ga > gb
              ? a
              : gb > ga
                  ? bb
                  : const <String>[];

      salida.add(BloqueDeSixes(
        numero: b,
        desde: desde,
        hasta: hasta,
        parejaA: a,
        parejaB: bb,
        ganadosA: ga,
        ganadosB: gb,
        empatados: eq,
        jugados: jug,
        ganadores: ganadores,
        sinLiquidar: jug == 0
            ? SixesSinLiquidar.sinJugar
            : ganadores.isEmpty
                ? SixesSinLiquidar.empatado
                : null,
      ));
    }
    return salida;
  }

  /// El dinero de los tres bloques.
  ///
  /// Cada bloque vale lo configurado EN TOTAL, igual que un duelo por equipos:
  /// se reparte entre los cruces con teamCrossAmount, que es la misma función
  /// que usa el Nassau. Así un bloque a $50 mueve $50, no $200.
  ///
  /// El empate no se cobra —push, coherente con el resto de la app— y no se
  /// acumula al bloque siguiente: acumular cambiaría de pareja a mitad de
  /// apuesta, que es otra cosa.
  static List<LedgerEntry> liquidar(
      Round round, List<String> pids, BetModuleInstance mod) {
    final cfg = mod.sixes;
    if (cfg.value <= 0) return const [];

    final entries = <LedgerEntry>[];
    for (final b in bloques(round, pids, mod)) {
      if (!b.resuelto) continue;
      final gana = b.ganadores;
      final pierde = gana == b.parejaA ? b.parejaB : b.parejaA;
      final amount =
          BetEngine.teamCrossAmount(cfg.value, gana.length, pierde.length);
      if (amount <= 0) continue;
      for (final g in gana) {
        for (final p in pierde) {
          entries.add(LedgerEntry(
            fromPlayerId: p,
            toPlayerId: g,
            amount: amount,
            betType: BetModuleType.sixes,
            // El motivo nombra el bloque Y el tramo: "Bloque 2" a secas obliga
            // a recordar de qué hoyos hablaba.
            reason: 'Bloque ${b.numero} (hoyos ${b.desde}-${b.hasta}) '
                '${b.ganadosA}–${b.ganadosB}',
          ));
        }
      }
    }
    return entries;
  }

  /// Con quién juega [pid] en el bloque de [hoyo]. null si el hoyo no cuenta.
  ///
  /// Es lo que responde "¿con quién voy ahora?" sin que nadie cuente bloques.
  static String? companeroEn(
      List<String> pids, String pid, int hoyo, int hoyosPorBloque) {
    final b = bloqueDelHoyo(hoyo, hoyosPorBloque);
    if (b == null) return null;
    final (a, bb) = parejasDelBloque(pids, b);
    final lado = a.contains(pid) ? a : (bb.contains(pid) ? bb : null);
    if (lado == null) return null;
    final companero = lado.where((x) => x != pid);
    return companero.isEmpty ? null : companero.first;
  }
}
