// ─────────────────────────────────────────────────────────────────────────────
// HANDICAP SERVICE — World Handicap System (WHS) 2024
// Calcula Score Differential, Handicap Index y Course Handicap
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math';
import '../models/models.dart';

// ── Modelo de diferencial de score por ronda ──────────────────────────────────
class ScoreDifferential {
  final String roundId;
  final String roundName;
  final DateTime playedAt;
  final double differential;
  final int grossScore;
  final int adjustedGrossScore; // RBA
  final double courseRating;
  final int slopeRating;
  final int parTotal;
  final int holesPlayed; // 9 o 18
  final String courseName;

  /// El score de la ida y el de la vuelta, si se pueden separar.
  ///
  /// Aparte del total porque es lo que un golfista mira: no cuánto hizo, sino
  /// DÓNDE se le fue la ronda. El total ya está en [grossScore].
  ///
  /// Nulos en los diferenciales guardados antes de que esto existiera. La
  /// pantalla enseña un guion en vez de inventar el reparto, que sería peor:
  /// una cifra plausible que nadie puede comprobar.
  final int? frontNine;
  final int? backNine;

  /// El tee con el que se CALCULÓ este diferencial.
  ///
  /// ── Por qué se guarda, y no se deduce del nombre del campo ────────────────
  ///
  /// El nombre del campo lleva el tee horneado —"Club de Golf México (AZULES)"—
  /// y se construía siempre con el PRIMER tee de la lista, así que decía una
  /// salida y la fórmula usaba otra. Se reportó como "el dato guardado está
  /// mal", y no lo estaba: el CR y el Slope salen de RoundPlayer.tee, y
  /// CourseInfo ni siquiera tiene esos campos.
  ///
  /// Pero desde fuera no había forma de saberlo. Guardando aquí el tee que
  /// entró en la fórmula, la pregunta se contesta mirando, sin auditar el
  /// código. Junto a [courseRating] y [slopeRating], que ya se guardaban, dice
  /// exactamente con qué se calculó.
  ///
  /// Nulo en los diferenciales de antes. Entonces se enseñan el CR y el Slope,
  /// que son el dato de verdad.
  final String? teeName;

  /// El suelo de lo humanamente posible.
  ///
  /// ── Un diferencial negativo NO es el problema ─────────────────────────────
  ///
  /// Lo parece, y no lo es: un jugador de hándicap positivo que firma por
  /// debajo del rating del campo produce un diferencial negativo legítimo. Un
  /// +2 que hace 68 en un campo de CR 72 da −4,2, y es correcto.
  ///
  /// Lo que no existe es −27. Serían veintisiete golpes por debajo del rating:
  /// ni el mejor del mundo. Así que el corte va donde acaba lo posible, no
  /// donde acaba lo cómodo.
  static const suelo = -10.0;

  /// Este diferencial no lo pudo producir una persona jugando.
  ///
  /// No se guarda: se deduce del propio valor. Guardarlo habría metido un campo
  /// derivado en Firestore que se queda viejo en cuanto cambie el criterio.
  bool get esImposible => differential < suelo;

  const ScoreDifferential({
    required this.roundId,
    required this.roundName,
    required this.playedAt,
    required this.differential,
    required this.grossScore,
    required this.adjustedGrossScore,
    required this.courseRating,
    required this.slopeRating,
    required this.parTotal,
    required this.holesPlayed,
    required this.courseName,
    this.frontNine,
    this.backNine,
    this.teeName,
  });

  /// Si hay desglose por vueltas.
  bool get hayVueltas => frontNine != null && backNine != null;

  Map<String, dynamic> toJson() => {
    'roundId': roundId,
    'roundName': roundName,
    'playedAt': playedAt.toIso8601String(),
    'differential': differential,
    'grossScore': grossScore,
    'adjustedGrossScore': adjustedGrossScore,
    'courseRating': courseRating,
    'slopeRating': slopeRating,
    'parTotal': parTotal,
    'holesPlayed': holesPlayed,
    'courseName': courseName,
    // Aditivos: solo se escriben cuando hay algo que decir, así que un
    // diferencial guardado ayer se lee igual que hoy.
    if (frontNine != null) 'frontNine': frontNine,
    if (backNine != null) 'backNine': backNine,
    if (teeName != null) 'teeName': teeName,
  };

  factory ScoreDifferential.fromJson(Map<String, dynamic> j) => ScoreDifferential(
    roundId:             (j['roundId']    as String?) ?? '',
    roundName:           (j['roundName']  as String?) ?? 'Ronda',
    playedAt:            DateTime.tryParse(j['playedAt'] as String? ?? '') ?? DateTime.now(),
    differential:        (j['differential'] as num?)?.toDouble() ?? 0.0,
    grossScore:          (j['grossScore'] as num?)?.toInt() ?? 0,
    adjustedGrossScore:  (j['adjustedGrossScore'] as num?)?.toInt() ?? 0,
    courseRating:        (j['courseRating'] as num?)?.toDouble() ?? 72.0,
    slopeRating:         (j['slopeRating'] as num?)?.toInt() ?? 113,
    parTotal:            (j['parTotal']   as num?)?.toInt() ?? 72,
    holesPlayed:         (j['holesPlayed'] as num?)?.toInt() ?? 18,
    courseName:          (j['courseName'] as String?) ?? '',
    frontNine:           (j['frontNine'] as num?)?.toInt(),
    backNine:            (j['backNine'] as num?)?.toInt(),
    teeName:             j['teeName'] as String?,
  );
}

// ── Resultado del cálculo del Handicap Index ──────────────────────────────────
class HandicapIndexResult {
  /// Handicap Index calculado (null si hay < 3 rondas)
  final double? index;
  /// Número de rondas disponibles
  final int totalRounds;
  /// Diferenciales usados para el cálculo (los N mejores)
  final List<ScoreDifferential> usedDifferentials;
  /// Todos los diferenciales (últimas 20)
  final List<ScoreDifferential> allDifferentials;
  /// Ajuste de reducción aplicado por ESR (0 si no aplica)
  final double esrAdjustment;
  /// Ajuste por pocas rondas (tabla WHS)
  final double tableAdjustment;

  /// Las rondas que se dejaron fuera por producir un diferencial imposible.
  ///
  /// Se guardan enteras, no solo su número: una ronda que no cuenta tiene que
  /// poder VERSE como tal, con su fecha y su cifra. Desaparecer sin más es lo
  /// que dejó este fallo semanas escondido, y contar cuántas sin decir cuáles
  /// no le sirve a nadie para encontrarlas.
  final List<ScoreDifferential> descartadas;

  /// El nueve que espera pareja, si hay uno.
  ///
  /// No entra en el índice —ver `emparejarNueves`— y por eso hay que DECIRLO:
  /// una ronda jugada que no aparece en ningún sitio se lee como un fallo de
  /// guardado, que es la forma en que este proyecto ha perdido datos ya.
  final ScoreDifferential? nueveSinPareja;

  const HandicapIndexResult({
    this.index,
    required this.totalRounds,
    required this.usedDifferentials,
    required this.allDifferentials,
    this.esrAdjustment = 0.0,
    this.tableAdjustment = 0.0,
    this.descartadas = const [],
    this.nueveSinPareja,
  });

  bool get hasIndex => index != null;
  String get displayIndex => index == null ? '—' : index!.toStringAsFixed(1);
}

// ── Servicio principal de handicap WHS ────────────────────────────────────────
class HandicapService {
  // Constante de referencia WHS
  static const double _refSlope = 113.0;
  static const double _maxHI = 54.0;

  /// Hoyos mínimos para que una ronda cuente. **WHS Regla 3.2.**
  ///
  /// Lo que el estándar dice y aquí NO se hace, dicho para que sea una decisión
  /// y no un olvido: WHS admite además que una ronda de entre 7 y 13 hoyos
  /// cuente como score de NUEVE. No se implementa porque exige decidir cuáles
  /// son esos nueve cuando los hoyos jugados están repartidos, y equivocarse en
  /// eso da un diferencial plausible y falso — que es justo el fallo del que
  /// viene todo esto. Se prefiere no contar la ronda a contarla mal.
  static const minimoHoyos18 = 14;
  static const minimoHoyos9 = 7;

  /// Calcula el Adjusted Gross Score (RBA) aplicando Net Double Bogey por hoyo.
  /// Para cada hoyo: max = par + 2 + strokes_de_handicap_en_ese_hoyo
  /// [grossScores]: mapa hole# → gross score (sólo hoyos jugados)
  /// [courseHoles]: información de cada hoyo (par, strokeIndex)
  /// [playingHandicap]: handicap de juego del jugador (entero)
  /// [playedHoles]: lista de hoyos jugados (para rondas de 9)
  static int calculateRBA({
    required Map<int, int?> grossScores,
    required List<CourseHole> courseHoles,
    required int playingHandicap,
    List<int>? playedHoles,
  }) {
    final holesInPlay = playedHoles ?? courseHoles.map((h) => h.hole).toList();
    int rba = 0;
    for (final holeNum in holesInPlay) {
      final gross = grossScores[holeNum];
      if (gross == null || gross == 0) continue;
      final holeInfo = courseHoles.firstWhere(
        (h) => h.hole == holeNum,
        orElse: () => CourseHole(hole: holeNum, par: 4, strokeIndex: 18),
      );
      // Strokes de handicap en este hoyo
      final strokesOnHole = _strokesOnHole(holeInfo.strokeIndex, playingHandicap);
      // Net Double Bogey = par + 2 + strokes
      final maxScore = holeInfo.par + 2 + strokesOnHole;
      rba += min(gross, maxScore);
    }
    return rba;
  }

  /// Cuántos golpes de ventaja recibe un jugador en un hoyo.
  ///
  /// ── El fallo de los múltiplos exactos de 18 ───────────────────────────────
  ///
  /// Lo cazó una prueba de par neto cuya aritmética no cuadraba: un jugador de
  /// 18 recibía DOS golpes en cada hoyo, cuando le toca uno.
  ///
  /// La versión anterior trataba el resto cero como "los dieciocho hoyos" y le
  /// sumaba una vuelta de más:
  ///
  ///     PH 18  →  18 % 18 == 0  →  umbral 18  →  (18 ~/ 18) + 1 = 2   ✗
  ///     PH 36  →  igual         →              →  (36 ~/ 18) + 1 = 3   ✗
  ///
  /// El reparto correcto no necesita ese caso especial: se dan tantas vueltas
  /// completas como quepan, y una más en los primeros hoyos por el resto.
  ///
  ///     PH 18  →  base 1, resto 0  →  1 en los dieciocho          ✓
  ///     PH 19  →  base 1, resto 1  →  2 en el SI 1, 1 en el resto ✓
  ///     PH  9  →  base 0, resto 9  →  1 del SI 1 al 9             ✓
  ///
  /// Importa porque de esto sale el tope de doble bogey neto del RBA: con un
  /// golpe de más por hoyo, el tope sube y el score ajustado sale más bajo de
  /// lo que debe.
  static int _strokesOnHole(int strokeIndex, int playingHandicap) {
    if (playingHandicap <= 0) return 0;
    final vueltas = playingHandicap ~/ 18;
    final resto = playingHandicap % 18;
    return vueltas + (strokeIndex <= resto ? 1 : 0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAS RONDAS DE NUEVE HOYOS — por qué dominaban el índice
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // «¿Por qué las rondas de diferenciales casi todas agarra las de 9 hoyos?»
  //
  // No era casualidad, y no era una coincidencia estadística: era ARITMÉTICA.
  //
  // El diferencial se calcula `(113 / Slope) × (RBA − CR)`. Con nueve hoyos, la
  // app partía el CR a la mitad —71,7 → 35,9— y el RBA es también la mitad,
  // pero el multiplicador `113 / Slope` NO se parte, porque el Slope es una
  // pendiente y no un total.
  //
  //   18 hoyos:  (113/149) × (90 − 71,7) = 13,9
  //    9 hoyos:  (113/149) × (47 − 35,9) =  8,4
  //
  // O sea que un nueve produce sistemáticamente ALREDEDOR DE LA MITAD del
  // diferencial que produciría la misma calidad de juego en dieciocho. Y como
  // WHS coge los OCHO MEJORES de veinte, los nueves ganan siempre. Tres de los
  // ocho usados eran de nueve hoyos, y por eso el índice estaba bajo.
  //
  // El código ya tenía un comentario que decía «para rondas de 9 hoyos se dobla
  // el diferencial (estándar WHS)». No doblaba nada: describía una intención que
  // nunca se escribió. Es la forma más difícil de encontrar un fallo — el
  // comentario dice que está resuelto.
  //
  // ── QUÉ DICE WHS, y por qué SUMAR es lo correcto ──────────────────────────
  //
  // El estándar no dobla un nueve: COMBINA DOS. Un score de nueve produce un
  // diferencial de nueve, que se guarda hasta que llega el siguiente y los dos
  // forman un diferencial de dieciocho.
  //
  // Y la aritmética confirma que sumar es la operación:
  //
  //   d₁ + d₂ = (113/S)(r₁−CR₉) + (113/S)(r₂−CR₉)
  //           = (113/S)((r₁+r₂) − 2·CR₉)
  //           = (113/S)(RBA₁₈ − CR₁₈)
  //
  // Que es exactamente el diferencial de dieciocho. No es una aproximación:
  // es la misma expresión.
  //
  // ── DÓNDE se hace, y por qué NO hay migración ─────────────────────────────
  //
  // Aquí, al calcular el índice — no al guardar el diferencial. Por el mismo
  // motivo que la guarda del suelo, escrito unas líneas más abajo: los
  // diferenciales están GUARDADOS en Firestore, así que arreglar el cálculo de
  // la ronda solo arreglaría las futuras.
  //
  // Y trae algo mejor: los diferenciales guardados NO ESTÁN MAL. Cada uno es el
  // diferencial correcto de sus nueve hoyos. Lo que estaba mal era compararlos
  // con los de dieciocho. Así que no hay nada que corregir en los datos, solo
  // en la selección — y el índice se arregla solo, sin recalcular nada.
  //
  // ── LO QUE LA APP NO GUARDA, y se dice en vez de calcularlo mal ───────────
  //
  // Dos cosas, y las dos son aproximaciones que quedan escritas:
  //
  //   · El SLOPE de nueve hoyos. WHS publica uno propio; la app guarda uno por
  //     tee, que es el de dieciocho. Como el Slope entra en `113/Slope` en los
  //     dos diferenciales que se suman, el error se cancela casi entero: la
  //     suma sigue siendo `(113/S)(RBA₁₈ − CR₁₈)` con S del tee.
  //   · El CR de la IDA y el de la VUELTA por separado. Se usa la mitad del de
  //     dieciocho, y las dos mitades de un campo no valen lo mismo. Sumar dos
  //     nueves del mismo tee vuelve a dar el CR de dieciocho exacto, así que
  //     el error también se cancela al combinar — no al mirar un nueve suelto.
  //
  // Un nueve SIN PAREJA no se usa. Se guarda y se dice, que es el criterio 2.

  /// Combina dos diferenciales de nueve hoyos en uno de dieciocho.
  ///
  /// Se fecha con la ronda MÁS RECIENTE de las dos: el diferencial de dieciocho
  /// no existía hasta que se jugó la segunda, y fecharlo con la primera lo
  /// metería antes de tiempo en la ventana de veinte.
  static ScoreDifferential combinarNueves(
      ScoreDifferential a, ScoreDifferential b) {
    final primera = a.playedAt.isBefore(b.playedAt) ? a : b;
    final segunda = a.playedAt.isBefore(b.playedAt) ? b : a;
    return ScoreDifferential(
      // El id lleva los dos: un diferencial combinado tiene que poder decir de
      // qué dos rondas salió, o se lee como una ronda de dieciocho que nadie
      // jugó.
      roundId: '${primera.roundId}+${segunda.roundId}',
      roundName: '${primera.roundName} + ${segunda.roundName}',
      playedAt: segunda.playedAt,
      differential:
          double.parse((a.differential + b.differential).toStringAsFixed(1)),
      grossScore: a.grossScore + b.grossScore,
      adjustedGrossScore: a.adjustedGrossScore + b.adjustedGrossScore,
      courseRating: a.courseRating + b.courseRating,
      slopeRating: segunda.slopeRating,
      parTotal: a.parTotal + b.parTotal,
      holesPlayed: a.holesPlayed + b.holesPlayed,
      courseName: primera.courseName == segunda.courseName
          ? primera.courseName
          : '${primera.courseName} + ${segunda.courseName}',
      frontNine: primera.grossScore,
      backNine: segunda.grossScore,
      teeName: segunda.teeName,
    );
  }

  /// Empareja los nueves de [diffs] y devuelve la lista lista para el índice.
  ///
  /// Los de dieciocho pasan tal cual. Los de nueve se ordenan por fecha y se
  /// combinan de dos en dos, en el orden en que se jugaron. El que sobre queda
  /// fuera y se devuelve aparte.
  static ({List<ScoreDifferential> paraElIndice, ScoreDifferential? sinPareja})
      emparejarNueves(List<ScoreDifferential> diffs) {
    final dieciocho = <ScoreDifferential>[];
    final nueves = <ScoreDifferential>[];
    for (final d in diffs) {
      (d.holesPlayed <= 9 ? nueves : dieciocho).add(d);
    }
    nueves.sort((a, b) => a.playedAt.compareTo(b.playedAt));

    final combinados = <ScoreDifferential>[];
    for (var i = 0; i + 1 < nueves.length; i += 2) {
      combinados.add(combinarNueves(nueves[i], nueves[i + 1]));
    }
    // El impar sobra. Es el más RECIENTE porque van en orden: el que espera
    // pareja es el último que se jugó, no uno de hace meses.
    final sobra = nueves.length.isOdd ? nueves.last : null;

    return (
      paraElIndice: [...dieciocho, ...combinados],
      sinPareja: sobra,
    );
  }

  /// Calcula el Score Differential para una ronda.
  /// Fórmula WHS: (113 / Slope) × (RBA − CR − PCC)
  /// Para rondas de 9 hoyos se aplica un ajuste especial.
  ///
  /// [pcc]: Playing Conditions Calculation (generalmente 0 si no se mide)
  static double calculateScoreDifferential({
    required int rba,
    required double courseRating,
    required int slopeRating,
    required int holesPlayed,
    double pcc = 0.0,
  }) {
    double cr = courseRating;
    double slope = slopeRating.toDouble();
    if (slope <= 0) slope = _refSlope;

    // Para rondas de 9 hoyos: se dobla el diferencial (estándar WHS)
    // En la práctica se usan dos rondas de 9 para calcular 1 diferencial de 18
    // Aquí calculamos el diferencial proporcional
    double diff = (_refSlope / slope) * (rba - cr - pcc);

    // Redondear a 1 decimal
    return double.parse(diff.toStringAsFixed(1));
  }

  /// Calcula el Score Differential directamente desde la ronda.
  /// Retorna null si el jugador no tiene scores válidos.
  static ScoreDifferential? calculateFromRound({
    required Round round,
    required String playerId,
  }) {
    final rp = round.roundPlayers.firstWhere(
      (r) => r.playerId == playerId,
      orElse: () => RoundPlayer(playerId: playerId, handicapEnRonda: 0),
    );
    final tee = rp.tee;
    final playerScores = round.scores[playerId] ?? {};

    // Hoyos jugados según startingNine y totalHoles
    final playedHoles = _getPlayedHoles(round);

    // ── CUÁNTOS HOYOS HACEN FALTA — WHS Regla 3.2 ─────────────────────────────
    //
    // Antes bastaba con la MITAD, y de ahí salió un fallo que estuvo semanas en
    // los datos sin que nadie lo viera: una ronda de prueba con diez hoyos
    // capturados producía "Gross 46 en 18 hoyos" y un diferencial de −27.
    //
    // WHS pide catorce hoyos para una ronda de dieciocho y siete para una de
    // nueve. Por debajo, la ronda NO ES ACEPTABLE y no produce diferencial.
    final anotados =
        playedHoles.where((h) => (playerScores[h]?.grossScore ?? 0) > 0).toList();
    final minimo = round.totalHoles == 9 ? minimoHoyos9 : minimoHoyos18;
    if (anotados.length < minimo) return null;

    // Playing Handicap para este tee
    final playingHandicap = tee.playingHandicap(rp.handicapEnRonda).round();

    // ── Y LOS QUE FALTAN VAN A PAR NETO, no a cero ────────────────────────────
    //
    // Es la otra mitad del mismo fallo, y la que hacía el daño: sumar solo los
    // hoyos anotados da un total que se compara contra el rating de la ronda
    // ENTERA. Diez hoyos suman 46 y el campo vale 72, así que el jugador
    // "hizo" 26 bajo par sin haber jugado.
    //
    // WHS lo resuelve así: un hoyo no jugado se anota a par neto —el par más
    // los golpes que le tocan al jugador ahí—. Ni cero ni el par a secas.
    final conParNeto = <int, int>{};
    for (final h in playedHoles) {
      final real = playerScores[h]?.grossScore ?? 0;
      if (real > 0) {
        conParNeto[h] = real;
        continue;
      }
      final info = round.course.holes.firstWhere((x) => x.hole == h,
          orElse: () => CourseHole(hole: h, par: 4, strokeIndex: 18));
      conParNeto[h] = info.par + _strokesOnHole(info.strokeIndex, playingHandicap);
    }

    // El score a efectos de hándicap: lo jugado más el par neto de lo que no.
    // No es lo que el jugador firmó, y por eso la lista dice cuántos hoyos
    // anotó de verdad.
    final grossScore = conParNeto.values.fold<int>(0, (a, b) => a + b);
    if (grossScore == 0) return null;

    // RBA (Adjusted Gross Score — Net Double Bogey)
    final rba = calculateRBA(
      grossScores: conParNeto,
      courseHoles: round.course.holes,
      playingHandicap: playingHandicap,
      playedHoles: playedHoles,
    );

    // Course Rating y Slope para los hoyos jugados
    // Para 9 hoyos usamos la mitad del CR/par proporcional
    double cr = tee.courseRating;
    int slope = tee.slopeRating;
    int par = tee.parTotal;

    if (round.totalHoles == 9) {
      // Ajuste proporcional para 9 hoyos (WHS recomienda usar datos separados de 9 hoyos)
      // Aproximación: mitad del CR y par
      cr = cr / 2.0;
      par = par ~/ 2;
    }

    final diff = calculateScoreDifferential(
      rba: rba,
      courseRating: cr,
      slopeRating: slope,
      holesPlayed: playedHoles.length,
    );

    return ScoreDifferential(
      roundId: round.id,
      roundName: round.name,
      playedAt: round.createdAt,
      differential: diff,
      grossScore: grossScore,
      adjustedGrossScore: rba,
      courseRating: cr,
      slopeRating: slope,
      parTotal: par,
      // Los hoyos que se ANOTARON, no los que la ronda decía tener. Con los
      // segundos, la lista enseñaba "18 H" de una ronda de diez.
      holesPlayed: anotados.length,
      courseName: round.course.name,
      // Por NÚMERO de hoyo, no por orden de juego: en una tarjeta, la ida son
      // los nueve primeros aunque se haya salido por el diez. Es lo que el
      // jugador reconoce cuando mira dónde se le fue la ronda.
      frontNine: _mitad(conParNeto, (h) => h <= 9),
      backNine: _mitad(conParNeto, (h) => h > 9),
      // El tee que acaba de entrar en la fórmula, no el que diga el nombre del
      // campo. Son dos cosas distintas y se confundieron una vez.
      teeName: tee.name,
    );
  }

  /// La suma de los hoyos que cumplen [cual], o null si no hay ninguno.
  ///
  /// Null y no cero: una ronda de nueve por la vuelta no tiene ida, y un cero
  /// ahí se leería como "hizo 0 en la ida".
  static int? _mitad(Map<int, int> scores, bool Function(int) cual) {
    final trozo = scores.entries.where((e) => cual(e.key));
    if (trozo.isEmpty) return null;
    return trozo.fold<int>(0, (a, e) => a + e.value);
  }

  /// Obtiene la lista de hoyos efectivamente jugados según la configuración de la ronda
  static List<int> _getPlayedHoles(Round round) {
    final allHoles = round.course.holes.map((h) => h.hole).toSet();
    if (round.totalHoles == 18) return round.course.holes.map((h) => h.hole).toList();

    // Ronda de 9 hoyos según startingNine
    if (round.startingNine == StartingNine.front) {
      return allHoles.where((h) => h <= 9).toList()..sort();
    } else {
      final back = allHoles.where((h) => h > 9).toList()..sort();
      if (back.isEmpty) return allHoles.take(9).toList()..sort();
      return back;
    }
  }

  // ── Tabla WHS: número de diferenciales a usar y ajuste ───────────────────────
  static _WHS _whsTableEntry(int rounds) {
    if (rounds < 3)  return _WHS(count: 0, adj: 0);
    if (rounds == 3) return _WHS(count: 1, adj: -2.0);
    if (rounds == 4) return _WHS(count: 1, adj: -1.0);
    if (rounds == 5) return _WHS(count: 1, adj: 0.0);
    if (rounds == 6) return _WHS(count: 2, adj: -1.0);
    if (rounds <= 8) return _WHS(count: 2, adj: 0.0);
    if (rounds <= 11) return _WHS(count: 3, adj: 0.0);
    if (rounds <= 14) return _WHS(count: 4, adj: 0.0);
    if (rounds <= 16) return _WHS(count: 5, adj: 0.0);
    if (rounds <= 18) return _WHS(count: 6, adj: 0.0);
    if (rounds == 19) return _WHS(count: 7, adj: 0.0);
    return _WHS(count: 8, adj: 0.0); // 20+
  }

  /// Calcula el Handicap Index a partir de una lista de ScoreDifferentials.
  /// Usa las últimas 20 rondas (o menos si no hay suficientes).
  static HandicapIndexResult calculateIndex(List<ScoreDifferential> allDiffs) {
    if (allDiffs.isEmpty) {
      return HandicapIndexResult(
        totalRounds: 0,
        usedDifferentials: [],
        allDifferentials: [],
      );
    }

    // ── LA GUARDA ────────────────────────────────────────────────────────────
    //
    // Un diferencial por debajo del suelo no lo produjo nadie jugando: lo
    // produjo un dato roto aguas arriba. Se descarta del cálculo.
    //
    // Y no es solo un cinturón. Los diferenciales se GUARDAN en Firestore, así
    // que arreglar `calculateFromRound` solo arregla las rondas futuras: los
    // que ya están escritos siguen ahí. Esta línea es lo que repara una cuenta
    // sin migrar nada.
    //
    // Se descartan, no se corrigen: no hay forma de saber qué debería haber
    // dicho un diferencial imposible, y adivinarlo sería inventar el dato en
    // vez de la cifra.
    final buenos = allDiffs.where((d) => !d.esImposible).toList();
    final descartadas = allDiffs.where((d) => d.esImposible).toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));

    // ── LOS NUEVES SE COMBINAN ANTES DE SELECCIONAR ──────────────────────────
    //
    // Es el paso que faltaba, y va AQUÍ y no antes: la ventana de veinte se
    // cuenta sobre diferenciales de dieciocho, así que dos nueves ocupan UNA
    // plaza, no dos. Emparejar después de recortar a veinte habría dejado la
    // ventana con veintitantas rondas dentro.
    //
    // Ver la cabecera de `emparejarNueves`: los guardados no están mal, lo que
    // estaba mal era compararlos con los de dieciocho.
    final emparejados = emparejarNueves(buenos);
    final sinPareja = emparejados.sinPareja;

    // Ordenar por fecha descendente y tomar las últimas 20
    final sorted = [...emparejados.paraElIndice]
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final last20 = sorted.take(20).toList();

    final n = last20.length;
    final entry = _whsTableEntry(n);

    if (entry.count == 0) {
      return HandicapIndexResult(
        totalRounds: n,
        usedDifferentials: [],
        allDifferentials: last20,
        tableAdjustment: entry.adj,
        descartadas: descartadas,
        nueveSinPareja: sinPareja,
      );
    }

    // Ordenar por diferencial ascendente para tomar los mejores (más bajos)
    final byDiff = [...last20]..sort((a, b) => a.differential.compareTo(b.differential));
    final used = byDiff.take(entry.count).toList();

    // Promedio de los mejores N
    final avg = used.fold<double>(0, (s, d) => s + d.differential) / entry.count;

    // Aplicar ajuste de tabla y truncar a 1 decimal (WHS trunca, no redondea)
    double hi = avg + entry.adj;

    // ESR: Exceptional Score Reduction
    double esrAdj = 0.0;
    if (hi > 0) {
      for (final d in used) {
        final diff = hi - d.differential;
        if (diff >= 10.0) {
          esrAdj = max(esrAdj, -2.0);
        } else if (diff >= 7.0) {
          esrAdj = max(esrAdj, -1.0);
        }
      }
    }
    hi += esrAdj;

    // Límite máximo
    hi = min(hi, _maxHI);
    // No puede ser negativo
    if (hi < 0) hi = 0;

    // Truncar a 1 decimal (WHS trunca, no redondea)
    hi = (hi * 10).truncateToDouble() / 10;

    return HandicapIndexResult(
      index: hi,
      totalRounds: n,
      usedDifferentials: used,
      allDifferentials: last20,
      esrAdjustment: esrAdj,
      tableAdjustment: entry.adj,
      descartadas: descartadas,
      nueveSinPareja: sinPareja,
    );
  }

  /// Calcula el Course Handicap a partir del Handicap Index.
  /// Fórmula 2024: CH = (HI × Slope / 113) + (CR − Par)
  static int courseHandicap({
    required double handicapIndex,
    required int slopeRating,
    required double courseRating,
    required int parTotal,
  }) {
    final ch = (handicapIndex * slopeRating / _refSlope) + (courseRating - parTotal);
    return ch.round();
  }

  /// Calcula el Playing Handicap (Course Handicap × Allowance)
  /// Allowance por defecto: 100% (stroke play individual)
  static int playingHandicap({
    required double handicapIndex,
    required int slopeRating,
    required double courseRating,
    required int parTotal,
    double allowancePct = 1.0,
  }) {
    final ch = courseHandicap(
      handicapIndex: handicapIndex,
      slopeRating: slopeRating,
      courseRating: courseRating,
      parTotal: parTotal,
    );
    return (ch * allowancePct).round();
  }

  /// Texto de descripción del nivel de handicap
  static String handicapLevelLabel(double hi) {
    if (hi <= 5)  return 'Scratch / Low';
    if (hi <= 12) return 'Medio-Bajo';
    if (hi <= 20) return 'Intermedio';
    if (hi <= 28) return 'Medio-Alto';
    return 'Alto';
  }
}

// ── Clase auxiliar para la tabla WHS ─────────────────────────────────────────
class _WHS {
  final int count;
  final double adj;
  const _WHS({required this.count, required this.adj});
}
