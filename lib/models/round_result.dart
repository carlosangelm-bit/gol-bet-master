// ─────────────────────────────────────────────────────────────────────────────
// ROUND RESULT — el dinero de una ronda cerrada, en un documento diminuto
//
// El tablero de Inicio necesita tu balance histórico, y hoy no se puede calcular
// barato: RoundSummary lleva los NOMBRES de los jugadores pero ni dinero ni ids,
// y el neto sale de LedgerEngine, que necesita la ronda COMPLETA. Sumar tu
// histórico significaba descargar cada ronda cerrada al abrir la app —Firestore
// no proyecta campos, así que leer un documento es leerlo entero—.
//
// Este es el patrón que el repo ya tiene funcionando para el handicap:
// scoreDifferentials es una colección aparte, escrita al cerrar la ronda y
// transmitida barata. Aquí se hace lo mismo con el dinero. Un documento ronda
// el kilobyte contra las decenas de una ronda entera.
//
// Se escribe en el mismo punto donde ya se persiste el diferencial, con el id de
// la ronda como id del documento: volver a cerrar una ronda REESCRIBE, nunca
// suma dos veces. Y como es derivado, se puede reconstruir entero desde las
// rondas —igual que los diferenciales tienen su backfill—.
// ─────────────────────────────────────────────────────────────────────────────
import 'models.dart';
import '../engines/ledger_engine.dart';
import '../engines/bet_engine.dart';
import '../engines/game_engine.dart';

/// El resultado en dinero de una ronda cerrada.
///
/// Todo lo que el tablero necesita de una ronda pasada, sin la ronda.
class RoundResult {
  final String roundId;
  final String roundName;
  final String courseName;
  final DateTime playedAt;

  /// Hoyos con score de quien más jugó. Distingue una vuelta de nueve de una
  /// de dieciocho al enseñar el score.
  final int holesPlayed;

  /// El PAR de los hoyos que esta ronda jugó de verdad.
  ///
  /// ── Por qué aparece esto ahora, y por qué no estaba ───────────────────────
  ///
  /// Un leaderboard de golf enseña el score CONTRA EL PAR: `-7` es lo que hace
  /// que alguien reconozca la pantalla sin leer nada. Y para restar el par hay
  /// que tenerlo.
  ///
  /// Aquí se guardaba `courseName` —el NOMBRE del campo— y nada más. El objeto
  /// `CourseInfo` con los pares por hoyo está delante en el momento exacto de
  /// construir esto, y se tiraba. Es la sexta vez en el proyecto que un dato
  /// horneado en un nombre acaba faltando: un nombre es para leerlo, y el par
  /// no se puede deducir de "Club de Golf Bosques".
  ///
  /// Es el par de los hoyos EN JUEGO, no el del campo entero: una vuelta de
  /// nueve contra un par 72 daría −36 y eso no es un score, es un error.
  ///
  /// Null en las rondas cerradas antes de esto. Una ronda sin par no produce
  /// score contra par —no lo inventa— y la columna se queda vacía para ella.
  final int? parDeLaRonda;

  /// Quiénes jugaron, por id. Son PERSONAS: los jugadores virtuales de un
  /// scramble no están, que no tienen ficha ni balance propio.
  final List<String> playerIds;

  /// id → nombre, para no tener que resolver el directorio al leer.
  ///
  /// Se guarda el nombre del día: si alguien se renombra después, la ronda
  /// vieja sigue diciendo cómo se llamaba entonces. Es lo correcto para un
  /// registro histórico.
  final Map<String, String> playerNames;

  /// id → neto. Positivo gana, misma convención que [LedgerEngine.playerBalances].
  final Map<String, double> balances;

  /// Neto por pareja, para el cara a cara.
  ///
  /// Clave `'menor|mayor'` y valor visto POR EL MENOR, exactamente la convención
  /// de `pairSliding` y de [BetEngine.pairKey]. No se inventa un cuarto
  /// separador: ya nos costó tener tres.
  final Map<String, double> pairBalances;

  /// id → score bruto total. Vacío para quien no anotó.
  final Map<String, int> grossByPlayer;

  // ── Lo que hacía falta para puntuar un torneo ─────────────────────────────
  //
  // El dinero solo sirve para el método "por dinero ganado". Puntuar por score
  // neto o por Stableford necesita el score, y estaba solo dentro de la ronda
  // completa. Se guarda AQUÍ, en el mismo punto donde ya se escribe el resto,
  // para que la tabla del torneo siga siendo una consulta de documentos ligeros
  // y no la descarga de veinte rondas enteras.
  //
  // Aditivos: vacíos en las rondas cerradas antes de este cambio, y hasta correr
  // el backfill del Historial esos métodos de puntuación no las verán. Se dice
  // en la pantalla del torneo en vez de dar una tabla corta por buena.

  /// id → score NETO total, con el handicap propio descontado.
  final Map<String, int> netByPlayer;

  /// id → puntos Stableford netos, con la tabla clásica.
  ///
  /// Se guarda la clásica y no la configurada: es el dato de la RONDA, y un
  /// torneo puede querer puntuar con otra tabla sin que eso reescriba lo que
  /// pasó. Si algún día hace falta la tabla del módulo, se recalcula de
  /// netByPlayer y los pares del campo.
  final Map<String, int> stablefordByPlayer;

  /// Los torneos para los que cuenta esta ronda.
  ///
  /// Se copia de la ronda, donde se marcó al configurarla. Es lo que consulta la
  /// fuente "marcadas": el torneo no adivina, pregunta quién dijo que contaba.
  final List<String> torneoIds;

  /// Los grupos de apuesta GUARDADOS de los que salió esta ronda.
  ///
  /// Lo que permite un torneo "todas las de Viernes CGM". Vacío si la ronda se
  /// armó a mano.
  final List<String> bettingGroupIds;

  const RoundResult({
    required this.roundId,
    required this.roundName,
    required this.courseName,
    required this.playedAt,
    required this.holesPlayed,
    this.parDeLaRonda,
    required this.playerIds,
    required this.playerNames,
    required this.balances,
    required this.pairBalances,
    required this.grossByPlayer,
    this.netByPlayer = const {},
    this.stablefordByPlayer = const {},
    this.bettingGroupIds = const [],
    this.torneoIds = const [],
  });

  /// Lo que le tocó a [pid]. Cero si no jugó —pero pregunta antes con
  /// [jugo] si la diferencia importa, que "no jugó" no es "quedó en tablas".
  double netoDe(String pid) => balances[pid] ?? 0.0;

  bool jugo(String pid) => playerIds.contains(pid);

  /// Lo que [a] le sacó a [b]. Positivo: a ganó.
  ///
  /// El mapa guarda la vista del id menor, así que si [a] es el mayor se
  /// invierte el signo.
  double netoEntre(String a, String b) {
    final v = pairBalances[BetEngine.pairKey(a, b)];
    if (v == null) return 0.0;
    return a.compareTo(b) <= 0 ? v : -v;
  }

  /// Deriva el resultado de una ronda cerrada.
  ///
  /// ── DOS LISTAS, y por qué esto estaba roto ────────────────────────────────
  ///
  /// El dinero es de PERSONAS y el score es de quien LLEVA LA TARJETA, y no
  /// siempre son los mismos. `models.dart` documenta la distinción desde hace
  /// tiempo, con una tabla de qué superficie usa qué predicado — y esta era la
  /// única superficie que faltaba en la tabla.
  ///
  /// Aquí se usaba `realPlayers` para TODO. En una ronda normal y en best ball
  /// da lo mismo: quien lleva tarjeta es cada persona. En SCRAMBLE no: la
  /// tarjeta la lleva el jugador virtual del equipo y los reales no tienen
  /// score propio, así que el resultado salía SIN SCORE PARA NADIE.
  ///
  /// No se veía porque nunca se cerró una ronda de scramble marcada para un
  /// torneo. Es la misma familia que los diferenciales imposibles: llevaba ahí
  /// desde el principio y solo aparece cuando alguien mira.
  ///
  /// ── A QUIÉN se le atribuye el score de un scramble ────────────────────────
  ///
  /// Al EQUIPO, no a los cuatro. Y no es una preferencia:
  ///
  /// Un scramble sale seis u ocho golpes por debajo de lo que cualquiera de los
  /// cuatro firmaría solo. Atribuir ese 65 a cada uno diría que los cuatro
  /// jugaron 65 con su propia bola — y ese número entra en el HISTÓRICO DE
  /// HANDICAP, donde produce diferenciales que no existen. Es exactamente el
  /// fallo que ya costó una entrega entera: un número plausible en el sitio
  /// donde nadie lo comprueba.
  ///
  /// El equipo es lo que jugó la bola. Ya tiene identidad —el jugador virtual—,
  /// ya tiene handicap combinado, y ya lleva la tarjeta.
  factory RoundResult.fromRound(Round round, {DateTime? playedAt}) {
    final reales = round.realPlayers;
    final ids = reales.map((p) => p.id).toList();
    final balances = LedgerEngine.playerBalances(round);

    // El neto por pareja se calcula solo entre personas: un cruce con un
    // jugador virtual no describe a nadie.
    final pares = <String, double>{};
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = ids[i], b = ids[j];
        final v = LedgerEngine.balanceBetween(round, a, b);
        if (v == 0) continue;
        // La clave ordena; el valor se guarda como lo ve el menor.
        final menor = a.compareTo(b) <= 0 ? a : b;
        pares[BetEngine.pairKey(a, b)] = menor == a ? v : -v;
      }
    }

    final gross = <String, int>{};
    final neto = <String, int>{};
    final stbl = <String, int>{};
    var hoyos = 0;
    // Quien LLEVA TARJETA. En una ronda normal y en best ball son los reales,
    // así que esto no cambia nada; en scramble es el virtual del equipo, y ahí
    // está la diferencia entre tener score y no tenerlo.
    for (final p in round.scoringPlayers) {
      final suyos = round.scores[p.id];
      if (suyos == null) continue;
      var total = 0, n = 0;
      for (final s in suyos.values) {
        if (s.hasScore) {
          total += s.grossScore!;
          n++;
        }
      }
      if (n > 0) {
        gross[p.id] = total;
        if (n > hoyos) hoyos = n;
        // El neto y los puntos salen de las MISMAS primitivas que usan los
        // motores, no de una segunda aritmética: una tabla de torneo que no
        // cuadre con lo que la ronda enseñó sería peor que no tenerla.
        neto[p.id] = GameEngine.netTotal(round, p.id, true);
        stbl[p.id] = GameEngine.stablefordTotal(round, p.id, true);
      }
    }

    // El par de lo que se jugó. `hoyosEnJuego` ya resuelve la vuelta de nueve
    // y por qué mitad empieza, así que no hay una segunda aritmética que pueda
    // discrepar de la que usó la tarjeta.
    final enJuego = BetEngine.segmentsOf(round).hoyosEnJuego.toSet();
    final delCampo =
        round.course.holes.where((h) => enJuego.contains(h.hole)).toList();
    final par = delCampo.isEmpty
        ? null
        : delCampo.fold<int>(0, (acc, h) => acc + h.par);

    return RoundResult(
      roundId: round.id,
      roundName: round.name,
      courseName: round.course.name,
      parDeLaRonda: par,
      playedAt: playedAt ?? DateTime.now(),
      holesPlayed: hoyos,
      playerIds: ids,
      // Los nombres llevan a los reales Y a quien lleva tarjeta: sin el
      // segundo, la tabla del torneo tendría el score del equipo y ningún
      // nombre que ponerle, y saldría como «—».
      playerNames: {
        for (final p in reales) p.id: p.name,
        for (final p in round.scoringPlayers) p.id: p.name,
      },
      balances: {
        for (final id in ids)
          if (balances[id] != null) id: balances[id]!,
      },
      pairBalances: pares,
      grossByPlayer: gross,
      netByPlayer: neto,
      stablefordByPlayer: stbl,
      torneoIds: List.of(round.torneoIds),
      bettingGroupIds: round.betGroups
          .map((g) => g.savedGroupId)
          .whereType<String>()
          .toSet()
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'roundId': roundId,
        'roundName': roundName,
        'courseName': courseName,
        'playedAt': playedAt.toIso8601String(),
        'holesPlayed': holesPlayed,
        if (parDeLaRonda != null) 'parDeLaRonda': parDeLaRonda,
        'playerIds': playerIds,
        'playerNames': playerNames,
        'balances': balances,
        'pairBalances': pairBalances,
        'grossByPlayer': grossByPlayer,
        // Solo si hay algo: un documento viejo no gana claves vacías.
        if (netByPlayer.isNotEmpty) 'netByPlayer': netByPlayer,
        if (stablefordByPlayer.isNotEmpty)
          'stablefordByPlayer': stablefordByPlayer,
        if (bettingGroupIds.isNotEmpty) 'bettingGroupIds': bettingGroupIds,
        if (torneoIds.isNotEmpty) 'torneoIds': torneoIds,
      };

  factory RoundResult.fromJson(Map<String, dynamic> j) => RoundResult(
        roundId: (j['roundId'] as String?) ?? '',
        roundName: (j['roundName'] as String?) ?? 'Ronda',
        courseName: (j['courseName'] as String?) ?? 'Campo',
        playedAt:
            DateTime.tryParse((j['playedAt'] as String?) ?? '') ?? DateTime(2000),
        holesPlayed: (j['holesPlayed'] as num?)?.toInt() ?? 0,
        parDeLaRonda: (j['parDeLaRonda'] as num?)?.toInt(),
        playerIds:
            ((j['playerIds'] as List?) ?? const []).map((e) => '$e').toList(),
        playerNames: ((j['playerNames'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', '$v')),
        balances: ((j['balances'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', (v as num).toDouble())),
        pairBalances: ((j['pairBalances'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', (v as num).toDouble())),
        grossByPlayer: ((j['grossByPlayer'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', (v as num).toInt())),
        netByPlayer: ((j['netByPlayer'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', (v as num).toInt())),
        stablefordByPlayer: ((j['stablefordByPlayer'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', (v as num).toInt())),
        bettingGroupIds:
            ((j['bettingGroupIds'] as List?) ?? const []).map((e) => '$e').toList(),
        torneoIds:
            ((j['torneoIds'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}
