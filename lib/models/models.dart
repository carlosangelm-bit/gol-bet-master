// ─────────────────────────────────────────────────────────────────────────────
// MODELOS DE DATOS — v4
// Entidades: Round, Player, RoundPlayer, CourseHole, HoleScore,
//            HoleEvent, OyeseRanking, BetModuleInstance (con config tipada),
//            BetGroup, LedgerEntry, SlidingRelation
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'correccion_de_score.dart';

import '../core/golf_icons.dart';

// ── Helper: parsear fecha desde String ISO o Timestamp de Firestore ───────────
// Firestore puede devolver Timestamp (que tiene .toDate()) o String ISO.
// Este helper maneja ambos casos sin necesitar importar cloud_firestore.
DateTime _parseDate(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  // Firestore Timestamp: tiene método toDate()
  try {
    final dt = (value as dynamic).toDate();
    if (dt is DateTime) return dt;
  } catch (_) {}
  return DateTime.now();
}

// ── Enums ─────────────────────────────────────────────────────────────────────
enum BetModuleType { skins, nassau, medal, putts, oyeses, units, nassauLowHigh, snake, rabbit, wolf, stableford, sixes }

/// Qué hacer cuando una categoría (bola baja o alta) queda empatada en un hoyo.
enum LowHighTieRule {
  /// Medio punto para cada equipo. No mueve la diferencia, pero sí los totales.
  split,

  /// Nadie suma. El punto se pierde.
  noPoint,

  /// El punto se acumula al siguiente hoyo de ESA misma categoría.
  carryover,
}

/// A qué categorías aplica el carryover cuando [LowHighTieRule.carryover].
enum LowHighCarryTarget { lowBall, highBall, both }

/// En qué segmentos se cobra la apuesta por diferencia de puntos.
enum PointBetScope {
  /// Solo Front 9 y Back 9.
  perSegment,

  /// Solo el Overall de 18 hoyos.
  overallOnly,

  /// Los tres segmentos.
  all,
}

/// Qué combinaciones admite cada conteo, y POR QUÉ no admite las demás.
///
/// Las combinaciones incoherentes no se prohíben con validación: no se
/// ofrecen, y la opción atenuada dice el motivo. Un usuario que ve "Equipos"
/// en gris con "Medal no tiene semántica de equipo" entiende el modelo; uno
/// que lo elige y recibe un error, no.
///
/// Cada campo está derivado del motor, no de una intuición:
///   · [teams]          → el switch de BetEngine.computeModule cuando
///                        hasTeamSides. Los tipos que caen al default no
///                        tienen motor de equipo: se liquidan como individual.
///   · [requiresTeams]  → BetModuleType.requiresTeams
///   · [perPairAmount]  → BetModuleInstance.supportsPlayerOverride
///   · [segments]       → si el motor liquida por Front/Back/Total
///
/// Añadir un formato nuevo es añadir una fila aquí. Que el catálogo viviera
/// repartido por cinco pantallas costó dos bugs silenciosos esta sesión.
class BetTypeRules {
  /// Se puede jugar por equipos.
  final bool teams;

  /// Por qué no, si [teams] es false. Texto para mostrar en la opción atenuada.
  final String? sinEquipos;

  /// No tiene definición sin dos lados.
  final bool requiresTeams;

  /// Liquida por segmentos (Front 9 / Back 9 / Total).
  final bool segments;
  final String? sinSegmentos;

  /// Admite un importe distinto por pareja dentro del mismo módulo.
  final bool perPairAmount;
  final String? sinMontoPorPareja;

  /// Sus participantes son PERSONAS, nunca lados ni equipos.
  ///
  /// Los side bets —Snake, Rabbit, Wolf— conviven con cualquier juego principal:
  /// se pueden añadir a una ronda por equipos y eso es correcto, así los
  /// describe la especificación. Pero entonces sus participantes son las cuatro
  /// personas, no los dos lados.
  ///
  /// Sin esta marca pasaba lo siguiente, y son TRES síntomas de una causa: en
  /// una ronda best ball, group.playerIds son los reales MÁS los virtuales de
  /// equipo, y un módulo nacido de defaultFor(tipo, group.playerIds) se los
  /// queda todos. Como los virtuales nunca tienen score en best ball, ningún
  /// hoyo parecía capturado —"quedan 18 hoyos" con 2 capturados—, Rabbit no
  /// llegaba a capturar el conejo ni a decir nada, el aviso de score incompleto
  /// pedía score a "Equipo A", y Wolf contaba seis participantes y se declaraba
  /// injugable en una ronda de cuatro personas.
  ///
  /// Se resuelve en UN sitio: [Round.participantesDe].
  ///
  /// ── Por qué también lo llevan Unidades, Medal y Putts ─────────────────────
  ///
  /// Lo llevaban los tres formatos nuevos y se midió si los individuales viejos
  /// tenían el mismo problema. Lo tenían, desde antes, y nadie lo había visto
  /// porque nadie había añadido un formato individual a una ronda por equipos:
  ///
  ///   · Unidades COBRABA A LOS EQUIPOS. En una ronda best ball, un birdie de
  ///     CAM producía `bb_A → cam \$50` y `bb_B → cam \$50`: dos asientos contra
  ///     entidades que no juegan, así que los importes no cuadraban con lo que
  ///     se pagó en el campo.
  ///   · Medal y Putts liquidaban CERO. Necesitan score de todos los
  ///     participantes, y los virtuales no lo tienen en best ball. Peor que mal:
  ///     la apuesta aparecía configurada, con su monto, y no pagaba nada.
  ///
  /// No es la decisión de retirar Match + Press. Aquello era catálogo —un tipo
  /// redundante que dejaba de ofrecerse— sin efecto sobre el dinero de nadie.
  /// Esto corrige dinero MAL CALCULADO, así que el argumento de "cambia números
  /// de rondas ya jugadas" pesa menos: los números actuales están mal y
  /// cambiarlos es corregirlos.
  ///
  /// Consecuencia que hay que saber: el balance de una ronda pasada se recalcula
  /// al abrirla, así que sale corregido solo. Lo que NO se recalcula solo es el
  /// `RoundResult` guardado que alimenta el tablero de Inicio —se escribió al
  /// cerrar, con los números viejos—. Para eso está el backfill del Historial.
  final bool soloPersonas;

  /// La apuesta es UNA para toda la partida, no se pacta cruce a cruce.
  ///
  /// La distinción importa porque un grupo de apuesta guardado es, por dentro,
  /// una lista de duelos: [BettingGroup.pairRules], y
  /// toBetModuleInstancesForToday crea CADA módulo con exactamente dos
  /// participantes. Así que un formato de partida no cabe ahí —pactar Snake por
  /// duelo daría una serpiente por pareja, que no es el juego— y hay que decirlo
  /// en vez de ofrecerlo y liquidar algo distinto.
  ///
  /// Ya existía la idea, en BetCount.esDeGrupo, cubriendo solo Oyes y Unidades.
  /// Ahora vive aquí y esa la deriva, para que no haya dos respuestas.
  final bool deLaPartida;

  /// Por qué no se puede pactar por duelo, y DÓNDE sí se puede poner.
  ///
  /// La segunda mitad es la que convierte una opción atenuada en algo útil: "no
  /// puedes" deja al usuario sin salida, "no aquí, allí sí" le dice qué hacer.
  final String? sinDuelo;

  /// Con cuántos jugadores se puede jugar. Null = cualquier número.
  ///
  /// Era un único número exacto —Wolf con 4— y resultó estrecho: Wolf también se
  /// juega con 5, y lo que cambia es UNA regla de reparto, no el formato. Un
  /// conjunto admite eso sin inventar nada, y el día que entre otro tamaño es
  /// una entrada más aquí.
  ///
  /// Se atenúa en el selector con su motivo, igual que las combinaciones
  /// incoherentes: un usuario que ve la opción en gris con la explicación
  /// entiende el modelo; uno que la elige y recibe un error, no.
  final Set<int>? jugadoresAdmitidos;

  /// Por qué no vale con MENOS de los admitidos, y por qué no vale con MÁS.
  ///
  /// Dos campos porque son dos razones distintas y decirlas juntas no informa:
  /// con 3 jugadores Wolf tiene un problema de rotación, y con 6 tiene un
  /// problema de falta de dato. Un mensaje único tendría que hablar de los dos.
  final String? sinEseNumeroPocos;
  final String? sinEseNumeroMuchos;

  const BetTypeRules({
    this.teams = false,
    this.sinEquipos,
    this.requiresTeams = false,
    this.segments = false,
    this.sinSegmentos,
    this.perPairAmount = false,
    this.sinMontoPorPareja,
    this.deLaPartida = false,
    this.sinDuelo,
    this.jugadoresAdmitidos,
    this.sinEseNumeroPocos,
    this.sinEseNumeroMuchos,
    this.soloPersonas = false,
  });
}

extension BetModuleTypeRules on BetModuleType {
  BetTypeRules get rules => switch (this) {
        BetModuleType.skins => const BetTypeRules(
            teams: true,
            perPairAmount: true,
            sinSegmentos: 'Los skins se resuelven hoyo a hoyo, no por vuelta.',
          ),
        BetModuleType.nassau => const BetTypeRules(
            teams: true,
            segments: true,
            sinMontoPorPareja:
                'Nassau tiene tres importes —Front, Back y Total— y un ajuste '
                'por pareja solo puede llevar uno.',
          ),
        BetModuleType.nassauLowHigh => const BetTypeRules(
            teams: true,
            requiresTeams: true,
            segments: true,
            sinMontoPorPareja:
                'Se juega 2 vs 2: los cruces entre jugadores no son apuestas, '
                'son cómo se reparte el importe del duelo.',
          ),
        BetModuleType.medal => const BetTypeRules(
            soloPersonas: true,
            perPairAmount: true,
            sinEquipos: 'Medal aún no tiene semántica de equipo: se liquidaría '
                'como duelos individuales entre todos.',
            sinSegmentos: 'Medal ya elige entre 9 y 18 hoyos en su detalle.',
          ),
        BetModuleType.putts => const BetTypeRules(
            soloPersonas: true,
            perPairAmount: true,
            sinEquipos: 'Putts aún no tiene semántica de equipo: se liquidaría '
                'como duelos individuales entre todos.',
            sinSegmentos: 'Putts ya elige entre total y hoyo a hoyo en su detalle.',
          ),
        BetModuleType.oyeses => const BetTypeRules(
            deLaPartida: true,
            sinDuelo: 'El ranking de cada par 3 es UNO para todos, no uno por '
                'pareja. Ponla como apuesta de la partida y saca a quien no '
                'entre en el paso de participantes.',
            // Oyes ya se comportaba bien —medido: 6 asientos y ninguno contra un
            // equipo, porque el ranking solo contiene personas— y lleva la marca
            // igual. No por simetría: dejar UNO de los siete formatos sin
            // semántica de equipo sin declararse es exactamente la incoherencia
            // que produjo los cuatro hallazgos, y bastaría con que un día el
            // ranking se rellenara desde otro sitio para reproducirla.
            soloPersonas: true,
            perPairAmount: true,
            sinEquipos: 'Los oyeses son de tiro individual: no hay bola de '
                'equipo que comparar.',
            sinSegmentos: 'Se juegan en los par 3, que no caen por vuelta.',
          ),
        BetModuleType.units => const BetTypeRules(
            deLaPartida: true,
            sinDuelo: 'Cada unidad se acredita contra todos los rivales a la '
                'vez. Ponla como apuesta de la partida.',
            soloPersonas: true,
            perPairAmount: true,
            sinEquipos: 'Las unidades premian un logro individual —birdie, '
                'eagle, sandy— que no se atribuye a un equipo.',
            sinSegmentos: 'Las unidades se cobran cuando ocurren, no por vuelta.',
          ),
        BetModuleType.stableford => const BetTypeRules(
            soloPersonas: true,
            perPairAmount: true,
            sinEquipos: 'Los puntos Stableford son de una tarjeta individual: '
                'no hay una bola de equipo que puntuar.',
            sinSegmentos: 'Stableford ya elige entre la vuelta entera y los '
                'nueve en su detalle.',
          ),
        BetModuleType.wolf => const BetTypeRules(
            soloPersonas: true,
            deLaPartida: true,
            sinDuelo: 'El Wolf rota entre 4 o 5 jugadores: no existe en un '
                'duelo de dos. Añádelo a la partida desde "Agregar apuesta" en '
                'la ronda.',
            jugadoresAdmitidos: {4, 5},
            sinEseNumeroPocos:
                'Con 3 la rotación cambia —cada uno sería Wolf uno de cada tres '
                'hoyos— y no queda un lado de dos contra dos.',
            sinEseNumeroMuchos:
                'Con 6 o más no hay una regla estándar que suponer, y '
                'suponerla sería inventar cómo se reparten los puntos.',
            // "decididos antes de empezar" y no "fijos de ronda": el texto se
            // reutiliza con las formaciones, y "pareja base contra el campo" no
            // tiene unos lados fijos —tiene tres juegos de lados solapados—. Lo
            // que importa es CUÁNDO se deciden, no cuántos hay.
            sinEquipos: 'Wolf arma SUS PROPIOS equipos, distintos en cada '
                'hoyo: el Wolf elige compañero al llegar al green. Unos lados '
                'decididos antes de empezar serían otra apuesta.',
            sinSegmentos: 'Se cobra hoyo a hoyo, así que no hay Front y Back '
                'que separar.',
            sinMontoPorPareja: 'El importe es del hoyo y se reparte entre los '
                'cruces del enfrentamiento de ese hoyo, que cambia cada vez.',
          ),
        BetModuleType.sixes => const BetTypeRules(
            soloPersonas: true,
            deLaPartida: true,
            sinDuelo: 'Sixes rota las parejas entre cuatro: no existe en un '
                'duelo de dos. Añádelo a la partida desde "Agregar apuesta" en '
                'la ronda.',
            // Cuatro y solo cuatro: son las tres únicas maneras de partir a
            // cuatro en dos parejas, y por eso tres bloques cierran la rotación.
            jugadoresAdmitidos: {4},
            sinEseNumeroPocos:
                'Con tres no hay dos parejas que rotar: alguien juega solo cada '
                'bloque, y eso es otro formato.',
            sinEseNumeroMuchos:
                'Con cinco o más la rotación no cierra: en tres bloques no da '
                'tiempo a que cada uno juegue con todos, y el manual lo resuelve '
                'con un jugador que va rotando —el swing man— que es otra '
                'apuesta, no una opción de esta.',
            sinEquipos: 'Sixes arma SUS PROPIAS parejas, y cambian en cada '
                'bloque: es el formato entero. Unos lados fijos de ronda serían '
                'otra apuesta.',
            sinSegmentos: 'Los tres bloques YA son su partición, y se cobran por '
                'separado. Un Front y un Back encima partirían los bloques por '
                'la mitad.',
            sinMontoPorPareja: 'El importe es del bloque y se reparte entre los '
                'cruces de las parejas de ese bloque, que cambian.',
          ),
        BetModuleType.rabbit => const BetTypeRules(
            soloPersonas: true,
            deLaPartida: true,
            sinDuelo: 'Hay UN conejo, y lo captura quien gana el hoyo entre '
                'todos. Por duelo saldría un conejo por pareja. Añádelo a la '
                'partida desde "Agregar apuesta" en la ronda.',
            // Sí liquida por segmentos —cierre del 9 y del 18— pero NO son los
            // Front/Back/Total configurables del Nassau: son los dos cierres de
            // la caza, y no hay un tercer importe "total". Por eso segments
            // queda en false y el motivo lo dice.
            sinEquipos: 'El conejo lo captura una persona ganando un hoyo: no '
                'hay bola de equipo que lo agarre.',
            sinSegmentos: 'Ya se cobra en los dos cierres —el del 9 y el del '
                '18— con el mismo importe. No hay un tercer tramo que separar.',
            sinMontoPorPareja: 'El dueño cobra lo mismo a todos: es una presa, '
                'no un duelo con cada uno.',
          ),
        BetModuleType.snake => const BetTypeRules(
            soloPersonas: true,
            deLaPartida: true,
            sinDuelo: 'Hay UNA serpiente por ronda. Pactada por duelo saldría '
                'una serpiente por pareja, que no es el juego. Añádela a la '
                'partida desde "Agregar apuesta" en la ronda.',
            sinEquipos: 'La serpiente la agarra una persona con sus putts: no '
                'hay 3-putt de equipo.',
            sinSegmentos: 'Es UNA serpiente por ronda —la última—, así que no '
                'se reparte en Front y Back.',
            sinMontoPorPareja: 'El dueño paga lo mismo a todos: es el precio de '
                'la serpiente, no un duelo con cada uno.',
          ),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// LAS SECCIONES DE "AGREGAR APUESTA" — una fuente, no una lista por pantalla
//
// Había TRES hojas de "Agregar apuesta" —Inicio durante la ronda, el paso de
// detalle de Setup y las configuraciones guardadas— y cada una enumeraba los
// tipos a mano en dos listas literales. Snake, Rabbit y Wolf no aparecieron en
// ninguna, y Bola Baja / Bola Alta llevaba tiempo sin aparecer en dos de ellas.
//
// Es la séptima superficie de esta clase en la sesión, y la lección ya estaba
// escrita: en el propio Setup, encima de la lista literal, había un comentario
// que decía "añadir uno nuevo sí sigue exigiendo meterlo aquí, o queda
// inalcanzable desde Setup". Predijo el fallo exacto. Un comentario que avisa no
// sustituye a una estructura que impide.
//
// Lo que hace que esto no vuelva a pasar no es que la lista salga del enum —eso
// ya lo hacían otros selectores— sino que [BetFamily] se resuelva con un switch
// EXHAUSTIVO: el compilador no deja añadir un tipo sin declarar en qué sección
// va, así que no hay forma de añadir uno y que quede fuera de las tres hojas.
//
// El ORDEN sale del enum. No hay una lista de presentación aparte, porque una
// lista de presentación aparte es exactamente lo que acabamos de quitar.
// ─────────────────────────────────────────────────────────────────────────────

/// Con qué grupo se presenta el tipo en las hojas de selección.
enum BetFamily {
  /// Se gana por hoyos ganados: el match y sus parientes.
  matchPlay,

  /// Todo lo demás.
  otras,
}

extension BetFamilyLabel on BetFamily {
  String get label => switch (this) {
        BetFamily.matchPlay => 'MATCH PLAY',
        BetFamily.otras => 'OTRAS APUESTAS',
      };
}

extension BetModuleFamilyOf on BetModuleType {
  /// En qué sección va este tipo.
  ///
  /// Switch exhaustivo A PROPÓSITO: es lo que obliga al siguiente formato a
  /// declararse y lo que impide que quede inalcanzable en las tres hojas.
  BetFamily get family => switch (this) {
        BetModuleType.nassau ||
        BetModuleType.nassauLowHigh =>
          BetFamily.matchPlay,
        BetModuleType.skins ||
        BetModuleType.medal ||
        BetModuleType.putts ||
        BetModuleType.oyeses ||
        BetModuleType.units ||
        BetModuleType.snake ||
        BetModuleType.rabbit ||
        BetModuleType.wolf ||
        BetModuleType.stableford ||
        BetModuleType.sixes =>
          BetFamily.otras,
      };

  /// Por qué este tipo no se puede añadir a una partida de [jugadores]
  /// personas, o null si sí se puede.
  ///
  /// Hoy solo lo usa la cardinalidad de Wolf. Vive aquí y no en un `if` dentro
  /// de cada hoja para que las tres digan lo mismo.
  /// true si tiene sentido pactar esta apuesta en UN duelo de dos personas.
  ///
  /// Tres formas de no tenerlo, y cada una con su motivo:
  ///   · es de la partida entera —Snake, Rabbit, Wolf, Oyes, Unidades—
  ///   · necesita dos equipos —Bola Baja / Bola Alta—
  ///   · necesita un número de jugadores que no es dos —Wolf—
  bool get sePactaPorDuelo => motivoSinDuelo == null;

  /// Por qué no se puede pactar por duelo. Null si sí se puede.
  String? get motivoSinDuelo {
    if (rules.deLaPartida) return rules.sinDuelo;
    if (rules.requiresTeams) {
      return 'Se juega 2 vs 2: un duelo de dos personas no tiene dos lados.';
    }
    return motivoNoDisponible(2);
  }

  String? motivoNoDisponible(int jugadores) {
    final admitidos = rules.jugadoresAdmitidos;
    if (admitidos == null || admitidos.contains(jugadores)) return null;

    // El prefijo se GENERA del conjunto, así que ampliar los tamaños admitidos
    // no deja un texto desactualizado hablando de otro número.
    final orden = admitidos.toList()..sort();
    final cuales = orden.length == 1
        ? '${orden.first}'
        : '${orden.take(orden.length - 1).join(', ')} o ${orden.last}';
    final detalle = jugadores < orden.first
        ? rules.sinEseNumeroPocos
        : rules.sinEseNumeroMuchos;

    return '$label se juega con $cuales jugadores, y esta partida tiene '
        '$jugadores.${detalle == null ? '' : ' $detalle'}';
  }
}

/// Las secciones de las hojas de "Agregar apuesta", en orden.
///
/// Solo tipos creables, agrupados por [BetFamily] y en orden del enum. Una
/// sección sin tipos no se devuelve: así retirar el último tipo de una familia
/// no deja una cabecera huérfana.
List<({BetFamily familia, List<BetModuleType> tipos})> get betTypeSections {
  final porFamilia = <BetFamily, List<BetModuleType>>{};
  for (final t in creatableBetTypes) {
    porFamilia.putIfAbsent(t.family, () => []).add(t);
  }
  return [
    for (final f in BetFamily.values)
      if ((porFamilia[f] ?? const []).isNotEmpty)
        (familia: f, tipos: porFamilia[f]!),
  ];
}

/// Los tipos del catálogo. **Toda hoja de selección debe usar esto.**
///
/// Es una sola lista a propósito. Costó tres bugs descubrir que el catálogo
/// vivía duplicado en cinco pantallas: al añadir Bola Baja / Bola Alta quedó
/// fuera del selector de Setup y de la sección de equipos, y en los dos casos el
/// fallo fue silencioso.
///
/// Hubo aquí un filtro —`isCreatable`— para retirar Match + Press del catálogo
/// dejándolo vivo en el motor. Se fue con él: un filtro que no filtra nada es
/// una bifurcación que hay que leer y entender cada vez para descubrir que no
/// hace nada. El día que haya otro tipo que retirar, se vuelve a poner en una
/// línea.
List<BetModuleType> get creatableBetTypes => BetModuleType.values;

extension BetModuleTeamRules on BetModuleType {
  /// true si el formato no tiene definición sin dos equipos enfrentados.
  ///
  /// Estos módulos deben editarse siempre en el editor que sabe configurar
  /// lados: abrirlos en uno que no los ofrece produce una apuesta sin equipos,
  /// que no liquida nada y parece bien configurada.
  bool get requiresTeams => this == BetModuleType.nassauLowHigh;
}

extension LowHighTieRuleLabel on LowHighTieRule {
  String get label => switch (this) {
        LowHighTieRule.split => 'Dividir (½ punto)',
        LowHighTieRule.noPoint => 'Sin punto',
        LowHighTieRule.carryover => 'Acumular',
      };

  String get description => switch (this) {
        LowHighTieRule.split =>
          'Cada equipo suma medio punto. No cambia la diferencia, pero sí los totales.',
        LowHighTieRule.noPoint => 'El punto se pierde. Nadie suma.',
        LowHighTieRule.carryover =>
          'El punto pasa al siguiente hoyo de esa misma bola, que vale doble.',
      };
}

extension PointBetScopeLabel on PointBetScope {
  String get label => switch (this) {
        PointBetScope.perSegment => 'Front y Back',
        PointBetScope.overallOnly => 'Solo Overall',
        PointBetScope.all => 'Los tres',
      };
}

/// Estructura de expansión de una apuesta.
/// Determina cómo se generan los BetModuleInstance internos.
enum BetStructure {
  /// Un único módulo con todos los participantes (comportamiento original).
  group,
  /// Duelo estrictamente 1 vs 1 (2 jugadores exactos).
  headToHead,
  /// Un jugador ancla contra cada uno de los rivales: N módulos 1v1.
  anchorVsMany,
  /// Todos contra todos: un módulo por cada combinación de 2 jugadores.
  roundRobin,
  /// Módulos añadidos manualmente; no se auto-expanden.
  manual,
}
enum UnitEventType { birdie, eagle, sandyPar, parUnico, birdieUnico, holeOut }
enum PartidaFormat { 
  allInOnePot,    // Todos en un solo pozo grupal
  oneVsOne,       // Cada pareja tiene su duelo independiente
  groupVsGroup,   // Grupo vs Grupo (legacy)
  teams2v2,       // Equipos 2 vs 2 (best-ball)
  teams3v3,       // Equipos 3 vs 3 (best-ball)
}

extension PartidaFormatExt on PartidaFormat {
  bool get isTeamFormat => this == PartidaFormat.teams2v2 || this == PartidaFormat.teams3v3;
  int get teamSize => this == PartidaFormat.teams2v2 ? 2 : (this == PartidaFormat.teams3v3 ? 3 : 0);
  
  String get label {
    switch (this) {
      // La misma palabra que BetFormatMode.onePot.label, y a propósito: son
      // conceptos distintos —esto es el formato de la PARTIDA— pero si alguna
      // vez se enseñan juntos no pueden llamarse de dos maneras.
      case PartidaFormat.allInOnePot: return 'Bote único';
      case PartidaFormat.oneVsOne: return 'Todos vs Todos';
      case PartidaFormat.groupVsGroup: return 'Grupo vs Grupo';
      case PartidaFormat.teams2v2: return 'Equipos 2v2';
      case PartidaFormat.teams3v3: return 'Equipos 3v3';
    }
  }
  
  String get description {
    switch (this) {
      case PartidaFormat.allInOnePot: return 'Un solo pozo grupal. El ganador cobra a todos.';
      case PartidaFormat.oneVsOne: return 'Cada pareja tiene su duelo independiente.';
      case PartidaFormat.groupVsGroup: return 'Grupo vs Grupo';
      case PartidaFormat.teams2v2: return 'Dos equipos de 2 jugadores (best-ball)';
      case PartidaFormat.teams3v3: return 'Dos equipos de 3 jugadores (best-ball)';
    }
  }
}

/// Modo de estructura de la apuesta dentro de un grupo de jugadores.
/// - [onePot]: todos los jugadores comparten un solo pozo/duelo grupal.
///   Ejemplo skins: un solo winner por hoyo toma de todos.
/// - [allVsAll]: cada par de jugadores tiene su propio duelo independiente.
///   Ejemplo skins: A vs B, A vs C, B vs C tienen sus propias skins.
enum BetFormatMode { onePot, allVsAll }

// ─────────────────────────────────────────────────────────────────────────────
// CÓMO SE DICE UNA CONFIGURACIÓN DE APUESTA — fuente única
//
// El criterio de Carlos, dicho entero después de cuatro fallos que eran el
// mismo: "lo importante sería que toda la UI se base en la misma configuración
// de apuesta". Una superficie que muestra un dato tiene que mostrar EL DATO, no
// su propia versión.
//
// El barrido encontró el formato descrito en CUATRO sitios con TRES pares de
// literales distintos —'Todos vs todos' con t minúscula en Apuestas, 'Todos vs
// Todos' en el asistente y en Plantillas, y otro par en la hoja de edición— y la
// explicación larga copiada dos veces palabra por palabra. Cada copia es una
// oportunidad de que una cambie y las otras no; ya pasó con el chip que decía
// una cosa mientras se construía otra.
//
// Esto NO decide nada: solo pone en un sitio cómo se dice lo que el modelo ya
// sabe. Misma forma que betTypeSections y aplicaEnFormato, y por el mismo
// motivo: enumerar en un catálogo lo que si no se escribe suelto en cada
// pantalla.
// ─────────────────────────────────────────────────────────────────────────────

extension BetFormatModeTexto on BetFormatMode {
  /// La etiqueta corta. La MISMA en el asistente, en Plantillas, en la hoja de
  /// edición y en la proyección de Apuestas.
  /// ── Por qué ya no dice "1 Pot" ────────────────────────────────────────────
  ///
  /// El catálogo nació con '1 Pot' junto a 'Todos vs Todos': una insignia en
  /// inglés al lado de otra en español, en la misma pantalla. Se vio en Apuestas
  /// con las dos tarjetas a la vista.
  ///
  /// Y conviene decir por qué el test que lee el código fuente NO lo cazó: ese
  /// test comprueba que no haya una segunda COPIA de la palabra, y no la había
  /// —la insignia leía de aquí—. Un catálogo centraliza dónde vive la palabra,
  /// no si la palabra es buena. Lo que sí cambió es que arreglarla es un sitio.
  ///
  /// 'Bote único' usa el vocabulario que el resto del código ya tiene:
  /// admiteBote, boteDe, "un solo bote".
  String get label => switch (this) {
        BetFormatMode.onePot => 'Bote único',
        BetFormatMode.allVsAll => 'Todos vs Todos',
      };

  /// Qué significa, en una línea.
  String get explicacion => switch (this) {
        BetFormatMode.onePot =>
          'Bote único: un solo ganador por hoyo/segmento toma del resto del '
              'grupo.',
        BetFormatMode.allVsAll =>
          'Todos vs Todos: A vs B, A vs C y B vs C cada uno con su apuesta '
              'propia.',
      };

  /// La versión corta para una tarjeta, sin repetir el nombre del modo.
  String get resumen => switch (this) {
        BetFormatMode.onePot => 'Un solo pozo grupal.\nEl ganador cobra a todos.',
        BetFormatMode.allVsAll =>
          'Cada pareja tiene su\nduelo independiente.',
      };
}

extension BetScopeKindTexto on BetScopeKind {
  /// La etiqueta corta del alcance, para una insignia.
  ///
  /// En mayúsculas porque los tres sitios que la enseñan son insignias. Si algún
  /// día hace falta en minúsculas, se añade aquí y no en la pantalla.
  String get insignia => switch (this) {
        BetScopeKind.everyone => 'TODA LA PARTIDA',
        BetScopeKind.pair => 'USTEDES DOS',
        BetScopeKind.subset => 'ALGUNOS',
        BetScopeKind.teams => 'POR EQUIPOS',
      };

  /// Qué implica para el dinero. Es lo que faltaba decir al elegirlo.
  String get consecuencia => switch (this) {
        BetScopeKind.everyone =>
          'La juegan todos los de la partida, y se liquida en cada pareja.',
        BetScopeKind.pair => 'Solo se liquida entre esos dos.',
        BetScopeKind.subset => 'Solo se liquida entre los elegidos.',
        BetScopeKind.teams => 'Los participantes salen de los lados.',
      };
}
enum BetModuleStatus { draft, configured, active, closed }
enum GrossNetMode { gross, net }
enum TieRule { carryOver, halved, push }
enum PressMode { manual, auto }
enum PayoutRule { winnerTakesAll, proportional }
enum PuttsMode { perHole, total }

/// Vuelta por la que se empieza a jugar.
/// Determina cuál vuelta lleva el stroke extra cuando la diferencia de HCPs es impar.
enum StartingNine {
  front, // Se empieza por el hoyo 1 (F9 lleva el stroke extra)
  back,  // Se empieza por el hoyo 10 (B9 lleva el stroke extra)
}

// ─────────────────────────────────────────────────────────────────────────────
// BetSide — un lado en un duelo (jugador individual o equipo de varios)
//
// Reglas:
//   • Un lado tiene ≥1 jugador.
//   • Dentro de un módulo, cada jugador pertenece a exactamente un lado.
//   • Para módulos sin sides (campo null), el sistema opera en modo
//     individual clásico usando participantIds directamente.
//
// Modo de scoring de equipo:
//   • bestBall (default): el menor score del equipo en el hoyo representa al lado.
//   • scramble: el equipo juega UNA bola. Se crea un "jugador virtual" que representa al equipo.
// ─────────────────────────────────────────────────────────────────────────────

/// Modo de juego para equipos (Best Ball vs Scramble)
enum TeamPlayMode {
  /// Best Ball: cada jugador juega su propia bola, se toma el mejor score del equipo.
  /// Todos los jugadores registran scores individuales.
  bestBall,
  
  /// Scramble: el equipo juega UNA sola bola como unidad.
  /// Se crea un "jugador virtual" que representa al equipo.
  /// Solo se registra UN score por equipo por hoyo.
  scramble,
}

extension TeamPlayModeLabel on TeamPlayMode {
  String get label {
    switch (this) {
      case TeamPlayMode.bestBall:   return 'Best Ball';
      case TeamPlayMode.scramble:    return 'Scramble';
    }
  }
  
  String get description {
    switch (this) {
      case TeamPlayMode.bestBall:   return 'Cada jugador juega su bola. Se usa el mejor score del equipo.';
      case TeamPlayMode.scramble:    return 'El equipo juega UNA bola. Se registra un score por equipo.';
    }
  }
}

class BetSide {
  final String id;        // UUID único dentro del módulo
  final String name;      // Nombre visible: "Team A", "CAM + RICH", etc.
  final List<String> playerIds; // ≥1 player
  final TeamPlayMode playMode;  // Best Ball o Scramble (default: bestBall)

  const BetSide({
    required this.id,
    required this.name,
    required this.playerIds,
    this.playMode = TeamPlayMode.bestBall,
  });

  /// Lado individual: un solo jugador (retrocompatibilidad).
  bool get isIndividual => playerIds.length == 1;

  /// Validar que el lado tiene al menos un jugador.
  bool get isValid => playerIds.isNotEmpty;
  
  /// Indica si este lado está en modo Scramble (jugador virtual).
  bool get isScramble => playMode == TeamPlayMode.scramble && playerIds.length > 1;

  Map<String, dynamic> toJson() => {
    'id':        id,
    'name':      name,
    'playerIds': playerIds,
    'playMode':  playMode.name,
  };

  factory BetSide.fromJson(Map<String, dynamic> j) => BetSide(
    id:        (j['id']   as String?) ?? 'side_${DateTime.now().millisecondsSinceEpoch}',
    name:      (j['name'] as String?) ?? 'Lado',
    playerIds: List<String>.from((j['playerIds'] as List?) ?? []),
    playMode:  TeamPlayMode.values.firstWhere(
      (e) => e.name == (j['playMode'] as String?),
      orElse: () => TeamPlayMode.bestBall,
    ),
  );

  /// Crea un lado individual a partir de un playerId (helper de migración).
  factory BetSide.individual(String playerId, String playerName) => BetSide(
    id:        'side_$playerId',
    name:      playerName,
    playerIds: [playerId],
    playMode:  TeamPlayMode.bestBall, // Individuales siempre son best ball (no aplica scramble)
  );

  // ── Validación de integridad para una lista de dos lados ──────────────────
  //
  // Regla: un jugador solo puede pertenecer a UN lado dentro del mismo módulo.
  // Si se viola, devuelve el playerId duplicado en el String? (null = ok).
  //
  // Uso:
  //   final err = BetSide.findDuplicatePlayer([sideA, sideB]);
  //   if (err != null) showError('$err aparece en ambos lados');
  static String? findDuplicatePlayer(List<BetSide> sides) {
    final seen = <String>{};
    for (final s in sides) {
      for (final pid in s.playerIds) {
        if (!seen.add(pid)) return pid;
      }
    }
    return null;
  }

  /// Valida que dos lados son correctos para un duelo:
  ///   • Exactamente 2 lados.
  ///   • Cada lado tiene ≥1 jugador.
  ///   • Ningún jugador aparece en ambos lados.
  /// Devuelve null si todo está bien, o un mensaje de error si hay problema.
  static String? validateDuel(List<BetSide> sides) {
    if (sides.length != 2) return 'Se requieren exactamente 2 lados';
    for (final s in sides) {
      if (s.playerIds.isEmpty) return 'El lado "${s.name}" no tiene jugadores';
    }
    final dup = findDuplicatePlayer(sides);
    if (dup != null) return 'El jugador $dup aparece en ambos lados';
    return null;
  }

  @override
  String toString() => 'BetSide($name: $playerIds)';
}

extension BetModuleLabel on BetModuleType {
  // switch y no un mapa con [this]!.
  //
  // Eran tres mapas const indexados con la aserción de no-nulo. Al añadir un
  // tipo al enum el analizador cazó los DIECISÉIS switch exhaustivos del
  // proyecto y NO cazó estos tres: un mapa incompleto compila igual y revienta
  // al pintar la etiqueta. Un switch sobre un enum sí es exhaustivo, así que el
  // siguiente formato no se puede añadir a medias.
  String get label => switch (this) {
        BetModuleType.skins => 'Skins',
        BetModuleType.nassau => 'Nassau', // con o sin press (pressEnabled)
        BetModuleType.medal => 'Medal',
        BetModuleType.putts => 'Putts',
        BetModuleType.oyeses => 'Oyes',
        BetModuleType.units => 'Unidades',
        BetModuleType.nassauLowHigh => 'Bola Baja / Bola Alta',
        BetModuleType.snake => 'Snake',
        BetModuleType.rabbit => 'Rabbit',
        BetModuleType.wolf => 'Wolf',
        BetModuleType.sixes => 'Sixes',
        BetModuleType.stableford => 'Stableford',
      };

  /// El icono del formato. **Uno solo para toda la app.**
  ///
  /// ── Por qué IconData y no un emoji ────────────────────────────────────────
  ///
  /// Un emoji es un carácter del SISTEMA: no hereda el color del tema, cambia
  /// de dibujo según el aparato, y a color junto a texto gris es el pico visual
  /// de la pantalla sin merecerlo.
  ///
  /// Y este catálogo lo leen DIEZ pantallas, así que cambiarlo aquí las alcanza
  /// todas — es la misma razón por la que las etiquetas de formato viven aquí y
  /// no en cada sitio que las enseña.
  ///
  /// Los animales —🐍 🐇 🐺— no tienen equivalente lineal en Material, y
  /// dibujar una serpiente a trazo para una app de golf sería adorno. Se
  /// resuelven por lo que SIGNIFICAN en el juego, que es lo que el jugador
  /// necesita reconocer: el Snake arrastra un castigo, el Rabbit se caza y se
  /// pierde, el Wolf es uno contra el resto.
  IconData get icono => switch (this) {
        BetModuleType.skins => GolfIcons.diana,
        BetModuleType.nassau => GolfIcons.golpe,
        BetModuleType.medal => GolfIcons.medalla,
        BetModuleType.putts => GolfIcons.bandera,
        BetModuleType.oyeses => GolfIcons.destello,
        BetModuleType.units => GolfIcons.trofeo,
        BetModuleType.nassauLowHigh => GolfIcons.equilibrio,
        // Arrastra un castigo de hoyo en hoyo.
        BetModuleType.snake => GolfIcons.arrastra,
        // Se caza y se pierde: cambia de manos.
        BetModuleType.rabbit => Icons.swap_horiz,
        // Uno contra el resto.
        BetModuleType.wolf => GolfIcons.duelo,
        BetModuleType.sixes => Icons.groups_outlined,
        BetModuleType.stableford => GolfIcons.grafico,
      };

  /// Qué hace este formato en una ronda de NUEVE hoyos.
  ///
  /// ── Por qué se dice, y por qué aquí ───────────────────────────────────────
  ///
  /// Quien pacta un Nassau espera TRES apuestas: la ida, la vuelta y el total.
  /// Con nueve hoyos no hay tres segmentos, y el motor liquida una sola — que
  /// es lo correcto, pero nadie lo había dicho.
  ///
  /// Va en el catálogo y no en una pantalla porque son varias las que lo
  /// enseñan, y dos redacciones del mismo hecho acaban diciendo cosas
  /// distintas. Es la lección del catálogo de configuración.
  ///
  /// Null = el formato no cambia: se juega igual sobre nueve que sobre
  /// dieciocho.
  String? get enNueveHoyos => switch (this) {
        BetModuleType.nassau =>
          'Una sola apuesta sobre los nueve hoyos. No hay ida, vuelta y total: '
              'no hay dos vueltas que separar.',
        BetModuleType.putts =>
          'Un solo segmento: los putts de los nueve hoyos.',
        _ => null,
      };

  String get description => switch (this) {
        BetModuleType.skins => 'Cada hoyo vale una skin. Empates acumulan.',
        BetModuleType.nassau =>
          'Front 9, Back 9 y Total 18. En una ronda de 9 hoyos es UNA sola '
              'apuesta. Activa presiones automáticas opcionalmente.',
        BetModuleType.medal => 'Score neto total más bajo gana.',
        BetModuleType.putts => 'Menor cantidad de putts por segmento.',
        BetModuleType.oyeses => 'Ranking en par 3s. El más cercano cobra.',
        BetModuleType.units => 'Eagles, birdies, sandy pars y más.',
        BetModuleType.nassauLowHigh =>
          '2 vs 2. Cada hoyo reparte un punto por la bola baja y otro por la alta.',
        BetModuleType.snake =>
          'El último 3-putt de la ronda se queda la serpiente y paga a todos.',
        BetModuleType.rabbit =>
          'El conejo lo captura quien gana un hoyo solo. Cobra quien lo tenga '
              'al cerrar cada nueve.',
        BetModuleType.wolf =>
          'Cada hoyo un jugador es el Wolf y elige compañero, o va solo por el '
              'doble.',
        BetModuleType.sixes =>
          'Tres bloques y las parejas rotan: al acabar has jugado un bloque con '
              'cada uno. Se cobra por bloque ganado.',
        BetModuleType.stableford =>
          'Cada hoyo da puntos según el neto: birdie 3, par 2, bogey 1. Gana '
              'quien más sume.',
      };
}

extension UnitEventLabel on UnitEventType {
  String get label => const {
    UnitEventType.birdie:       'Birdie',
    UnitEventType.eagle:        'Eagle',
    UnitEventType.sandyPar:     'Sandy Par',
    UnitEventType.parUnico:     'Par único',
    UnitEventType.birdieUnico:  'Birdie único',
    UnitEventType.holeOut:      'Hole Out',
  }[this]!;

  String get description => const {
    UnitEventType.birdie:       '1 bajo par en cualquier hoyo',
    UnitEventType.eagle:        '2 bajo par en cualquier hoyo',
    UnitEventType.sandyPar:     'Par desde el bunker',
    UnitEventType.parUnico:     'Único jugador en hacer par',
    UnitEventType.birdieUnico:  'Único jugador en hacer birdie',
    UnitEventType.holeOut:      'Hole-in-one o chip-in',
  }[this]!;
}

extension BetModuleStatusLabel on BetModuleStatus {
  String get label => const {
    BetModuleStatus.draft:      'Borrador',
    BetModuleStatus.configured: 'Configurado',
    BetModuleStatus.active:     'Activo',
    BetModuleStatus.closed:     'Cerrado',
  }[this]!;
}

// ── CourseHole ────────────────────────────────────────────────────────────────
class CourseHole {
  final int hole;
  final int par;
  final int strokeIndex; // 1=hardest
  const CourseHole({required this.hole, required this.par, required this.strokeIndex});
  bool get isPar3 => par == 3;
  Map<String, dynamic> toJson() => {'hole': hole, 'par': par, 'strokeIndex': strokeIndex};
  factory CourseHole.fromJson(Map<String, dynamic> j) => CourseHole(
    hole: (j['hole'] as num?)?.toInt() ?? 1,
    par:  (j['par']  as num?)?.toInt() ?? 4,
    strokeIndex: (j['strokeIndex'] as num?)?.toInt() ?? 1,
  );
}

class CourseInfo {
  final String name;
  final List<CourseHole> holes;
  const CourseInfo({required this.name, required this.holes});
  int get totalPar  => holes.fold(0, (s, h) => s + h.par);
  int get front9Par => holes.where((h) => h.hole <= 9).fold(0, (s, h) => s + h.par);
  int get back9Par  => holes.where((h) => h.hole > 9) .fold(0, (s, h) => s + h.par);
  Map<String, dynamic> toJson() => {
    'name': name,
    'holes': holes.map((h) => h.toJson()).toList(),
  };
  factory CourseInfo.fromJson(Map<String, dynamic> j) => CourseInfo(
    name:  (j['name'] as String?) ?? 'Campo',
    holes: ((j['holes'] as List?) ?? []).map((h) {
      try { return CourseHole.fromJson(h is Map ? Map<String, dynamic>.from(h) : {}); }
      catch (_) { return const CourseHole(hole: 1, par: 4, strokeIndex: 1); }
    }).toList(),
  );

  static final standard = CourseInfo(name: 'Campo Estándar', holes: const [
    CourseHole(hole: 1,  par: 4, strokeIndex: 5),
    CourseHole(hole: 2,  par: 5, strokeIndex: 11),
    CourseHole(hole: 3,  par: 3, strokeIndex: 15),
    CourseHole(hole: 4,  par: 4, strokeIndex: 1),
    CourseHole(hole: 5,  par: 4, strokeIndex: 9),
    CourseHole(hole: 6,  par: 3, strokeIndex: 17),
    CourseHole(hole: 7,  par: 4, strokeIndex: 3),
    CourseHole(hole: 8,  par: 5, strokeIndex: 13),
    CourseHole(hole: 9,  par: 4, strokeIndex: 7),
    CourseHole(hole: 10, par: 4, strokeIndex: 6),
    CourseHole(hole: 11, par: 4, strokeIndex: 2),
    CourseHole(hole: 12, par: 3, strokeIndex: 18),
    CourseHole(hole: 13, par: 5, strokeIndex: 8),
    CourseHole(hole: 14, par: 4, strokeIndex: 4),
    CourseHole(hole: 15, par: 3, strokeIndex: 16),
    CourseHole(hole: 16, par: 4, strokeIndex: 10),
    CourseHole(hole: 17, par: 4, strokeIndex: 12),
    CourseHole(hole: 18, par: 5, strokeIndex: 14),
  ]);
}

// ── Player ────────────────────────────────────────────────────────────────────
class Player {
  final String id;
  String name;
  double handicapBase;
  int colorIndex;
  /// UID de Firebase Auth del jugador si tiene cuenta vinculada (null si no tiene)
  final String? linkedUserId;
  /// Indica si es un jugador virtual (equipo Scramble). Default: false.
  final bool isVirtual;
  /// Lista de playerIds que componen este equipo virtual (solo para isVirtual=true)
  final List<String> teamMemberIds;
  /// Iniciales personalizadas del jugador (máx 4 chars). Usado donde el espacio
  /// es limitado (columnas de scorecard, chips). Si es null se generan
  /// automáticamente de la primera letra de cada palabra del nombre.
  final String? initials;

  Player({
    required this.id,
    required this.name,
    this.handicapBase = 0,
    this.colorIndex = 0,
    this.linkedUserId,
    this.isVirtual = false,
    this.teamMemberIds = const [],
    this.initials,
  });

  bool get hasLinkedAccount => linkedUserId != null && linkedUserId!.isNotEmpty;

  /// Nombre corto para espacios limitados (≤4 chars):
  /// 1. Si tiene initials personalizadas → las usa
  /// 2. Si el primer nombre tiene ≤8 chars → primer nombre
  /// 3. En otro caso → primeras 2 iniciales del nombre completo
  String get shortName {
    if (initials != null && initials!.isNotEmpty) return initials!;
    final first = name.split(' ').first;
    if (first.length <= 8) return first;
    return name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
  }

  Player copyWith({String? name, double? handicapBase, int? colorIndex, String? linkedUserId, bool? isVirtual, List<String>? teamMemberIds, String? initials}) => Player(
    id: id,
    name: name ?? this.name,
    handicapBase: handicapBase ?? this.handicapBase,
    colorIndex: colorIndex ?? this.colorIndex,
    linkedUserId: linkedUserId ?? this.linkedUserId,
    isVirtual: isVirtual ?? this.isVirtual,
    teamMemberIds: teamMemberIds ?? this.teamMemberIds,
    initials: initials ?? this.initials,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'handicapBase': handicapBase, 'colorIndex': colorIndex,
    if (linkedUserId != null && linkedUserId!.isNotEmpty) 'linkedUserId': linkedUserId,
    if (isVirtual) 'isVirtual': true,
    if (teamMemberIds.isNotEmpty) 'teamMemberIds': teamMemberIds,
    if (initials != null && initials!.isNotEmpty) 'initials': initials,
  };
  factory Player.fromJson(Map<String, dynamic> j) => Player(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? 'Jugador',
    handicapBase: (j['handicapBase'] as num?)?.toDouble() ?? 0.0,
    colorIndex: (j['colorIndex'] as int?) ?? 0,
    linkedUserId: j['linkedUserId'] as String?,
    isVirtual: j['isVirtual'] as bool? ?? false,
    // `is List` y no `!= null`: un valor con otra forma —un número, un texto—
    // reventaba la deserialización de la ronda entera. Mismo criterio que el
    // parseo de campos de la API.
    teamMemberIds: j['teamMemberIds'] is List
        ? List<String>.from(j['teamMemberIds'] as List)
        : const [],
    initials: j['initials'] as String?,
  );
}

// ── TeeInfo — datos de la salida elegida por el jugador ──────────────────────
class TeeInfo {
  final String name;
  final double courseRating;
  final int slopeRating;
  final int parTotal;
  /// 'M' = masculino, 'F' = femenino, '' = sin género (estándar o legacy)
  final String gender;

  const TeeInfo({
    required this.name,
    required this.courseRating,
    required this.slopeRating,
    required this.parTotal,
    this.gender = '',
  });

  /// Clave única que combina nombre + género para evitar colisiones
  /// entre tees masculinos y femeninos con el mismo nombre (ej. "Blancas")
  String get key => gender.isEmpty ? name : '$name|$gender';

  double playingHandicap(double hcpIndex) {
    final ph = hcpIndex * (slopeRating / 113.0) + (courseRating - parTotal);
    return ph.roundToDouble();
  }

  Map<String, dynamic> toJson() => {
    'name': name, 'courseRating': courseRating,
    'slopeRating': slopeRating, 'parTotal': parTotal,
    if (gender.isNotEmpty) 'gender': gender,
  };
  factory TeeInfo.fromJson(Map<String, dynamic> j) => TeeInfo(
    name:         j['name']         as String? ?? 'Tee',
    courseRating: (j['courseRating'] as num?)?.toDouble() ?? 72.0,
    slopeRating:  (j['slopeRating']  as num?)?.toInt()    ?? 113,
    parTotal:     (j['parTotal']     as num?)?.toInt()    ?? 72,
    gender:       j['gender']        as String? ?? '',
  );

  static final standard = TeeInfo(
    name: 'Estándar', courseRating: 72.0, slopeRating: 113, parTotal: 72,
  );
}

// ── RoundPlayer — handicap congelado + tee + ventajas ────────────────────────
class RoundPlayer {
  final String playerId;
  final double handicapEnRonda;
  final TeeInfo tee;
  final Map<String, double> manualHandicaps;

  RoundPlayer({
    required this.playerId,
    required this.handicapEnRonda,
    TeeInfo? tee,
    Map<String, double>? manualHandicaps,
  })  : tee = tee ?? TeeInfo.standard,
        manualHandicaps = manualHandicaps ?? const {};

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'handicapEnRonda': handicapEnRonda,
    'tee': tee.toJson(),
    'manualHandicaps': manualHandicaps,
  };
  factory RoundPlayer.fromJson(Map<String, dynamic> j) => RoundPlayer(
    playerId:        (j['playerId'] as String?) ?? '',
    handicapEnRonda: (j['handicapEnRonda'] as num?)?.toDouble() ?? 0.0,
    tee: j['tee'] != null && j['tee'] is Map
        ? TeeInfo.fromJson(Map<String, dynamic>.from(j['tee'] as Map))
        : TeeInfo.standard,
    manualHandicaps: (j['manualHandicaps'] as Map?)
        ?.map((k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0)) ?? const {},
  );
}

// ── HoleScore ────────────────────────────────────────────────────────────────
class HoleScore {
  final String playerId;
  final int hole;
  int? grossScore;
  int putts;

  HoleScore({required this.playerId, required this.hole, this.grossScore, this.putts = 0});
  bool get hasScore => grossScore != null && grossScore! > 0;

  HoleScore copyWith({int? grossScore, int? putts}) => HoleScore(
    playerId: playerId, hole: hole,
    grossScore: grossScore ?? this.grossScore,
    putts: putts ?? this.putts,
  );

  Map<String, dynamic> toJson() => {'playerId': playerId, 'hole': hole, 'grossScore': grossScore, 'putts': putts};
  factory HoleScore.fromJson(Map<String, dynamic> j) => HoleScore(
    playerId: (j['playerId'] as String?) ?? '',
    hole: (j['hole'] as int?) ?? 1,
    grossScore: j['grossScore'] as int?,
    putts: (j['putts'] as int?) ?? 0,
  );
}

// ── HoleEvent — eventos manuales (Units) ─────────────────────────────────────
class HoleEvent {
  final String playerId;
  final int hole;
  final UnitEventType type;
  HoleEvent({required this.playerId, required this.hole, required this.type});

  Map<String, dynamic> toJson() => {'playerId': playerId, 'hole': hole, 'type': type.name};
  factory HoleEvent.fromJson(Map<String, dynamic> j) => HoleEvent(
    playerId: (j['playerId'] as String?) ?? '',
    hole: (j['hole'] as int?) ?? 1,
    type: UnitEventType.values.firstWhere(
      (t) => t.name == (j['type'] as String?),
      orElse: () => UnitEventType.values.first,
    ),
  );
}

// ── OyeseRanking ─────────────────────────────────────────────────────────────
class OyeseRanking {
  final int hole;
  final List<String> ranking;
  OyeseRanking({required this.hole, required this.ranking});

  Map<String, dynamic> toJson() => {'hole': hole, 'ranking': ranking};
  factory OyeseRanking.fromJson(Map<String, dynamic> j) => OyeseRanking(
    hole: (j['hole'] as int?) ?? 1,
    ranking: List<String>.from((j['ranking'] as List?) ?? []),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFIG TIPADA POR MÓDULO
// Cada tipo de apuesta tiene su propia clase de configuración.
// BetModuleInstance las une bajo un paraguas común.
// ─────────────────────────────────────────────────────────────────────────────

class SkinsConfig {
  final double valuePerSkin;   // valor por skin
  final GrossNetMode mode;     // gross o net
  final bool carryOver;        // empates acumulan
  final TieRule tieRule;       // carryOver | push

  const SkinsConfig({
    this.valuePerSkin = 100,
    this.mode = GrossNetMode.net,
    this.carryOver = false,
    this.tieRule = TieRule.push,
  });

  SkinsConfig copyWith({double? valuePerSkin, GrossNetMode? mode, bool? carryOver, TieRule? tieRule}) =>
      SkinsConfig(
        valuePerSkin: valuePerSkin ?? this.valuePerSkin,
        mode: mode ?? this.mode,
        carryOver: carryOver ?? this.carryOver,
        tieRule: tieRule ?? this.tieRule,
      );

  Map<String, dynamic> toJson() => {
    'valuePerSkin': valuePerSkin,
    'mode': mode.name,
    'carryOver': carryOver,
    'tieRule': tieRule.name,
  };
  factory SkinsConfig.fromJson(Map<String, dynamic> j) => SkinsConfig(
    valuePerSkin: (j['valuePerSkin'] as num?)?.toDouble() ?? 100,
    mode: GrossNetMode.values.firstWhere((e) => e.name == (j['mode'] ?? 'net'), orElse: () => GrossNetMode.net),
    carryOver: j['carryOver'] as bool? ?? false,
    tieRule: TieRule.values.firstWhere((e) => e.name == (j['tieRule'] ?? 'push'), orElse: () => TieRule.push),
  );
  static const def = SkinsConfig();
}

// ── Bola Baja / Bola Alta ─────────────────────────────────────────────────────
//
// Formato 2 vs 2. Cada hoyo reparte hasta DOS puntos:
//   • bola baja  → el menor score de cada equipo, uno contra otro
//   • bola alta  → el mayor score de cada equipo, uno contra otro
// Las dos categorías son independientes: un equipo puede llevarse las dos,
// repartirlas 1-1, o empatar cualquiera.
//
// Se acumula en tres segmentos, y el Overall NO es la suma de Front y Back: se
// recorre la ronda completa por separado. Con carryover activo eso importa,
// porque un punto acumulado que expira al cerrar el Front sí sigue vivo en el
// recorrido del Overall.
//
// Liquidación: dos modalidades que pueden convivir y se SUMAN.
//   • [segmentBetEnabled] → monto fijo al que gane cada segmento
//   • [pointBetEnabled]   → monto por cada punto neto de diferencia
class NassauLowHighConfig {
  final GrossNetMode mode;
  final LowHighTieRule tieRule;

  // ── Segmentos activos ──────────────────────────────────────────────────────
  final bool front9Enabled;
  final bool back9Enabled;
  final bool overallEnabled;

  // ── Modalidades de liquidación ─────────────────────────────────────────────
  final bool segmentBetEnabled;
  final bool pointBetEnabled;

  // ── Apuesta fija por segmento ganado ───────────────────────────────────────
  /// Monto por defecto. Los `*Amount` lo sobrescriben por segmento cuando no
  /// son null, para poder tener un Overall más caro sin repetir los otros dos.
  final double segmentAmount;
  final double? front9Amount;
  final double? back9Amount;
  final double? overallAmount;

  // ── Apuesta por diferencia de puntos ───────────────────────────────────────
  final double amountPerPoint;
  final PointBetScope pointScope;

  // ── Carryover ──────────────────────────────────────────────────────────────
  /// A qué bolas aplica el acumulado. Solo tiene efecto con
  /// [LowHighTieRule.carryover]; con las otras reglas se ignora.
  final LowHighCarryTarget carryAppliesTo;

  const NassauLowHighConfig({
    this.mode = GrossNetMode.net,
    this.tieRule = LowHighTieRule.noPoint,
    this.front9Enabled = true,
    this.back9Enabled = true,
    this.overallEnabled = true,
    this.segmentBetEnabled = true,
    this.pointBetEnabled = false,
    this.segmentAmount = 200,
    this.front9Amount,
    this.back9Amount,
    this.overallAmount,
    this.amountPerPoint = 20,
    this.pointScope = PointBetScope.all,
    this.carryAppliesTo = LowHighCarryTarget.both,
  });

  /// Monto fijo de un segmento, cayendo a [segmentAmount] si no tiene propio.
  double amountForFront()   => front9Amount   ?? segmentAmount;
  double amountForBack()    => back9Amount    ?? segmentAmount;
  double amountForOverall() => overallAmount  ?? segmentAmount;

  /// true si la apuesta por puntos aplica al Overall.
  bool get pointsOnOverall =>
      pointScope == PointBetScope.overallOnly || pointScope == PointBetScope.all;

  /// true si la apuesta por puntos aplica a Front y Back.
  bool get pointsOnHalves =>
      pointScope == PointBetScope.perSegment || pointScope == PointBetScope.all;

  bool get carriesLow =>
      tieRule == LowHighTieRule.carryover &&
      carryAppliesTo != LowHighCarryTarget.highBall;

  bool get carriesHigh =>
      tieRule == LowHighTieRule.carryover &&
      carryAppliesTo != LowHighCarryTarget.lowBall;

  /// true si hay algo que cobrar. Sin ninguna modalidad activa el módulo no
  /// liquida nada y la UI debería impedir guardarlo así.
  bool get hasSettlement => segmentBetEnabled || pointBetEnabled;

  NassauLowHighConfig copyWith({
    GrossNetMode? mode,
    LowHighTieRule? tieRule,
    bool? front9Enabled,
    bool? back9Enabled,
    bool? overallEnabled,
    bool? segmentBetEnabled,
    bool? pointBetEnabled,
    double? segmentAmount,
    double? front9Amount,
    bool clearFront9Amount = false,
    double? back9Amount,
    bool clearBack9Amount = false,
    double? overallAmount,
    bool clearOverallAmount = false,
    double? amountPerPoint,
    PointBetScope? pointScope,
    LowHighCarryTarget? carryAppliesTo,
  }) =>
      NassauLowHighConfig(
        mode: mode ?? this.mode,
        tieRule: tieRule ?? this.tieRule,
        front9Enabled: front9Enabled ?? this.front9Enabled,
        back9Enabled: back9Enabled ?? this.back9Enabled,
        overallEnabled: overallEnabled ?? this.overallEnabled,
        segmentBetEnabled: segmentBetEnabled ?? this.segmentBetEnabled,
        pointBetEnabled: pointBetEnabled ?? this.pointBetEnabled,
        segmentAmount: segmentAmount ?? this.segmentAmount,
        front9Amount:
            clearFront9Amount ? null : (front9Amount ?? this.front9Amount),
        back9Amount:
            clearBack9Amount ? null : (back9Amount ?? this.back9Amount),
        overallAmount:
            clearOverallAmount ? null : (overallAmount ?? this.overallAmount),
        amountPerPoint: amountPerPoint ?? this.amountPerPoint,
        pointScope: pointScope ?? this.pointScope,
        carryAppliesTo: carryAppliesTo ?? this.carryAppliesTo,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'tieRule': tieRule.name,
        'front9Enabled': front9Enabled,
        'back9Enabled': back9Enabled,
        'overallEnabled': overallEnabled,
        'segmentBetEnabled': segmentBetEnabled,
        'pointBetEnabled': pointBetEnabled,
        'segmentAmount': segmentAmount,
        if (front9Amount != null) 'front9Amount': front9Amount,
        if (back9Amount != null) 'back9Amount': back9Amount,
        if (overallAmount != null) 'overallAmount': overallAmount,
        'amountPerPoint': amountPerPoint,
        'pointScope': pointScope.name,
        'carryAppliesTo': carryAppliesTo.name,
      };

  factory NassauLowHighConfig.fromJson(Map<String, dynamic> j) =>
      NassauLowHighConfig(
        mode: GrossNetMode.values.firstWhere(
            (m) => m.name == j['mode'], orElse: () => GrossNetMode.net),
        tieRule: LowHighTieRule.values.firstWhere(
            (r) => r.name == j['tieRule'],
            orElse: () => LowHighTieRule.noPoint),
        front9Enabled: j['front9Enabled'] as bool? ?? true,
        back9Enabled: j['back9Enabled'] as bool? ?? true,
        overallEnabled: j['overallEnabled'] as bool? ?? true,
        segmentBetEnabled: j['segmentBetEnabled'] as bool? ?? true,
        pointBetEnabled: j['pointBetEnabled'] as bool? ?? false,
        segmentAmount: (j['segmentAmount'] as num?)?.toDouble() ?? 200,
        front9Amount: (j['front9Amount'] as num?)?.toDouble(),
        back9Amount: (j['back9Amount'] as num?)?.toDouble(),
        overallAmount: (j['overallAmount'] as num?)?.toDouble(),
        amountPerPoint: (j['amountPerPoint'] as num?)?.toDouble() ?? 20,
        pointScope: PointBetScope.values.firstWhere(
            (s) => s.name == j['pointScope'],
            orElse: () => PointBetScope.all),
        carryAppliesTo: LowHighCarryTarget.values.firstWhere(
            (c) => c.name == j['carryAppliesTo'],
            orElse: () => LowHighCarryTarget.both),
      );
}

// ── PressInstance ─────────────────────────────────────────────────────────────
// Una presión individual. Press #1 (sequenceNumber=1) = match principal.
//
// Encabezaba esto una descripción de Match + Press que había quedado suelta al
// mover su configuración a otro sitio. Es la segunda vez que un banner mal
// puesto en este fichero engaña a quien corta por él: el de
// «MatchAutoPressConfig» encabezaba en realidad la sección de Bola Baja / Bola
// Alta, y retirarlo se llevó por delante una clase que no tenía nada que ver.
enum PressStatus { open, closed }

class PressInstance {
  final String id;
  final String betModuleId;
  final int    sequenceNumber;   // 1 = match principal, 2+ = presiones adicionales
  final bool   isPrimaryMatch;   // true solo para Press #1
  final int    startHole;        // hoyo donde inicia esta presión
  final int?   endHole;          // hoyo donde cerró (null = abierta)
  final double value;            // valor en dinero
  final PressStatus status;
  final String? winnerPlayerId;  // null si abierta o empate
  final String? resultLabel;     // ej. 'Carlos +2', 'AS', 'Alan 1UP'

  const PressInstance({
    required this.id,
    required this.betModuleId,
    required this.sequenceNumber,
    required this.isPrimaryMatch,
    required this.startHole,
    required this.value,
    this.endHole,
    this.status = PressStatus.open,
    this.winnerPlayerId,
    this.resultLabel,
  });

  PressInstance copyWith({
    int? endHole, PressStatus? status,
    String? winnerPlayerId, String? resultLabel,
  }) => PressInstance(
    id: id, betModuleId: betModuleId,
    sequenceNumber: sequenceNumber, isPrimaryMatch: isPrimaryMatch,
    startHole: startHole, value: value,
    endHole:        endHole        ?? this.endHole,
    status:         status         ?? this.status,
    winnerPlayerId: winnerPlayerId ?? this.winnerPlayerId,
    resultLabel:    resultLabel    ?? this.resultLabel,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'betModuleId': betModuleId,
    'sequenceNumber': sequenceNumber, 'isPrimaryMatch': isPrimaryMatch,
    'startHole': startHole, 'value': value,
    if (endHole != null) 'endHole': endHole,
    'status': status.name,
    if (winnerPlayerId != null) 'winnerPlayerId': winnerPlayerId,
    if (resultLabel    != null) 'resultLabel': resultLabel,
  };

  factory PressInstance.fromJson(Map<String, dynamic> j) => PressInstance(
    id:             (j['id']             as String?) ?? '',
    betModuleId:    (j['betModuleId']    as String?) ?? '',
    sequenceNumber: (j['sequenceNumber'] as int?)    ?? 1,
    isPrimaryMatch: (j['isPrimaryMatch'] as bool?)   ?? false,
    startHole:      (j['startHole']      as int?)    ?? 1,
    value:          (j['value']          as num?)?.toDouble() ?? 0.0,
    endHole:        j['endHole']         as int?,
    status: PressStatus.values.firstWhere(
      (s) => s.name == (j['status'] ?? 'open'), orElse: () => PressStatus.open),
    winnerPlayerId: j['winnerPlayerId'] as String?,
    resultLabel:    j['resultLabel']    as String?,
  );
}

// ── NassauConfig ──────────────────────────────────────────────────────────────
// Configuración unificada para Nassau (con o sin presiones automáticas).
// Cuando pressEnabled=true se activan los campos de press; las presiones
// se calculan por segmento (F9/B9) y terminan al finalizar el segmento.
class NassauConfig {
  // ── Valores base ─────────────────────────────────────────────────────────────
  final double frontValue;
  final double backValue;
  final double totalValue;
  final GrossNetMode mode;
  final TieRule tieRule;
  // ── Carry ────────────────────────────────────────────────────────────────────
  //
  // ── SON DOS COSAS, y antes eran una sola mal hecha ──────────────────────────
  //
  // Había un MULTIPLICADOR configurable: pedir carry hacía que el B9 y el total
  // de 18 valieran ×2. Carlos revisó una ronda real de cinco y las dos partes
  // estaban mal.
  //
  //   1 · EL CARRY NATURAL **traslada**, no multiplica. Si el F9 queda empatado
  //       su dinero no tiene dueño y se pasa al B9: con 50·50·100 el B9 vale
  //       $100 —$50 propios más los $50 del F9— y **el total de 18 sigue siendo
  //       $100**. Es una apuesta aparte y nadie la tocó.
  //
  //       Con front == back el multiplicador acertaba el B9 por casualidad
  //       (50×2 == 50+50) y erraba el total siempre. Con front != back erraba
  //       los dos: 30 y 50 dan 80, no 100.
  //
  //   2 · EL CARRY PEDIDO no es un factor, es VENTAJA. Solo lo pide quien va
  //       perdiendo, y lo que compra es una SEGUNDA apuesta sobre los mismos
  //       nueve hoyos, del mismo importe, en la que recibe un golpe más:
  //       si le tocaban 3, en la del carry le tocan 4. Se juegan las dos.
  //
  // Por eso el mapa guarda QUIÉN lo pidió y no cuánto multiplica: el golpe extra
  // es de una persona, no del par.
  final bool carryEnabled;

  /// Quién PIDIÓ el carry en cada pareja: [carryPairKey] → id del solicitante.
  ///
  /// En un grupo de cuatro, A puede pedirlo contra B y no contra C. El valor es
  /// el id porque la apuesta del carry se juega con la ventaja de ESE jugador
  /// aumentada en un golpe, y con la clave sola no se sabría de quién.
  ///
  /// Usa el separador '|' a propósito, el mismo que [aperturaB9ByPair] y que
  /// `pairSliding`: las claves son intercambiables sin traducir, y una traducción
  /// fallida no da error — la apuesta simplemente no aparecería.
  final Map<String, String> carryPedidoByPair;
  // ── Presiones ────────────────────────────────────────────────────────────────
  // pressEnabled=false → Nassau clásico sin presiones
  // pressEnabled=true  → presiones automáticas por segmento
  final bool pressEnabled;
  final int autoPressTrigger;       // down-gap que dispara un press (default 2)
  final double frontPressValue;     // valor de cada press en el F9
  final double backPressValue;      // valor de cada press en el B9
  final bool allowMultiplePresses;  // permite más de un press por segmento
  final int? maxPresses;            // max por segmento (null = ilimitado)

  /// La PRESIÓN DE APERTURA de la vuelta trasera, por pareja.
  ///
  /// ── Qué es, y por qué es una apuesta y no un ajuste ───────────────────────
  ///
  /// Al entrar en los nueve traseros, cualquiera de los dos puede abrir una
  /// apuesta que se juega esos nueve DESDE CERO, en paralelo al B9 del Nassau.
  /// Algunos grupos la llaman "adjust bet". Se comporta igual que la apuesta
  /// original se comportó en el hoyo 1: marcador a cero y los nueve por delante.
  ///
  /// No es una presión automática: aquella nace de ir 2 abajo y arranca en el
  /// hoyo siguiente. Esta se pide, cubre los nueve completos, y vale lo mismo
  /// que el segmento original.
  ///
  /// ── Y LA PIDE CUALQUIERA DE LOS DOS ───────────────────────────────────────
  ///
  /// La convención más extendida dice que solo la pide el que va perdiendo,
  /// porque el propósito es darle una vía de recuperación. **El grupo de Carlos
  /// juega que la pide cualquiera**, y esa es la regla de esta app. Queda escrito
  /// aquí, donde se decide, para que nadie lo "corrija" más adelante creyendo
  /// que es un descuido.
  ///
  /// Clave: [carryPairKey], la misma que el carry. En un grupo de cuatro, A
  /// puede abrirla contra B y no contra C.
  final Map<String, bool> aperturaB9ByPair;

  const NassauConfig({
    this.frontValue           = 50,
    this.backValue            = 50,
    this.totalValue           = 100,
    this.mode                 = GrossNetMode.net,
    this.tieRule              = TieRule.push,
    this.carryEnabled         = false,
    this.pressEnabled         = false,
    this.autoPressTrigger     = 2,
    this.frontPressValue      = 50,
    this.backPressValue       = 50,
    // Una por nueve, que es como lo juega el grupo. Sigue siendo configurable
    // —el campo estaba y no lo leía nadie— pero el default obedece la regla.
    //
    // El respaldo de fromJson se queda en true: las rondas guardadas se leen
    // como se jugaron. Esto decide lo que se crea de cero.
    this.allowMultiplePresses = false,
    this.maxPresses,
    this.aperturaB9ByPair = const {},
    this.carryPedidoByPair = const {},
  });

  /// Clave canónica del par. Mismo formato que `pairSliding`.
  static String carryPairKey(String id1, String id2) {
    final sorted = [id1, id2]..sort();
    return '${sorted[0]}|${sorted[1]}';
  }

  /// La partida es un MATCH sobre 18, sin partición en vueltas.
  ///
  /// ── Esto es lo que era Match + Press ──────────────────────────────────────
  ///
  /// Era un tipo aparte con su propio motor, su propia configuración y su propia
  /// pantalla. Y era un Nassau con los dos nueves a cero:
  ///
  ///     Nassau  F9 \$0 · B9 \$0 · Total \$100 · Presiones \$50
  ///
  /// Mantener los dos costaba dos sitios por cada regla nueva —el multiplicador
  /// hubo que retirarlo de las dos configuraciones, y la línea «5 3 1» habría
  /// que escribirla dos veces—, así que se retiró el tipo y se quedó esto.
  ///
  /// Se DEDUCE de los importes y no se guarda como una bandera: dos formas de
  /// decir lo mismo acaban discrepando, y la que manda al liquidar es siempre el
  /// importe.
  ///
  /// ── Y no es idéntico, conviene saberlo ────────────────────────────────────
  ///
  /// En Match + Press cada presión corría hasta el hoyo 18 y todas convivían.
  /// Aquí una presión vive dentro de SU nueve y cierra donde nace la siguiente.
  /// La configuración era la misma; el reloj de las presiones no. Nadie lo tenía
  /// configurado, así que el cambio no le quita nada a nadie — pero está escrito
  /// porque no es un cambio de nombre.
  bool get soloElMatch => frontValue == 0 && backValue == 0;

  /// Quién pidió el carry en esta pareja, o null si nadie.
  String? carryPedidoPor(String id1, String id2) =>
      carryPedidoByPair[carryPairKey(id1, id2)];

  /// ¿Esta pareja abrió la presión de apertura del B9?
  bool aperturaB9For(String id1, String id2) =>
      aperturaB9ByPair[carryPairKey(id1, id2)] == true;

  NassauConfig copyWith({
    double? frontValue, double? backValue, double? totalValue,
    GrossNetMode? mode, TieRule? tieRule,
    bool? carryEnabled, Map<String, String>? carryPedidoByPair,
    bool? pressEnabled, int? autoPressTrigger,
    double? frontPressValue, double? backPressValue,
    bool? allowMultiplePresses, int? maxPresses,
    Map<String, bool>? aperturaB9ByPair,
  }) => NassauConfig(
    frontValue:           frontValue           ?? this.frontValue,
    backValue:            backValue            ?? this.backValue,
    totalValue:           totalValue           ?? this.totalValue,
    mode:                 mode                 ?? this.mode,
    tieRule:              tieRule              ?? this.tieRule,
    carryEnabled:         carryEnabled         ?? this.carryEnabled,
    carryPedidoByPair:    carryPedidoByPair    ?? this.carryPedidoByPair,
    pressEnabled:         pressEnabled         ?? this.pressEnabled,
    autoPressTrigger:     autoPressTrigger     ?? this.autoPressTrigger,
    frontPressValue:      frontPressValue      ?? this.frontPressValue,
    backPressValue:       backPressValue       ?? this.backPressValue,
    allowMultiplePresses: allowMultiplePresses ?? this.allowMultiplePresses,
    maxPresses:           maxPresses           ?? this.maxPresses,
    aperturaB9ByPair:     aperturaB9ByPair     ?? this.aperturaB9ByPair,
  );

  // ── Los «valores efectivos» ya no viven aquí ──────────────────────────────
  //
  // Eran tres getters —`effectiveBackValue`, `effectiveTotalValue`,
  // `effectiveBackPressValue`— que multiplicaban por el factor. Se retiraron
  // con el multiplicador, y con ellos el motivo por el que el fallo llegó a
  // producción: había CINCO sitios calculando el valor de los segmentos por su
  // cuenta —dos en el motor con `* carryFactor` a mano, tres a través de estos
  // getters— y ninguno estaba de acuerdo con los otros. Uno exigía el F9
  // empatado, otro no; unos multiplicaban la presión, otros no.
  //
  // Ahora hay UNO: [BetEngine.valoresDelNassau]. Vive en el motor y no en el
  // modelo porque necesita saber cómo quedó el primer nueve, que es un hecho de
  // la ronda y no de la configuración.

  Map<String, dynamic> toJson() => {
    'frontValue':           frontValue,
    'backValue':            backValue,
    'totalValue':           totalValue,
    'mode':                 mode.name,
    'tieRule':              tieRule.name,
    'carryEnabled':         carryEnabled,
    if (carryPedidoByPair.isNotEmpty) 'carryPedidoByPair': carryPedidoByPair,
    'pressEnabled':         pressEnabled,
    'autoPressTrigger':     autoPressTrigger,
    'frontPressValue':      frontPressValue,
    'backPressValue':       backPressValue,
    'allowMultiplePresses': allowMultiplePresses,
    if (maxPresses != null) 'maxPresses': maxPresses,
    if (aperturaB9ByPair.isNotEmpty) 'aperturaB9ByPair': aperturaB9ByPair,
  };

  factory NassauConfig.fromJson(Map<String, dynamic> j) {
    final front = (j['frontValue'] as num?)?.toDouble() ?? 50;
    final back  = (j['backValue']  as num?)?.toDouble() ?? 50;
    return NassauConfig(
      frontValue:           front,
      backValue:            back,
      totalValue:           (j['totalValue']    as num?)?.toDouble() ?? 100,
      mode:     GrossNetMode.values.firstWhere((e) => e.name == (j['mode'] ?? 'net'),  orElse: () => GrossNetMode.net),
      tieRule:  TieRule.values.firstWhere((e) => e.name == (j['tieRule'] ?? 'push'), orElse: () => TieRule.push),
      carryEnabled:         j['carryEnabled']         as bool? ?? false,
      // Sin lectura del multiplicador viejo, a propósito: una ronda guardada con
      // `carryApplied` pierde el carry y hay que volver a pedirlo. Es el precio
      // de la limpieza, y es de dos toques.
      carryPedidoByPair: (j['carryPedidoByPair'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          const {},
      pressEnabled:         j['pressEnabled']         as bool? ?? false,
      // retrocompat: autoPressTrigger también puede venir como pressTriggerValue
      autoPressTrigger:     (j['autoPressTrigger']    as int?)
                         ?? (j['pressTriggerValue']   as int?) ?? 2,
      // retrocompat: frontPressValue puede venir del antiguo NassauPressConfig
      frontPressValue:      (j['frontPressValue']     as num?)?.toDouble() ?? front,
      backPressValue:       (j['backPressValue']      as num?)?.toDouble() ?? back,
      allowMultiplePresses: j['allowMultiplePresses'] as bool? ?? true,
      maxPresses:           j['maxPresses']           as int?,
      aperturaB9ByPair: ((j['aperturaB9ByPair'] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', v == true)),
    );
  }

  static const def = NassauConfig();
}

class MedalConfig {
  final double value;
  final GrossNetMode mode;
  final int holes;           // 9 o 18
  final PayoutRule payoutRule;

  const MedalConfig({
    this.value = 100,
    this.mode = GrossNetMode.net,
    this.holes = 18,
    this.payoutRule = PayoutRule.winnerTakesAll,
  });

  MedalConfig copyWith({double? value, GrossNetMode? mode, int? holes, PayoutRule? payoutRule}) =>
      MedalConfig(
        value: value ?? this.value,
        mode: mode ?? this.mode,
        holes: holes ?? this.holes,
        payoutRule: payoutRule ?? this.payoutRule,
      );

  Map<String, dynamic> toJson() => {
    'value': value, 'mode': mode.name, 'holes': holes, 'payoutRule': payoutRule.name,
  };
  factory MedalConfig.fromJson(Map<String, dynamic> j) => MedalConfig(
    value: (j['value'] as num?)?.toDouble() ?? 100,
    mode: GrossNetMode.values.firstWhere((e) => e.name == (j['mode'] ?? 'net'), orElse: () => GrossNetMode.net),
    holes: j['holes'] as int? ?? 18,
    payoutRule: PayoutRule.values.firstWhere((e) => e.name == (j['payoutRule'] ?? 'winnerTakesAll'), orElse: () => PayoutRule.winnerTakesAll),
  );
  static const def = MedalConfig();
}

class PuttsConfig {
  final double value;
  final PuttsMode puttsMode;   // perHole | total
  final bool threePuttPenalty; // penalti por 3-putt
  final TieRule tieRule;

  const PuttsConfig({
    this.value = 50,
    this.puttsMode = PuttsMode.total,
    this.threePuttPenalty = false,
    this.tieRule = TieRule.push,
  });

  PuttsConfig copyWith({double? value, PuttsMode? puttsMode, bool? threePuttPenalty, TieRule? tieRule}) =>
      PuttsConfig(
        value: value ?? this.value,
        puttsMode: puttsMode ?? this.puttsMode,
        threePuttPenalty: threePuttPenalty ?? this.threePuttPenalty,
        tieRule: tieRule ?? this.tieRule,
      );

  Map<String, dynamic> toJson() => {
    'value': value, 'puttsMode': puttsMode.name,
    'threePuttPenalty': threePuttPenalty, 'tieRule': tieRule.name,
  };
  factory PuttsConfig.fromJson(Map<String, dynamic> j) => PuttsConfig(
    value: (j['value'] as num?)?.toDouble() ?? 50,
    puttsMode: PuttsMode.values.firstWhere((e) => e.name == (j['puttsMode'] ?? 'total'), orElse: () => PuttsMode.total),
    threePuttPenalty: j['threePuttPenalty'] as bool? ?? false,
    tieRule: TieRule.values.firstWhere((e) => e.name == (j['tieRule'] ?? 'push'), orElse: () => TieRule.push),
  );
  static const def = PuttsConfig();
}

class OyesesConfig {
  final double value;
  final List<int> eligibleHoles; // hoyos elegibles (vacío = todos los par 3)
  final PayoutRule payoutRule;

  // ── Zapato ────────────────────────────────────────────────────────────────
  // El zapato se otorga al jugador que gana TODOS los oyeses.
  // zapatoEnabled  : activa la regla del zapato
  // zapatoValue    : monto del zapato (0 = calcular automático = 2 × sum de todos los oyeses)
  //                  Si es 0 se usa el cálculo automático; si > 0, ese es el monto fijo.
  // zapatoRequires18: true (default) = solo aplica si se juegan los 18 hoyos completos
  //                   false          = aplica también en 9 hoyos (2+ oyeses)
  final bool   zapatoEnabled;
  final double zapatoValue;      // 0 = automático
  final bool   zapatoRequires18; // true = solo aplica en 18H

  const OyesesConfig({
    this.value = 50,
    this.eligibleHoles = const [],
    this.payoutRule = PayoutRule.winnerTakesAll,
    this.zapatoEnabled    = false,
    this.zapatoValue      = 0,
    this.zapatoRequires18 = false,  // default false: aplica cuando se completan todos los oyeses del módulo
  });

  /// Valor efectivo del zapato dado un número de oyeses totales disponibles.
  /// Si zapatoValue > 0 se usa ese monto fijo.
  /// Si zapatoValue == 0 se calcula como totalOyeses × value.
  /// Ej: 4 oyeses de \$50 → zapato = 4 × 50 = \$200.
  double zapatoAmount(int totalOyeses) =>
      zapatoValue > 0 ? zapatoValue : totalOyeses * value;

  OyesesConfig copyWith({
    double? value, List<int>? eligibleHoles, PayoutRule? payoutRule,
    bool? zapatoEnabled, double? zapatoValue, bool? zapatoRequires18,
  }) => OyesesConfig(
    value:            value            ?? this.value,
    eligibleHoles:    eligibleHoles    ?? this.eligibleHoles,
    payoutRule:       payoutRule       ?? this.payoutRule,
    zapatoEnabled:    zapatoEnabled    ?? this.zapatoEnabled,
    zapatoValue:      zapatoValue      ?? this.zapatoValue,
    zapatoRequires18: zapatoRequires18 ?? this.zapatoRequires18,
  );

  Map<String, dynamic> toJson() => {
    'value': value, 'eligibleHoles': eligibleHoles, 'payoutRule': payoutRule.name,
    'zapatoEnabled':    zapatoEnabled,
    'zapatoValue':      zapatoValue,
    'zapatoRequires18': zapatoRequires18,
  };
  factory OyesesConfig.fromJson(Map<String, dynamic> j) => OyesesConfig(
    value: (j['value'] as num?)?.toDouble() ?? 50,
    eligibleHoles: j['eligibleHoles'] is List
        ? List<int>.from(j['eligibleHoles'] as List)
        : const [],
    payoutRule: PayoutRule.values.firstWhere(
        (e) => e.name == (j['payoutRule'] ?? 'winnerTakesAll'),
        orElse: () => PayoutRule.winnerTakesAll),
    zapatoEnabled:    j['zapatoEnabled']    as bool?   ?? false,
    zapatoValue:      (j['zapatoValue']     as num?)?.toDouble() ?? 0,
    zapatoRequires18: j['zapatoRequires18'] as bool?   ?? false,
  );
  static const def = OyesesConfig();
}

class UnitsConfig {
  /// Valor individual por tipo de evento (en dinero, no multiplicador).
  /// Si un evento no está en el mapa se usa [defaultValue].
  final Map<UnitEventType, double> eventValues;

  /// Valor por defecto para eventos sin entrada en [eventValues].
  static const double defaultValue = 50.0;

  const UnitsConfig({this.eventValues = const {}});

  /// Valor configurado para un evento concreto.
  double valueFor(UnitEventType e) => eventValues[e] ?? defaultValue;

  /// Devuelve todos los eventos con sus valores actuales.
  static Map<UnitEventType, double> get defaults => {
    for (final e in UnitEventType.values) e: defaultValue,
  };

  UnitsConfig copyWith({Map<UnitEventType, double>? eventValues}) =>
      UnitsConfig(eventValues: eventValues ?? this.eventValues);

  /// Devuelve una nueva instancia donde TODOS los eventos tienen el mismo [value].
  /// Útil para el editor agrupado donde se configura un único valor por pareja.
  UnitsConfig withAllEventsValue(double v) =>
      UnitsConfig(eventValues: {for (final e in UnitEventType.values) e: v});

  /// true si todos los eventos configurados tienen el mismo valor (o el mapa
  /// está vacío → todos usan [defaultValue]).
  bool get isUniform {
    if (eventValues.isEmpty) return true;
    final vals = UnitEventType.values.map(valueFor);
    return vals.every((v) => v == vals.first);
  }

  /// Valor único representativo:
  ///   • Si todos los eventos tienen el mismo valor → ese valor.
  ///   • Si hay heterogeneidad → valor de birdie como canónico.
  double get representativeValue =>
      isUniform ? valueFor(UnitEventType.birdie) : valueFor(UnitEventType.birdie);

  Map<String, dynamic> toJson() => {
    'eventValues': {
      for (final e in eventValues.entries) e.key.name: e.value,
    },
  };

  factory UnitsConfig.fromJson(Map<String, dynamic> j) {
    final raw = j['eventValues'] as Map<String, dynamic>? ?? {};
    final parsed = <UnitEventType, double>{};
    for (final entry in raw.entries) {
      try {
        final type = UnitEventType.values.firstWhere((t) => t.name == entry.key);
        parsed[type] = (entry.value as num).toDouble();
      } catch (_) {}
    }
    // Retrocompatibilidad: si venía 'valuePerUnit' antiguo, aplicar a todos
    final legacy = (j['valuePerUnit'] as num?)?.toDouble();
    if (legacy != null && parsed.isEmpty) {
      for (final e in UnitEventType.values) {
        parsed[e] = legacy;
      }
    }
    return UnitsConfig(eventValues: parsed);
  }

  static const def = UnitsConfig();
}

// ─────────────────────────────────────────────────────────────────────────────
// BetModuleInstance — instancia configurable de un módulo de apuesta
// ─────────────────────────────────────────────────────────────────────────────
// ── TeamHandicapConfig — allowance de handicap en duelos por equipos ─────────
//
// Implementa los pasos 2 y 3 del WHS para equipos. Los pasos 1 y 4 ya viven
// en otro sitio: el Course Handicap en [TeeInfo.playingHandicap] y el reparto
// por stroke index en GameEngine.strokesReceivedFromOfficial18Sliding.
//
// Los formatos habituales se reducen a DOS formas:
//
//   perPlayer (Four-Ball / Best Ball)
//     Cada jugador conserva SU handicap reducido por [allowance]. Los golpes
//     se cuentan relativos al más bajo del partido.
//       · WHS recomienda 90%. Muchos clubes usan 85% o 75%.
//
//   combined (Foursomes / Chapman / Scramble)
//     El equipo tiene UN handicap: allowance × (lowWeight×bajo + resto×alto).
//       · Foursomes  = 100% × (0.50·L + 0.50·H)  → 50% de la suma
//       · Chapman    = 100% × (0.60·L + 0.40·H)
//       · Scramble   =  50% × (0.70·L + 0.30·H)  → el clásico 35%/15%
enum TeamHcpMethod {
  /// Cada jugador lleva su propio handicap (Four-Ball).
  perPlayer,

  /// El equipo lleva un handicap combinado (Foursomes, Chapman, Scramble).
  combined,
}

class TeamHandicapConfig {
  final TeamHcpMethod method;

  /// Porcentaje del handicap que se concede. 1.0 = 100%.
  /// Es el único control que se muestra normalmente en la UI.
  final double allowance;

  /// Peso del jugador de MENOR handicap dentro del equipo (solo [combined]).
  /// El resto (1 − lowWeight) va al de mayor handicap.
  final double lowWeight;

  const TeamHandicapConfig({
    this.method    = TeamHcpMethod.perPlayer,
    this.allowance = 1.0,
    this.lowWeight = 0.5,
  });

  /// Comportamiento previo a que existiera esta config: 100% por jugador.
  /// Es el default de las rondas ya guardadas, para no cambiarles el dinero.
  static const legacy = TeamHandicapConfig();

  // ── Presets ───────────────────────────────────────────────────────────────
  /// Four-Ball al 90% — recomendación WHS/USGA.
  static const fourBall   = TeamHandicapConfig(allowance: 0.90);
  /// Variante local muy extendida en clubes.
  static const local85    = TeamHandicapConfig(allowance: 0.85);
  /// Foursomes: 50% de la suma de los dos handicaps.
  static const foursomes  = TeamHandicapConfig(
      method: TeamHcpMethod.combined, allowance: 1.0, lowWeight: 0.50);
  /// Chapman / Pinehurst: 60% del bajo + 40% del alto.
  static const chapman    = TeamHandicapConfig(
      method: TeamHcpMethod.combined, allowance: 1.0, lowWeight: 0.60);
  /// Scramble: equivale al clásico 35% del bajo + 15% del alto.
  static const scramble   = TeamHandicapConfig(
      method: TeamHcpMethod.combined, allowance: 0.50, lowWeight: 0.70);

  /// Bola alterna (foursomes): 50% de la SUMA de los dos handicaps.
  ///
  /// lowWeight 0.5 reparte a partes iguales —0.5·bajo + 0.5·alto— y allowance
  /// 1.0 deja el resultado tal cual. No es el 35/15 del scramble: en alterna
  /// los dos jugadores pegan golpes de verdad, así que el equipo no es tan
  /// mejor que sus miembros como en un scramble.
  static const alterna    = TeamHandicapConfig(
      method: TeamHcpMethod.combined, allowance: 1.0, lowWeight: 0.50);

  /// Preset por defecto según el modo de juego elegido en Setup.
  static TeamHandicapConfig defaultFor(TeamPlayMode mode) =>
      mode == TeamPlayMode.scramble ? scramble : fourBall;

  bool get isCombined => method == TeamHcpMethod.combined;

  /// Handicap combinado del equipo a partir de los handicaps de sus miembros.
  ///
  /// NO aplica [allowance] — eso lo hace el motor una sola vez sobre el
  /// resultado, para no multiplicarlo dos veces.
  ///
  /// Con 2 jugadores usa [lowWeight]. Con 3+ reparte de forma decreciente
  /// siguiendo la tabla USGA de Scramble (25/20/15/10 normalizada).
  double combinedHandicap(List<double> memberHandicaps) {
    if (memberHandicaps.isEmpty) return 0;
    final h = [...memberHandicaps]..sort(); // menor primero
    if (h.length == 1) return h.first;
    if (h.length == 2) {
      return h[0] * lowWeight + h[1] * (1 - lowWeight);
    }
    // 3+ jugadores: pesos decrecientes normalizados a 1
    const raw = [25.0, 20.0, 15.0, 10.0, 8.0, 6.0];
    final w = List<double>.generate(
        h.length, (i) => i < raw.length ? raw[i] : 4.0);
    final total = w.fold<double>(0, (s, v) => s + v);
    double acc = 0;
    for (int i = 0; i < h.length; i++) {
      acc += h[i] * (w[i] / total);
    }
    return acc;
  }

  String get label {
    if (!isCombined) return '${(allowance * 100).round()}% por jugador';
    return '${(allowance * 100).round()}% · '
        '${(lowWeight * 100).round()}/${((1 - lowWeight) * 100).round()}';
  }

  TeamHandicapConfig copyWith({
    TeamHcpMethod? method,
    double? allowance,
    double? lowWeight,
  }) => TeamHandicapConfig(
        method:    method    ?? this.method,
        allowance: allowance ?? this.allowance,
        lowWeight: lowWeight ?? this.lowWeight,
      );

  Map<String, dynamic> toJson() => {
        'method':    method.name,
        'allowance': allowance,
        'lowWeight': lowWeight,
      };

  factory TeamHandicapConfig.fromJson(Map<String, dynamic> j) =>
      TeamHandicapConfig(
        method: TeamHcpMethod.values.firstWhere(
            (m) => m.name == j['method'],
            orElse: () => TeamHcpMethod.perPlayer),
        allowance: (j['allowance'] as num?)?.toDouble() ?? 1.0,
        lowWeight: (j['lowWeight'] as num?)?.toDouble() ?? 0.5,
      );

  @override
  bool operator ==(Object other) =>
      other is TeamHandicapConfig &&
      other.method == method &&
      other.allowance == allowance &&
      other.lowWeight == lowWeight;

  @override
  int get hashCode => Object.hash(method, allowance, lowWeight);
}

// ── BetScope — ALCANCE de una apuesta ────────────────────────────────────────
//
// Separa QUIÉN juega (alcance) de QUÉ se juega (tipo + config).
//
// Antes, "quién juega" era una foto congelada en `participantIds`: al crear la
// ronda se materializaba el producto cartesiano (8 jugadores todos-vs-todos =
// 28 instancias) y quien entraba después quedaba fuera para siempre, porque su
// id no estaba en ninguna de esas listas.
//
// Con un alcance declarado, los participantes se RESUELVEN en el momento del
// cálculo contra los jugadores actuales de la ronda. Un alcance [everyone] deja
// entrar solo al jugador que se suma tarde, sin tocar la configuración.
enum BetScopeKind {
  /// Todos los jugadores presentes del grupo. Se re-resuelve dinámicamente.
  everyone,

  /// Subconjunto fijo de jugadores (lista explícita e inmutable).
  subset,

  /// Duelo suelto entre exactamente dos jugadores.
  pair,

  /// Lado A vs lado B — los participantes salen de [BetModuleInstance.sides].
  teams,
}

class BetScope {
  final BetScopeKind kind;

  /// Jugadores del alcance. Relevante solo para [subset] y [pair].
  /// Vacío en [everyone] (dinámico) y [teams] (viven en `sides`).
  final List<String> playerIds;

  const BetScope._(this.kind, this.playerIds);

  const BetScope.everyone() : this._(BetScopeKind.everyone, const []);
  const BetScope.teams()    : this._(BetScopeKind.teams,    const []);
  const BetScope.subset(List<String> ids) : this._(BetScopeKind.subset, ids);

  BetScope.pair(String a, String b) : this._(BetScopeKind.pair, [a, b]);

  bool get isEveryone => kind == BetScopeKind.everyone;
  bool get isPair     => kind == BetScopeKind.pair;

  /// Etiqueta corta para la UI.
  String get label => switch (kind) {
        BetScopeKind.everyone => 'Todos',
        BetScopeKind.subset   => '${playerIds.length} jugadores',
        BetScopeKind.pair     => 'Duelo 1v1',
        BetScopeKind.teams    => 'Equipos',
      };

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (playerIds.isNotEmpty) 'playerIds': playerIds,
      };

  factory BetScope.fromJson(Map<String, dynamic> j) {
    final kind = BetScopeKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => BetScopeKind.subset,
    );
    final ids = (j['playerIds'] as List? ?? []).map((e) => e.toString()).toList();
    return BetScope._(kind, ids);
  }

  @override
  bool operator ==(Object other) =>
      other is BetScope &&
      other.kind == kind &&
      other.playerIds.length == playerIds.length &&
      other.playerIds.every(playerIds.contains);

  @override
  int get hashCode => Object.hash(kind, Object.hashAllUnordered(playerIds));
}


// ── SNAKE ─────────────────────────────────────────────────────────────────────
//
// El último 3-putt de la ronda se queda la serpiente y paga a todos al cierre.
//
// No pide NADA nuevo en el campo: `HoleScore.putts` ya se captura y ya se
// muestra en la pantalla de score. Snake es recorrer los hoyos y encontrar el
// último que pasa del umbral.
//
// Con una limitación del dato que conviene saber: `putts` es un int que arranca
// en 0, así que "no se capturaron los putts" y "hizo 0 putts" son
// indistinguibles. El sesgo es seguro —quien no capturó putts nunca agarra la
// serpiente por error— pero es un falso negativo real. Distinguirlos pediría un
// campo nuevo en HoleScore, que está fuera de esta tarea a propósito.

/// Qué pasa si dos jugadores pasan del umbral en el MISMO último hoyo.
///
/// Existe porque el resultado no puede depender del orden de la lista de
/// jugadores. Con dos empatados hay dos respuestas defendibles y ninguna es
/// obvia, así que se elige en vez de salir por accidente.
enum SnakeEmpate {
  /// Cada uno paga la serpiente completa a los demás. Es lo más común.
  ambosPagan,

  /// Se reparten: cada uno paga su parte. Para grupos que la ven como un bote.
  dividen,
}

extension SnakeEmpateLabel on SnakeEmpate {
  String get label => switch (this) {
        SnakeEmpate.ambosPagan => 'Pagan los dos completo',
        SnakeEmpate.dividen => 'Se reparten la serpiente',
      };

  String get description => switch (this) {
        SnakeEmpate.ambosPagan =>
          'Cada uno paga el monto completo a los demás. Lo más habitual.',
        SnakeEmpate.dividen => 'El monto se divide entre los que empataron.',
      };
}

class SnakeConfig {
  /// Lo que el dueño de la serpiente paga A CADA uno de los demás.
  ///
  /// Con cuatro jugadores y 100, el dueño paga 300 en total. Se define por rival
  /// y no como bote para que el importe no cambie de significado al cambiar el
  /// número de jugadores.
  final double value;

  /// Putts a partir de los cuales cuenta. 3 por defecto; algunos grupos usan 4.
  final int umbral;

  final SnakeEmpate empate;

  const SnakeConfig({
    this.value = 100,
    this.umbral = 3,
    this.empate = SnakeEmpate.ambosPagan,
  });

  static const def = SnakeConfig();

  SnakeConfig copyWith({double? value, int? umbral, SnakeEmpate? empate}) =>
      SnakeConfig(
        value: value ?? this.value,
        umbral: umbral ?? this.umbral,
        empate: empate ?? this.empate,
      );

  Map<String, dynamic> toJson() =>
      {'value': value, 'umbral': umbral, 'empate': empate.name};

  factory SnakeConfig.fromJson(Map<String, dynamic> j) => SnakeConfig(
        value: (j['value'] as num?)?.toDouble() ?? 100,
        umbral: (j['umbral'] as num?)?.toInt() ?? 3,
        empate: SnakeEmpate.values.firstWhere((e) => e.name == j['empate'],
            orElse: () => SnakeEmpate.ambosPagan),
      );
}


// ── RABBIT ────────────────────────────────────────────────────────────────────
//
// El conejo empieza suelto. Lo captura quien gana un hoyo en solitario, y quien
// lo tenga al cerrar cada nueve COBRA a todos los demás. Se reinicia entre
// segmentos: la segunda vuelta es una caza nueva.
//
// Tampoco pide nada en el campo: sale de los scores netos que ya se capturan.
//
// Las variantes van todas apagadas por defecto, que es el estándar. Lo que se
// preguntó porque no se podía deducir del resumen de la especificación:
//
//   · "En solitario" = neto más bajo ESTRICTAMENTE único.
//   · Un empate no suelta el conejo: solo impide capturarlo.

class RabbitConfig {
  /// Lo que el dueño del conejo cobra A CADA uno de los demás, por segmento.
  final double value;

  /// Vencer al dueño transfiere el conejo en el acto.
  ///
  /// Apagada —el estándar— ganarle al dueño lo SUELTA, y hay que ganar otro
  /// hoyo para agarrarlo. Es la regla que hace que el conejo sea difícil de
  /// mantener y a la vez difícil de robar.
  final bool robable;

  /// El importe que nadie cobró en un segmento pasa al siguiente.
  ///
  /// Apagada, se pierde.
  final bool acumula;

  /// Para capturar hace falta birdie neto, no solo ganar el hoyo.
  final bool squirrel;

  const RabbitConfig({
    this.value = 100,
    this.robable = false,
    this.acumula = false,
    this.squirrel = false,
  });

  static const def = RabbitConfig();

  RabbitConfig copyWith(
          {double? value, bool? robable, bool? acumula, bool? squirrel}) =>
      RabbitConfig(
        value: value ?? this.value,
        robable: robable ?? this.robable,
        acumula: acumula ?? this.acumula,
        squirrel: squirrel ?? this.squirrel,
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        // Solo se serializa lo que se apartó del estándar. Las rondas guardadas
        // antes de que existieran estas variantes se leen igual.
        if (robable) 'robable': true,
        if (acumula) 'acumula': true,
        if (squirrel) 'squirrel': true,
      };

  factory RabbitConfig.fromJson(Map<String, dynamic> j) => RabbitConfig(
        value: (j['value'] as num?)?.toDouble() ?? 100,
        robable: j['robable'] == true,
        acumula: j['acumula'] == true,
        squirrel: j['squirrel'] == true,
      );
}


// ── WOLF ──────────────────────────────────────────────────────────────────────
//
// Cada hoyo uno de los cuatro es el Wolf y elige con quién juega, o va solo.
//
// El insight que define el diseño: NADIE NECESITA VER EN LA APP quién es el Wolf
// durante el hoyo —eso se sabe en el tee—; lo importante es registrar el
// resultado. Eso quita de en medio todo lo que hacía a Wolf caro: la máquina de
// decisión secuencial, el bloqueo de opciones tras cada tiro, la captura en
// tiempo real. Nada de eso se construye.
//
// Lo que queda es UNA pregunta por hoyo, al anotar el score: con quién jugó. Y
// el Wolf no se pregunta, se DERIVA del orden de salida.

/// Con quién jugó el Wolf en un hoyo.
///
/// Dato manual por hoyo que no es un score, igual que [OyeseRanking].
///
/// Se valoró unificar los dos en un mapa genérico y no sale natural: lo único
/// que comparten es `Map<int, X>` con claves de JSON en texto —unas seis líneas
/// de serialización— y los payloads no se parecen en nada. Una abstracción
/// genérica pediría o payloads dinámicos, perdiendo el tipado, o genéricos con
/// un serializador por parámetro, que es más maquinaria de la que ahorra. Dos
/// instancias de un patrón claro.
class WolfCall {
  final int hole;

  /// El compañero elegido. **Null = Lone Wolf**, jugó solo.
  ///
  /// Que el hoyo no esté en el mapa es otra cosa: significa que nadie eligió
  /// todavía, y ese hoyo no liquida. No se inventa un compañero.
  ///
  /// ── Sobre Dump, que se valoró y no se construyó ───────────────────────────
  ///
  /// Dump es que el compañero elegido rechace y deje al Wolf solo. El ESTADO ya
  /// cabe aquí sin lógica nueva —se registra "Solo" y el reparto sale correcto
  /// bajo la lectura natural: quedarse solo es quedarse solo—, así que en
  /// dinero no hace falta nada.
  ///
  /// Lo que falta es lo que NO se puede deducir: si el que rechaza paga una
  /// penalización, y si el Wolf abandonado cobra el multiplicador del que eligió
  /// ir solo o otro. Eso es inventar cómo se reparten los puntos, que es
  /// justamente la línea que no se cruza.
  ///
  /// Lo único que se perdería construyéndolo a medias es la NARRACIÓN —"CAV lo
  /// dejó tirado en el 7"— y eso es una etiqueta, no dinero. Cuando alguien lo
  /// pida con las reglas de su grupo, es un campo aquí y una frase en las notas.
  final String? partnerId;

  const WolfCall({required this.hole, this.partnerId});

  bool get solo => partnerId == null;

  Map<String, dynamic> toJson() =>
      {'hole': hole, if (partnerId != null) 'partnerId': partnerId};

  factory WolfCall.fromJson(Map<String, dynamic> j) => WolfCall(
        hole: (j['hole'] as num?)?.toInt() ?? 1,
        partnerId: j['partnerId'] as String?,
      );
}

/// Sixes / Hollywood: tres bloques y las parejas rotan.
///
/// Carlos no juega Sixes. Igual que con Wolf, lo que el manual no fija va
/// configurable con su valor habitual por defecto, en vez de decidirse a ciegas.
///
/// Lo que el manual SÍ fija y por eso no se configura: qué cuenta en cada bloque
/// —mejor bola— y que hay tres bloques. Tres es lo que hace que la rotación
/// cierre con cuatro jugadores; con dos o cuatro bloques alguien repetiría
/// compañero y otro se quedaría sin jugar con alguien.
class SixesConfig {
  /// Lo que vale CADA bloque ganado, en total.
  ///
  /// En total y no por jugador: el bloque es un duelo entre dos parejas y el
  /// dinero se reparte entre los cruces, igual que un Nassau por equipos.
  final double value;

  /// Cuántos hoyos dura cada bloque.
  ///
  /// 6 es el estándar con cuatro jugadores —tres bloques en 18— y 3 es lo que
  /// usa el fivesome. El valor por defecto se ajusta a la longitud de la ronda
  /// al crear la apuesta (ver BetRecipe.build), así que una ronda de 9 sale con
  /// bloques de 3 sin que nadie lo toque.
  final int hoyosPorBloque;

  /// Qué pasa si un bloque queda empatado en hoyos ganados.
  ///
  /// [TieRule.push] por defecto, que es lo coherente con el resto de la app: no
  /// se cobra. Acumular al bloque siguiente sería raro aquí y no otra opción
  /// más: el bloque siguiente tiene OTRAS PAREJAS, así que arrastrar el importe
  /// lo cobraría gente que no jugó esa apuesta.
  final TieRule tieRule;

  const SixesConfig({
    this.value = 50,
    this.hoyosPorBloque = 6,
    this.tieRule = TieRule.push,
  });

  static const def = SixesConfig();

  SixesConfig copyWith({double? value, int? hoyosPorBloque, TieRule? tieRule}) =>
      SixesConfig(
        value: value ?? this.value,
        hoyosPorBloque: hoyosPorBloque ?? this.hoyosPorBloque,
        tieRule: tieRule ?? this.tieRule,
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        if (hoyosPorBloque != 6) 'hoyosPorBloque': hoyosPorBloque,
        if (tieRule != TieRule.push) 'tieRule': tieRule.name,
      };

  factory SixesConfig.fromJson(Map<String, dynamic> j) => SixesConfig(
        value: (j['value'] as num?)?.toDouble() ?? 50,
        hoyosPorBloque: (j['hoyosPorBloque'] as num?)?.toInt() ?? 6,
        tieRule: TieRule.values.firstWhere((t) => t.name == j['tieRule'],
            orElse: () => TieRule.push),
      );
}

class WolfConfig {
  /// Lo que cada perdedor paga a cada ganador en un hoyo.
  ///
  /// Es la convención que ya usa el reparto de importes de equipo: el
  /// enfrentamiento del hoyo se resuelve entre lados y el dinero se mueve por
  /// cruces, así que los asientos nombran personas reales.
  final double value;

  /// Multiplicador del Lone Wolf que GANA.
  ///
  /// 2 por defecto; el rango que se cita es 2-4. El Lone Wolf que pierde paga
  /// sencillo a cada rival, que es lo estándar y no se hace configurable.
  final double loneMultiplier;

  const WolfConfig({this.value = 50, this.loneMultiplier = 2});

  static const def = WolfConfig();

  WolfConfig copyWith({double? value, double? loneMultiplier}) => WolfConfig(
        value: value ?? this.value,
        loneMultiplier: loneMultiplier ?? this.loneMultiplier,
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        if (loneMultiplier != 2) 'loneMultiplier': loneMultiplier,
      };

  factory WolfConfig.fromJson(Map<String, dynamic> j) => WolfConfig(
        value: (j['value'] as num?)?.toDouble() ?? 50,
        loneMultiplier: (j['loneMultiplier'] as num?)?.toDouble() ?? 2,
      );
}


// ── STABLEFORD ────────────────────────────────────────────────────────────────
//
// Gana quien más puntos acumule. Cada hoyo vale según su neto relativo al par,
// con la tabla clásica: birdie 3, par 2, bogey 1, doble o peor 0.
//
// El cálculo ya existía —GameEngine lo produce por hoyo desde siempre para la
// tarjeta— así que esto no construye la aritmética, la EXPONE como apuesta.
//
// Y una distinción que importa: los puntos Stableford son ABSOLUTOS. Salen del
// handicap propio distribuido por stroke index, no del acuerdo bilateral de
// pairSliding que usan Medal, Skins y Nassau. Es lo correcto para este formato
// —es una competición individual de puntos, no un duelo— pero significa que una
// ronda con ventajas solo por pareja no las verá reflejadas aquí. El interruptor
// bruto/neto sí se respeta, así que "sin ventaja" da Stableford bruto.

class StablefordConfig {
  /// Lo que paga el ganador de la apuesta.
  final double value;

  final GrossNetMode mode;

  /// Cuántos puntos vale el par. La tabla entera se desplaza con él.
  final int puntosDelPar;

  /// Suelo y techo de la tabla. Con piso negativo se penalizan los desastres.
  final int piso;
  final int techo;

  const StablefordConfig({
    this.value = 100,
    this.mode = GrossNetMode.net,
    this.puntosDelPar = 2,
    this.piso = 0,
    this.techo = 5,
  });

  static const def = StablefordConfig();

  /// true si la tabla es la clásica. Para poder decirlo en pantalla sin
  /// enumerar los tres números.
  bool get tablaClasica => puntosDelPar == 2 && piso == 0 && techo == 5;

  StablefordConfig copyWith({
    double? value,
    GrossNetMode? mode,
    int? puntosDelPar,
    int? piso,
    int? techo,
  }) =>
      StablefordConfig(
        value: value ?? this.value,
        mode: mode ?? this.mode,
        puntosDelPar: puntosDelPar ?? this.puntosDelPar,
        piso: piso ?? this.piso,
        techo: techo ?? this.techo,
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'mode': mode.name,
        // Solo lo que se aparta de la tabla clásica: una ronda guardada antes de
        // que la tabla fuera configurable se lee igual.
        if (puntosDelPar != 2) 'puntosDelPar': puntosDelPar,
        if (piso != 0) 'piso': piso,
        if (techo != 5) 'techo': techo,
      };

  factory StablefordConfig.fromJson(Map<String, dynamic> j) => StablefordConfig(
        value: (j['value'] as num?)?.toDouble() ?? 100,
        mode: j['mode'] == 'gross' ? GrossNetMode.gross : GrossNetMode.net,
        puntosDelPar: (j['puntosDelPar'] as num?)?.toInt() ?? 2,
        piso: (j['piso'] as num?)?.toInt() ?? 0,
        techo: (j['techo'] as num?)?.toInt() ?? 5,
      );
}

class BetModuleInstance {
  final String id;
  final BetModuleType type;
  final String name;
  final List<String> participantIds; // subconjunto de jugadores del grupo (retrocompat)
  final BetModuleStatus status;

  // ── Lados del duelo (Opción A: campo nuevo opcional) ──────────────────────
  //
  // null  → modo individual clásico. El motor usa participantIds directamente
  //         (exactamente igual que antes). Cero impacto en rondas existentes.
  //
  // List<BetSide> con exactamente 2 elementos → duelo lado A vs lado B.
  //   • Cada lado puede tener 1+ jugadores.
  //   • Un jugador pertenece a un solo lado dentro del módulo.
  //   • Modo de equipo: best ball (menor score del equipo en el hoyo).
  final List<BetSide>? sides;

  // Configs tipadas — solo una tendrá valor según el tipo
  final BetFormatMode          formatMode;
  final SkinsConfig?          skinsConfig;
  final NassauConfig?         nassauConfig;
  final NassauLowHighConfig?  nassauLowHighConfig;
  final MedalConfig?          medalConfig;
  final PuttsConfig?          puttsConfig;
  final OyesesConfig?         oyesesConfig;
  final UnitsConfig?          unitsConfig;
  final SnakeConfig?          snakeConfig;
  final RabbitConfig?         rabbitConfig;
  final WolfConfig?           wolfConfig;
  final SixesConfig?          sixesConfig;
  final StablefordConfig?     stablefordConfig;

  // Presiones dinámicas para Match + Auto Press
  final List<PressInstance> presses;

  // ── Estructura de expansión ───────────────────────────────────────────────
  /// Cómo se generó este módulo. group = clásico (default, retrocompat).
  final BetStructure structure;
  /// ID del grupo lógico al que pertenece cuando se expande desde
  /// anchorVsMany o roundRobin. Null en módulos group/headToHead.
  final String? betGroupId;
  /// Nombre legible del grupo lógico (ej. "Nassau todos vs todos").
  final String? betGroupName;
  /// ID del jugador ancla cuando structure == anchorVsMany.
  final String? anchorPlayerId;

  // ── Overrides por jugador (LEGACY — solo retrocompat) ──────────────────────
  /// Campo heredado. Las nuevas ediciones usan [pairConfigOverrides].
  /// Se preserva solo para deserializar rondas ya guardadas.
  final Map<String, Map<String, dynamic>>? playerConfigOverrides;

  // ── Overrides por duelo/par ───────────────────────────────────────────────
  /// Excepciones de valor por par de jugadores para Skins, Oyeses y Units.
  ///
  /// Clave: [pairKey(pidA, pidB)] — dos playerIds ordenados alfabéticamente
  ///        unidos con "__", ej. "AAM__CAM".
  /// Valor: mapa de configuración plano, ej:
  ///   { 'value': 25.0 }      → Skins (valuePerSkin) y Oyeses (value)
  ///   { 'allEvents': 25.0 }  → Units (todos los eventos del duelo)
  ///
  /// Regla de resolución:
  ///   • Sin override de pareja → config default del grupo.
  ///   • Con override de pareja → ese valor (sin conflictos).
  ///
  /// Null = no hay overrides (retrocompat, módulos viejos).
  final Map<String, Map<String, dynamic>>? pairConfigOverrides;

  // ── Alcance de la apuesta ─────────────────────────────────────────────────
  /// Declara QUIÉN juega esta apuesta. Ver [BetScope].
  ///
  /// null = módulo legacy. Se infiere de `sides`/`participantIds` en
  /// [effectiveScope], de modo que las rondas ya guardadas se comportan
  /// exactamente igual que antes.
  final BetScope? scope;

  // ── Handicap en duelos por equipos ────────────────────────────────────────
  /// Allowance y método de handicap del duelo por equipos. Ver
  /// [TeamHandicapConfig]. Solo aplica cuando [hasTeamSides] es true.
  ///
  /// null = ronda anterior a esta config → [TeamHandicapConfig.legacy]
  /// (100% por jugador), para no cambiar el dinero de lo ya guardado.
  final TeamHandicapConfig? teamHandicapConfig;

  const BetModuleInstance({
    required this.id,
    required this.type,
    required this.name,
    required this.participantIds,
    this.scope,
    this.teamHandicapConfig,
    this.sides,                          // null = modo individual clásico
    this.status = BetModuleStatus.configured,
    this.formatMode = BetFormatMode.onePot,
    this.skinsConfig,
    this.nassauConfig,
    this.nassauLowHighConfig,
    this.medalConfig,
    this.puttsConfig,
    this.oyesesConfig,
    this.unitsConfig,
    this.snakeConfig,
    this.rabbitConfig,
    this.wolfConfig,
    this.sixesConfig,
    this.stablefordConfig,
    this.presses = const [],
    this.structure = BetStructure.group,
    this.betGroupId,
    this.betGroupName,
    this.anchorPlayerId,
    this.playerConfigOverrides,
    this.pairConfigOverrides,
  });

  // ── Acceso a lados con validación rápida ─────────────────────────────────
  /// true si este módulo opera en modo equipo (sides definidos y válidos).
  bool get hasTeamSides =>
      sides != null && sides!.length == 2 &&
      sides!.every((s) => s.isValid);

  /// Lado A (index 0) cuando hasTeamSides == true.
  BetSide get sideA => sides![0];

  /// Lado B (index 1) cuando hasTeamSides == true.
  BetSide get sideB => sides![1];

  /// Todos los playerIds involucrados en el duelo de equipo.
  List<String> get allSidePlayerIds =>
      hasTeamSides ? [...sideA.playerIds, ...sideB.playerIds] : participantIds;

  /// Error de validación de lados (null = ok). Útil en UI antes de guardar.
  /// Verifica: exactamente 2 lados, ≥1 jugador por lado, sin jugadores repetidos.
  String? get sidesValidationError =>
      sides != null ? BetSide.validateDuel(sides!) : null;

  // ── Acceso rápido a config efectiva ────────────────────────────────────────
  /// true si la apuesta corre en modo todos-contra-todos (pares)
  bool get isAllVsAll => formatMode == BetFormatMode.allVsAll;

  SkinsConfig          get skins          => skinsConfig          ?? SkinsConfig.def;
  NassauConfig         get nassau         => nassauConfig         ?? NassauConfig.def;
  NassauLowHighConfig  get lowHigh        => nassauLowHighConfig  ?? const NassauLowHighConfig();
  MedalConfig          get medal          => medalConfig          ?? MedalConfig.def;
  PuttsConfig          get putts          => puttsConfig          ?? PuttsConfig.def;
  OyesesConfig         get oyeses         => oyesesConfig         ?? OyesesConfig.def;
  UnitsConfig          get units          => unitsConfig          ?? UnitsConfig.def;
  SnakeConfig          get snake          => snakeConfig          ?? SnakeConfig.def;
  RabbitConfig         get rabbit         => rabbitConfig         ?? RabbitConfig.def;
  WolfConfig           get wolf           => wolfConfig           ?? WolfConfig.def;
  SixesConfig          get sixes          => sixesConfig          ?? SixesConfig.def;
  StablefordConfig     get stableford     => stablefordConfig     ?? StablefordConfig.def;

  // ── Compatibilidad con BetEngine (valor base y flags) ──────────────────────
  double get value => switch (type) {
    BetModuleType.snake         => snake.value,
    BetModuleType.rabbit        => rabbit.value,
    BetModuleType.wolf          => wolf.value,
    BetModuleType.sixes         => sixes.value,
    BetModuleType.stableford    => stableford.value,
    BetModuleType.skins         => skins.valuePerSkin,
    BetModuleType.nassau        => nassau.frontValue,
    BetModuleType.medal         => medal.value,
    BetModuleType.putts         => putts.value,
    BetModuleType.oyeses        => oyeses.value,
    BetModuleType.units         => units.valueFor(UnitEventType.birdie),
    // Sin un importe único: tiene fijo por segmento y variable por punto.
    // Se expone el fijo por ser el que domina la liquidación típica.
    BetModuleType.nassauLowHigh => lowHigh.segmentAmount,
  };

  bool get useHandicap => switch (type) {
    BetModuleType.skins         => skins.mode == GrossNetMode.net,
    BetModuleType.nassau        => nassau.mode == GrossNetMode.net,
    BetModuleType.nassauLowHigh => lowHigh.mode == GrossNetMode.net,
    BetModuleType.medal         => medal.mode == GrossNetMode.net,
    // Sin esta rama Stableford calcularía BRUTO en silencio: el default del
    // switch es false. Es la trampa que el encargo pedía comprobar.
    BetModuleType.stableford    => stableford.mode == GrossNetMode.net,
    _                           => false,
  };

  bool get carryOver    => type == BetModuleType.skins  && skins.carryOver;
  bool get pressEnabled => type == BetModuleType.nassau && nassau.pressEnabled;
  int  get pressTrigger => nassau.autoPressTrigger;

  Map<String, dynamic> get extra => type == BetModuleType.nassau ? {
    'frontValue': nassau.frontValue,
    'backValue':  nassau.backValue,
    'totalValue': nassau.totalValue,
  } : const {};

  // ── Summary para mostrar en el tile ──────────────────────────────────────
  String get summaryLabel => switch (type) {
    BetModuleType.snake  => '\$${snake.value.toStringAsFixed(0)} · '
                            '${snake.umbral}+ putts',
    BetModuleType.stableford => '\$${stableford.value.toStringAsFixed(0)} · '
                            '${stableford.mode == GrossNetMode.net ? 'Net' : 'Gross'}'
                            '${stableford.tablaClasica ? '' : ' · tabla propia'}',
    BetModuleType.wolf   => '\$${wolf.value.toStringAsFixed(0)}/hoyo · '
                            'solo ×${wolf.loneMultiplier.toStringAsFixed(0)}',
    BetModuleType.sixes  => '\$${sixes.value.toStringAsFixed(0)}/bloque · '
                            'bloques de ${sixes.hoyosPorBloque}',
    BetModuleType.rabbit => '\$${rabbit.value.toStringAsFixed(0)}/nueve'
                            '${rabbit.robable ? ' · robable' : ''}'
                            '${rabbit.squirrel ? ' · squirrel' : ''}',
    BetModuleType.skins  => '\$${skins.valuePerSkin.toStringAsFixed(0)}/skin'
                            '${skins.carryOver ? ' · carry' : ''}'
                            ' · ${skins.mode == GrossNetMode.net ? 'Net' : 'Gross'}',
    BetModuleType.nassau => 'F\$${nassau.frontValue.toStringAsFixed(0)}'
                            ' B\$${nassau.backValue.toStringAsFixed(0)}'
                            ' T\$${nassau.totalValue.toStringAsFixed(0)}'
                            '${nassau.pressEnabled ? ' · Press' : ''}'
                            '${nassau.carryEnabled ? ' · Carry' : ''}',
    BetModuleType.medal  => '\$${medal.value.toStringAsFixed(0)}'
                            ' · ${medal.holes}H'
                            ' · ${medal.mode == GrossNetMode.net ? 'Net' : 'Gross'}',
    BetModuleType.putts  => '\$${putts.value.toStringAsFixed(0)}'
                            '${putts.threePuttPenalty ? ' · 3-putt' : ''}',
    BetModuleType.oyeses => '\$${oyeses.value.toStringAsFixed(0)}/oyés'
                            '${oyeses.zapatoEnabled ? ' · zapato' : ''}',
    BetModuleType.units  => '\$${units.representativeValue.toStringAsFixed(0)} / unidad'
                            ' · ${UnitEventType.values.length} eventos',
    BetModuleType.nassauLowHigh => () {
      final c = lowHigh;
      final partes = <String>[
        if (c.segmentBetEnabled) '\$${c.segmentAmount.toStringAsFixed(0)}/segmento',
        if (c.pointBetEnabled)   '\$${c.amountPerPoint.toStringAsFixed(0)}/punto',
      ];
      final modo = c.mode == GrossNetMode.net ? 'Net' : 'Gross';
      return '${partes.join(" + ")} · $modo';
    }(),
  };

  // ── copyWith ──────────────────────────────────────────────────────────────
  // clearSides: si true, pone sides=null (volver a modo individual).
  BetModuleInstance copyWith({
    /// Solo para CLONAR: la formación "pareja base contra el campo" monta tres
    /// apuestas del mismo tipo, y el id es lo que las distingue en el ledger y en
    /// las hojas de edición. Nadie más debería cambiarlo.
    String? id,
    String? name,
    List<String>? participantIds,
    List<BetSide>? sides,
    bool clearSides = false,
    BetModuleStatus? status,
    BetFormatMode?        formatMode,
    SkinsConfig?          skinsConfig,
    NassauConfig?         nassauConfig,
    NassauLowHighConfig?  nassauLowHighConfig,
    MedalConfig?          medalConfig,
    PuttsConfig?          puttsConfig,
    OyesesConfig?         oyesesConfig,
    UnitsConfig?          unitsConfig,
    SnakeConfig?          snakeConfig,
    RabbitConfig?         rabbitConfig,
    WolfConfig?           wolfConfig,
    SixesConfig?          sixesConfig,
    StablefordConfig?     stablefordConfig,
    List<PressInstance>?  presses,
    BetStructure?                        structure,
    String?                              betGroupId,
    String?                              betGroupName,
    String?                              anchorPlayerId,
    Map<String, Map<String, dynamic>>?   playerConfigOverrides,
    bool                                 clearPlayerOverrides = false,
    Map<String, Map<String, dynamic>>?   pairConfigOverrides,
    bool                                 clearPairOverrides = false,
    BetScope?                            scope,
    bool                                 clearScope = false,
    TeamHandicapConfig?                  teamHandicapConfig,
  }) => BetModuleInstance(
    id: id ?? this.id, type: type,
    name: name ?? this.name,
    participantIds: participantIds ?? this.participantIds,
    scope: clearScope ? null : (scope ?? this.scope),
    teamHandicapConfig: teamHandicapConfig ?? this.teamHandicapConfig,
    sides: clearSides ? null : (sides ?? this.sides),
    status: status ?? this.status,
    formatMode:           formatMode           ?? this.formatMode,
    skinsConfig:          skinsConfig          ?? this.skinsConfig,
    nassauConfig:         nassauConfig         ?? this.nassauConfig,
    nassauLowHighConfig:  nassauLowHighConfig  ?? this.nassauLowHighConfig,
    medalConfig:          medalConfig          ?? this.medalConfig,
    puttsConfig:          puttsConfig          ?? this.puttsConfig,
    oyesesConfig:         oyesesConfig         ?? this.oyesesConfig,
    unitsConfig:          unitsConfig          ?? this.unitsConfig,
    snakeConfig:          snakeConfig          ?? this.snakeConfig,
    rabbitConfig:         rabbitConfig         ?? this.rabbitConfig,
    wolfConfig:           wolfConfig           ?? this.wolfConfig,
    sixesConfig:          sixesConfig          ?? this.sixesConfig,
    stablefordConfig:     stablefordConfig     ?? this.stablefordConfig,
    presses:              presses              ?? this.presses,
    structure:             structure             ?? this.structure,
    betGroupId:            betGroupId            ?? this.betGroupId,
    betGroupName:          betGroupName          ?? this.betGroupName,
    anchorPlayerId:        anchorPlayerId        ?? this.anchorPlayerId,
    playerConfigOverrides: clearPlayerOverrides
        ? null
        : (playerConfigOverrides ?? this.playerConfigOverrides),
    pairConfigOverrides: clearPairOverrides
        ? null
        : (pairConfigOverrides ?? this.pairConfigOverrides),
  );

  // ── JSON ──────────────────────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'id': id, 'type': type.name, 'name': name,
    'participantIds': participantIds,
    'status': status.name,
    'formatMode': formatMode.name,
    // scope: solo si se declaró explícitamente. Los módulos sin esta clave se
    // deserializan con scope=null y lo infieren en effectiveScope, así que las
    // rondas ya guardadas siguen comportándose igual.
    if (scope != null) 'scope': scope!.toJson(),
    // teamHandicapConfig: solo si se declaró. Sin la clave → legacy (100%).
    if (teamHandicapConfig != null)
      'teamHandicapConfig': teamHandicapConfig!.toJson(),
    // structure: solo se serializa si no es el default (retrocompat — rondas
    // viejas sin este campo se deserializan como BetStructure.group).
    if (structure != BetStructure.group) 'structure': structure.name,
    if (betGroupId    != null) 'betGroupId':    betGroupId,
    if (betGroupName  != null) 'betGroupName':  betGroupName,
    if (anchorPlayerId != null) 'anchorPlayerId': anchorPlayerId,
    // playerConfigOverrides: solo si hay entradas (retrocompat, módulos viejos no lo tienen).
    if (playerConfigOverrides != null && playerConfigOverrides!.isNotEmpty)
      'playerConfigOverrides': {
        for (final e in playerConfigOverrides!.entries) e.key: e.value,
      },
    // pairConfigOverrides: nuevo modelo de overrides por duelo.
    if (pairConfigOverrides != null && pairConfigOverrides!.isNotEmpty)
      'pairConfigOverrides': {
        for (final e in pairConfigOverrides!.entries) e.key: e.value,
      },
    // sides: solo se serializa si existe. Rondas sin sides → no tienen clave (retrocompat).
    if (sides != null) 'sides': sides!.map((s) => s.toJson()).toList(),
    if (skinsConfig          != null) 'skinsConfig':          skinsConfig!.toJson(),
    if (nassauConfig         != null) 'nassauConfig':         nassauConfig!.toJson(),
    if (nassauLowHighConfig  != null) 'nassauLowHighConfig':  nassauLowHighConfig!.toJson(),
    if (medalConfig          != null) 'medalConfig':          medalConfig!.toJson(),
    if (puttsConfig          != null) 'puttsConfig':          puttsConfig!.toJson(),
    if (oyesesConfig         != null) 'oyesesConfig':         oyesesConfig!.toJson(),
    if (unitsConfig          != null) 'unitsConfig':          unitsConfig!.toJson(),
    if (snakeConfig          != null) 'snakeConfig':          snakeConfig!.toJson(),
    if (rabbitConfig         != null) 'rabbitConfig':         rabbitConfig!.toJson(),
    if (wolfConfig           != null) 'wolfConfig':           wolfConfig!.toJson(),
    if (sixesConfig          != null) 'sixesConfig':          sixesConfig!.toJson(),
    if (stablefordConfig     != null) 'stablefordConfig':     stablefordConfig!.toJson(),
    if (presses.isNotEmpty)           'presses': presses.map((p) => p.toJson()).toList(),
  };

  factory BetModuleInstance.fromJson(Map<String, dynamic> j) {
    // Retrocompat: el tipo 'nassauPress' se migra a 'nassau' (módulo unificado)
    final rawType = (j['type'] as String?) ?? 'skins';
    final type = BetModuleType.values.firstWhere(
      (t) => t.name == (rawType == 'nassauPress' ? 'nassau' : rawType),
      orElse: () => BetModuleType.skins,
    );
    Map<String, dynamic> asMap(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

    // sides: null si no existe la clave (modo individual clásico, retrocompat)
    final rawSides = j['sides'] as List?;
    final sides = rawSides?.map((s) {
            try { return BetSide.fromJson(s is Map ? Map<String, dynamic>.from(s) : {}); }
            catch (_) { return null; }
          }).whereType<BetSide>().toList();

    return BetModuleInstance(
      id:   (j['id']   as String?) ?? 'mod_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      name: j['name'] as String? ?? type.label,
      participantIds: List<String>.from((j['participantIds'] as List?) ?? []),
      // scope null si la clave no existe → effectiveScope lo infiere (retrocompat)
      scope: j['scope'] != null ? BetScope.fromJson(asMap(j['scope'])) : null,
      teamHandicapConfig: j['teamHandicapConfig'] != null
          ? TeamHandicapConfig.fromJson(asMap(j['teamHandicapConfig']))
          : null,
      sides: sides,
      status: BetModuleStatus.values.firstWhere(
          (s) => s.name == (j['status'] ?? 'configured'),
          orElse: () => BetModuleStatus.configured),
      formatMode: BetFormatMode.values.firstWhere(
          (f) => f.name == (j['formatMode'] ?? 'onePot'),
          orElse: () => BetFormatMode.onePot),
      skinsConfig:          j['skinsConfig']          != null ? SkinsConfig.fromJson(asMap(j['skinsConfig']))          : null,
      // Retrocompat: si el tipo era 'nassauPress', migrarlo a 'nassau' con pressEnabled=true
      nassauConfig: () {
        final isLegacyNP = (j['type'] as String?) == 'nassauPress';
        if (isLegacyNP && j['nassauPressConfig'] != null) {
          // Migrar campos de NassauPressConfig al NassauConfig unificado
          final np = asMap(j['nassauPressConfig']);
          return NassauConfig(
            frontValue:           (np['frontValue']       as num?)?.toDouble() ?? 50,
            backValue:            (np['backValue']        as num?)?.toDouble() ?? 50,
            totalValue:           (np['totalValue']       as num?)?.toDouble() ?? 100,
            mode:     GrossNetMode.values.firstWhere((e) => e.name == (np['mode'] ?? 'net'), orElse: () => GrossNetMode.net),
            tieRule:  TieRule.values.firstWhere((e) => e.name == (np['tieRule'] ?? 'push'), orElse: () => TieRule.push),
            carryEnabled:         np['carryEnabled']         as bool? ?? false,
            pressEnabled:         true,  // era nassauPress → press siempre activo
            autoPressTrigger:     (np['pressTriggerValue']   as int?) ?? 2,
            frontPressValue:      (np['frontPressValue']     as num?)?.toDouble() ?? 50,
            backPressValue:       (np['backPressValue']      as num?)?.toDouble() ?? 50,
            allowMultiplePresses: np['allowMultiplePresses'] as bool? ?? true,
            maxPresses:           np['maxPresses']           as int?,
          );
        }
        return j['nassauConfig'] != null ? NassauConfig.fromJson(asMap(j['nassauConfig'])) : null;
      }(),
      medalConfig:          j['medalConfig']          != null ? MedalConfig.fromJson(asMap(j['medalConfig']))          : null,
      puttsConfig:          j['puttsConfig']          != null ? PuttsConfig.fromJson(asMap(j['puttsConfig']))          : null,
      oyesesConfig:         j['oyesesConfig']         != null ? OyesesConfig.fromJson(asMap(j['oyesesConfig']))        : null,
      unitsConfig:          j['unitsConfig']          != null ? UnitsConfig.fromJson(asMap(j['unitsConfig']))          : null,
      snakeConfig:          j['snakeConfig']          != null ? SnakeConfig.fromJson(asMap(j['snakeConfig']))          : null,
      rabbitConfig:         j['rabbitConfig']         != null ? RabbitConfig.fromJson(asMap(j['rabbitConfig']))        : null,
      wolfConfig:           j['wolfConfig']           != null ? WolfConfig.fromJson(asMap(j['wolfConfig']))            : null,
      sixesConfig:          j['sixesConfig']          != null ? SixesConfig.fromJson(asMap(j['sixesConfig']))           : null,
      stablefordConfig:     j['stablefordConfig']     != null ? StablefordConfig.fromJson(asMap(j['stablefordConfig'])): null,
      presses: j['presses'] != null
          ? ((j['presses'] as List?) ?? []).map((p) {
              try { return PressInstance.fromJson(p is Map ? Map<String, dynamic>.from(p) : {}); }
              catch (_) { return null; }
            }).whereType<PressInstance>().toList()
          : const [],
      // Retrocompat: si no existe 'structure' (rondas viejas) → BetStructure.group.
      structure: BetStructure.values.firstWhere(
          (s) => s.name == (j['structure'] as String? ?? 'group'),
          orElse: () => BetStructure.group),
      betGroupId:    j['betGroupId']    as String?,
      betGroupName:  j['betGroupName']  as String?,
      anchorPlayerId: j['anchorPlayerId'] as String?,
      // playerConfigOverrides: null si no existe la clave (retrocompat).
      playerConfigOverrides: () {
        final raw = j['playerConfigOverrides'];
        if (raw == null) return null;
        final result = <String, Map<String, dynamic>>{};
        try {
          (raw as Map).forEach((k, v) {
            if (k is String && v is Map) {
              result[k] = Map<String, dynamic>.from(v);
            }
          });
        } catch (_) {}
        return result.isEmpty ? null : result;
      }(),
      // pairConfigOverrides: nuevo modelo por duelo.
      pairConfigOverrides: () {
        final raw = j['pairConfigOverrides'];
        if (raw == null) return null;
        final result = <String, Map<String, dynamic>>{};
        try {
          (raw as Map).forEach((k, v) {
            if (k is String && v is Map) {
              result[k] = Map<String, dynamic>.from(v);
            }
          });
        } catch (_) {}
        return result.isEmpty ? null : result;
      }(),
    );
  }

  /// Clona esta apuesta para un duelo concreto, con id propio.
  ///
  /// Conserva TODA la configuración (misma [configSignature]) y solo cambia
  /// participantes, alcance e identificador. Se usa al meter a un jugador
  /// nuevo en una apuesta existente: se le crea un duelo contra cada rival
  /// que ya la juega, con exactamente las mismas condiciones.
  ///
  /// Los overrides por par NO se copian: son excepciones de otros duelos.
  BetModuleInstance copyForPair(String newId, String p1Id, String p2Id) =>
      BetModuleInstance(
        id:                    newId,
        type:                  type,
        name:                  name,
        participantIds:        [p1Id, p2Id],
        scope:                 BetScope.pair(p1Id, p2Id),
        teamHandicapConfig:    teamHandicapConfig,
        sides:                 null,
        status:                status,
        formatMode:            formatMode,
        skinsConfig:           skinsConfig,
        nassauConfig:          nassauConfig,
        nassauLowHighConfig:   nassauLowHighConfig,
        medalConfig:           medalConfig,
        puttsConfig:           puttsConfig,
        oyesesConfig:          oyesesConfig,
        unitsConfig:           unitsConfig,
        snakeConfig:           snakeConfig,
        rabbitConfig:          rabbitConfig,
        wolfConfig:            wolfConfig,
        sixesConfig:           sixesConfig,
        stablefordConfig:      stablefordConfig,
        structure:             structure,
        betGroupId:            betGroupId,
        betGroupName:          betGroupName,
        anchorPlayerId:        anchorPlayerId,
      );

  // ── IDENTIDAD DE LA APUESTA ────────────────────────────────────────────────

  /// Firma de la CONFIGURACIÓN. Dos módulos con la misma firma son "la misma
  /// apuesta" desde el punto de vista del usuario, aunque sean instancias
  /// distintas para pares distintos.
  ///
  /// Sirve para agrupar en la UI: seis duelos con un Nassau de $50/$50/$100
  /// son UNA fila, no seis. Y si uno está a $100, se separa solo.
  ///
  /// Deliberadamente NO incluye [id], [participantIds], [scope], [betGroupId]
  /// ni [pairConfigOverrides]: eso es QUIÉN juega y qué excepciones tiene, no
  /// QUÉ se juega.
  String get configSignature {
    final Map<String, dynamic> cfg = switch (type) {
      BetModuleType.snake          => snake.toJson(),
      BetModuleType.rabbit         => rabbit.toJson(),
      BetModuleType.wolf           => wolf.toJson(),
      BetModuleType.sixes          => sixes.toJson(),
      BetModuleType.stableford     => stableford.toJson(),
      BetModuleType.skins          => skins.toJson(),
      BetModuleType.nassau         => nassau.toJson(),
      BetModuleType.medal          => medal.toJson(),
      BetModuleType.putts          => putts.toJson(),
      BetModuleType.oyeses         => oyeses.toJson(),
      BetModuleType.units          => units.toJson(),
      BetModuleType.nassauLowHigh  => lowHigh.toJson(),
    };
    // Orden estable: el mapa podría iterar distinto entre instancias
    final keys = cfg.keys.toList()..sort();
    final body = keys.map((k) => '$k=${cfg[k]}').join(',');

    // Los duelos por equipos son apuestas distintas entre sí aunque compartan
    // importes: "A vs B" y "C vs D" no se pueden fusionar en una fila.
    final teamPart = hasTeamSides
        ? '|teams:${sides!.map((s) => (s.playerIds.toList()..sort()).join('-')).join('vs')}'
          '|thc:${teamHandicap.toJson()}'
        : '';

    return '${type.name}|${formatMode.name}|$body$teamPart';
  }

  // ── Helpers de overrides ──────────────────────────────────────────────────

  /// Clave canónica para un par de jugadores: IDs ordenados alfabéticamente
  /// separados por "__". Ej: pairKey("CAM","AAM") == "AAM__CAM".
  static String pairKey(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}__${sorted[1]}';
  }

  /// Devuelve el valor de override para el par [pidA]/[pidB], o null si no hay.
  /// Clave dependiente del tipo:
  ///   Skins/Oyeses/Putts/Medal → 'value'    Units → 'allEvents'
  double? overrideForPair(String pidA, String pidB) {
    final ov = pairConfigOverrides?[pairKey(pidA, pidB)];
    if (ov == null) return null;
    switch (type) {
      case BetModuleType.skins:
      case BetModuleType.oyeses:
      case BetModuleType.putts:
      case BetModuleType.medal:
        return (ov['value'] as num?)?.toDouble();
      case BetModuleType.units:
        return (ov['allEvents'] as num?)?.toDouble();
      default:
        return null;
    }
  }

  /// Devuelve el valor de override LEGACY por jugador individual, o null.
  /// Solo se usa para leer datos viejos; las nuevas ediciones usan [overrideForPair].
  double? overrideFor(String playerId) {
    final ov = playerConfigOverrides?[playerId];
    if (ov == null) return null;
    switch (type) {
      case BetModuleType.skins:
      case BetModuleType.oyeses:
        return (ov['value'] as num?)?.toDouble();
      case BetModuleType.units:
        return (ov['allEvents'] as num?)?.toDouble();
      default:
        return null;
    }
  }

  /// Calcula el valor efectivo del duelo entre [pidA] y [pidB].
  ///
  /// Prioridad (de mayor a menor):
  ///  1. [pairConfigOverrides] para el par → valor del par (sin conflicto).
  ///  2. [playerConfigOverrides] legacy → regla mínimo entre ambos jugadores.
  ///  3. Default del grupo.
  ///
  /// Devuelve (valor, hasConflict). Con el nuevo modelo hasConflict=false siempre.
  (double, bool) effectiveValueForDuel(String pidA, String pidB) {
    // 1. Override de pareja (nuevo modelo)
    final pairOv = overrideForPair(pidA, pidB);
    if (pairOv != null) return (pairOv, false);

    // 2. Legacy: overrides por jugador (retrocompat)
    final ovA = overrideFor(pidA);
    final ovB = overrideFor(pidB);
    final base = _baseValue;
    if (ovA == null && ovB == null) return (base, false);
    if (ovA != null && ovB == null) return (ovA, false);
    if (ovA == null && ovB != null) return (ovB, false);
    if (ovA == ovB) return (ovA!, false);
    return (ovA! < ovB! ? ovA : ovB, true); // mínimo legacy + warning
  }

  /// Valor base del módulo según su tipo (sin overrides).
  /// Público para que la UI pueda usarlo como hint/placeholder.
  double get baseValue => switch (type) {
    BetModuleType.skins  => skins.valuePerSkin,
    BetModuleType.oyeses => oyeses.value,
    // Units: valor representativo (uniforme si todos iguales, birdie si heterogéneo).
    BetModuleType.units  => units.representativeValue,
    BetModuleType.putts  => putts.value,
    BetModuleType.medal  => medal.value,
    _                    => value,
  };

  // Alias privado para uso interno (retrocompat de llamadas internas).
  double get _baseValue => baseValue;

  /// Contrario de [baseValue]: copia con el importe base fijado en [v].
  ///
  /// Solo está definido para los tipos con [supportsPlayerOverride]. Nassau y
  /// Match tienen VARIOS importes (front/back/total, match/press), así que "el
  /// importe base" no los describe: devuelve null en vez de mentir escribiendo
  /// uno solo y dejando los otros sin tocar.
  ///
  /// Sirve para saber si dos configuraciones difieren SOLO en el importe:
  /// si `a.withBaseValue(b.baseValue)` tiene la misma [configSignature] que
  /// `b`, entonces el importe era la única diferencia. Eso decide si el caso
  /// se puede expresar con [pairConfigOverrides], que solo lleva el monto.
  BetModuleInstance? withBaseValue(double v) => switch (type) {
        BetModuleType.skins =>
          copyWith(skinsConfig: skins.copyWith(valuePerSkin: v)),
        BetModuleType.oyeses =>
          copyWith(oyesesConfig: oyeses.copyWith(value: v)),
        BetModuleType.putts =>
          copyWith(puttsConfig: putts.copyWith(value: v)),
        BetModuleType.medal =>
          copyWith(medalConfig: medal.copyWith(value: v)),
        BetModuleType.stableford =>
          copyWith(stablefordConfig: stableford.copyWith(value: v)),
        BetModuleType.units =>
          copyWith(unitsConfig: units.withAllEventsValue(v)),
        _ => null,
      };

  /// Clave con la que [pairConfigOverrides] guarda el importe de este tipo.
  /// null si el tipo no admite override por pareja.
  String? get pairOverrideKey => switch (type) {
        BetModuleType.units => 'allEvents',
        BetModuleType.skins ||
        BetModuleType.oyeses ||
        BetModuleType.putts ||
        BetModuleType.medal ||
        BetModuleType.stableford =>
          'value',
        _ => null,
      };

  /// true si este tipo de módulo soporta override de valor por duelo.
  bool get supportsPlayerOverride =>
      type == BetModuleType.skins   ||
      type == BetModuleType.oyeses  ||
      type == BetModuleType.units   ||
      type == BetModuleType.putts   ||
      type == BetModuleType.medal   ||
      type == BetModuleType.stableford;

  // ── Factory helpers para crear instancias por defecto ─────────────────────
  static BetModuleInstance defaultFor(
    BetModuleType type,
    List<String> participantIds, {
    String? id,
    List<BetSide>? sides, // null = modo individual clásico
  }) {
    final uuid = id ?? '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
    return BetModuleInstance(
      id: uuid, type: type, name: type.label,
      participantIds: participantIds,
      sides: sides,
      skinsConfig:          type == BetModuleType.skins         ? SkinsConfig.def          : null,
      nassauConfig:         type == BetModuleType.nassau        ? NassauConfig.def         : null,
      nassauLowHighConfig:  type == BetModuleType.nassauLowHigh ? const NassauLowHighConfig() : null,
      medalConfig:          type == BetModuleType.medal         ? MedalConfig.def          : null,
      puttsConfig:          type == BetModuleType.putts         ? PuttsConfig.def          : null,
      oyesesConfig:         type == BetModuleType.oyeses        ? OyesesConfig.def         : null,
      unitsConfig:          type == BetModuleType.units         ? UnitsConfig.def          : null,
      snakeConfig:          type == BetModuleType.snake         ? SnakeConfig.def          : null,
      rabbitConfig:         type == BetModuleType.rabbit        ? RabbitConfig.def         : null,
      wolfConfig:           type == BetModuleType.wolf          ? WolfConfig.def           : null,
      sixesConfig:          type == BetModuleType.sixes         ? SixesConfig.def          : null,
      stablefordConfig:     type == BetModuleType.stableford    ? StablefordConfig.def     : null,
    );
  }

  // ── expandBetModules ─────────────────────────────────────────────────────────
  /// Expande una configuración de apuesta en uno o varios [BetModuleInstance]
  /// que el engine ya entiende (sin modificar BetEngine).
  ///
  /// Reglas:
  ///  • [group]        → 1 módulo con todos los [participantIds].
  ///  • [headToHead]   → 1 módulo; exige exactamente 2 jugadores.
  ///  • [anchorVsMany] → N módulos 1v1 (anchor vs cada rival).
  ///  • [roundRobin]   → C(n,2) módulos 1v1 (todas las combinaciones).
  ///  • [manual]       → 1 módulo igual que group (sin auto-expansión).
  ///
  /// Todos los módulos generados en anchorVsMany/roundRobin comparten
  /// [betGroupId] y [betGroupName] para identificarlos como familia.
  ///
  /// Lanza [ArgumentError] si no se cumplen las validaciones de cardinalidad.
  static List<BetModuleInstance> expandBetModules({
    required BetModuleType type,
    required BetStructure structure,
    required List<String> participantIds,
    String? anchorPlayerId,
    String? betGroupId,
    String? betGroupName,
    Map<String, Map<String, dynamic>>? playerConfigOverrides,
    Map<String, Map<String, dynamic>>? pairConfigOverrides,
    // Configuración tipada opcional: si null se usan los defaults.
    SkinsConfig?          skinsConfig,
    NassauConfig?         nassauConfig,
    NassauLowHighConfig?  nassauLowHighConfig,
    MedalConfig?          medalConfig,
    PuttsConfig?          puttsConfig,
    OyesesConfig?         oyesesConfig,
    UnitsConfig?          unitsConfig,
    SnakeConfig?          snakeConfig,
    RabbitConfig?         rabbitConfig,
    WolfConfig?           wolfConfig,
    SixesConfig?          sixesConfig,
    StablefordConfig?     stablefordConfig,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;

    // ── Función interna: construye un módulo 1v1 entre dos jugadores ──────────
    BetModuleInstance make1v1(String pA, String pB, int index) {
      final uid = '${type.name}_${structure.name}_${pA}_${pB}_$ts$index';
      return BetModuleInstance(
        id: uid, type: type, name: type.label,
        participantIds: [pA, pB],
        structure:     structure,
        betGroupId:    betGroupId,
        betGroupName:  betGroupName,
        anchorPlayerId: anchorPlayerId,
        playerConfigOverrides: playerConfigOverrides,
        pairConfigOverrides:   pairConfigOverrides,
        skinsConfig:          skinsConfig          ?? (type == BetModuleType.skins         ? SkinsConfig.def          : null),
        nassauConfig:         nassauConfig         ?? (type == BetModuleType.nassau        ? NassauConfig.def         : null),
        nassauLowHighConfig:  nassauLowHighConfig  ?? (type == BetModuleType.nassauLowHigh ? const NassauLowHighConfig() : null),
        medalConfig:          medalConfig          ?? (type == BetModuleType.medal         ? MedalConfig.def          : null),
        puttsConfig:          puttsConfig          ?? (type == BetModuleType.putts         ? PuttsConfig.def          : null),
        oyesesConfig:         oyesesConfig         ?? (type == BetModuleType.oyeses        ? OyesesConfig.def         : null),
        unitsConfig:          unitsConfig          ?? (type == BetModuleType.units         ? UnitsConfig.def          : null),
        snakeConfig:          snakeConfig          ?? (type == BetModuleType.snake         ? SnakeConfig.def          : null),
        rabbitConfig:         rabbitConfig         ?? (type == BetModuleType.rabbit        ? RabbitConfig.def         : null),
        wolfConfig:           wolfConfig           ?? (type == BetModuleType.wolf          ? WolfConfig.def           : null),
        sixesConfig:          sixesConfig          ?? (type == BetModuleType.sixes         ? SixesConfig.def          : null),
        stablefordConfig:     stablefordConfig     ?? (type == BetModuleType.stableford    ? StablefordConfig.def     : null),
      );
    }

    // ── Función interna: construye un módulo grupal ───────────────────────────
    BetModuleInstance makeGroup(List<String> pids) {
      final uid = '${type.name}_${structure.name}_$ts';
      return BetModuleInstance(
        id: uid, type: type, name: type.label,
        participantIds: pids,
        structure:     structure,
        betGroupId:    betGroupId,
        betGroupName:  betGroupName,
        skinsConfig:          skinsConfig          ?? (type == BetModuleType.skins         ? SkinsConfig.def          : null),
        nassauConfig:         nassauConfig         ?? (type == BetModuleType.nassau        ? NassauConfig.def         : null),
        nassauLowHighConfig:  nassauLowHighConfig  ?? (type == BetModuleType.nassauLowHigh ? const NassauLowHighConfig() : null),
        medalConfig:          medalConfig          ?? (type == BetModuleType.medal         ? MedalConfig.def          : null),
        puttsConfig:          puttsConfig          ?? (type == BetModuleType.putts         ? PuttsConfig.def          : null),
        oyesesConfig:         oyesesConfig         ?? (type == BetModuleType.oyeses        ? OyesesConfig.def         : null),
        unitsConfig:          unitsConfig          ?? (type == BetModuleType.units         ? UnitsConfig.def          : null),
        snakeConfig:          snakeConfig          ?? (type == BetModuleType.snake         ? SnakeConfig.def          : null),
        rabbitConfig:         rabbitConfig         ?? (type == BetModuleType.rabbit        ? RabbitConfig.def         : null),
        wolfConfig:           wolfConfig           ?? (type == BetModuleType.wolf          ? WolfConfig.def           : null),
        sixesConfig:          sixesConfig          ?? (type == BetModuleType.sixes         ? SixesConfig.def          : null),
        stablefordConfig:     stablefordConfig     ?? (type == BetModuleType.stableford    ? StablefordConfig.def     : null),
      );
    }

    switch (structure) {
      // ── group / manual: un único módulo con todos los participantes ─────────
      case BetStructure.group:
      case BetStructure.manual:
        if (participantIds.length < 2) {
          throw ArgumentError('group requiere mínimo 2 jugadores.');
        }
        return [makeGroup(participantIds)];

      // ── headToHead: exactamente 2 jugadores ─────────────────────────────────
      case BetStructure.headToHead:
        if (participantIds.length != 2) {
          throw ArgumentError('headToHead requiere exactamente 2 jugadores.');
        }
        return [makeGroup(participantIds)];

      // ── anchorVsMany: jugador ancla vs cada rival (N módulos 1v1) ───────────
      case BetStructure.anchorVsMany:
        if (anchorPlayerId == null) {
          throw ArgumentError('anchorVsMany requiere anchorPlayerId.');
        }
        final rivals = participantIds.where((id) => id != anchorPlayerId).toList();
        if (rivals.isEmpty) {
          throw ArgumentError('anchorVsMany requiere al menos 1 rival.');
        }
        return rivals
            .asMap()
            .entries
            .map((e) => make1v1(anchorPlayerId, e.value, e.key))
            .toList();

      // ── roundRobin: todas las combinaciones C(n,2) ──────────────────────────
      case BetStructure.roundRobin:
        if (participantIds.length < 3) {
          throw ArgumentError('roundRobin requiere mínimo 3 jugadores.');
        }
        final result = <BetModuleInstance>[];
        int idx = 0;
        for (int i = 0; i < participantIds.length; i++) {
          for (int k = i + 1; k < participantIds.length; k++) {
            result.add(make1v1(participantIds[i], participantIds[k], idx++));
          }
        }
        return result;
    }
  }

  // ── Helpers de participantes ───────────────────────────────────────────────

  /// Participantes efectivos del módulo dentro de [groupPlayerIds].
  ///
  /// Regla canónica: si el módulo tiene participantIds propios no vacíos,
  /// úsalos; de lo contrario todos los jugadores del grupo participan.
  ///
  /// Esta es la única implementación de esta lógica — todos los engines
  /// y pantallas deben llamar a este método, nunca re-derivarlo.
  List<String> effectivePids(List<String> groupPlayerIds) =>
      resolveParticipants(groupPlayerIds);

  /// Devuelve true si el módulo involucra a ambos jugadores [p1Id] y [p2Id].
  ///
  /// Cuando participantIds está vacío, el módulo aplica a todos los jugadores
  /// del grupo; el caller debe verificar que p1Id y p2Id pertenezcan al grupo.
  bool containsPair(String p1Id, String p2Id) {
    if (effectiveScope.isEveryone) return true; // aplica a todos los presentes
    if (participantIds.isEmpty) return true;
    return participantIds.contains(p1Id) && participantIds.contains(p2Id);
  }

  /// Config de handicap de equipo efectiva. Los módulos guardados antes de
  /// que existiera esta opción se comportan como hasta ahora: 100% por jugador.
  TeamHandicapConfig get teamHandicap =>
      teamHandicapConfig ?? TeamHandicapConfig.legacy;

  // ── ALCANCE ────────────────────────────────────────────────────────────────

  /// Alcance efectivo del módulo.
  ///
  /// Si [scope] es null (módulo legacy) se infiere sin cambiar el
  /// comportamiento previo:
  ///   • con `sides` válidos            → teams
  ///   • participantIds vacío           → everyone (equivalía a "todo el grupo")
  ///   • participantIds con 2 jugadores → pair
  ///   • resto                          → subset
  BetScope get effectiveScope {
    final s = scope;
    if (s != null) return s;
    if (hasTeamSides) return const BetScope.teams();
    if (participantIds.isEmpty) return const BetScope.everyone();
    if (participantIds.length == 2) {
      return BetScope.pair(participantIds[0], participantIds[1]);
    }
    return BetScope.subset(participantIds);
  }

  /// Resuelve los participantes reales contra los jugadores actuales.
  ///
  /// [groupPlayerIds] son los jugadores presentes del grupo/partida en ESTE
  /// momento. Con alcance [BetScopeKind.everyone] el resultado cambia sola
  /// cuando entra o sale un jugador — ése es justo el objetivo.
  ///
  /// Los alcances fijos (subset/pair) se filtran contra [groupPlayerIds] para
  /// no arrastrar jugadores que ya no están en la ronda; si el filtro dejara
  /// menos de 2 jugadores se devuelve la lista sin filtrar, para no romper
  /// rondas cuyo grupo no tenga bien poblado playerIds.
  List<String> resolveParticipants(List<String> groupPlayerIds) {
    final sc = effectiveScope;
    switch (sc.kind) {
      case BetScopeKind.everyone:
        return groupPlayerIds;
      case BetScopeKind.teams:
        return allSidePlayerIds;
      case BetScopeKind.subset:
      case BetScopeKind.pair:
        final ids = sc.playerIds.isNotEmpty ? sc.playerIds : participantIds;
        if (groupPlayerIds.isEmpty) return ids;
        final present = ids.where(groupPlayerIds.contains).toList();
        return present.length >= 2 ? present : ids;
    }
  }
}

// ── BetGroup — partida (grupo de jugadores + instancias de módulos) ───────────
class BetGroup {
  final String id;
  final String name;
  final PartidaFormat format;
  final List<String> playerIds;
  final List<BetModuleInstance> modules;

  /// El grupo de apuesta GUARDADO del que salió esta partida, si salió de uno.
  ///
  /// Faltaba, y sin esto un torneo no puede decir "todas las rondas de Viernes
  /// CGM": el id de esta partida es un uuid nuevo por ronda, así que no había
  /// forma de volver del historial al grupo. Se comparaba por nombre en el mejor
  /// de los casos, y un renombrado habría partido el torneo en dos.
  ///
  /// Aditivo y opcional: null significa "esta partida se armó a mano".
  final String? savedGroupId;

  const BetGroup({
    required this.id, required this.name,
    required this.format, required this.playerIds, required this.modules,
    this.savedGroupId,
  });

  BetGroup copyWith({List<BetModuleInstance>? modules, List<String>? playerIds}) => BetGroup(
    id: id, name: name, format: format,
    playerIds: playerIds ?? this.playerIds,
    modules: modules ?? this.modules,
    savedGroupId: savedGroupId,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'format': format.name,
    'playerIds': playerIds,
    if (savedGroupId != null) 'savedGroupId': savedGroupId,
    'modules': modules.map((m) => m.toJson()).toList(),
  };
  factory BetGroup.fromJson(Map<String, dynamic> j) {
    final rawPids = j['playerIds'];
    final pids = rawPids is List ? List<String>.from(rawPids) : <String>[];
    return BetGroup(
      id: (j['id'] as String?) ?? '',
      name: (j['name'] as String?) ?? 'Partida',
      format: PartidaFormat.values.firstWhere((f) => f.name == j['format'],
          orElse: () => PartidaFormat.allInOnePot),
      playerIds: pids,
      savedGroupId: j['savedGroupId'] as String?,
      modules: (j['modules'] is List ? (j['modules'] as List) : []).map((m) {
        final map = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
        // Detectar si es formato legacy (BetModule antiguo) o nuevo (BetModuleInstance)
        try {
          if (map.containsKey('skinsConfig') || map.containsKey('nassauConfig') ||
              map.containsKey('medalConfig') || map.containsKey('puttsConfig') ||
              map.containsKey('oyesesConfig') || map.containsKey('unitsConfig') ||
              map.containsKey('snakeConfig') || map.containsKey('rabbitConfig') || map.containsKey('wolfConfig') || map.containsKey('sixesConfig') || map.containsKey('stablefordConfig') ||
              map.containsKey('participantIds')) {
            return BetModuleInstance.fromJson(map);
          } else {
            // Migrar formato legacy
            return _migrateLegacyModule(map, pids);
          }
        } catch (_) {
          return null;
        }
      }).whereType<BetModuleInstance>().toList(),
    );
  }

  // Migración de BetModule antiguo → BetModuleInstance
  static BetModuleInstance _migrateLegacyModule(Map<String, dynamic> j, List<String> playerIds) {
    final type = BetModuleType.values.firstWhere(
      (t) => t.name == j['type'], orElse: () => BetModuleType.skins);
    final value = (j['value'] as num?)?.toDouble() ?? 100;
    final carryOver = j['carryOver'] as bool? ?? false;
    final useHandicap = j['useHandicap'] as bool? ?? true;
    final pressEnabled = j['pressEnabled'] as bool? ?? false;
    final pressTrigger = j['pressTrigger'] as int? ?? 2;
    final extra = (j['extra'] as Map<String, dynamic>?) ?? {};
    final mode = useHandicap ? GrossNetMode.net : GrossNetMode.gross;
    final id = '${type.name}_migrated_${DateTime.now().millisecondsSinceEpoch}';

    return BetModuleInstance(
      id: id, type: type, name: type.label, participantIds: playerIds,
      skinsConfig: type == BetModuleType.skins ? SkinsConfig(
        valuePerSkin: value, mode: mode, carryOver: carryOver,
      ) : null,
      nassauConfig: type == BetModuleType.nassau ? NassauConfig(
        frontValue: (extra['frontValue'] as num?)?.toDouble() ?? value,
        backValue:  (extra['backValue']  as num?)?.toDouble() ?? value,
        totalValue: (extra['totalValue'] as num?)?.toDouble() ?? value * 2,
        mode: mode, pressEnabled: pressEnabled, autoPressTrigger: pressTrigger,
      ) : null,
      medalConfig: type == BetModuleType.medal ? MedalConfig(value: value, mode: mode) : null,
      puttsConfig: type == BetModuleType.putts ? PuttsConfig(value: value) : null,
      oyesesConfig: type == BetModuleType.oyeses ? OyesesConfig(value: value) : null,
      unitsConfig: type == BetModuleType.units ? UnitsConfig.def : null,
      snakeConfig: type == BetModuleType.snake ? SnakeConfig.def : null,
      rabbitConfig: type == BetModuleType.rabbit ? RabbitConfig.def : null,
      wolfConfig: type == BetModuleType.wolf ? WolfConfig.def : null,
      sixesConfig: type == BetModuleType.sixes ? SixesConfig.def : null,
      stablefordConfig: type == BetModuleType.stableford ? StablefordConfig.def : null,
    );
  }
}

// ── LedgerEntry ───────────────────────────────────────────────────────────────
class LedgerEntry {
  final String fromPlayerId;
  final String toPlayerId;
  final double amount;
  final BetModuleType betType;
  final String reason;
  final int? hole;

  const LedgerEntry({
    required this.fromPlayerId, required this.toPlayerId,
    required this.amount, required this.betType,
    required this.reason, this.hole,
  });
}

// ── NetDebt ───────────────────────────────────────────────────────────────────
class NetDebt {
  final String fromPlayerId;
  final String toPlayerId;
  final double amount;
  const NetDebt({required this.fromPlayerId, required this.toPlayerId, required this.amount});
}

// ── PlayerLink — relación usuario↔jugador en Firestore ───────────────────────
// Vive en users/{uid}/playerLinks/{playerId}
// Guarda favoritos, apodo personal, sliding recurrente y notas.
class PlayerLink {
  final String playerId;
  final bool isFavorite;
  final String? customDisplayName;   // apodo local del usuario
  final double defaultSlidingAdjustment; // >0 = el dueño RECIBE strokes del compañero; <0 = el dueño DA strokes al compañero
  final double? defaultHandicapOverride; // HCP fijo si el usuario quiere sobrescribir
  final String? notes;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PlayerLink({
    required this.playerId,
    this.isFavorite = false,
    this.customDisplayName,
    this.defaultSlidingAdjustment = 0,
    this.defaultHandicapOverride,
    this.notes,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  PlayerLink copyWith({
    bool? isFavorite,
    String? customDisplayName,
    double? defaultSlidingAdjustment,
    double? defaultHandicapOverride,
    String? notes,
    int? sortOrder,
  }) => PlayerLink(
    playerId: playerId,
    isFavorite: isFavorite ?? this.isFavorite,
    customDisplayName: customDisplayName ?? this.customDisplayName,
    defaultSlidingAdjustment: defaultSlidingAdjustment ?? this.defaultSlidingAdjustment,
    defaultHandicapOverride: defaultHandicapOverride ?? this.defaultHandicapOverride,
    notes: notes ?? this.notes,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toFirestore() => {
    'playerId':                   playerId,
    'isFavorite':                 isFavorite,
    if (customDisplayName != null) 'customDisplayName': customDisplayName,
    'defaultSlidingAdjustment':   defaultSlidingAdjustment,
    if (defaultHandicapOverride != null) 'defaultHandicapOverride': defaultHandicapOverride,
    if (notes != null) 'notes':   notes,
    'sortOrder':                  sortOrder,
    'createdAt':                  createdAt.toIso8601String(),
    'updatedAt':                  updatedAt.toIso8601String(),
  };

  factory PlayerLink.fromFirestore(Map<String, dynamic> d, String id) => PlayerLink(
    playerId:                 id,
    isFavorite:               d['isFavorite'] as bool? ?? false,
    customDisplayName:        d['customDisplayName'] as String?,
    defaultSlidingAdjustment: (d['defaultSlidingAdjustment'] as num?)?.toDouble() ?? 0,
    defaultHandicapOverride:  (d['defaultHandicapOverride'] as num?)?.toDouble(),
    notes:                    d['notes'] as String?,
    sortOrder:                (d['sortOrder'] as int?) ?? 0,
    createdAt: _parseDate(d['createdAt']),
    updatedAt: _parseDate(d['updatedAt']),
  );

  /// Nombre a mostrar: usa customDisplayName si está, sino el del Player global.
  String displayName(String fallback) => customDisplayName?.isNotEmpty == true
      ? customDisplayName!
      : fallback;
}

/// Claves [BetModuleInstance.pairKey] de jugadores que son COMPAÑEROS en alguna
/// apuesta por equipos de la ronda.
///
/// Pintarlos como duelo es ruido: sugiere un enfrentamiento que no existe, y el
/// marcador que se les muestra es de match play individual, sin relación con
/// cómo se calculó la apuesta que sí juegan juntos.
///
/// Vive aquí y no en una pantalla porque la consumen DOS vistas —la pestaña 1v1
/// de la Tarjeta y la de Duelos en Apuestas— que construyen sus pares por
/// caminos distintos. Con la regla duplicada, arreglar una dejaba la otra
/// mostrando compañeros como rivales; que es justo como se descubrió.
Set<String> companerosDeLado(Round round) {
  final result = <String>{};
  for (final g in round.betGroups) {
    for (final m in g.modules) {
      if (!m.hasTeamSides) continue;
      for (final side in m.sides!) {
        for (var i = 0; i < side.playerIds.length; i++) {
          for (var k = i + 1; k < side.playerIds.length; k++) {
            result.add(
                BetModuleInstance.pairKey(side.playerIds[i], side.playerIds[k]));
          }
        }
      }
    }
  }
  return result;
}

/// true si la ronda tiene alguna apuesta con alcance de equipos.
///
/// Sirve de interruptor: los cruces 1v1 solo se filtran cuando hay un duelo por
/// equipos que los vuelve engañosos. Una ronda sin equipos —incluida una sin
/// apuestas— se comporta como siempre.
bool tieneApuestaPorEquipos(Round round) {
  for (final g in round.betGroups) {
    for (final m in g.modules) {
      if (m.effectiveScope.kind == BetScopeKind.teams) return true;
    }
  }
  return false;
}

/// true si [p1Id] y [p2Id] comparten alguna apuesta que NO sea por equipos.
///
/// Decide si tiene sentido dibujar su cruce 1v1. Sin esto, la pestaña pintaba
/// un marcador de match play entre dos jugadores que solo compartían una
/// apuesta por equipos: un resultado que nadie pactó, calculado porque se
/// puede. El importe sí era real —sale del reparto por cruces— pero el
/// marcador de hoyos no correspondía a nada.
///
/// La condición va por ALCANCE y no por tipo de apuesta a propósito. Una lista
/// de tipos ("si hay match play o skins") se queda corta: alguien puede pactar
/// un duelo suelto con oyeses o units, y habría que mantener la lista cada vez
/// que se añada un tipo nuevo.
bool tieneApuestaIndividual(Round round, String p1Id, String p2Id) {
  for (final g in round.betGroups) {
    // containsPair da por buenos los alcances abiertos, así que el caller debe
    // confirmar que ambos jugadores estén en la partida.
    if (!g.playerIds.contains(p1Id) || !g.playerIds.contains(p2Id)) continue;
    for (final m in g.modules) {
      if (m.effectiveScope.kind == BetScopeKind.teams) continue;
      if (m.containsPair(p1Id, p2Id)) return true;
    }
  }
  return false;
}

// ── PairAgreement ─────────────────────────────────────────────────────────────
//
// Lo que dos jugadores apuestan habitualmente entre ellos. Existe para que
// configurar una ronda deje de ser construir desde cero y pase a ser revisar:
// al entrar los jugadores, sus acuerdos se instancian solos.
//
// Se indexa por [BetModuleInstance.pairKey], que ordena los dos ids, de modo
// que Oscar↔Rafa y Rafa↔Oscar son el mismo acuerdo y no puede haber dos
// versiones divergentes del mismo trato.
//
// Vive DENTRO de un [GamePreset], no en una colección global: los mismos
// jugadores pueden apostar distinto en el juego de los martes que en el de los
// viernes, así que el juego es parte de la identidad del acuerdo. Sin él,
// "Yo↔Oscar" es ambiguo.
//
// Tampoco cabía en [PlayerLink], que está indexado por UN jugador y solo puede
// expresar "yo ↔ esa persona": no tiene dónde poner el acuerdo entre Oscar y
// Rafa, que es justo el caso que hay que soportar.
//
// La ventaja (sliding) queda deliberadamente FUERA. Ya tiene su propio camino
// —PlayerLink.defaultSlidingAdjustment y SlidingAdjustmentEngine— y meter una
// segunda fuente de verdad para lo mismo solo generaría discrepancias.
class PairAgreement {
  /// Los dos jugadores, siempre en orden lexicográfico ([p1Id] < [p2Id]).
  ///
  /// Se guardan explícitos en vez de derivarlos de la clave a propósito. En el
  /// modelo conviven TRES convenciones de clave de par con separadores
  /// distintos —'|' en carryByPair y pairSliding, '__' en pairConfigOverrides—
  /// así que descomponer una clave compuesta obliga a acertar el separador y
  /// falla en silencio si cambia. Con los ids guardados no hay nada que parsear.
  final String p1Id;
  final String p2Id;

  /// Apuestas del par, como plantillas: cuenta el tipo y la config tipada.
  /// `participantIds` y `scope` son irrelevantes aquí porque [instantiateFor]
  /// los sobrescribe vía [BetModuleInstance.copyForPair].
  final List<BetModuleInstance> templates;

  final DateTime createdAt;
  final DateTime updatedAt;

  const PairAgreement._({
    required this.p1Id,
    required this.p2Id,
    required this.templates,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Crea el acuerdo ordenando los ids, de modo que (a,b) y (b,a) produzcan
  /// exactamente el mismo objeto y la misma [pairKey].
  factory PairAgreement.forPair({
    required String playerAId,
    required String playerBId,
    required List<BetModuleInstance> templates,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final sorted = [playerAId, playerBId]..sort();
    final now = updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return PairAgreement._(
      p1Id: sorted[0],
      p2Id: sorted[1],
      templates: templates,
      createdAt: createdAt ?? now,
      updatedAt: now,
    );
  }

  /// Clave canónica, y también el id del documento en Firestore.
  String get pairKey => BetModuleInstance.pairKey(p1Id, p2Id);

  bool get isEmpty => templates.isEmpty;

  /// true si el acuerdo es entre estos dos jugadores, en cualquier orden.
  bool isBetween(String a, String b) =>
      (p1Id == a && p2Id == b) || (p1Id == b && p2Id == a);

  /// Instancia las plantillas como duelos reales entre los dos jugadores.
  /// [newId] genera un id distinto por módulo (normalmente Uuid().v4).
  List<BetModuleInstance> instantiate(String Function() newId) =>
      templates.map((t) => t.copyForPair(newId(), p1Id, p2Id)).toList();

  PairAgreement copyWith({List<BetModuleInstance>? templates}) =>
      PairAgreement._(
        p1Id: p1Id,
        p2Id: p2Id,
        templates: templates ?? this.templates,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toFirestore() => {
        'p1Id': p1Id,
        'p2Id': p2Id,
        'templates': templates.map((t) => t.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Devuelve null si el documento no identifica a dos jugadores distintos:
  /// un acuerdo sin par no se puede aplicar a nada.
  static PairAgreement? fromFirestore(Map<String, dynamic> d, String id) {
    final a = (d['p1Id'] as String?) ?? '';
    final b = (d['p2Id'] as String?) ?? '';
    if (a.isEmpty || b.isEmpty || a == b) return null;

    // Una plantilla ilegible se descarta sin tumbar el acuerdo completo: un
    // acuerdo a medias sigue siendo útil, perderlo entero no.
    final raw = (d['templates'] as List?) ?? const [];
    final parsed = <BetModuleInstance>[];
    for (final t in raw) {
      if (t is! Map) continue;
      try {
        parsed.add(BetModuleInstance.fromJson(Map<String, dynamic>.from(t)));
      } catch (_) {
        continue;
      }
    }

    return PairAgreement.forPair(
      playerAId: a,
      playerBId: b,
      templates: parsed,
      createdAt: _parseDate(d['createdAt']),
      updatedAt: _parseDate(d['updatedAt']),
    );
  }
}

// ── SlidingRelation ───────────────────────────────────────────────────────────
class SlidingRelation {
  final String playerAId;
  final String playerBId;
  double adjustment;
  SlidingRelation({required this.playerAId, required this.playerBId, this.adjustment = 0});

  Map<String, dynamic> toJson() => {'playerAId': playerAId, 'playerBId': playerBId, 'adjustment': adjustment};
  factory SlidingRelation.fromJson(Map<String, dynamic> j) => SlidingRelation(
    playerAId:  (j['playerAId'] as String?) ?? '',
    playerBId:  (j['playerBId'] as String?) ?? '',
    adjustment: (j['adjustment'] as num?)?.toDouble() ?? 0.0,
  );
}

// ── BetChangeProposal — cambio colaborativo de apuesta pendiente de aprobación ──
//
// Flujo:
//   1. participante propone cambio → status = pending
//   2. la otra parte ve banner "cambio pendiente" con Accept/Reject
//   3. Accept → status = approved → RoundProvider aplica el cambio al BetModuleInstance
//      Reject → status = rejected → se descarta
//   4. Owner puede aplicar directamente (sin aprobación) → status = approved inmediatamente
//
// El campo [payload] es un mapa plano serializable con el delta de configuración.
// Ejemplos:
//   Cambio de monto Nassau: {'nassauFront': 25.0, 'nassauBack': 25.0, 'nassauTotal': 50.0}
//   Cambio de ventaja:      {'manualStrokes': 2.0, 'p1ReceivesFrom': 'pB_id'}
//   Cambio de modo:         {'mode': 'gross'}
// ─────────────────────────────────────────────────────────────────────────────

enum BetProposalStatus { pending, approved, rejected, disputed }

class BetChangeProposal {
  final String id;
  /// Grupo y módulo al que aplica. null moduleId = propuesta de ventaja del duelo.
  final String groupId;
  final String? moduleId;
  /// Par de jugadores del duelo.
  final String p1Id;
  final String p2Id;
  /// UID del usuario que hizo la propuesta.
  final String proposedByUid;
  /// ID del jugador del proponente (para mostrar nombre).
  final String proposedByPlayerId;
  /// El cambio propuesto como mapa serializable.
  final Map<String, dynamic> payload;
  /// Tipo de cambio: 'amount', 'handicap', 'mode', 'rules'.
  final String changeType;
  /// Estado actual de la propuesta.
  final BetProposalStatus status;
  /// UID que aprobó/rechazó (null si pendiente).
  final String? resolvedByUid;
  /// Timestamp ISO de creación.
  final String createdAt;
  /// UIDs que ya han aprobado (para mayoría o unanimidad).
  final List<String> approvedByUids;

  const BetChangeProposal({
    required this.id,
    required this.groupId,
    this.moduleId,
    required this.p1Id,
    required this.p2Id,
    required this.proposedByUid,
    required this.proposedByPlayerId,
    required this.payload,
    required this.changeType,
    this.status = BetProposalStatus.pending,
    this.resolvedByUid,
    required this.createdAt,
    this.approvedByUids = const [],
  });

  bool get isPending  => status == BetProposalStatus.pending;
  bool get isApproved => status == BetProposalStatus.approved;
  bool get isRejected => status == BetProposalStatus.rejected;

  BetChangeProposal copyWith({
    BetProposalStatus? status,
    String? resolvedByUid,
    List<String>? approvedByUids,
  }) => BetChangeProposal(
    id: id, groupId: groupId, moduleId: moduleId,
    p1Id: p1Id, p2Id: p2Id,
    proposedByUid: proposedByUid, proposedByPlayerId: proposedByPlayerId,
    payload: payload, changeType: changeType,
    status: status ?? this.status,
    resolvedByUid: resolvedByUid ?? this.resolvedByUid,
    createdAt: createdAt,
    approvedByUids: approvedByUids ?? this.approvedByUids,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    if (moduleId != null) 'moduleId': moduleId,
    'p1Id': p1Id,
    'p2Id': p2Id,
    'proposedByUid': proposedByUid,
    'proposedByPlayerId': proposedByPlayerId,
    'payload': payload,
    'changeType': changeType,
    'status': status.name,
    if (resolvedByUid != null) 'resolvedByUid': resolvedByUid,
    'createdAt': createdAt,
    'approvedByUids': approvedByUids,
  };

  factory BetChangeProposal.fromJson(Map<String, dynamic> j) => BetChangeProposal(
    id:                   (j['id'] as String?) ?? '',
    groupId:              (j['groupId'] as String?) ?? '',
    moduleId:             j['moduleId'] as String?,
    p1Id:                 (j['p1Id'] as String?) ?? '',
    p2Id:                 (j['p2Id'] as String?) ?? '',
    proposedByUid:        (j['proposedByUid'] as String?) ?? '',
    proposedByPlayerId:   (j['proposedByPlayerId'] as String?) ?? '',
    payload:              (j['payload'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? {},
    changeType:           (j['changeType'] as String?) ?? 'amount',
    status: BetProposalStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => BetProposalStatus.pending,
    ),
    resolvedByUid:    j['resolvedByUid'] as String?,
    createdAt:        (j['createdAt'] as String?) ?? '',
    approvedByUids:   (j['approvedByUids'] as List?)?.map((e) => e.toString()).toList() ?? [],
  );
}

// ── Round ─────────────────────────────────────────────────────────────────────
class Round {
  final String id;
  final String name;
  final CourseInfo course;
  final List<Player> players;
  final List<RoundPlayer> roundPlayers;
  final List<BetGroup> betGroups;
  final Map<String, Map<int, HoleScore>> scores;
  final Map<String, Map<int, List<HoleEvent>>> events;
  final Map<int, OyeseRanking> oyeseRankings;

  /// Para qué torneos cuenta esta ronda.
  ///
  /// La marca se pone AL CONFIGURAR la ronda, no después. Es lo que sustituye a
  /// la fuente por fechas: un rango arrastra todo lo que cae dentro —Copa CGM
  /// 2026 salió con 79 rondas y 55 personas— mientras que una marca explícita
  /// cuenta lo que se dijo que cuenta.
  ///
  /// Aditivo y vacío por defecto: las rondas jugadas antes de que existiera la
  /// marca no cuentan para ningún torneo por esta vía, y para armar un torneo
  /// sobre el histórico está la fuente "elegidas a mano".
  final List<String> torneoIds;

  /// Con quién jugó el Wolf en cada hoyo.
  ///
  /// ADITIVO y con default vacío a propósito: hacerlo obligatorio habría roto
  /// cada sitio que construye una Round —fixtures incluidos— sin que ninguno de
  /// ellos tenga nada que decir sobre Wolf.
  ///
  /// La AUSENCIA de un hoyo en el mapa significa "nadie eligió compañero", y
  /// ese hoyo no liquida. Dentro del mapa, partnerId nulo significa Lone Wolf.
  /// Son dos cosas distintas y el modelo las distingue.
  final Map<int, WolfCall> wolfCalls;
  final List<SlidingRelation> sliding;
  final DateTime createdAt;
  final int currentHole;
  final bool isFinished;

  // ── pairSliding: fuente canónica de acuerdos bilaterales ─────────────────────
  // Clave: '$lowId|$highId'  (IDs ordenados lexicográficamente, separados por '|')
  // Valor: cuántos strokes recibe el jugador con ID menor (lowId) del jugador con
  //        ID mayor (highId).
  //   +5 → lowId recibe 5 de highId   (highId da 5 a lowId)
  //   -5 → lowId da 5 a highId         (highId recibe 5 de lowId)
  //
  // Para consultar recv(A, B): usar BetEngine.canonicalSlidingBetween(round, A, B).
  // Este campo reemplaza progresivamente a manualHandicaps (que queda como
  // compatibilidad legacy). El engine prioriza pairSliding cuando existe.
  final Map<String, double> pairSliding;

  /// Si esta ronda ALIMENTA el historial de sliding del grupo al cerrarse.
  ///
  /// Decide si la ronda cuenta, no si los números se ven: la ventaja acumulada
  /// está siempre visible y siempre editable en Setup. Apagado permite jugar
  /// con sliding sin que la ronda altere el acumulado —útil cuando falta gente
  /// o es una ronda suelta—, caso que antes no se podía expresar.
  ///
  /// Default true: las rondas guardadas antes de que existiera el campo se
  /// comportan como siempre.
  final bool slidingRecalcula;

  /// Vuelta de inicio: determina qué mitad lleva el stroke extra (diff impar).
  final StartingNine startingNine;
  /// Total de hoyos de la ronda: 9 o 18 (por defecto 18).
  final int totalHoles;
  /// true = ronda en vivo compartida (todos los jugadores ven/editan en tiempo real)
  final bool isLive;
  /// UID del usuario que creó/organiza la ronda en vivo
  final String? ownerUid;
  /// Código de 6 chars para identificar la ronda (ej: "GOLF42")
  final String? liveCode;
  /// Modo de captura: 'admin' = solo admin captura; 'open' = todos capturan
  final String scoringMode;
  /// true si solo el admin puede capturar scores
  bool get isAdminScoring => scoringMode == 'admin';

  /// Propuestas de cambio colaborativo de apuestas pendientes de aprobación.
  /// Solo se persisten en rondas en vivo (liveRounds Firestore).
  final List<BetChangeProposal> pendingProposals;

  /// Quién fue el ÚLTIMO en pasar el umbral de putts, por hoyo.
  ///
  /// ── Por qué hace falta un dato nuevo ──────────────────────────────────────
  ///
  /// «La serpiente es del último en la secuencia del hoyo.» Y eso no se podía
  /// saber: la app registra QUIÉN hizo tres putts, no en qué orden.
  ///
  /// Sin el orden, dos jugadores que pasan el umbral en el mismo hoyo son un
  /// empate de verdad, y el motor tenía que elegir entre dos respuestas
  /// defendibles. Con el orden, el empate desaparece: siempre hay un último.
  ///
  /// ── Y por qué un mapa por HOYO y no una lista de secuencia ───────────────
  ///
  /// Guardar el orden completo de putts de cada hoyo sería un dato mucho mayor
  /// para responder una pregunta mucho más pequeña, y habría que capturarlo
  /// siempre. Esto solo guarda la respuesta a la única pregunta que importa —
  /// quién fue el último de los que pasaron el umbral— y solo en los hoyos
  /// donde hubo más de uno.
  ///
  /// Vacío es lo normal: la mayoría de los hoyos no tienen ni un 3-putt.
  final Map<int, String> ultimoEnPasarElUmbral;

  /// El equipo que lleva la tarjeta de esta ronda, si es una ronda de equipo.
  ///
  /// ── Por qué un campo y no derivarlo de las apuestas ──────────────────────
  ///
  /// `scoringPlayers` deduce quién anota de los LADOS de las apuestas, y
  /// funciona: en scramble el portador es el virtual del equipo. Pero una ronda
  /// de shotgun por equipos NO TIENE APUESTAS —el organizador no pacta por
  /// ochenta y ocho personas— así que no hay lado del que deducir nada, y los
  /// cuatro acabarían con su tarjeta propia.
  ///
  /// Inventar un módulo de apuestas vacío para que la deducción funcione sería
  /// meter una apuesta que nadie pidió con el único fin de que un cálculo
  /// interno saliera. La ronda lo DICE, que es más corto y más cierto.
  ///
  /// Null en todo lo demás, y ahí nada cambia.
  final String? equipoId;

  /// Los scores que el organizador corrigió, con quién y cuándo.
  ///
  /// Va EN LA RONDA y no en una colección aparte porque es de la ronda: quien
  /// pueda leerla ve sus correcciones, y quien no, no. Un registro en otro
  /// sitio necesitaría sus propias reglas para decir exactamente eso.
  final List<CorreccionDeScore> correcciones;

  Round({
    required this.id, required this.name, required this.course,
    required this.players, required this.roundPlayers,
    required this.betGroups, required this.scores,
    required this.events, required this.oyeseRankings,
    this.wolfCalls = const {},
    this.torneoIds = const [],
    required this.sliding, required this.createdAt,
    this.currentHole = 1, this.isFinished = false,
    this.startingNine = StartingNine.front,
    this.totalHoles = 18,
    this.isLive = false,
    this.ownerUid,
    this.liveCode,
    this.scoringMode = 'open',
    Map<String, double>? pairSliding,
    this.slidingRecalcula = true,
    List<BetChangeProposal>? pendingProposals,
    this.correcciones = const [],
    this.equipoId,
    this.ultimoEnPasarElUmbral = const {},
  }) : pairSliding = pairSliding ?? const {},
       pendingProposals = pendingProposals ?? const [];

  HoleScore getScore(String playerId, int hole) =>
      scores[playerId]?[hole] ?? HoleScore(playerId: playerId, hole: hole);

  List<HoleEvent> getEvents(String playerId, int hole) =>
      events[playerId]?[hole] ?? [];

  OyeseRanking? getOyese(int hole) => oyeseRankings[hole];

  /// Con quién jugó el Wolf en [hole]. Null = nadie lo eligió todavía.
  WolfCall? getWolfCall(int hole) => wolfCalls[hole];

  /// Quién debe ANOTAR en esta ronda.
  ///
  /// No es `players`: en una ronda por equipos hay jugadores que aparecen para
  /// que se les pueda nombrar pero que no llevan tarjeta. Y sobre todo NO es
  /// `players.where((p) => scores.containsKey(p.id))`, que es lo que había
  /// copiado en 19 sitios: ese predicado pasa a cualquiera que tenga
  /// CONTENEDOR de scores, aunque esté vacío.
  ///
  /// Setup siembra un contenedor por jugador de la ronda, así que en cuanto
  /// alguien tiene contenedor sin llegar a anotar nunca —el virtual de best
  /// ball, por ejemplo— cualquier `every(...hasScore)` sobre esa lista es
  /// falso para siempre. Así se quedaba el contador de captura en "0/18" con
  /// hoyos capturados, y por eso el síntoma aparecía desde el primer hoyo.
  ///
  /// [roundPlayers] es la lista buena: es la declaración de quién juega, no una
  /// consecuencia de qué mapas se hayan inicializado.
  ///
  /// Con roundPlayers vacío se cae al predicado viejo. Una ronda guardada sin
  /// esa lista daría cero jugadores, y `every` sobre lista vacía es true: el
  /// contador diría 18/18 desde el hoyo 1, que es peor que el bug.
  List<Player> get scoringPlayers {
    // ── Lo DECLARADO manda sobre lo deducido ────────────────────────────────
    //
    // Una ronda de shotgun por equipos no tiene apuestas de las que deducir
    // nada, así que lo dice: ver [equipoId]. Va primero porque si la deducción
    // corriera igual devolvería los cuatro reales, que es justo lo contrario.
    if (equipoId != null) {
      final equipo = players.where((p) => p.id == equipoId).firstOrNull;
      if (equipo != null) return [equipo];
    }

    // Se DERIVA de los lados de las apuestas. Ni declarada ni observada.
    //
    // Los tres intentos anteriores preguntaban mal:
    //
    //   · scores.containsKey → pasa a quien tiene CONTENEDOR aunque esté
    //     vacío. El virtual de best ball tiene uno sembrado que no se llena
    //     nunca: 0/18 en toda ronda por equipos.
    //   · roundPlayers → es la DECLARACIÓN de quién juega, y también incluye a
    //     ese virtual. Mismo 0/18 por otra puerta.
    //   · "quien ya escribió un score" → observación. Correcto sobre lo
    //     capturado, pero el conjunto CRECE durante la ronda: mientras un lado
    //     no había anotado nunca, no se le exigía, y los hoyos a medias pasaban
    //     por completos. Al escribir su primer score el contador RETROCEDÍA
    //     —17/18 → 1/18— porque de golpe se le exigía en los 18.
    //
    // Quien lleva tarjeta lo dicen los LADOS: scoreCarriersOf ya distingue el
    // virtual del equipo en scramble de los reales en best ball. Eso no cambia
    // al capturar, así que el contador es monótono: añadir un score nunca puede
    // bajarlo.
    final llevanTarjeta = <String>{};
    final enAlgunLado = <String>{};
    for (final g in betGroups) {
      for (final m in g.modules) {
        if (!m.hasTeamSides) continue;
        for (final lado in m.sides!) {
          enAlgunLado.addAll(lado.playerIds);
          final portadores = scoreCarriersOf(lado);
          llevanTarjeta.addAll(portadores);
          // Si el portador es un virtual —scramble— sus miembros quedan
          // cubiertos por él y NO llevan tarjeta propia. Hay que decirlo
          // explícitamente porque en scramble los reales no aparecen en
          // lado.playerIds: Setup los sustituye por el id del virtual.
          for (final id in portadores) {
            final p = players.where((x) => x.id == id).firstOrNull;
            if (p != null && p.isVirtual) enAlgunLado.addAll(p.teamMemberIds);
          }
        }
      }
    }

    // Quien no está en ningún lado lleva su propia tarjeta. Salvo los
    // virtuales: uno que no sea portador —el bb_team_X de best ball— existe
    // para nombrar al equipo en pantalla, no para anotar.
    for (final rp in roundPlayers) {
      if (enAlgunLado.contains(rp.playerId)) continue;
      if (llevanTarjeta.contains(rp.playerId)) continue;
      final p = players.where((x) => x.id == rp.playerId).firstOrNull;
      if (p != null && p.isVirtual) continue;
      llevanTarjeta.add(rp.playerId);
    }

    final resultado =
        players.where((p) => llevanTarjeta.contains(p.id)).toList();
    if (resultado.isNotEmpty) return resultado;

    // Sin apuestas ni roundPlayers hay que devolver a ALGUIEN: every sobre
    // lista vacía es true y los 18 hoyos saldrían completos.
    return players.where((p) => scores.containsKey(p.id)).toList();
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // LOS TRES PREDICADOS DE JUGADORES, Y QUÉ SUPERFICIE USA CADA UNO
  //
  // Cuatro veces en una sola sesión un jugador virtual de equipo se filtró a una
  // superficie que solo tiene sentido entre personas: el ranking de Oyes, la
  // pestaña Duelos, su contador, y la tabla de captura. Las cuatro veces el
  // arreglo fue el mismo y las cuatro quedó algún consumidor fuera, porque el
  // barrido se hacía buscando la GRAFÍA del predicado.
  //
  // La auditoría útil es al revés: listar las superficies que enumeran gente y
  // comprobar una a una qué preguntan. La lista es corta y no depende de
  // acertar el grep.
  //
  //   [players]         todos, reales y virtuales. Para BUSCAR por id —resolver
  //                     un nombre— y para agrupar por virtual/real a propósito.
  //   [realPlayers]     personas. Lo que solo hace una persona: pegar un tiro
  //                     de aproximación, cobrar, aparecer en un duelo.
  //   [scoringPlayers]  quién lleva TARJETA. Best ball → los reales; scramble →
  //                     los virtuales. Para capturar y para "¿está el hoyo
  //                     completo?".
  //
  // Superficie                      predicado        por qué
  // ─────────────────────────────── ──────────────── ─────────────────────────
  // captura · filas de la tabla     scoringPlayers   quién anota
  // captura · jugador seleccionado  scoringPlayers   ídem
  // captura · hoyo completo         scoringPlayers   ídem
  // captura · ranking de Oyes       realPlayers      un equipo no pega un tiro
  // inicio · "N jugadores"          realPlayers      cuenta de personas
  // inicio · balances               realPlayers      el dinero es de personas
  // inicio · pares de jugadores     realPlayers      un duelo es entre dos
  // apuestas · pestaña Duelos       realPlayers      ídem
  // apuestas · contador de duelos   —                sale de la MISMA lista
  // tarjeta · vista 1v1             realPlayers      ídem
  // resultados · reparto visual     players          separa virtual/real a
  //                                                  propósito
  // apuestas · jugadores sueltos    players          necesita ver los virtuales
  //                                                  para leer teamMemberIds
  // ═══════════════════════════════════════════════════════════════════════════

  /// Las personas de la ronda. Excluye los jugadores de equipo.
  ///
  /// [players] lleva los reales Y los virtuales, porque las apuestas por
  /// equipos necesitan ambos. Pero hay cosas que solo hace una persona: pegar
  /// un tiro de aproximación, embocar un putt, hacer un birdie. Ofrecer
  /// "Equipo A" en el ranking de Oyes no es una opción rara, es una imposible.
  List<Player> get realPlayers => players.where((p) => !p.isVirtual).toList();

  /// Quién ANOTA por este lado.
  ///
  /// No es lo mismo que quién juega. En scramble el equipo entrega UNA
  /// tarjeta: el score lo lleva el jugador virtual y los reales ni siquiera
  /// entran en la ronda —Setup los excluye vía realPlayersNotInScramble—. En
  /// best ball anotan los reales, cada uno la suya.
  ///
  /// Preguntar por [BetSide.playerIds] daba lo segundo siempre, y por eso una
  /// ronda en scramble se quedaba a cero: GameEngine.holeDeltaVs buscaba el
  /// score de CAM y AAM, que no existe, concluía que el hoyo no se había
  /// jugado, y repetía el diagnóstico en los 18.
  ///
  /// Si el virtual no aparece se devuelven los reales: es lo que había antes,
  /// y una lectura de best ball vale más que reventar.
  List<String> scoreCarriersOf(BetSide side) {
    if (side.playMode != TeamPlayMode.scramble) return side.playerIds;
    final miembros = side.playerIds.toSet();
    for (final p in players) {
      if (!p.isVirtual || p.teamMemberIds.isEmpty) continue;
      // Se empareja por composición, no por el patrón del id: el nombre del
      // virtual es una convención de Setup y el motor no debería depender de
      // cómo la escriba.
      if (p.teamMemberIds.toSet().length == miembros.length &&
          p.teamMemberIds.toSet().containsAll(miembros)) {
        return [p.id];
      }
    }
    return side.playerIds;
  }

  /// Quién debe tener score para que esta apuesta pueda liquidar.
  ///
  /// Única respuesta a esa pregunta: la usan el motor y la validación de
  /// completitud. Que cada uno la dedujera por su cuenta es lo que dejaba el
  /// aviso "no tiene score de todos sus jugadores" encendido para siempre.
  List<String> scoreCarriersOfModule(
          BetModuleInstance mod, List<String> groupPlayerIds) =>
      mod.hasTeamSides
          ? [...scoreCarriersOf(mod.sideA), ...scoreCarriersOf(mod.sideB)]
          : participantesDe(mod, groupPlayerIds);

  /// ── PRECEDENCIA DEL ALCANCE, medida y no supuesta ─────────────────────────
  ///
  /// Tres campos deciden quién juega una apuesta y se pusieron en tres momentos
  /// distintos: `structure` al crearla —que EXPANDE en varios módulos—, `scope`
  /// al editarla, y `participantIds` como lista cruda. Comprobado ejecutando los
  /// seis casos contra la ronda del 28 de agosto:
  ///
  ///   · `scope` MANDA sobre `participantIds`. Con scope=everyone y
  ///     participantIds=[CAM,Dylan], juegan los cuatro.
  ///   · Sin `scope` —rondas anteriores al campo— deciden los participantIds.
  ///     Así que la MISMA lista significa cosas distintas según exista scope o
  ///     no, y eso hay que saberlo al leer una ronda vieja.
  ///   · `formatMode` no decide QUIÉN, solo CÓMO reparte entre los que hay. Con
  ///     dos participantes, onePot y allVsAll dan lo mismo.
  ///
  /// Y la consecuencia que importa: editar el alcance desde un duelo escribe
  /// sobre el MISMO módulo, así que no crea una apuesta paralela — sustituye la
  /// de todos. Un pote de cuatro acotado a un par deja a los otros dos en cero.
  /// El aviso vive en la pantalla que lo permite, BetModuleEditSheet.
  ///
  /// Los participantes de [mod] tal como los entiende SU formato.
  ///
  /// Para casi todos es [BetModuleInstance.effectivePids] sin más. Para los que
  /// declaran [BetTypeRules.soloPersonas] —los side bets— se quitan los
  /// jugadores virtuales de equipo: Snake cuenta los putts de una persona,
  /// Rabbit lo captura una persona ganando un hoyo, y Wolf necesita cuatro
  /// personas. Un equipo no hace tres putts.
  ///
  /// UN sitio a propósito. La alternativa era un filtro dentro de cada motor y
  /// otro en la capa de notas, o sea cuatro sitios que tienen que coincidir —y
  /// es exactamente la clase de duplicación que ya nos costó siete superficies
  /// en esta sesión—.
  List<String> participantesDe(
      BetModuleInstance mod, List<String> groupPlayerIds) {
    final pids = mod.effectivePids(groupPlayerIds);
    if (!mod.type.rules.soloPersonas) return pids;
    final virtuales = players.where((p) => p.isVirtual).map((p) => p.id).toSet();
    return pids.where((id) => !virtuales.contains(id)).toList();
  }

  double getHandicap(String playerId) =>
      roundPlayers.firstWhere((rp) => rp.playerId == playerId,
          orElse: () => RoundPlayer(playerId: playerId, handicapEnRonda: 0)).handicapEnRonda;

  /// Devuelve (strokesP1, strokesP2): cuántos strokes extra recibe cada jugador.
  /// Prioridad (idéntica a BetEngine._strokesP1ReceivesFromP2):
  ///   1. pairSliding (fuente canónica)
  ///   2. manualHandicaps legacy
  ///   3. HCP diff fallback
  (int, int) strokesVs(String p1Id, String p2Id) {
    // 1. pairSliding — fuente canónica
    final psKey = p1Id.compareTo(p2Id) <= 0 ? '$p1Id|$p2Id' : '$p2Id|$p1Id';
    final psStored = pairSliding[psKey];
    if (psStored != null) {
      final lowId = p1Id.compareTo(p2Id) <= 0 ? p1Id : p2Id;
      final recv = ((p1Id == lowId) ? psStored : -psStored).round();
      return recv >= 0 ? (recv, 0) : (0, -recv);
    }

    // 2. Legacy manualHandicaps
    final rp1 = roundPlayers.firstWhere((r) => r.playerId == p1Id,
        orElse: () => RoundPlayer(playerId: p1Id, handicapEnRonda: 0));
    if (rp1.manualHandicaps.containsKey(p2Id)) {
      final diff = rp1.manualHandicaps[p2Id]!.round();
      return diff >= 0 ? (diff, 0) : (0, -diff);
    }
    final rp2 = roundPlayers.firstWhere((r) => r.playerId == p2Id,
        orElse: () => RoundPlayer(playerId: p2Id, handicapEnRonda: 0));
    if (rp2.manualHandicaps.containsKey(p1Id)) {
      final diff = -(rp2.manualHandicaps[p1Id]!.round());
      return diff >= 0 ? (diff, 0) : (0, -diff);
    }

    // 3. Fallback HCP diff
    final diff = (rp1.handicapEnRonda - rp2.handicapEnRonda).round();
    return diff >= 0 ? (diff, 0) : (0, -diff);
  }

  Round copyWith({
    bool? slidingRecalcula,
    Map<String, Map<int, HoleScore>>? scores,
    Map<String, Map<int, List<HoleEvent>>>? events,
    Map<int, OyeseRanking>? oyeseRankings,
    Map<int, WolfCall>? wolfCalls,
    List<String>? torneoIds,
    List<BetGroup>? betGroups,
    List<RoundPlayer>? roundPlayers,
    List<Player>? players,
    int? currentHole, bool? isFinished,
    StartingNine? startingNine,
    int? totalHoles,
    bool? isLive,
    String? ownerUid,
    String? liveCode,
    String? scoringMode,
    Map<String, double>? pairSliding,
    List<BetChangeProposal>? pendingProposals,
    List<CorreccionDeScore>? correcciones,
    String? equipoId,
    Map<int, String>? ultimoEnPasarElUmbral,
  }) => Round(
    id: id, name: name, course: course,
    players: players ?? this.players,
    roundPlayers: roundPlayers ?? this.roundPlayers,
    betGroups: betGroups ?? this.betGroups,
    scores: scores ?? this.scores,
    events: events ?? this.events,
    oyeseRankings: oyeseRankings ?? this.oyeseRankings,
    wolfCalls: wolfCalls ?? this.wolfCalls,
    torneoIds: torneoIds ?? this.torneoIds,
    sliding: sliding, createdAt: createdAt,
    currentHole: currentHole ?? this.currentHole,
    isFinished: isFinished ?? this.isFinished,
    startingNine: startingNine ?? this.startingNine,
    totalHoles: totalHoles ?? this.totalHoles,
    isLive: isLive ?? this.isLive,
    ownerUid: ownerUid ?? this.ownerUid,
    liveCode: liveCode ?? this.liveCode,
    scoringMode: scoringMode ?? this.scoringMode,
    pairSliding: pairSliding ?? this.pairSliding,
    slidingRecalcula: slidingRecalcula ?? this.slidingRecalcula,
    pendingProposals: pendingProposals ?? this.pendingProposals,
    correcciones: correcciones ?? this.correcciones,
    equipoId: equipoId ?? this.equipoId,
    ultimoEnPasarElUmbral:
        ultimoEnPasarElUmbral ?? this.ultimoEnPasarElUmbral,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BETTING GROUPS — Sistema de grupos habituales con apuestas por duelo
// ─────────────────────────────────────────────────────────────────────────────

/// Plantilla de módulo de apuesta para uso en PairBetRule.
/// Análogo a BetModuleInstance pero sin id de ronda ni participantIds
/// (los participantes se conocen al activar la regla en una ronda).
class BetModuleTemplate {
  final BetModuleType            type;
  final BetFormatMode            formatMode;
  final SkinsConfig?             skinsConfig;
  final NassauConfig?            nassauConfig;
  final MedalConfig?             medalConfig;
  final PuttsConfig?             puttsConfig;
  final OyesesConfig?            oyesesConfig;
  final UnitsConfig?             unitsConfig;
  final SnakeConfig?             snakeConfig;
  final RabbitConfig?            rabbitConfig;
  final WolfConfig?              wolfConfig;
  final SixesConfig?             sixesConfig;
  final StablefordConfig?        stablefordConfig;
  final NassauLowHighConfig?     nassauLowHighConfig;

  const BetModuleTemplate({
    required this.type,
    this.formatMode  = BetFormatMode.allVsAll,
    this.skinsConfig,
    this.nassauConfig,
    this.medalConfig,
    this.puttsConfig,
    this.oyesesConfig,
    this.unitsConfig,
    this.snakeConfig,
    this.rabbitConfig,
    this.wolfConfig,
    this.sixesConfig,
    this.stablefordConfig,
    this.nassauLowHighConfig,
  });

  // ── Getters de acceso rápido (igual que BetModuleInstance) ─────────────────
  SkinsConfig          get skins  => skinsConfig          ?? SkinsConfig.def;
  NassauConfig         get nassau => nassauConfig         ?? NassauConfig.def;
  NassauLowHighConfig  get lowHigh => nassauLowHighConfig ?? const NassauLowHighConfig();
  MedalConfig          get medal  => medalConfig          ?? MedalConfig.def;
  PuttsConfig          get putts  => puttsConfig          ?? PuttsConfig.def;
  OyesesConfig         get oyeses => oyesesConfig         ?? OyesesConfig.def;
  UnitsConfig          get units  => unitsConfig          ?? UnitsConfig.def;
  SnakeConfig          get snake  => snakeConfig          ?? SnakeConfig.def;
  RabbitConfig         get rabbit => rabbitConfig         ?? RabbitConfig.def;
  WolfConfig           get wolf   => wolfConfig           ?? WolfConfig.def;
  SixesConfig          get sixes  => sixesConfig          ?? SixesConfig.def;
  StablefordConfig     get stableford => stablefordConfig ?? StablefordConfig.def;

  /// Etiqueta corta del valor principal.
  String get summaryLabel {
    switch (type) {
      case BetModuleType.snake:
        return '\$${snake.value.toStringAsFixed(0)} · ${snake.umbral}+ putts';
      case BetModuleType.rabbit:
        return '\$${rabbit.value.toStringAsFixed(0)}/nueve';
      case BetModuleType.wolf:
        return '\$${wolf.value.toStringAsFixed(0)}/hoyo';
      case BetModuleType.sixes:
        return '\$${sixes.value.toStringAsFixed(0)}/bloque';
      case BetModuleType.stableford:
        return '\$${stableford.value.toStringAsFixed(0)}';
      case BetModuleType.skins:
        return '\$${skins.valuePerSkin.toStringAsFixed(0)}/skin';
      case BetModuleType.nassau:
        final n = nassau;
        return 'F\$${n.frontValue.toStringAsFixed(0)}·'
               'B\$${n.backValue.toStringAsFixed(0)}·'
               'T\$${n.totalValue.toStringAsFixed(0)}';
      case BetModuleType.medal:
        return '\$${medal.value.toStringAsFixed(0)}';
      case BetModuleType.putts:
        return '\$${putts.value.toStringAsFixed(0)}/putts';
      case BetModuleType.oyeses:
        return '\$${oyeses.value.toStringAsFixed(0)}/oyés';
      case BetModuleType.units:
        return '\$${units.representativeValue.toStringAsFixed(0)}/u';
      case BetModuleType.nassauLowHigh:
        return '\$${lowHigh.segmentAmount.toStringAsFixed(0)}/segmento';
    }
  }

  /// Crea un template con la configuración por defecto para el tipo dado.
  factory BetModuleTemplate.defaultFor(BetModuleType t) => BetModuleTemplate(
    type:                  t,
    skinsConfig:          t == BetModuleType.skins         ? SkinsConfig.def          : null,
    nassauConfig:         t == BetModuleType.nassau        ? NassauConfig.def         : null,
    medalConfig:          t == BetModuleType.medal         ? MedalConfig.def          : null,
    puttsConfig:          t == BetModuleType.putts         ? PuttsConfig.def          : null,
    oyesesConfig:         t == BetModuleType.oyeses        ? OyesesConfig.def         : null,
    unitsConfig:          t == BetModuleType.units         ? UnitsConfig.def          : null,
    snakeConfig:          t == BetModuleType.snake         ? SnakeConfig.def          : null,
    rabbitConfig:         t == BetModuleType.rabbit        ? RabbitConfig.def         : null,
    wolfConfig:           t == BetModuleType.wolf          ? WolfConfig.def           : null,
    stablefordConfig:     t == BetModuleType.stableford    ? StablefordConfig.def     : null,
    nassauLowHighConfig:  t == BetModuleType.nassauLowHigh? const NassauLowHighConfig() : null,
  );

  /// Convierte la plantilla a un BetModuleInstance 1v1 listo para el engine.
  /// Se asigna betGroupId para que los chips consolidados lo agrupen.
  BetModuleInstance toInstance({
    required String id,
    required List<String> participantIds,
    String? betGroupId,
    String? betGroupName,
  }) => BetModuleInstance(
    id:                   id,
    type:                 type,
    name:                 type.label,
    participantIds:       participantIds,
    formatMode:           formatMode,
    skinsConfig:          skinsConfig,
    nassauConfig:         nassauConfig,
    medalConfig:          medalConfig,
    puttsConfig:          puttsConfig,
    oyesesConfig:         oyesesConfig,
    unitsConfig:          unitsConfig,
    snakeConfig:          snakeConfig,
    rabbitConfig:         rabbitConfig,
    wolfConfig:           wolfConfig,
    stablefordConfig:     stablefordConfig,
    betGroupId:           betGroupId,
    betGroupName:         betGroupName,
    structure:            BetStructure.headToHead,
  );

  BetModuleTemplate copyWith({
    BetModuleType?         type,
    BetFormatMode?         formatMode,
    SkinsConfig?           skinsConfig,
    NassauConfig?          nassauConfig,
    MedalConfig?           medalConfig,
    PuttsConfig?           puttsConfig,
    OyesesConfig?          oyesesConfig,
    UnitsConfig?           unitsConfig,
    SnakeConfig?           snakeConfig,
    RabbitConfig?          rabbitConfig,
    WolfConfig?            wolfConfig,
    SixesConfig?           sixesConfig,
    StablefordConfig?      stablefordConfig,
  }) => BetModuleTemplate(
    type:                  type                 ?? this.type,
    formatMode:            formatMode           ?? this.formatMode,
    skinsConfig:           skinsConfig          ?? this.skinsConfig,
    nassauConfig:          nassauConfig         ?? this.nassauConfig,
    medalConfig:           medalConfig          ?? this.medalConfig,
    puttsConfig:           puttsConfig          ?? this.puttsConfig,
    oyesesConfig:          oyesesConfig         ?? this.oyesesConfig,
    unitsConfig:           unitsConfig          ?? this.unitsConfig,
    snakeConfig:           snakeConfig          ?? this.snakeConfig,
    rabbitConfig:          rabbitConfig         ?? this.rabbitConfig,
    wolfConfig:            wolfConfig           ?? this.wolfConfig,
    sixesConfig:           sixesConfig          ?? this.sixesConfig,
    stablefordConfig:      stablefordConfig     ?? this.stablefordConfig,
  );

  Map<String, dynamic> toJson() => {
    'type':                  type.name,
    'formatMode':            formatMode.name,
    if (skinsConfig          != null) 'skinsConfig':          skinsConfig!.toJson(),
    if (nassauConfig         != null) 'nassauConfig':         nassauConfig!.toJson(),
    if (medalConfig          != null) 'medalConfig':          medalConfig!.toJson(),
    if (puttsConfig          != null) 'puttsConfig':          puttsConfig!.toJson(),
    if (oyesesConfig         != null) 'oyesesConfig':         oyesesConfig!.toJson(),
    if (unitsConfig          != null) 'unitsConfig':          unitsConfig!.toJson(),
    if (snakeConfig          != null) 'snakeConfig':          snakeConfig!.toJson(),
    if (rabbitConfig         != null) 'rabbitConfig':         rabbitConfig!.toJson(),
    if (wolfConfig           != null) 'wolfConfig':           wolfConfig!.toJson(),
    if (sixesConfig          != null) 'sixesConfig':          sixesConfig!.toJson(),
    if (stablefordConfig     != null) 'stablefordConfig':     stablefordConfig!.toJson(),
  };

  factory BetModuleTemplate.fromJson(Map<String, dynamic> j) {
    final type = BetModuleType.values.firstWhere(
      (t) => t.name == j['type'], orElse: () => BetModuleType.skins);
    return BetModuleTemplate(
      type:       type,
      formatMode: BetFormatMode.values.firstWhere(
          (f) => f.name == j['formatMode'],
          orElse: () => BetFormatMode.allVsAll),
      skinsConfig: j['skinsConfig'] != null
          ? SkinsConfig.fromJson(Map<String, dynamic>.from(j['skinsConfig'] as Map)) : null,
      nassauConfig: j['nassauConfig'] != null
          ? NassauConfig.fromJson(Map<String, dynamic>.from(j['nassauConfig'] as Map)) : null,
      medalConfig: j['medalConfig'] != null
          ? MedalConfig.fromJson(Map<String, dynamic>.from(j['medalConfig'] as Map)) : null,
      puttsConfig: j['puttsConfig'] != null
          ? PuttsConfig.fromJson(Map<String, dynamic>.from(j['puttsConfig'] as Map)) : null,
      oyesesConfig: j['oyesesConfig'] != null
          ? OyesesConfig.fromJson(Map<String, dynamic>.from(j['oyesesConfig'] as Map)) : null,
      unitsConfig: j['unitsConfig'] != null
          ? UnitsConfig.fromJson(Map<String, dynamic>.from(j['unitsConfig'] as Map)) : null,
      snakeConfig: j['snakeConfig'] != null
          ? SnakeConfig.fromJson(Map<String, dynamic>.from(j['snakeConfig'] as Map)) : null,
      rabbitConfig: j['rabbitConfig'] != null
          ? RabbitConfig.fromJson(Map<String, dynamic>.from(j['rabbitConfig'] as Map)) : null,
      wolfConfig: j['wolfConfig'] != null
          ? WolfConfig.fromJson(Map<String, dynamic>.from(j['wolfConfig'] as Map)) : null,
      stablefordConfig: j['stablefordConfig'] != null
          ? StablefordConfig.fromJson(Map<String, dynamic>.from(j['stablefordConfig'] as Map)) : null,
    );
  }

  /// Copia snapshot de un BetModuleInstance existente (p.ej. al exportar desde
  /// un duelo ya configurado).  Independiente: cambiar uno no afecta al otro.
  factory BetModuleTemplate.fromInstance(BetModuleInstance inst) =>
      BetModuleTemplate(
        type:                  inst.type,
        formatMode:            inst.formatMode,
        skinsConfig:           inst.skinsConfig,
        nassauConfig:          inst.nassauConfig,
        medalConfig:           inst.medalConfig,
        puttsConfig:           inst.puttsConfig,
        oyesesConfig:          inst.oyesesConfig,
        unitsConfig:           inst.unitsConfig,
        snakeConfig:           inst.snakeConfig,
        rabbitConfig:          inst.rabbitConfig,
        wolfConfig:            inst.wolfConfig,
        stablefordConfig:      inst.stablefordConfig,
      );

}

// ─────────────────────────────────────────────────────────────────────────────

/// Regla de apuesta para un duelo específico entre dos jugadores.
/// Contiene una lista de plantillas de módulos (puede haber Nassau + Skins, etc.)
class PairBetRule {
  final String id;
  final String playerAId;
  final String playerBId;
  final List<BetModuleTemplate> modules;

  const PairBetRule({
    required this.id,
    required this.playerAId,
    required this.playerBId,
    this.modules = const [],
  });

  /// Clave canónica del duelo (orden alfabético de IDs).
  String get pairKey {
    final sorted = [playerAId, playerBId]..sort();
    return '${sorted[0]}__${sorted[1]}';
  }

  /// true si ambos jugadores están en el conjunto dado.
  bool isActive(Set<String> presentIds) =>
      presentIds.contains(playerAId) && presentIds.contains(playerBId);

  PairBetRule copyWith({
    String? id,
    String? playerAId,
    String? playerBId,
    List<BetModuleTemplate>? modules,
  }) => PairBetRule(
    id:        id        ?? this.id,
    playerAId: playerAId ?? this.playerAId,
    playerBId: playerBId ?? this.playerBId,
    modules:   modules   ?? this.modules,
  );

  Map<String, dynamic> toJson() => {
    'id':        id,
    'playerAId': playerAId,
    'playerBId': playerBId,
    'modules':   modules.map((m) => m.toJson()).toList(),
  };

  factory PairBetRule.fromJson(Map<String, dynamic> j) => PairBetRule(
    id:        (j['id']        as String?) ?? '',
    playerAId: (j['playerAId'] as String?) ?? '',
    playerBId: (j['playerBId'] as String?) ?? '',
    modules:   (j['modules'] as List? ?? [])
        .map((m) => BetModuleTemplate.fromJson(
            Map<String, dynamic>.from(m as Map)))
        .toList(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

/// Qué juega un invitado que no estaba en el grupo.
///
/// El caso: "en algún grupo de apuesta es común que a veces falte uno y vaya
/// otro". Quitar a alguien es limpio —sus reglas desaparecen y los demás quedan
/// igual— pero AÑADIR no es simétrico: [PairBetRule] es por pareja concreta, así
/// que quien no estaba no tiene regla con nadie y entraría sin jugar nada.
///
/// La forma que sí admite un invitado gratis existe ya en el modelo, en otro
/// objeto: GamePreset guarda modulesJson SIN participantIds —la regla que
/// aplica a todos— más pairAgreementsJson de excepciones. Un grupo no tiene esa
/// separación, así que hay que DERIVARLA.
///
/// Se deriva comparando las plantillas de todos los cruces por su toJson: si
/// todos juegan lo mismo, eso es el patrón y el invitado lo hereda contra todos.
/// Si no coinciden, [uniforme] es false y NO se adivina — el grupo puede tener
/// un Nassau de $50 entre cuatro y unas Skins de $200 entre otros dos, y elegir
/// uno de los dos por mayoría sería inventarle al invitado un acuerdo que nadie
/// pactó.
///
/// La otra opción sería que el invitado ocupara el sitio del que falta y
/// heredara SUS reglas. Es lo que más se parece a "va otro en su lugar", pero
/// exige saber a quién sustituye, y eso no se puede inferir de una lista de
/// presentes: quitar a uno y añadir a otro es indistinguible de que el grupo
/// crezca y encoja a la vez.
class PatronDeGrupo {
  /// true si todos los cruces con apuesta juegan exactamente lo mismo.
  final bool uniforme;

  /// Las plantillas del patrón. Vacía si no es uniforme.
  final List<BetModuleTemplate> modules;

  const PatronDeGrupo({required this.uniforme, required this.modules});

  /// Por qué no se puede heredar, para decirlo en pantalla.
  String? get motivo => uniforme
      ? null
      : 'Los duelos de este grupo no juegan todos lo mismo, así que no hay un '
          'patrón que heredar. Añádele su apuesta en «Revisar todo».';
}

/// Una apuesta de partida del grupo, mirada contra la nómina de HOY.
///
/// Existe porque las apuestas de partida se comportan distinto de los duelos y
/// eso hay que poder decirlo: un duelo simplemente no se activa si falta uno de
/// los dos, mientras una apuesta de partida puede dejar de ser JUGABLE según
/// cuántos vengan. Wolf necesita exactamente 4 o 5; si el grupo es de seis y hoy
/// van los seis, no se puede jugar.
///
/// Se descartó prohibir guardar los formatos con requisito de tamaño. El grupo de
/// los viernes puede ser de seis habituales y jugar Wolf casi todos los sábados
/// porque suelen faltar dos: prohibirlo por lo que pasa cuando vienen todos sería
/// quitarle el formato el resto de las veces. Se guarda, y el arranque rápido
/// dice si hoy entra o no y por qué.
class ApuestaDePartidaHoy {
  final BetModuleTemplate plantilla;

  /// Por qué NO se juega hoy. Null si sí.
  final String? motivo;

  const ApuestaDePartidaHoy({required this.plantilla, this.motivo});

  bool get jugable => motivo == null;
}

/// Grupo habitual de golf/apuestas.
/// NO representa una ronda. Solo define el ecosistema de jugadores habituales
/// y las reglas de apuesta que existen entre ellos por duelo.
class BettingGroup {
  final String          id;
  final String          name;
  final String?         description;
  final String          emoji;
  final List<String>    playerIds;   // IDs de los jugadores habituales
  final List<PairBetRule> pairRules; // reglas por duelo

  /// Apuestas del grupo ENTERO, no de un duelo.
  ///
  /// Snake, Rabbit, Wolf, Oyes y Unidades no caben en pairRules: cada regla de
  /// ahí produce un módulo con exactamente dos participantes, y una serpiente
  /// por pareja no es el juego. Los tipos que van aquí son los que declaran
  /// [BetTypeRules.deLaPartida], y el editor los saca de esa marca en vez de
  /// enumerarlos.
  ///
  /// ADITIVO Y OPCIONAL: ausente significa "no hay apuestas de partida", así que
  /// los grupos guardados antes de que existiera el campo se comportan igual que
  /// siempre. Solo se serializa cuando hay alguna.
  final List<BetModuleTemplate> modulosDePartida;

  final DateTime        updatedAt;

  const BettingGroup({
    required this.id,
    required this.name,
    this.description,
    // La MARCA del grupo, como clave de GolfIcons.paleta y no como emoji.
    // Se guarda una clave para que el dibujo lo ponga el tema: la marca que
    // alguien eligió se veía distinta en el teléfono de cada uno de sus
    // amigos. Un valor viejo cae en la bandera, sin migración.
    this.emoji        = GolfIcons.claveInicial,
    this.playerIds    = const [],
    this.pairRules    = const [],
    this.modulosDePartida = const [],
    required this.updatedAt,
  });

  /// Número de reglas que tienen al menos un módulo configurado.
  int get activeRulesCount =>
      pairRules.where((r) => r.modules.isNotEmpty).length;

  /// Número total de módulos de apuesta en el grupo, de duelo y de partida.
  int get totalModules =>
      pairRules.fold(0, (sum, r) => sum + r.modules.length) +
      modulosDePartida.length;

  /// Las reglas para la nómina de HOY, con los invitados incluidos.
  ///
  /// Devuelve una lista nueva; **no modifica el grupo**. Es donde esto se rompe
  /// más fácil: reutilizar pairRules para la sesión de hoy haría que jugar sin
  /// uno lo borrara del grupo para siempre. La lista de hoy es una copia, no una
  /// edición.
  ///
  /// Los que estaban y siguen → sus reglas tal cual. Los que no vienen → sus
  /// reglas desaparecen solas, porque [activeRulesFor] ya filtra por presentes.
  /// Los invitados → el patrón del grupo contra todos los presentes, si hay
  /// patrón; nada si no lo hay.
  List<PairBetRule> rulesForToday(List<String> presentes) {
    final set = presentes.toSet();
    final habituales = playerIds.toSet();
    final salida = List<PairBetRule>.of(activeRulesFor(set));

    final invitados = presentes.where((p) => !habituales.contains(p)).toList();
    if (invitados.isEmpty) return salida;

    final pat = patron;
    if (!pat.uniforme) return salida; // no se adivina: se dice en pantalla

    // Un cruce por cada pareja que involucre a un invitado y que no exista ya.
    final existentes = {for (final r in salida) r.pairKey};
    for (var i = 0; i < presentes.length; i++) {
      for (var j = i + 1; j < presentes.length; j++) {
        final a = presentes[i], b = presentes[j];
        if (!invitados.contains(a) && !invitados.contains(b)) continue;
        final clave = ([a, b]..sort()).join('|');
        if (existentes.contains(clave)) continue;
        salida.add(PairBetRule(
          id: 'hoy_$clave',
          playerAId: a,
          playerBId: b,
          modules: List.of(pat.modules),
        ));
      }
    }
    return salida;
  }

  /// Las apuestas de partida contra la nómina de HOY, con su motivo si no entran.
  ///
  /// El motivo sale de [BetModuleType.motivoNoDisponible], la misma función que
  /// atenúa el tipo en los selectores. Una sola respuesta a "¿se puede jugar
  /// esto con esta gente?", así que el grupo no puede decir una cosa y la ronda
  /// otra.
  List<ApuestaDePartidaHoy> modulosDePartidaHoy(List<String> presentes) => [
        for (final tpl in modulosDePartida)
          ApuestaDePartidaHoy(
            plantilla: tpl,
            motivo: tpl.type.motivoNoDisponible(presentes.length),
          ),
      ];

  /// Los módulos para la nómina de HOY, invitados incluidos.
  List<BetModuleInstance> toBetModuleInstancesForToday({
    required List<String> presentes,
    required String betGroupId,
    required String betGroupName,
  }) {
    final result = <BetModuleInstance>[];
    var counter = 0;
    for (final rule in rulesForToday(presentes)) {
      for (final tpl in rule.modules) {
        result.add(tpl.toInstance(
          id: '${betGroupId}_${rule.id}_${tpl.type.name}_$counter',
          participantIds: [rule.playerAId, rule.playerBId],
          betGroupId: '${betGroupId}_${rule.id}_${tpl.type.name}',
          betGroupName: betGroupName,
        ));
        counter++;
      }
    }

    // ── Las apuestas de partida ────────────────────────────────────────────
    //
    // Participantes = TODOS los presentes, no una pareja. Es la diferencia que
    // hacía imposible guardarlas: cada regla de pairRules produce un módulo de
    // dos y punto.
    //
    // Solo entran las JUGABLES. Crear un módulo de Wolf con seis participantes
    // daría una apuesta que aparece configurada, con su monto, y no liquida
    // nada — el mismo fallo que Medal y Putts tenían con los equipos. Lo que se
    // deja fuera se dice en el arranque rápido, antes de empezar.
    for (final apuesta in modulosDePartidaHoy(presentes)) {
      if (!apuesta.jugable) continue;
      final tpl = apuesta.plantilla;
      result.add(tpl.toInstance(
        id: '${betGroupId}_partida_${tpl.type.name}_$counter',
        participantIds: List.of(presentes),
        betGroupId: '${betGroupId}_partida_${tpl.type.name}',
        betGroupName: betGroupName,
      ));
      counter++;
    }

    return result;
  }

  /// El patrón que comparten todos los cruces con apuesta, si lo hay.
  ///
  /// Lo consume la pantalla de arranque rápido para saber qué darle a un
  /// invitado que no estaba en el grupo.
  PatronDeGrupo get patron {
    final conApuesta = pairRules.where((r) => r.modules.isNotEmpty).toList();
    if (conApuesta.isEmpty) {
      return const PatronDeGrupo(uniforme: false, modules: []);
    }
    // La firma de un cruce: sus plantillas serializadas y ordenadas, para que
    // el ORDEN en que se guardaron no haga parecer distintos dos cruces iguales.
    String firma(PairBetRule r) {
      final fs = r.modules.map((m) => m.toJson().toString()).toList()..sort();
      return fs.join('||');
    }

    final primera = firma(conApuesta.first);
    final todos = conApuesta.every((r) => firma(r) == primera);
    return PatronDeGrupo(
      uniforme: todos,
      modules: todos ? List.of(conApuesta.first.modules) : const [],
    );
  }

  /// Reglas activas dado el conjunto de jugadores presentes.
  List<PairBetRule> activeRulesFor(Set<String> presentIds) =>
      pairRules
          .where((r) => r.isActive(presentIds) && r.modules.isNotEmpty)
          .toList();

  /// Número de duelos activos dado el conjunto de jugadores presentes.
  int activeDuelsFor(Set<String> presentIds) =>
      activeRulesFor(presentIds).length;

  /// Número total de módulos activos dado el conjunto de jugadores presentes.
  int activeModulesFor(Set<String> presentIds) =>
      activeRulesFor(presentIds)
          .fold(0, (sum, r) => sum + r.modules.length);

  /// Convierte las pair rules activas en BetModuleInstances listos para el engine.
  /// Se agrupan bajo un BetGroup de la ronda con betGroupId = pairRule.id.
  List<BetModuleInstance> toBetModuleInstances({
    required Set<String> presentIds,
    required String betGroupId,    // ID del BetGroup de la ronda destino
    required String betGroupName,  // nombre legible del BetGroup
  }) {
    final result = <BetModuleInstance>[];
    final activeRules = activeRulesFor(presentIds);
    int counter = 0;
    for (final rule in activeRules) {
      for (final tpl in rule.modules) {
        counter++;
        result.add(tpl.toInstance(
          id:           '${betGroupId}_${rule.id}_${tpl.type.name}_$counter',
          participantIds: [rule.playerAId, rule.playerBId],
          betGroupId:   '${betGroupId}_${rule.id}_${tpl.type.name}',
          betGroupName: betGroupName,
        ));
      }
    }
    return result;
  }

  BettingGroup copyWith({
    String?             id,
    String?             name,
    String?             description,
    String?             emoji,
    List<String>?       playerIds,
    List<PairBetRule>?  pairRules,
    List<BetModuleTemplate>? modulosDePartida,
    DateTime?           updatedAt,
  }) => BettingGroup(
    id:          id          ?? this.id,
    name:        name        ?? this.name,
    description: description ?? this.description,
    emoji:       emoji       ?? this.emoji,
    playerIds:   playerIds   ?? this.playerIds,
    pairRules:   pairRules   ?? this.pairRules,
    modulosDePartida: modulosDePartida ?? this.modulosDePartida,
    updatedAt:   updatedAt   ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id':          id,
    'name':        name,
    if (description != null) 'description': description,
    'emoji':       emoji,
    'playerIds':   playerIds,
    'pairRules':   pairRules.map((r) => r.toJson()).toList(),
    // Solo si hay alguna: un grupo sin apuestas de partida no gana una clave
    // vacía, y los guardados antes de que existiera el campo se leen igual.
    if (modulosDePartida.isNotEmpty)
      'modulosDePartida': modulosDePartida.map((m) => m.toJson()).toList(),
    'updatedAt':   updatedAt.toIso8601String(),
  };

  factory BettingGroup.fromJson(Map<String, dynamic> j) => BettingGroup(
    id:          (j['id']   as String?) ?? '',
    name:        (j['name'] as String?) ?? 'Grupo',
    description: j['description'] as String?,
    emoji:       (j['emoji'] as String?) ?? GolfIcons.claveInicial,
    playerIds:   (j['playerIds'] as List? ?? [])
        .map((e) => e as String)
        .toList(),
    pairRules:   (j['pairRules'] as List? ?? [])
        .map((r) => PairBetRule.fromJson(
            Map<String, dynamic>.from(r as Map)))
        .toList(),
    modulosDePartida: (j['modulosDePartida'] as List? ?? [])
        .map((m) => BetModuleTemplate.fromJson(
            Map<String, dynamic>.from(m as Map)))
        .toList(),
    updatedAt: j['updatedAt'] is String
        ? (DateTime.tryParse(j['updatedAt'] as String) ?? DateTime.now())
        : DateTime.now(),
  );

  /// Serialización para Firestore (usa FieldValue.serverTimestamp para updatedAt).
  Map<String, dynamic> toFirestore() {
    final j = toJson();
    j.remove('updatedAt');  // se sustituye por serverTimestamp
    return j;
  }

  factory BettingGroup.fromFirestore(
      Map<String, dynamic> d, String docId) {
    final raw = Map<String, dynamic>.from(d);
    raw['id'] = docId;
    // updatedAt puede ser Timestamp de Firestore (duck-typing) o String ISO
    raw['updatedAt'] = _parseDate(d['updatedAt']).toIso8601String();
    return BettingGroup.fromJson(raw);
  }
}
