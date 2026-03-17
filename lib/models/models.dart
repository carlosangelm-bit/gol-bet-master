// ─────────────────────────────────────────────────────────────────────────────
// MODELOS DE DATOS — v4
// Entidades: Round, Player, RoundPlayer, CourseHole, HoleScore,
//            HoleEvent, OyeseRanking, BetModuleInstance (con config tipada),
//            BetGroup, LedgerEntry, SlidingRelation
// ─────────────────────────────────────────────────────────────────────────────

// ── Enums ─────────────────────────────────────────────────────────────────────
enum BetModuleType { skins, nassau, matchAutoPress, medal, putts, oyeses, units }
enum UnitEventType { birdie, eagle, sandyPar, parUnico, birdieUnico, holeOut }
enum PartidaFormat { allInOnePot, oneVsOne, groupVsGroup }

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

extension BetModuleLabel on BetModuleType {
  String get label => const {
    BetModuleType.skins:         'Skins',
    BetModuleType.nassau:        'Nassau',
    BetModuleType.matchAutoPress:'Match + Press',
    BetModuleType.medal:         'Medal',
    BetModuleType.putts:         'Putts',
    BetModuleType.oyeses:        'Oyeses',
    BetModuleType.units:         'Units',
  }[this]!;

  String get icon => const {
    BetModuleType.skins:         '🎯',
    BetModuleType.nassau:        '🏌️',
    BetModuleType.matchAutoPress:'⚔️',
    BetModuleType.medal:         '🥇',
    BetModuleType.putts:         '⛳',
    BetModuleType.oyeses:        '🌟',
    BetModuleType.units:         '💫',
  }[this]!;

  String get description => const {
    BetModuleType.skins:         'Cada hoyo vale una skin. Empates acumulan.',
    BetModuleType.nassau:        'Front 9, Back 9 y Total 18 independientes.',
    BetModuleType.matchAutoPress:'Match principal + presiones automáticas al llegar a X up.',
    BetModuleType.medal:         'Score neto total más bajo gana.',
    BetModuleType.putts:         'Menor cantidad de putts por segmento.',
    BetModuleType.oyeses:        'Ranking en par 3s. El más cercano cobra.',
    BetModuleType.units:         'Eagles, birdies, sandy pars y más.',
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
    hole: (j['hole'] as num).toInt(),
    par:  (j['par']  as num).toInt(),
    strokeIndex: (j['strokeIndex'] as num).toInt(),
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
    name:  j['name'] as String,
    holes: (j['holes'] as List).map((h) => CourseHole.fromJson(h as Map<String, dynamic>)).toList(),
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

  Player({required this.id, required this.name, this.handicapBase = 0, this.colorIndex = 0});

  Player copyWith({String? name, double? handicapBase, int? colorIndex}) => Player(
    id: id, name: name ?? this.name,
    handicapBase: handicapBase ?? this.handicapBase,
    colorIndex: colorIndex ?? this.colorIndex,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'handicapBase': handicapBase, 'colorIndex': colorIndex};
  factory Player.fromJson(Map<String, dynamic> j) => Player(
    id: j['id'] as String, name: j['name'] as String,
    handicapBase: (j['handicapBase'] as num).toDouble(),
    colorIndex: (j['colorIndex'] as int?) ?? 0,
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
    playerId:        j['playerId'] as String,
    handicapEnRonda: (j['handicapEnRonda'] as num).toDouble(),
    tee: j['tee'] != null
        ? TeeInfo.fromJson(j['tee'] as Map<String, dynamic>)
        : TeeInfo.standard,
    manualHandicaps: (j['manualHandicaps'] as Map<String, dynamic>?)
        ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? const {},
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
    playerId: j['playerId'] as String, hole: j['hole'] as int,
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
    playerId: j['playerId'] as String, hole: j['hole'] as int,
    type: UnitEventType.values.firstWhere((t) => t.name == j['type']),
  );
}

// ── OyeseRanking ─────────────────────────────────────────────────────────────
class OyeseRanking {
  final int hole;
  final List<String> ranking;
  OyeseRanking({required this.hole, required this.ranking});

  Map<String, dynamic> toJson() => {'hole': hole, 'ranking': ranking};
  factory OyeseRanking.fromJson(Map<String, dynamic> j) => OyeseRanking(
    hole: j['hole'] as int,
    ranking: List<String>.from(j['ranking'] as List),
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

  const MatchAutoPressConfig({
    this.matchValue = 100,
    this.pressValue = 50,
    this.pressTriggerValue = 2,
    this.mode = GrossNetMode.net,
    this.tieRule = TieRule.push,
    this.allowMultiplePresses = true,
    this.maxPresses,
  });

  MatchAutoPressConfig copyWith({
    double? matchValue, double? pressValue, int? pressTriggerValue,
    GrossNetMode? mode, TieRule? tieRule,
    bool? allowMultiplePresses, int? maxPresses,
  }) => MatchAutoPressConfig(
    matchValue:          matchValue         ?? this.matchValue,
    pressValue:          pressValue         ?? this.pressValue,
    pressTriggerValue:   pressTriggerValue  ?? this.pressTriggerValue,
    mode:                mode               ?? this.mode,
    tieRule:             tieRule            ?? this.tieRule,
    allowMultiplePresses:allowMultiplePresses ?? this.allowMultiplePresses,
    maxPresses:          maxPresses         ?? this.maxPresses,
  );

  Map<String, dynamic> toJson() => {
    'matchValue':          matchValue,
    'pressValue':          pressValue,
    'pressTriggerValue':   pressTriggerValue,
    'mode':                mode.name,
    'tieRule':             tieRule.name,
    'allowMultiplePresses':allowMultiplePresses,
    if (maxPresses != null) 'maxPresses': maxPresses,
  };

  factory MatchAutoPressConfig.fromJson(Map<String, dynamic> j) => MatchAutoPressConfig(
    matchValue:          (j['matchValue']        as num?)?.toDouble() ?? 100,
    pressValue:          (j['pressValue']        as num?)?.toDouble() ?? 50,
    pressTriggerValue:   (j['pressTriggerValue'] as int?)              ?? 2,
    mode: GrossNetMode.values.firstWhere(
      (e) => e.name == (j['mode'] ?? 'net'), orElse: () => GrossNetMode.net),
    tieRule: TieRule.values.firstWhere(
      (e) => e.name == (j['tieRule'] ?? 'push'), orElse: () => TieRule.push),
    allowMultiplePresses: j['allowMultiplePresses'] as bool? ?? true,
    maxPresses:           j['maxPresses'] as int?,
  );

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
    id:             j['id']             as String,
    betModuleId:    j['betModuleId']    as String,
    sequenceNumber: j['sequenceNumber'] as int,
    isPrimaryMatch: j['isPrimaryMatch'] as bool? ?? false,
    startHole:      j['startHole']      as int,
    value:          (j['value']         as num).toDouble(),
    endHole:        j['endHole']        as int?,
    status: PressStatus.values.firstWhere(
      (s) => s.name == (j['status'] ?? 'open'), orElse: () => PressStatus.open),
    winnerPlayerId: j['winnerPlayerId'] as String?,
    resultLabel:    j['resultLabel']    as String?,
  );
}

// ── NassauConfig ──────────────────────────────────────────────────────────────
class NassauConfig {
  final double frontValue;
  final double backValue;
  final double totalValue;
  final GrossNetMode mode;
  final bool pressEnabled;
  final PressMode pressMode;    // manual | auto
  final int autoPressTrigger;   // activar press cuando vas X down
  final TieRule tieRule;

  const NassauConfig({
    this.frontValue = 50,
    this.backValue = 50,
    this.totalValue = 100,
    this.mode = GrossNetMode.net,
    this.pressEnabled = false,
    this.pressMode = PressMode.auto,
    this.autoPressTrigger = 2,
    this.tieRule = TieRule.push,
  });

  NassauConfig copyWith({
    double? frontValue, double? backValue, double? totalValue,
    GrossNetMode? mode, bool? pressEnabled, PressMode? pressMode,
    int? autoPressTrigger, TieRule? tieRule,
  }) => NassauConfig(
    frontValue: frontValue ?? this.frontValue,
    backValue: backValue ?? this.backValue,
    totalValue: totalValue ?? this.totalValue,
    mode: mode ?? this.mode,
    pressEnabled: pressEnabled ?? this.pressEnabled,
    pressMode: pressMode ?? this.pressMode,
    autoPressTrigger: autoPressTrigger ?? this.autoPressTrigger,
    tieRule: tieRule ?? this.tieRule,
  );

  Map<String, dynamic> toJson() => {
    'frontValue': frontValue, 'backValue': backValue, 'totalValue': totalValue,
    'mode': mode.name, 'pressEnabled': pressEnabled,
    'pressMode': pressMode.name, 'autoPressTrigger': autoPressTrigger,
    'tieRule': tieRule.name,
  };
  factory NassauConfig.fromJson(Map<String, dynamic> j) => NassauConfig(
    frontValue: (j['frontValue'] as num?)?.toDouble() ?? 50,
    backValue:  (j['backValue']  as num?)?.toDouble() ?? 50,
    totalValue: (j['totalValue'] as num?)?.toDouble() ?? 100,
    mode: GrossNetMode.values.firstWhere((e) => e.name == (j['mode'] ?? 'net'), orElse: () => GrossNetMode.net),
    pressEnabled: j['pressEnabled'] as bool? ?? false,
    pressMode: PressMode.values.firstWhere((e) => e.name == (j['pressMode'] ?? 'auto'), orElse: () => PressMode.auto),
    autoPressTrigger: j['autoPressTrigger'] as int? ?? 2,
    tieRule: TieRule.values.firstWhere((e) => e.name == (j['tieRule'] ?? 'push'), orElse: () => TieRule.push),
  );
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
    this.zapatoRequires18 = true,
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
    zapatoRequires18: j['zapatoRequires18'] as bool?   ?? true,
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
class BetModuleInstance {
  final String id;
  final BetModuleType type;
  final String name;
  final List<String> participantIds; // subconjunto de jugadores del grupo
  final BetModuleStatus status;

  // Configs tipadas — solo una tendrá valor según el tipo
  final BetFormatMode          formatMode;
  final SkinsConfig?          skinsConfig;
  final NassauConfig?         nassauConfig;
  final MatchAutoPressConfig? matchAutoPressConfig;
  final MedalConfig?          medalConfig;
  final PuttsConfig?          puttsConfig;
  final OyesesConfig?         oyesesConfig;
  final UnitsConfig?          unitsConfig;

  // Presiones dinámicas para Match + Auto Press
  final List<PressInstance> presses;

  const BetModuleInstance({
    required this.id,
    required this.type,
    required this.name,
    required this.participantIds,
    this.status = BetModuleStatus.configured,
    this.formatMode = BetFormatMode.onePot,
    this.skinsConfig,
    this.nassauConfig,
    this.matchAutoPressConfig,
    this.medalConfig,
    this.puttsConfig,
    this.oyesesConfig,
    this.unitsConfig,
    this.presses = const [],
  });

  // ── Acceso rápido a config efectiva ────────────────────────────────────────
  /// true si la apuesta corre en modo todos-contra-todos (pares)
  bool get isAllVsAll => formatMode == BetFormatMode.allVsAll;

  SkinsConfig          get skins          => skinsConfig          ?? SkinsConfig.def;
  NassauConfig         get nassau         => nassauConfig         ?? NassauConfig.def;
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
  };

  bool get useHandicap => switch (type) {
    BetModuleType.skins         => skins.mode == GrossNetMode.net,
    BetModuleType.nassau        => nassau.mode == GrossNetMode.net,
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
                            '${nassau.pressEnabled ? ' · Press' : ''}',
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
    BetModuleType.units  => '\$${units.valueFor(UnitEventType.birdie).toStringAsFixed(0)}/unit · ${UnitEventType.values.length} eventos',
  };

  // ── copyWith ──────────────────────────────────────────────────────────────
  BetModuleInstance copyWith({
    String? name,
    List<String>? participantIds,
    BetModuleStatus? status,
    BetFormatMode?        formatMode,
    SkinsConfig?          skinsConfig,
    NassauConfig?         nassauConfig,
    MatchAutoPressConfig? matchAutoPressConfig,
    MedalConfig?          medalConfig,
    PuttsConfig?          puttsConfig,
    OyesesConfig?         oyesesConfig,
    UnitsConfig?          unitsConfig,
    List<PressInstance>?  presses,
  }) => BetModuleInstance(
    id: id, type: type,
    name: name ?? this.name,
    participantIds: participantIds ?? this.participantIds,
    status: status ?? this.status,
    formatMode:           formatMode           ?? this.formatMode,
    skinsConfig:          skinsConfig          ?? this.skinsConfig,
    nassauConfig:         nassauConfig         ?? this.nassauConfig,
    matchAutoPressConfig: matchAutoPressConfig ?? this.matchAutoPressConfig,
    medalConfig:          medalConfig          ?? this.medalConfig,
    puttsConfig:          puttsConfig          ?? this.puttsConfig,
    oyesesConfig:         oyesesConfig         ?? this.oyesesConfig,
    unitsConfig:          unitsConfig          ?? this.unitsConfig,
    presses:              presses              ?? this.presses,
  );

  // ── JSON ──────────────────────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'id': id, 'type': type.name, 'name': name,
    'participantIds': participantIds,
    'status': status.name,
    'formatMode': formatMode.name,
    if (skinsConfig          != null) 'skinsConfig':          skinsConfig!.toJson(),
    if (nassauConfig         != null) 'nassauConfig':         nassauConfig!.toJson(),
    if (matchAutoPressConfig != null) 'matchAutoPressConfig': matchAutoPressConfig!.toJson(),
    if (medalConfig          != null) 'medalConfig':          medalConfig!.toJson(),
    if (puttsConfig          != null) 'puttsConfig':          puttsConfig!.toJson(),
    if (oyesesConfig         != null) 'oyesesConfig':         oyesesConfig!.toJson(),
    if (unitsConfig          != null) 'unitsConfig':          unitsConfig!.toJson(),
    if (presses.isNotEmpty)           'presses': presses.map((p) => p.toJson()).toList(),
  };

  factory BetModuleInstance.fromJson(Map<String, dynamic> j) {
    final type = BetModuleType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => BetModuleType.skins,
    );
    return BetModuleInstance(
      id:   j['id']   as String,
      type: type,
      name: j['name'] as String? ?? type.label,
      participantIds: List<String>.from(j['participantIds'] as List? ?? []),
      status: BetModuleStatus.values.firstWhere(
          (s) => s.name == (j['status'] ?? 'configured'),
          orElse: () => BetModuleStatus.configured),
      formatMode: BetFormatMode.values.firstWhere(
          (f) => f.name == (j['formatMode'] ?? 'onePot'),
          orElse: () => BetFormatMode.onePot),
      skinsConfig:          j['skinsConfig']          != null ? SkinsConfig.fromJson(j['skinsConfig']          as Map<String, dynamic>) : null,
      nassauConfig:         j['nassauConfig']         != null ? NassauConfig.fromJson(j['nassauConfig']         as Map<String, dynamic>) : null,
      matchAutoPressConfig: j['matchAutoPressConfig'] != null ? MatchAutoPressConfig.fromJson(j['matchAutoPressConfig'] as Map<String, dynamic>) : null,
      medalConfig:          j['medalConfig']          != null ? MedalConfig.fromJson(j['medalConfig']          as Map<String, dynamic>) : null,
      puttsConfig:          j['puttsConfig']          != null ? PuttsConfig.fromJson(j['puttsConfig']          as Map<String, dynamic>) : null,
      oyesesConfig:         j['oyesesConfig']         != null ? OyesesConfig.fromJson(j['oyesesConfig']        as Map<String, dynamic>) : null,
      unitsConfig:          j['unitsConfig']          != null ? UnitsConfig.fromJson(j['unitsConfig']          as Map<String, dynamic>) : null,
      presses: j['presses'] != null
          ? (j['presses'] as List).map((p) => PressInstance.fromJson(p as Map<String, dynamic>)).toList()
          : const [],
    );
  }

  // ── Factory helpers para crear instancias por defecto ─────────────────────
  static BetModuleInstance defaultFor(BetModuleType type, List<String> participantIds, {String? id}) {
    final uuid = id ?? '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
    return BetModuleInstance(
      id: uuid, type: type, name: type.label,
      participantIds: participantIds,
      skinsConfig:          type == BetModuleType.skins         ? SkinsConfig.def          : null,
      nassauConfig:         type == BetModuleType.nassau        ? NassauConfig.def         : null,
      matchAutoPressConfig: type == BetModuleType.matchAutoPress? MatchAutoPressConfig.def : null,
      medalConfig:          type == BetModuleType.medal         ? MedalConfig.def          : null,
      puttsConfig:          type == BetModuleType.putts         ? PuttsConfig.def          : null,
      oyesesConfig:         type == BetModuleType.oyeses        ? OyesesConfig.def         : null,
      unitsConfig:          type == BetModuleType.units         ? UnitsConfig.def          : null,
    );
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
  factory BetGroup.fromJson(Map<String, dynamic> j) => BetGroup(
    id: j['id'] as String, name: j['name'] as String,
    format: PartidaFormat.values.firstWhere((f) => f.name == j['format'],
        orElse: () => PartidaFormat.allInOnePot),
    playerIds: List<String>.from(j['playerIds'] as List),
    modules: (j['modules'] as List).map((m) {
      final map = m as Map<String, dynamic>;
      // Detectar si es formato legacy (BetModule antiguo) o nuevo (BetModuleInstance)
      if (map.containsKey('skinsConfig') || map.containsKey('nassauConfig') ||
          map.containsKey('medalConfig') || map.containsKey('puttsConfig') ||
          map.containsKey('oyesesConfig') || map.containsKey('unitsConfig') ||
          map.containsKey('participantIds')) {
        return BetModuleInstance.fromJson(map);
      } else {
        // Migrar formato legacy
        return _migrateLegacyModule(map, List<String>.from(j['playerIds'] as List));
      }
    }).toList(),
  );

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
  final double defaultSlidingAdjustment; // strokes que este jugador da/recibe por defecto
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
    createdAt: d['createdAt'] != null
        ? DateTime.tryParse(d['createdAt'] as String) ?? DateTime.now()
        : DateTime.now(),
    updatedAt: d['updatedAt'] != null
        ? DateTime.tryParse(d['updatedAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );

  /// Nombre a mostrar: usa customDisplayName si está, sino el del Player global.
  String displayName(String fallback) => customDisplayName?.isNotEmpty == true
      ? customDisplayName!
      : fallback;
}

// ── SlidingRelation ───────────────────────────────────────────────────────────
class SlidingRelation {
  final String playerAId;
  final String playerBId;
  double adjustment;
  SlidingRelation({required this.playerAId, required this.playerBId, this.adjustment = 0});

  Map<String, dynamic> toJson() => {'playerAId': playerAId, 'playerBId': playerBId, 'adjustment': adjustment};
  factory SlidingRelation.fromJson(Map<String, dynamic> j) => SlidingRelation(
    playerAId: j['playerAId'] as String, playerBId: j['playerBId'] as String,
    adjustment: (j['adjustment'] as num).toDouble(),
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
  /// Vuelta de inicio: determina qué mitad lleva el stroke extra (diff impar).
  final StartingNine startingNine;
  /// Total de hoyos de la ronda: 9 o 18 (por defecto 18).
  final int totalHoles;

  Round({
    required this.id, required this.name, required this.course,
    required this.players, required this.roundPlayers,
    required this.betGroups, required this.scores,
    required this.events, required this.oyeseRankings,
    required this.sliding, required this.createdAt,
    this.currentHole = 1, this.isFinished = false,
    this.startingNine = StartingNine.front,
    this.totalHoles = 18,
  });

  HoleScore getScore(String playerId, int hole) =>
      scores[playerId]?[hole] ?? HoleScore(playerId: playerId, hole: hole);

  List<HoleEvent> getEvents(String playerId, int hole) =>
      events[playerId]?[hole] ?? [];

  OyeseRanking? getOyese(int hole) => oyeseRankings[hole];

  double getHandicap(String playerId) =>
      roundPlayers.firstWhere((rp) => rp.playerId == playerId,
          orElse: () => RoundPlayer(playerId: playerId, handicapEnRonda: 0)).handicapEnRonda;

  (int, int) strokesVs(String p1Id, String p2Id) {
    final rp1 = roundPlayers.firstWhere((r) => r.playerId == p1Id,
        orElse: () => RoundPlayer(playerId: p1Id, handicapEnRonda: 0));
    final rp2 = roundPlayers.firstWhere((r) => r.playerId == p2Id,
        orElse: () => RoundPlayer(playerId: p2Id, handicapEnRonda: 0));

    if (rp1.manualHandicaps.containsKey(p2Id)) {
      final diff = rp1.manualHandicaps[p2Id]!.round();
      return diff >= 0 ? (diff, 0) : (0, (-diff));
    }
    final diff = (rp1.handicapEnRonda - rp2.handicapEnRonda).round();
    return diff >= 0 ? (diff, 0) : (0, (-diff));
  }

  Round copyWith({
    Map<String, Map<int, HoleScore>>? scores,
    Map<String, Map<int, List<HoleEvent>>>? events,
    Map<int, OyeseRanking>? oyeseRankings,
    List<BetGroup>? betGroups,
    int? currentHole, bool? isFinished,
    StartingNine? startingNine,
    int? totalHoles,
  }) => Round(
    id: id, name: name, course: course, players: players,
    roundPlayers: roundPlayers,
    betGroups: betGroups ?? this.betGroups,
    scores: scores ?? this.scores,
    events: events ?? this.events,
    oyeseRankings: oyeseRankings ?? this.oyeseRankings,
    sliding: sliding, createdAt: createdAt,
    currentHole: currentHole ?? this.currentHole,
    isFinished: isFinished ?? this.isFinished,
    startingNine: startingNine ?? this.startingNine,
    totalHoles: totalHoles ?? this.totalHoles,
  );
}
