// ─────────────────────────────────────────────────────────────────────────────
// MODELOS DE DATOS — v4
// Entidades: Round, Player, RoundPlayer, CourseHole, HoleScore,
//            HoleEvent, OyeseRanking, BetModuleInstance (con config tipada),
//            BetGroup, LedgerEntry, SlidingRelation
// ─────────────────────────────────────────────────────────────────────────────

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
enum BetModuleType { skins, nassau, matchAutoPress, medal, putts, oyeses, units, nassauLowHigh }

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

  const BetTypeRules({
    this.teams = false,
    this.sinEquipos,
    this.requiresTeams = false,
    this.segments = false,
    this.sinSegmentos,
    this.perPairAmount = false,
    this.sinMontoPorPareja,
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
            perPairAmount: true,
            sinEquipos: 'Medal aún no tiene semántica de equipo: se liquidaría '
                'como duelos individuales entre todos.',
            sinSegmentos: 'Medal ya elige entre 9 y 18 hoyos en su detalle.',
          ),
        BetModuleType.putts => const BetTypeRules(
            perPairAmount: true,
            sinEquipos: 'Putts aún no tiene semántica de equipo: se liquidaría '
                'como duelos individuales entre todos.',
            sinSegmentos: 'Putts ya elige entre total y hoyo a hoyo en su detalle.',
          ),
        BetModuleType.oyeses => const BetTypeRules(
            perPairAmount: true,
            sinEquipos: 'Los oyeses son de tiro individual: no hay bola de '
                'equipo que comparar.',
            sinSegmentos: 'Se juegan en los par 3, que no caen por vuelta.',
          ),
        BetModuleType.units => const BetTypeRules(
            perPairAmount: true,
            sinEquipos: 'Las unidades premian un logro individual —birdie, '
                'eagle, sandy— que no se atribuye a un equipo.',
            sinSegmentos: 'Las unidades se cobran cuando ocurren, no por vuelta.',
          ),
        // Retirado del catálogo, pero las rondas guardadas lo siguen usando.
        BetModuleType.matchAutoPress => const BetTypeRules(
            teams: true,
            sinSegmentos: 'El match corre los 18 hoyos; las presiones abren '
                'sus propios tramos.',
            sinMontoPorPareja:
                'Tiene dos importes —match y presión— y un ajuste por pareja '
                'solo puede llevar uno.',
          ),
      };
}

/// Tipos que se pueden crear hoy. **Toda hoja de selección debe usar esto.**
///
/// Un tipo retirado sigue existiendo en el enum, en la deserialización, en el
/// motor y en las pantallas que lo pintan: las rondas guardadas que lo usan
/// tienen que abrir y liquidar exactamente igual que antes. Lo único que
/// desaparece es la posibilidad de crear uno nuevo.
///
/// Es una sola lista a propósito. Esta misma sesión costó tres bugs descubrir
/// que el catálogo de tipos vivía duplicado en cinco pantallas: al añadir Bola
/// Baja / Bola Alta quedó fuera del selector de Setup y de la sección de
/// equipos, y en ambos casos el fallo fue silencioso.
List<BetModuleType> get creatableBetTypes =>
    BetModuleType.values.where((t) => t.isCreatable).toList();

extension BetModuleAvailability on BetModuleType {
  /// false = retirado. Ver [creatableBetTypes].
  ///
  /// matchAutoPress es redundante: NassauConfig ya trae todo el aparato de
  /// presiones, así que un match a 18 con presses es un Nassau con
  /// frontValue = 0, backValue = 0, totalValue = X y presiones activas.
  /// Mantener dos motores para lo mismo obligaba además a elegir cuál
  /// representa el duelo al ajustar ventajas — ver sliding_adjustment_engine.
  bool get isCreatable => this != BetModuleType.matchAutoPress;
}

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
      case PartidaFormat.allInOnePot: return '1 Pot';
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
  String get label => const {
    BetModuleType.skins:         'Skins',
    BetModuleType.nassau:        'Nassau',  // con o sin press (pressEnabled)
    BetModuleType.matchAutoPress:'Match + Press',
    BetModuleType.medal:         'Medal',
    BetModuleType.putts:         'Putts',
    BetModuleType.oyeses:        'Oyes',
    BetModuleType.units:         'Unidades',
    BetModuleType.nassauLowHigh: 'Bola Baja / Bola Alta',
  }[this]!;

  String get icon => const {
    BetModuleType.skins:         '🎯',
    BetModuleType.nassau:        '🏌️',  // ícono unificado
    BetModuleType.matchAutoPress:'⚔️',
    BetModuleType.medal:         '🥇',
    BetModuleType.putts:         '⛳',
    BetModuleType.oyeses:        '🌟',
    BetModuleType.units:         '💫',
    BetModuleType.nassauLowHigh: '⚖️',
  }[this]!;

  String get description => const {
    BetModuleType.skins:         'Cada hoyo vale una skin. Empates acumulan.',
    BetModuleType.nassau:        'Front 9, Back 9 y Total 18. Activa presiones automáticas opcionalmente.',
    BetModuleType.matchAutoPress:'Match principal + presiones automáticas al llegar a X up.',
    BetModuleType.medal:         'Score neto total más bajo gana.',
    BetModuleType.putts:         'Menor cantidad de putts por segmento.',
    BetModuleType.oyeses:        'Ranking en par 3s. El más cercano cobra.',
    BetModuleType.units:         'Eagles, birdies, sandy pars y más.',
    BetModuleType.nassauLowHigh: '2 vs 2. Cada hoyo reparte un punto por la bola baja y otro por la alta.',
  }[this]!;
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
    teamMemberIds: j['teamMemberIds'] != null ? List<String>.from(j['teamMemberIds'] as List) : [],
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

// ── MatchAutoPressConfig ─────────────────────────────────────────────────────
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

// Configuración para el juego Match + Press Automático.
// Un match principal (Press #1) más presiones que se abren dinámicamente
// cuando el score del match principal alcanza abs(score) == pressTriggerValue.
class MatchAutoPressConfig {
  final double matchValue;        // valor del match principal (Press #1)
  final double pressValue;        // valor de cada presión adicional
  final int pressTriggerValue;    // cuántos hoyos de diferencia disparan una nueva presión
  final GrossNetMode mode;        // gross o net
  final TieRule tieRule;          // push por defecto
  final bool allowMultiplePresses;// permite más de una presión simultánea
  final int? maxPresses;          // máximo de presiones (null = ilimitado)
  // ── Carry ────────────────────────────────────────────────────────────────────
  // Cuando un jugador pide carry al terminar la primera vuelta:
  // - el matchValue se multiplica por carryFactor (default 2×)
  // - todas las presiones activas y futuras también se multiplican
  // carryByPair: clave = pairKey(p1Id, p2Id), valor = factor aplicado
  // Permite que cada duelo dentro de un grupo tenga su propio carry
  // sin afectar a otros duelos que compartan el módulo.
  final Map<String, double> carryByPair; // clave: pairKey(id1,id2) → carryFactor

  // Deprecated fields kept for backwards-compat / migration
  final bool carryApplied;        // legacy: true cuando el carry fue aceptado (grupo de 2)
  final double carryFactor;       // legacy: multiplicador del carry (default 2.0)

  const MatchAutoPressConfig({
    this.matchValue = 100,
    this.pressValue = 50,
    this.pressTriggerValue = 2,
    this.mode = GrossNetMode.net,
    this.tieRule = TieRule.push,
    this.allowMultiplePresses = true,
    this.maxPresses,
    this.carryApplied = false,
    this.carryFactor = 2.0,
    this.carryByPair = const {},
  });

  // Helper: clave canónica del par (IDs ordenados, separados por '|')
  static String pairKey(String id1, String id2) {
    final sorted = [id1, id2]..sort();
    return '${sorted[0]}|${sorted[1]}';
  }

  // ¿Tiene carry activo para este par específico?
  bool carryAppliedForPair(String id1, String id2) {
    final key = pairKey(id1, id2);
    if (carryByPair.containsKey(key)) return true;
    // Retrocompatibilidad: si carryApplied global y no hay carryByPair, se aplica a todos los pares
    if (carryApplied && carryByPair.isEmpty) return true;
    return false;
  }

  // Factor de carry para este par específico
  double carryFactorForPair(String id1, String id2) {
    final key = pairKey(id1, id2);
    return carryByPair[key] ?? (carryApplied && carryByPair.isEmpty ? carryFactor : 1.0);
  }

  MatchAutoPressConfig copyWith({
    double? matchValue, double? pressValue, int? pressTriggerValue,
    GrossNetMode? mode, TieRule? tieRule,
    bool? allowMultiplePresses, int? maxPresses,
    bool? carryApplied, double? carryFactor,
    Map<String, double>? carryByPair,
  }) => MatchAutoPressConfig(
    matchValue:          matchValue         ?? this.matchValue,
    pressValue:          pressValue         ?? this.pressValue,
    pressTriggerValue:   pressTriggerValue  ?? this.pressTriggerValue,
    mode:                mode               ?? this.mode,
    tieRule:             tieRule            ?? this.tieRule,
    allowMultiplePresses:allowMultiplePresses ?? this.allowMultiplePresses,
    maxPresses:          maxPresses         ?? this.maxPresses,
    carryApplied:        carryApplied       ?? this.carryApplied,
    carryFactor:         carryFactor        ?? this.carryFactor,
    carryByPair:         carryByPair        ?? this.carryByPair,
  );

  Map<String, dynamic> toJson() => {
    'matchValue':          matchValue,
    'pressValue':          pressValue,
    'pressTriggerValue':   pressTriggerValue,
    'mode':                mode.name,
    'tieRule':             tieRule.name,
    'allowMultiplePresses':allowMultiplePresses,
    if (maxPresses != null) 'maxPresses': maxPresses,
    'carryApplied':        carryApplied,
    'carryFactor':         carryFactor,
    if (carryByPair.isNotEmpty) 'carryByPair': carryByPair,
  };

  factory MatchAutoPressConfig.fromJson(Map<String, dynamic> j) {
    // Migrar carryByPair desde JSON
    Map<String, double> carryByPairParsed = {};
    if (j['carryByPair'] != null) {
      final raw = j['carryByPair'] as Map<String, dynamic>;
      carryByPairParsed = raw.map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    return MatchAutoPressConfig(
      matchValue:          (j['matchValue']        as num?)?.toDouble() ?? 100,
      pressValue:          (j['pressValue']        as num?)?.toDouble() ?? 50,
      pressTriggerValue:   (j['pressTriggerValue'] as int?)              ?? 2,
      mode: GrossNetMode.values.firstWhere(
        (e) => e.name == (j['mode'] ?? 'net'), orElse: () => GrossNetMode.net),
      tieRule: TieRule.values.firstWhere(
        (e) => e.name == (j['tieRule'] ?? 'push'), orElse: () => TieRule.push),
      allowMultiplePresses: j['allowMultiplePresses'] as bool? ?? true,
      maxPresses:           j['maxPresses'] as int?,
      carryApplied:         j['carryApplied'] as bool? ?? false,
      carryFactor:          (j['carryFactor'] as num?)?.toDouble() ?? 2.0,
      carryByPair:          carryByPairParsed,
    );
  }

  static const def = MatchAutoPressConfig();
}

// ── PressInstance ─────────────────────────────────────────────────────────────
// Una presión individual dentro de un juego Match + Auto Press.
// Press #1 (sequenceNumber=1) = match principal, isPrimaryMatch=true.
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
  final bool carryEnabled;      // el F9 empatado dobla el valor del B9

  /// Carry aceptado POR PAREJA: clave [carryPairKey], valor el factor.
  ///
  /// En un grupo de cuatro, A puede pedir carry contra B y no contra C.
  /// [carryApplied] es un booleano de módulo entero y no puede expresarlo;
  /// Match + Press ya resolvió este caso y aquí se replica, porque el carry
  /// por pareja tiene el mismo sentido en Nassau.
  ///
  /// Usa el separador '|' a propósito, el mismo que MatchAutoPressConfig: así
  /// migrar un módulo de un tipo al otro es copiar el mapa tal cual. Con
  /// separadores distintos habría que traducir cada clave, y una traducción
  /// fallida no da error — el carry simplemente dejaría de aplicarse.
  final Map<String, double> carryByPair;

  /// Legacy: carry de módulo entero. Se conserva para las rondas guardadas
  /// antes de [carryByPair]; las nuevas ediciones escriben el mapa.
  final bool carryApplied;
  final double carryFactor;     // multiplicador carry (default 2.0)
  // ── Presiones ────────────────────────────────────────────────────────────────
  // pressEnabled=false → Nassau clásico sin presiones
  // pressEnabled=true  → presiones automáticas por segmento
  final bool pressEnabled;
  final int autoPressTrigger;       // down-gap que dispara un press (default 2)
  final double frontPressValue;     // valor de cada press en el F9
  final double backPressValue;      // valor de cada press en el B9
  final bool allowMultiplePresses;  // permite más de un press por segmento
  final int? maxPresses;            // max por segmento (null = ilimitado)

  const NassauConfig({
    this.frontValue           = 50,
    this.backValue            = 50,
    this.totalValue           = 100,
    this.mode                 = GrossNetMode.net,
    this.tieRule              = TieRule.push,
    this.carryEnabled         = false,
    this.carryApplied         = false,
    this.carryFactor          = 2.0,
    this.pressEnabled         = false,
    this.autoPressTrigger     = 2,
    this.frontPressValue      = 50,
    this.backPressValue       = 50,
    this.allowMultiplePresses = true,
    this.maxPresses,
    this.carryByPair = const {},
  });

  /// Clave canónica del par. Mismo formato que [MatchAutoPressConfig.pairKey].
  static String carryPairKey(String id1, String id2) {
    final sorted = [id1, id2]..sort();
    return '${sorted[0]}|${sorted[1]}';
  }

  /// ¿Hay carry activo para esta pareja?
  ///
  /// Si el mapa está vacío se cae al booleano legacy, para que una ronda
  /// guardada antes de [carryByPair] siga comportándose igual.
  bool carryAppliedForPair(String id1, String id2) {
    if (carryByPair.containsKey(carryPairKey(id1, id2))) return true;
    return carryApplied && carryByPair.isEmpty;
  }

  /// Factor de carry de esta pareja. 1.0 = sin carry.
  double carryFactorForPair(String id1, String id2) {
    final key = carryPairKey(id1, id2);
    return carryByPair[key] ??
        (carryApplied && carryByPair.isEmpty ? carryFactor : 1.0);
  }

  NassauConfig copyWith({
    double? frontValue, double? backValue, double? totalValue,
    GrossNetMode? mode, TieRule? tieRule,
    bool? carryEnabled, Map<String, double>? carryByPair,
    bool? carryApplied, double? carryFactor,
    bool? pressEnabled, int? autoPressTrigger,
    double? frontPressValue, double? backPressValue,
    bool? allowMultiplePresses, int? maxPresses,
  }) => NassauConfig(
    frontValue:           frontValue           ?? this.frontValue,
    backValue:            backValue            ?? this.backValue,
    totalValue:           totalValue           ?? this.totalValue,
    mode:                 mode                 ?? this.mode,
    tieRule:              tieRule              ?? this.tieRule,
    carryEnabled:         carryEnabled         ?? this.carryEnabled,
    carryApplied:         carryApplied         ?? this.carryApplied,
    carryByPair:          carryByPair          ?? this.carryByPair,
    carryFactor:          carryFactor          ?? this.carryFactor,
    pressEnabled:         pressEnabled         ?? this.pressEnabled,
    autoPressTrigger:     autoPressTrigger     ?? this.autoPressTrigger,
    frontPressValue:      frontPressValue      ?? this.frontPressValue,
    backPressValue:       backPressValue       ?? this.backPressValue,
    allowMultiplePresses: allowMultiplePresses ?? this.allowMultiplePresses,
    maxPresses:           maxPresses           ?? this.maxPresses,
  );

  // Valores efectivos considerando carry
  double get effectiveBackValue      => carryApplied ? backValue      * carryFactor : backValue;
  double get effectiveTotalValue     => carryApplied ? totalValue     * carryFactor : totalValue;
  double get effectiveBackPressValue => carryApplied ? backPressValue * carryFactor : backPressValue;

  Map<String, dynamic> toJson() => {
    'frontValue':           frontValue,
    'backValue':            backValue,
    'totalValue':           totalValue,
    'mode':                 mode.name,
    'tieRule':              tieRule.name,
    'carryEnabled':         carryEnabled,
    'carryApplied':         carryApplied,
    if (carryByPair.isNotEmpty) 'carryByPair': carryByPair,
    'carryFactor':          carryFactor,
    'pressEnabled':         pressEnabled,
    'autoPressTrigger':     autoPressTrigger,
    'frontPressValue':      frontPressValue,
    'backPressValue':       backPressValue,
    'allowMultiplePresses': allowMultiplePresses,
    if (maxPresses != null) 'maxPresses': maxPresses,
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
      carryApplied:         j['carryApplied']         as bool? ?? false,
      carryByPair: (j['carryByPair'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble())) ??
          const {},
      carryFactor:          (j['carryFactor']         as num?)?.toDouble() ?? 2.0,
      pressEnabled:         j['pressEnabled']         as bool? ?? false,
      // retrocompat: autoPressTrigger también puede venir como pressTriggerValue
      autoPressTrigger:     (j['autoPressTrigger']    as int?)
                         ?? (j['pressTriggerValue']   as int?) ?? 2,
      // retrocompat: frontPressValue puede venir del antiguo NassauPressConfig
      frontPressValue:      (j['frontPressValue']     as num?)?.toDouble() ?? front,
      backPressValue:       (j['backPressValue']      as num?)?.toDouble() ?? back,
      allowMultiplePresses: j['allowMultiplePresses'] as bool? ?? true,
      maxPresses:           j['maxPresses']           as int?,
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
    eligibleHoles: j['eligibleHoles'] != null
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
  final MatchAutoPressConfig? matchAutoPressConfig;
  final MedalConfig?          medalConfig;
  final PuttsConfig?          puttsConfig;
  final OyesesConfig?         oyesesConfig;
  final UnitsConfig?          unitsConfig;

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
    this.matchAutoPressConfig,
    this.medalConfig,
    this.puttsConfig,
    this.oyesesConfig,
    this.unitsConfig,
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
  MatchAutoPressConfig get matchAutoPress => matchAutoPressConfig ?? MatchAutoPressConfig.def;
  MedalConfig          get medal          => medalConfig          ?? MedalConfig.def;
  PuttsConfig          get putts          => puttsConfig          ?? PuttsConfig.def;
  OyesesConfig         get oyeses         => oyesesConfig         ?? OyesesConfig.def;
  UnitsConfig          get units          => unitsConfig          ?? UnitsConfig.def;

  // ── Compatibilidad con BetEngine (valor base y flags) ──────────────────────
  double get value => switch (type) {
    BetModuleType.skins         => skins.valuePerSkin,
    BetModuleType.nassau        => nassau.frontValue,
    BetModuleType.matchAutoPress=> matchAutoPress.matchValue,
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
    BetModuleType.matchAutoPress=> matchAutoPress.mode == GrossNetMode.net,
    BetModuleType.medal         => medal.mode == GrossNetMode.net,
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
    BetModuleType.skins  => '\$${skins.valuePerSkin.toStringAsFixed(0)}/skin'
                            '${skins.carryOver ? ' · carry 🔥' : ''}'
                            ' · ${skins.mode == GrossNetMode.net ? 'Net' : 'Gross'}',
    BetModuleType.nassau => 'F\$${nassau.frontValue.toStringAsFixed(0)}'
                            ' B\$${nassau.backValue.toStringAsFixed(0)}'
                            ' T\$${nassau.totalValue.toStringAsFixed(0)}'
                            '${nassau.pressEnabled ? ' · Press ⚡' : ''}'
                            '${nassau.carryEnabled ? ' · Carry' : ''}',
    BetModuleType.matchAutoPress =>
                            'Match \$${matchAutoPress.matchValue.toStringAsFixed(0)}'
                            ' · Press \$${matchAutoPress.pressValue.toStringAsFixed(0)}'
                            ' · trigger ${matchAutoPress.pressTriggerValue}up',
    BetModuleType.medal  => '\$${medal.value.toStringAsFixed(0)}'
                            ' · ${medal.holes}H'
                            ' · ${medal.mode == GrossNetMode.net ? 'Net' : 'Gross'}',
    BetModuleType.putts  => '\$${putts.value.toStringAsFixed(0)}'
                            '${putts.threePuttPenalty ? ' · 3-putt' : ''}',
    BetModuleType.oyeses => '\$${oyeses.value.toStringAsFixed(0)}/oyés'
                            '${oyeses.zapatoEnabled ? ' · zapato 👟' : ''}',
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
    String? name,
    List<String>? participantIds,
    List<BetSide>? sides,
    bool clearSides = false,
    BetModuleStatus? status,
    BetFormatMode?        formatMode,
    SkinsConfig?          skinsConfig,
    NassauConfig?         nassauConfig,
    NassauLowHighConfig?  nassauLowHighConfig,
    MatchAutoPressConfig? matchAutoPressConfig,
    MedalConfig?          medalConfig,
    PuttsConfig?          puttsConfig,
    OyesesConfig?         oyesesConfig,
    UnitsConfig?          unitsConfig,
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
    id: id, type: type,
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
    matchAutoPressConfig: matchAutoPressConfig ?? this.matchAutoPressConfig,
    medalConfig:          medalConfig          ?? this.medalConfig,
    puttsConfig:          puttsConfig          ?? this.puttsConfig,
    oyesesConfig:         oyesesConfig         ?? this.oyesesConfig,
    unitsConfig:          unitsConfig          ?? this.unitsConfig,
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
    if (matchAutoPressConfig != null) 'matchAutoPressConfig': matchAutoPressConfig!.toJson(),
    if (medalConfig          != null) 'medalConfig':          medalConfig!.toJson(),
    if (puttsConfig          != null) 'puttsConfig':          puttsConfig!.toJson(),
    if (oyesesConfig         != null) 'oyesesConfig':         oyesesConfig!.toJson(),
    if (unitsConfig          != null) 'unitsConfig':          unitsConfig!.toJson(),
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
            carryApplied:         np['carryApplied']         as bool? ?? false,
            carryFactor:          (np['carryFactor']         as num?)?.toDouble() ?? 2.0,
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
      matchAutoPressConfig: j['matchAutoPressConfig'] != null ? MatchAutoPressConfig.fromJson(asMap(j['matchAutoPressConfig'])) : null,
      medalConfig:          j['medalConfig']          != null ? MedalConfig.fromJson(asMap(j['medalConfig']))          : null,
      puttsConfig:          j['puttsConfig']          != null ? PuttsConfig.fromJson(asMap(j['puttsConfig']))          : null,
      oyesesConfig:         j['oyesesConfig']         != null ? OyesesConfig.fromJson(asMap(j['oyesesConfig']))        : null,
      unitsConfig:          j['unitsConfig']          != null ? UnitsConfig.fromJson(asMap(j['unitsConfig']))          : null,
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
        matchAutoPressConfig:  matchAutoPressConfig,
        medalConfig:           medalConfig,
        puttsConfig:           puttsConfig,
        oyesesConfig:          oyesesConfig,
        unitsConfig:           unitsConfig,
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
      BetModuleType.skins          => skins.toJson(),
      BetModuleType.nassau         => nassau.toJson(),
      BetModuleType.matchAutoPress => matchAutoPress.toJson(),
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
        BetModuleType.medal =>
          'value',
        _ => null,
      };

  /// true si este tipo de módulo soporta override de valor por duelo.
  bool get supportsPlayerOverride =>
      type == BetModuleType.skins   ||
      type == BetModuleType.oyeses  ||
      type == BetModuleType.units   ||
      type == BetModuleType.putts   ||
      type == BetModuleType.medal;

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
      matchAutoPressConfig: type == BetModuleType.matchAutoPress? MatchAutoPressConfig.def : null,
      medalConfig:          type == BetModuleType.medal         ? MedalConfig.def          : null,
      puttsConfig:          type == BetModuleType.putts         ? PuttsConfig.def          : null,
      oyesesConfig:         type == BetModuleType.oyeses        ? OyesesConfig.def         : null,
      unitsConfig:          type == BetModuleType.units         ? UnitsConfig.def          : null,
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
    MatchAutoPressConfig? matchAutoPressConfig,
    MedalConfig?          medalConfig,
    PuttsConfig?          puttsConfig,
    OyesesConfig?         oyesesConfig,
    UnitsConfig?          unitsConfig,
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
        matchAutoPressConfig: matchAutoPressConfig ?? (type == BetModuleType.matchAutoPress? MatchAutoPressConfig.def : null),
        medalConfig:          medalConfig          ?? (type == BetModuleType.medal         ? MedalConfig.def          : null),
        puttsConfig:          puttsConfig          ?? (type == BetModuleType.putts         ? PuttsConfig.def          : null),
        oyesesConfig:         oyesesConfig         ?? (type == BetModuleType.oyeses        ? OyesesConfig.def         : null),
        unitsConfig:          unitsConfig          ?? (type == BetModuleType.units         ? UnitsConfig.def          : null),
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
        matchAutoPressConfig: matchAutoPressConfig ?? (type == BetModuleType.matchAutoPress? MatchAutoPressConfig.def : null),
        medalConfig:          medalConfig          ?? (type == BetModuleType.medal         ? MedalConfig.def          : null),
        puttsConfig:          puttsConfig          ?? (type == BetModuleType.putts         ? PuttsConfig.def          : null),
        oyesesConfig:         oyesesConfig         ?? (type == BetModuleType.oyeses        ? OyesesConfig.def         : null),
        unitsConfig:          unitsConfig          ?? (type == BetModuleType.units         ? UnitsConfig.def          : null),
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

  const BetGroup({
    required this.id, required this.name,
    required this.format, required this.playerIds, required this.modules,
  });

  BetGroup copyWith({List<BetModuleInstance>? modules, List<String>? playerIds}) => BetGroup(
    id: id, name: name, format: format,
    playerIds: playerIds ?? this.playerIds,
    modules: modules ?? this.modules,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'format': format.name,
    'playerIds': playerIds,
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
      modules: (j['modules'] is List ? (j['modules'] as List) : []).map((m) {
        final map = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
        // Detectar si es formato legacy (BetModule antiguo) o nuevo (BetModuleInstance)
        try {
          if (map.containsKey('skinsConfig') || map.containsKey('nassauConfig') ||
              map.containsKey('medalConfig') || map.containsKey('puttsConfig') ||
              map.containsKey('oyesesConfig') || map.containsKey('unitsConfig') ||
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

  Round({
    required this.id, required this.name, required this.course,
    required this.players, required this.roundPlayers,
    required this.betGroups, required this.scores,
    required this.events, required this.oyeseRankings,
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
  }) : pairSliding = pairSliding ?? const {},
       pendingProposals = pendingProposals ?? const [];

  HoleScore getScore(String playerId, int hole) =>
      scores[playerId]?[hole] ?? HoleScore(playerId: playerId, hole: hole);

  List<HoleEvent> getEvents(String playerId, int hole) =>
      events[playerId]?[hole] ?? [];

  OyeseRanking? getOyese(int hole) => oyeseRankings[hole];

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
          : mod.effectivePids(groupPlayerIds);

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
  }) => Round(
    id: id, name: name, course: course,
    players: players ?? this.players,
    roundPlayers: roundPlayers ?? this.roundPlayers,
    betGroups: betGroups ?? this.betGroups,
    scores: scores ?? this.scores,
    events: events ?? this.events,
    oyeseRankings: oyeseRankings ?? this.oyeseRankings,
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
  final MatchAutoPressConfig?    matchAutoPressConfig;
  final MedalConfig?             medalConfig;
  final PuttsConfig?             puttsConfig;
  final OyesesConfig?            oyesesConfig;
  final UnitsConfig?             unitsConfig;
  final NassauLowHighConfig?     nassauLowHighConfig;

  const BetModuleTemplate({
    required this.type,
    this.formatMode  = BetFormatMode.allVsAll,
    this.skinsConfig,
    this.nassauConfig,
    this.matchAutoPressConfig,
    this.medalConfig,
    this.puttsConfig,
    this.oyesesConfig,
    this.unitsConfig,
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

  /// Etiqueta corta del valor principal.
  String get summaryLabel {
    switch (type) {
      case BetModuleType.skins:
        return '\$${skins.valuePerSkin.toStringAsFixed(0)}/skin';
      case BetModuleType.nassau:
        final n = nassau;
        return 'F\$${n.frontValue.toStringAsFixed(0)}·'
               'B\$${n.backValue.toStringAsFixed(0)}·'
               'T\$${n.totalValue.toStringAsFixed(0)}';
      case BetModuleType.matchAutoPress:
        return '\$…/hoyo';
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
    matchAutoPressConfig: t == BetModuleType.matchAutoPress? MatchAutoPressConfig()   : null,
    medalConfig:          t == BetModuleType.medal         ? MedalConfig.def          : null,
    puttsConfig:          t == BetModuleType.putts         ? PuttsConfig.def          : null,
    oyesesConfig:         t == BetModuleType.oyeses        ? OyesesConfig.def         : null,
    unitsConfig:          t == BetModuleType.units         ? UnitsConfig.def          : null,
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
    matchAutoPressConfig: matchAutoPressConfig,
    medalConfig:          medalConfig,
    puttsConfig:          puttsConfig,
    oyesesConfig:         oyesesConfig,
    unitsConfig:          unitsConfig,
    betGroupId:           betGroupId,
    betGroupName:         betGroupName,
    structure:            BetStructure.headToHead,
  );

  BetModuleTemplate copyWith({
    BetModuleType?         type,
    BetFormatMode?         formatMode,
    SkinsConfig?           skinsConfig,
    NassauConfig?          nassauConfig,
    MatchAutoPressConfig?  matchAutoPressConfig,
    MedalConfig?           medalConfig,
    PuttsConfig?           puttsConfig,
    OyesesConfig?          oyesesConfig,
    UnitsConfig?           unitsConfig,
  }) => BetModuleTemplate(
    type:                  type                 ?? this.type,
    formatMode:            formatMode           ?? this.formatMode,
    skinsConfig:           skinsConfig          ?? this.skinsConfig,
    nassauConfig:          nassauConfig         ?? this.nassauConfig,
    matchAutoPressConfig:  matchAutoPressConfig ?? this.matchAutoPressConfig,
    medalConfig:           medalConfig          ?? this.medalConfig,
    puttsConfig:           puttsConfig          ?? this.puttsConfig,
    oyesesConfig:          oyesesConfig         ?? this.oyesesConfig,
    unitsConfig:           unitsConfig          ?? this.unitsConfig,
  );

  Map<String, dynamic> toJson() => {
    'type':                  type.name,
    'formatMode':            formatMode.name,
    if (skinsConfig          != null) 'skinsConfig':          skinsConfig!.toJson(),
    if (nassauConfig         != null) 'nassauConfig':         nassauConfig!.toJson(),
    if (matchAutoPressConfig != null) 'matchAutoPressConfig': matchAutoPressConfig!.toJson(),
    if (medalConfig          != null) 'medalConfig':          medalConfig!.toJson(),
    if (puttsConfig          != null) 'puttsConfig':          puttsConfig!.toJson(),
    if (oyesesConfig         != null) 'oyesesConfig':         oyesesConfig!.toJson(),
    if (unitsConfig          != null) 'unitsConfig':          unitsConfig!.toJson(),
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
      matchAutoPressConfig: j['matchAutoPressConfig'] != null
          ? MatchAutoPressConfig.fromJson(Map<String, dynamic>.from(j['matchAutoPressConfig'] as Map)) : null,
      medalConfig: j['medalConfig'] != null
          ? MedalConfig.fromJson(Map<String, dynamic>.from(j['medalConfig'] as Map)) : null,
      puttsConfig: j['puttsConfig'] != null
          ? PuttsConfig.fromJson(Map<String, dynamic>.from(j['puttsConfig'] as Map)) : null,
      oyesesConfig: j['oyesesConfig'] != null
          ? OyesesConfig.fromJson(Map<String, dynamic>.from(j['oyesesConfig'] as Map)) : null,
      unitsConfig: j['unitsConfig'] != null
          ? UnitsConfig.fromJson(Map<String, dynamic>.from(j['unitsConfig'] as Map)) : null,
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
        matchAutoPressConfig:  inst.matchAutoPressConfig,
        medalConfig:           inst.medalConfig,
        puttsConfig:           inst.puttsConfig,
        oyesesConfig:          inst.oyesesConfig,
        unitsConfig:           inst.unitsConfig,
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
  final DateTime        updatedAt;

  const BettingGroup({
    required this.id,
    required this.name,
    this.description,
    this.emoji        = '⛳',
    this.playerIds    = const [],
    this.pairRules    = const [],
    required this.updatedAt,
  });

  /// Número de reglas que tienen al menos un módulo configurado.
  int get activeRulesCount =>
      pairRules.where((r) => r.modules.isNotEmpty).length;

  /// Número total de módulos de apuesta en el grupo.
  int get totalModules =>
      pairRules.fold(0, (sum, r) => sum + r.modules.length);

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
    DateTime?           updatedAt,
  }) => BettingGroup(
    id:          id          ?? this.id,
    name:        name        ?? this.name,
    description: description ?? this.description,
    emoji:       emoji       ?? this.emoji,
    playerIds:   playerIds   ?? this.playerIds,
    pairRules:   pairRules   ?? this.pairRules,
    updatedAt:   updatedAt   ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id':          id,
    'name':        name,
    if (description != null) 'description': description,
    'emoji':       emoji,
    'playerIds':   playerIds,
    'pairRules':   pairRules.map((r) => r.toJson()).toList(),
    'updatedAt':   updatedAt.toIso8601String(),
  };

  factory BettingGroup.fromJson(Map<String, dynamic> j) => BettingGroup(
    id:          (j['id']   as String?) ?? '',
    name:        (j['name'] as String?) ?? 'Grupo',
    description: j['description'] as String?,
    emoji:       (j['emoji'] as String?) ?? '⛳',
    playerIds:   (j['playerIds'] as List? ?? [])
        .map((e) => e as String)
        .toList(),
    pairRules:   (j['pairRules'] as List? ?? [])
        .map((r) => PairBetRule.fromJson(
            Map<String, dynamic>.from(r as Map)))
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
