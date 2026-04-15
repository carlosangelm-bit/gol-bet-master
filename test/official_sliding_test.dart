// =============================================================================
// Tests T1–T10: pairSliding como valor oficial de 18 hoyos
//
// Verifica los helpers slidingShareForNine y strokesReceivedFromOfficial18Sliding
// y su integración con Medal, Nassau y Skins 1v1.
//
// REGLA CENTRAL:
//   • pairSliding es SIEMPRE el valor oficial de 18 hoyos (diff18).
//   • La vuelta de INICIO recibe ceil(diff18/2) y la secundaria floor(diff18/2).
//   • Dentro de cada vuelta los strokes se distribuyen por SI entre los hoyos
//     efectivamente jugados en esa vuelta.
//   • Ronda de 9 hoyos: solo se aplica el share de la vuelta jugada.
//   • Ronda parcial: el share se distribuye entre los hoyos jugados de esa vuelta.
// =============================================================================

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/game_engine.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cursos de test
// ─────────────────────────────────────────────────────────────────────────────

/// Curso 18H estándar con SI 1–18.
/// F9: hoyos 1-9 con SI 1,3,5,7,9,11,13,15,17.
/// B9: hoyos 10-18 con SI 2,4,6,8,10,12,14,16,18.
final _course18 = CourseInfo(
  name: '18H Test',
  holes: [
    for (int i = 0; i < 9; i++)
      CourseHole(hole: i + 1, par: 4, strokeIndex: (i * 2) + 1), // SI: 1,3,5,7,9,11,13,15,17
    for (int i = 0; i < 9; i++)
      CourseHole(hole: i + 10, par: 4, strokeIndex: (i * 2) + 2), // SI: 2,4,6,8,10,12,14,16,18
  ],
);

/// Curso de solo F9 (hoyos 1-9, SI 1,3,5,7,9,11,13,15,17).
final _courseF9 = CourseInfo(
  name: 'F9 Only',
  holes: [
    for (int i = 0; i < 9; i++)
      CourseHole(hole: i + 1, par: 4, strokeIndex: (i * 2) + 1),
  ],
);

/// Curso de solo B9 (hoyos 10-18, SI 2,4,6,8,10,12,14,16,18).
final _courseB9 = CourseInfo(
  name: 'B9 Only',
  holes: [
    for (int i = 0; i < 9; i++)
      CourseHole(hole: i + 10, par: 4, strokeIndex: (i * 2) + 2),
  ],
);

// ─────────────────────────────────────────────────────────────────────────────
// Helper para construir Round
// ─────────────────────────────────────────────────────────────────────────────

Round _makeRound({
  required List<Map<String, dynamic>> players,
  required List<BetGroup> groups,
  required Map<String, List<int>> scores, // pid → grosses (0 = no jugado)
  int totalHoles = 18,
  StartingNine startingNine = StartingNine.front,
  CourseInfo? course,
  Map<String, double>? pairSlid,
}) {
  final c = course ?? _course18;

  // Orden de hoyos según startingNine
  final List<int> holeNums;
  if (totalHoles <= 9) {
    holeNums = c.holes.map((ch) => ch.hole).toList()..sort();
    if (startingNine == StartingNine.back) {
      // back-nine solo: hoyos ya están 10-18
    }
  } else {
    holeNums = startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(18, (i) => i + 1);
  }

  final scoresMap = <String, Map<int, HoleScore>>{};
  for (final entry in scores.entries) {
    final pid = entry.key;
    final vals = entry.value;
    final holeMap = <int, HoleScore>{};
    for (int i = 0; i < vals.length && i < holeNums.length; i++) {
      final s = vals[i];
      if (s > 0) {
        final h = holeNums[i];
        holeMap[h] = HoleScore(playerId: pid, hole: h, grossScore: s, putts: 2);
      }
    }
    if (holeMap.isNotEmpty) scoresMap[pid] = holeMap;
  }

  final rPlayers = players.map((p) {
    final pid = p['id'] as String;
    final hcp = (p['hcp'] as num).toDouble();
    return RoundPlayer(playerId: pid, handicapEnRonda: hcp);
  }).toList();

  final pObjects = players
      .map((p) => Player(
            id: p['id'] as String,
            name: (p['name'] as String?) ?? (p['id'] as String),
            handicapBase: (p['hcp'] as num).toDouble(),
          ))
      .toList();

  return Round(
    id: 'official-sliding-test',
    name: 'Official Sliding Test',
    course: c,
    players: pObjects,
    roundPlayers: rPlayers,
    betGroups: groups,
    scores: scoresMap,
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2025, 1, 1),
    totalHoles: totalHoles,
    startingNine: startingNine,
    pairSliding: pairSlid ?? const {},
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper para crear módulo Nassau básico
// ─────────────────────────────────────────────────────────────────────────────
BetModuleInstance _nassauMod({double front = 50, double back = 50, double total = 100}) =>
    BetModuleInstance(
      id: 'nas1',
      type: BetModuleType.nassau,
      name: 'Nassau',
      participantIds: const [],
      nassauConfig: NassauConfig(
        frontValue: front,
        backValue: back,
        totalValue: total,
      ),
    );

// Helper para crear módulo Medal
BetModuleInstance _medalMod({double value = 50}) =>
    BetModuleInstance(
      id: 'med1',
      type: BetModuleType.medal,
      name: 'Medal',
      participantIds: const [],
      medalConfig: MedalConfig(value: value, mode: GrossNetMode.net),
    );

// Helper para crear módulo Skins 1v1
BetModuleInstance _skinsMod({double valuePerSkin = 10, bool carryOver = false}) =>
    BetModuleInstance(
      id: 'ski1',
      type: BetModuleType.skins,
      name: 'Skins',
      participantIds: const [],
      skinsConfig: SkinsConfig(
        valuePerSkin: valuePerSkin,
        carryOver: carryOver,
        mode: GrossNetMode.net,
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Acceso directo a los helpers de GameEngine
// ─────────────────────────────────────────────────────────────────────────────

// T1 – T5: tests unitarios de los helpers puros
// T6 – T10: tests de integración con módulos

void main() {
  // ============================================================================
  // T1: slidingShareForNine – diff par (4): ambas vueltas reciben 2
  // ============================================================================
  test('T1: slidingShareForNine — diff18 par: ambas vueltas reciben lo mismo', () {
    const diff18 = 4;

    // front start → F9 es startingNine
    final shareF9front = GameEngine.slidingShareForNine(
      diff18: diff18,
      startingNine: StartingNine.front,
      targetIsStartingNine: true, // F9 = vuelta inicio
    );
    final shareB9front = GameEngine.slidingShareForNine(
      diff18: diff18,
      startingNine: StartingNine.front,
      targetIsStartingNine: false, // B9 = vuelta secundaria
    );

    // back start → B9 es startingNine
    final shareB9back = GameEngine.slidingShareForNine(
      diff18: diff18,
      startingNine: StartingNine.back,
      targetIsStartingNine: true, // B9 = vuelta inicio
    );
    final shareF9back = GameEngine.slidingShareForNine(
      diff18: diff18,
      startingNine: StartingNine.back,
      targetIsStartingNine: false, // F9 = vuelta secundaria
    );

    // Diff par: ceil(4/2) = floor(4/2) = 2
    expect(shareF9front, 2, reason: 'F9 con front-start, diff 4: share 2');
    expect(shareB9front, 2, reason: 'B9 con front-start, diff 4: share 2');
    expect(shareB9back,  2, reason: 'B9 con back-start, diff 4: share 2');
    expect(shareF9back,  2, reason: 'F9 con back-start, diff 4: share 2');

    // invariante: suma siempre = diff18
    expect(shareF9front + shareB9front, diff18);
    expect(shareB9back  + shareF9back,  diff18);
  });

  // ============================================================================
  // T2: slidingShareForNine – diff impar (9): inicio recibe ceil, secundaria floor
  // ============================================================================
  test('T2: slidingShareForNine — diff18 impar: inicio=ceil, secundaria=floor', () {
    const diff18 = 9;

    // front start → F9 (inicio) recibe ceil(9/2)=5, B9 (secundaria) floor(9/2)=4
    final shareF9 = GameEngine.slidingShareForNine(
      diff18: diff18,
      startingNine: StartingNine.front,
      targetIsStartingNine: true,
    );
    final shareB9 = GameEngine.slidingShareForNine(
      diff18: diff18,
      startingNine: StartingNine.front,
      targetIsStartingNine: false,
    );

    expect(shareF9, 5, reason: 'F9 con front-start, diff 9: share ceil=5');
    expect(shareB9, 4, reason: 'B9 con front-start, diff 9: share floor=4');
    expect(shareF9 + shareB9, diff18, reason: 'suma = diff18');

    // back start → B9 (inicio) recibe ceil(9/2)=5, F9 (secundaria) floor=4
    final shareB9back = GameEngine.slidingShareForNine(
      diff18: diff18,
      startingNine: StartingNine.back,
      targetIsStartingNine: true,
    );
    final shareF9back = GameEngine.slidingShareForNine(
      diff18: diff18,
      startingNine: StartingNine.back,
      targetIsStartingNine: false,
    );

    expect(shareB9back, 5, reason: 'B9 con back-start, diff 9: share ceil=5');
    expect(shareF9back, 4, reason: 'F9 con back-start, diff 9: share floor=4');
    expect(shareB9back + shareF9back, diff18, reason: 'suma = diff18');
  });

  // ============================================================================
  // T3: strokesReceivedFromOfficial18Sliding – ronda 18H completa
  //     diff18=9, front-start: F9 recibe 5 strokes (SI 1-5), B9 recibe 4 (SI 2-8)
  // ============================================================================
  test('T3: strokesReceivedFromOfficial18Sliding — 18H front-start, diff9', () {
    // F9: hoyos 1-9, SI 1,3,5,7,9,11,13,15,17 → los 5 primeros por SI reciben stroke
    // Los 5 hoyos con SI más bajo en F9: H1(SI1), H2(SI3), H3(SI5), H4(SI7), H5(SI9)
    // Los 4 hoyos con SI más bajo en B9: H10(SI2), H11(SI4), H12(SI6), H13(SI8)

    final courseF9holes = _course18.holes.where((h) => h.hole <= 9).toList();
    final courseB9holes = _course18.holes.where((h) => h.hole > 9).toList();

    const diff18 = 9;
    const startingNine = StartingNine.front;

    // Verificar F9: los primeros 5 por SI reciben 1 stroke
    // SI ordenados F9: 1,3,5,7,9,11,13,15,17 → rank 1=H1, 2=H2, ..., 5=H5
    for (final ch in courseF9holes) {
      final strokes = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: diff18,
        ch: ch,
        playedHolesInSameNine: courseF9holes,
        startingNine: startingNine,
      );
      // Share F9 = ceil(9/2) = 5. Hoyos con SI rank ≤ 5 reciben 1
      final rank = courseF9holes.map((h) => h.strokeIndex).toList()..sort();
      final expectedRankLimit = 5;
      final chRank = rank.indexOf(ch.strokeIndex) + 1; // 1-based rank by SI
      final expected = chRank <= expectedRankLimit ? 1 : 0;
      expect(strokes, expected,
          reason: 'F9 H${ch.hole} (SI=${ch.strokeIndex}) → $expected stroke');
    }

    // Verificar B9: los primeros 4 por SI reciben 1 stroke
    // SI ordenados B9: 2,4,6,8,10,12,14,16,18 → rank 1=H10, 2=H11, ..., 4=H13
    for (final ch in courseB9holes) {
      final strokes = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: diff18,
        ch: ch,
        playedHolesInSameNine: courseB9holes,
        startingNine: startingNine,
      );
      final rank = courseB9holes.map((h) => h.strokeIndex).toList()..sort();
      final chRank = rank.indexOf(ch.strokeIndex) + 1;
      final expected = chRank <= 4 ? 1 : 0;
      expect(strokes, expected,
          reason: 'B9 H${ch.hole} (SI=${ch.strokeIndex}) → $expected stroke');
    }

    // Total strokes en toda la ronda = 5 + 4 = 9 = diff18
    int totalStrokes = 0;
    for (final ch in _course18.holes) {
      final nineHoles = ch.hole <= 9 ? courseF9holes : courseB9holes;
      totalStrokes += GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: diff18,
        ch: ch,
        playedHolesInSameNine: nineHoles,
        startingNine: startingNine,
      );
    }
    expect(totalStrokes, diff18,
        reason: 'Total strokes en 18H debe ser igual a diff18=$diff18');
  });

  // ============================================================================
  // T4: Ronda de solo 9 hoyos (F9) — solo se aplica el share de F9
  //     diff18=9, front-start: F9 share=5, B9 share=4 (pero B9 no existe)
  // ============================================================================
  test('T4: strokesReceivedFromOfficial18Sliding — solo F9, front-start, diff9', () {
    final f9holes = _courseF9.holes.toList();
    const diff18 = 9;
    const startingNine = StartingNine.front;

    // Share F9 con front-start = ceil(9/2) = 5
    // Los 5 hoyos con menor SI reciben 1 stroke, los otros 4 reciben 0
    int totalStrokes = 0;
    for (final ch in f9holes) {
      final strokes = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: diff18,
        ch: ch,
        playedHolesInSameNine: f9holes,
        startingNine: startingNine,
      );
      totalStrokes += strokes;
    }
    // En F9 con share=5, total strokes = 5 (no 9, porque solo hay F9)
    expect(totalStrokes, 5,
        reason: 'Solo F9 con diff18=9, front-start: share=5 strokes en F9');
  });

  // ============================================================================
  // T5: Ronda de solo 9 hoyos (B9) — aplica el share correcto según startingNine
  //     diff18=9, back-start: B9 es la vuelta inicio → share=ceil=5
  //     diff18=9, front-start: B9 es la vuelta secundaria → share=floor=4
  // ============================================================================
  test('T5: strokesReceivedFromOfficial18Sliding — solo B9, shares correctos', () {
    final b9holes = _courseB9.holes.toList();
    const diff18 = 9;

    // Caso A: back-start → B9 es la vuelta de inicio → share = ceil(9/2) = 5
    {
      int total = 0;
      for (final ch in b9holes) {
        total += GameEngine.strokesReceivedFromOfficial18Sliding(
          diff18: diff18,
          ch: ch,
          playedHolesInSameNine: b9holes,
          startingNine: StartingNine.back,
        );
      }
      expect(total, 5,
          reason: 'Solo B9 con back-start (B9=inicio): share=5 strokes');
    }

    // Caso B: front-start → B9 es la vuelta secundaria → share = floor(9/2) = 4
    {
      int total = 0;
      for (final ch in b9holes) {
        total += GameEngine.strokesReceivedFromOfficial18Sliding(
          diff18: diff18,
          ch: ch,
          playedHolesInSameNine: b9holes,
          startingNine: StartingNine.front,
        );
      }
      expect(total, 4,
          reason: 'Solo B9 con front-start (B9=secundaria): share=4 strokes');
    }
  });

  // ============================================================================
  // T6: Integración Medal — diff18=6 (par), F9 y B9 reciben 3 strokes cada una
  // ============================================================================
  test('T6: Medal integración — diff18=6 par, ambas vueltas share=3', () {
    // A recibe 6 strokes de B en 18H (pairSliding oficial).
    // Con diff18=6 (par): F9 recibe 3, B9 recibe 3.
    //
    // Escenario: A y B hacen 5 brutos en todos los hoyos.
    // A recibe 1 stroke en los 3 hoyos con menor SI de cada vuelta.
    // Net A en esos 3 hoyos = 5-1=4. Net A en los otros = 5.
    // Net A total = 3×4 + 6×5 + 3×4 + 6×5 = 12 + 30 + 12 + 30 = 84
    // Net B total = 18×5 = 90
    // → A gana Medal.

    final mod = _medalMod(value: 50);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 10.0}, {'id': 'B', 'hcp': 4.0}],
      groups: [group],
      scores: {
        'A': List.filled(18, 5), // 5 en todos los hoyos
        'B': List.filled(18, 5),
      },
      pairSlid: {'A|B': 6.0}, // A recibe 6 de B (A<B lexicográficamente)
    );

    final entries = BetEngine.computeGroup(round, group);
    // A gana: B debe pagar a A
    expect(entries.where((e) => e.toPlayerId == 'A').length, 1,
        reason: 'A gana Medal: debe haber 1 entry B→A');
    final entry = entries.firstWhere((e) => e.toPlayerId == 'A');
    expect(entry.fromPlayerId, 'B');
    expect(entry.amount, 50.0);
  });

  // ============================================================================
  // T7: Integración Nassau — diff18=9 impar, front-start
  //     F9 share=5 (A recibe 5 en F9), B9 share=4 (A recibe 4 en B9)
  // ============================================================================
  test('T7: Nassau integración — diff18=9, front-start, split correcto F9/B9', () {
    // A recibe 9 strokes de B en 18H (pairSliding).
    // front-start: F9 share=5, B9 share=4.
    // Escenario: todos 5 brutos en todos los hoyos.
    //
    // F9 (hoyos 1-9, share=5):
    //   A recibe 1 stroke en hoyos con SI rank 1-5: H1(SI1),H2(SI3),H3(SI5),H4(SI7),H5(SI9)
    //   Net A en esos: 4. Net A en H6-H9: 5. Net A F9 = 5×4 + 4×5 = 20+20=40
    //   Net B F9 = 9×5 = 45
    //   → A gana F9 por margen de 45-40=5 (5 hoyos a favor de A)
    //   En términos de score total: A net 40 < B 45 → A gana F9.
    //
    // B9 (hoyos 10-18, share=4):
    //   A recibe 1 stroke en hoyos SI rank 1-4: H10(SI2),H11(SI4),H12(SI6),H13(SI8)
    //   Net A en esos: 4. Net A en H14-H18: 5. Net A B9 = 4×4 + 5×5 = 16+25=41
    //   Net B B9 = 9×5 = 45
    //   → A gana B9 también.
    //
    // Total18: A gana Nassau F9, B9 y Total.

    final mod = _nassauMod(front: 50, back: 50, total: 100);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );
    final round = _makeRound(
      players: [{'id': 'A', 'hcp': 12.0}, {'id': 'B', 'hcp': 3.0}],
      groups: [group],
      scores: {
        'A': List.filled(18, 5),
        'B': List.filled(18, 5),
      },
      pairSlid: {'A|B': 9.0}, // A recibe 9 de B
      startingNine: StartingNine.front,
    );

    final entries = BetEngine.computeGroup(round, group);
    // A gana F9, B9 y Total: 3 entries B→A
    final toA = entries.where((e) => e.toPlayerId == 'A').toList();
    expect(toA.length, 3,
        reason: 'A gana F9, B9 y Total: 3 entries Nassau B→A');
    expect(toA.any((e) => e.reason.contains('Front') && e.amount == 50), isTrue,
        reason: 'Entry Nassau Front 9 de B a A por 50');
    expect(toA.any((e) => e.reason.contains('Back') && e.amount == 50), isTrue,
        reason: 'Entry Nassau Back 9 de B a A por 50');
    expect(toA.any((e) => e.reason.contains('Total') && e.amount == 100), isTrue,
        reason: 'Entry Nassau Total 18 de B a A por 100');
  });

  // ============================================================================
  // T8: Nassau back-start — diff18=9 impar, B9 es la vuelta de inicio (share=5)
  //     Verifica que el stroke extra va a B9 (no a F9) cuando back-start.
  // ============================================================================
  test('T8: Nassau back-start — diff18=9, B9 inicio recibe ceil=5', () {
    // Con back-start y diff18=9:
    //   B9 (vuelta inicio) share = ceil(9/2) = 5
    //   F9 (vuelta secundaria) share = floor(9/2) = 4
    //
    // Todos 5 brutos. A recibe strokes.
    // El hoyo H14 tiene SI=4 en B9. Con share=5, rank 4 ≤ 5 → recibe 1 stroke.
    // Con share=4 en F9: el hoyo correspondiente en F9 con el mismo rank no recibiría si
    // hubiera sido F9-inicio con solo 4 share.
    //
    // Verificación: A gana tanto B9 como F9 (en ambos casos A tiene mejor net).
    // La distinción clave es qué vuelta recibe MÁS strokes.
    //
    // Con back-start, B9=inicio → 5 strokes en B9, 4 en F9.
    // Con front-start, F9=inicio → 5 strokes en F9, 4 en B9.
    //
    // Comparamos directamente: con back-start A tiene net B9 = 4×4+5×5=41 (5 recibidos)
    // vs con front-start A tiene net B9 = 4×4+5×5=41 (4 recibidos, share=4 en B9).
    // La diferencia es si en B9 A recibe 4 o 5 strokes.

    final mod = _nassauMod(front: 50, back: 50, total: 100);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );

    // back-start: B9 es inicio → share=5 en B9
    final roundBack = _makeRound(
      players: [{'id': 'A', 'hcp': 12.0}, {'id': 'B', 'hcp': 3.0}],
      groups: [group],
      scores: {
        'A': List.filled(18, 5),
        'B': List.filled(18, 5),
      },
      pairSlid: {'A|B': 9.0},
      startingNine: StartingNine.back,
      course: _course18,
    );

    // front-start: F9 es inicio → share=5 en F9
    final roundFront = _makeRound(
      players: [{'id': 'A', 'hcp': 12.0}, {'id': 'B', 'hcp': 3.0}],
      groups: [group],
      scores: {
        'A': List.filled(18, 5),
        'B': List.filled(18, 5),
      },
      pairSlid: {'A|B': 9.0},
      startingNine: StartingNine.front,
      course: _course18,
    );

    // En ambos casos A gana (tiene más strokes que B), pero la distribución difiere.
    // Verificamos que en back-start, B9 recibe share=5 y F9 recibe share=4.
    final b9holesBack = _course18.holes.where((h) => h.hole > 9).toList();
    final f9holesBack = _course18.holes.where((h) => h.hole <= 9).toList();

    int totalB9back = 0, totalF9back = 0;
    for (final ch in b9holesBack) {
      totalB9back += GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 9,
        ch: ch,
        playedHolesInSameNine: b9holesBack,
        startingNine: StartingNine.back,
      );
    }
    for (final ch in f9holesBack) {
      totalF9back += GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 9,
        ch: ch,
        playedHolesInSameNine: f9holesBack,
        startingNine: StartingNine.back,
      );
    }

    expect(totalB9back, 5, reason: 'Back-start: B9 recibe ceil(9/2)=5 strokes');
    expect(totalF9back, 4, reason: 'Back-start: F9 recibe floor(9/2)=4 strokes');
    expect(totalB9back + totalF9back, 9, reason: 'Total = diff18');

    // Y en front-start F9=5, B9=4
    int totalB9front = 0, totalF9front = 0;
    for (final ch in b9holesBack) {
      totalB9front += GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 9,
        ch: ch,
        playedHolesInSameNine: b9holesBack,
        startingNine: StartingNine.front,
      );
    }
    for (final ch in f9holesBack) {
      totalF9front += GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 9,
        ch: ch,
        playedHolesInSameNine: f9holesBack,
        startingNine: StartingNine.front,
      );
    }

    expect(totalF9front, 5, reason: 'Front-start: F9 recibe ceil(9/2)=5 strokes');
    expect(totalB9front, 4, reason: 'Front-start: B9 recibe floor(9/2)=4 strokes');

    // Ambas rondas producen entries (A gana)
    final entriesBack  = BetEngine.computeGroup(roundBack,  group);
    final entriesFront = BetEngine.computeGroup(roundFront, group);
    expect(entriesBack.where((e) => e.toPlayerId == 'A').length,  greaterThan(0));
    expect(entriesFront.where((e) => e.toPlayerId == 'A').length, greaterThan(0));
  });

  // ============================================================================
  // T9: Skins 1v1 con ronda parcial de F9 — diff18=9
  //     Solo se juegan 5 hoyos de F9. El share de F9 (5 strokes) se distribuye
  //     entre los 5 hoyos jugados.
  // ============================================================================
  test('T9: Skins 1v1 — parcial F9 (5 hoyos jugados), diff18=9', () {
    // A recibe 9 strokes de B en 18H (pairSliding).
    // front-start, solo F9 con 5 hoyos jugados (hoyos 1-5).
    // Share F9 = ceil(9/2) = 5.
    // Los 5 strokes se distribuyen entre los 5 hoyos jugados: cada uno recibe 1.
    //
    // A gross=5, B gross=5 en todos.
    // A net = 5-1=4 en cada hoyo jugado.
    // B net = 5 en cada hoyo.
    // A gana cada hoyo → 5 skins ganados por A.

    final mod = _skinsMod(valuePerSkin: 10, carryOver: false);
    final group = BetGroup(
      id: 'g1', name: 'G', format: PartidaFormat.allInOnePot,
      playerIds: const ['A', 'B'], modules: [mod],
    );

    // Construimos la ronda con solo F9 completa (9 hoyos, solo jugamos 5)
    // Usamos totalHoles=9 y curso F9 solo, pero registramos solo 5 hoyos con score.
    final f9course = _courseF9; // hoyos 1-9

    // Scores: solo hoyos 1-5 tienen score
    final aScores = <int, HoleScore>{};
    final bScores = <int, HoleScore>{};
    for (int h = 1; h <= 5; h++) {
      aScores[h] = HoleScore(playerId: 'A', hole: h, grossScore: 5, putts: 2);
      bScores[h] = HoleScore(playerId: 'B', hole: h, grossScore: 5, putts: 2);
    }

    final round = Round(
      id: 't9',
      name: 'T9',
      course: f9course,
      players: [
        Player(id: 'A', name: 'A', handicapBase: 12),
        Player(id: 'B', name: 'B', handicapBase: 3),
      ],
      roundPlayers: [
        RoundPlayer(playerId: 'A', handicapEnRonda: 12),
        RoundPlayer(playerId: 'B', handicapEnRonda: 3),
      ],
      betGroups: [group],
      scores: {'A': aScores, 'B': bScores},
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2025, 1, 1),
      totalHoles: 9,
      startingNine: StartingNine.front,
      pairSliding: {'A|B': 9.0},
    );

    final entries = BetEngine.computeGroup(round, group);

    // Verificar los strokes: con 5 hoyos jugados y share=5, todos reciben 1 stroke
    final playedHoles = f9course.holes.where((h) => h.hole <= 5).toList();
    for (final ch in playedHoles) {
      final strokes = GameEngine.strokesReceivedFromOfficial18Sliding(
        diff18: 9,
        ch: ch,
        playedHolesInSameNine: playedHoles,
        startingNine: StartingNine.front,
      );
      expect(strokes, 1,
          reason: 'H${ch.hole}: con share=5 y 5 hoyos, cada hoyo recibe 1');
    }

    // A gana todos los hoyos jugados (net 4 < B net 5)
    final toA = entries.where((e) => e.toPlayerId == 'A').toList();
    expect(toA.length, 5, reason: 'A gana los 5 hoyos jugados → 5 skins');
    expect(toA.every((e) => e.amount == 10), isTrue,
        reason: 'Cada skin vale 10');
  });

  // ============================================================================
  // T10: Invariante total — diff18 siempre suma a diff18 en 18H completa
  //      Para distintos valores de diff18 y startingNine.
  // ============================================================================
  test('T10: invariante — total strokes en 18H = diff18 para varios diffs y startingNines', () {
    final allHoles = _course18.holes.toList();
    final f9holes = allHoles.where((h) => h.hole <= 9).toList();
    final b9holes = allHoles.where((h) => h.hole > 9).toList();

    for (final startingNine in [StartingNine.front, StartingNine.back]) {
      for (final diff18 in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 18, 20]) {
        int total = 0;
        for (final ch in allHoles) {
          final nineHoles = ch.hole <= 9 ? f9holes : b9holes;
          total += GameEngine.strokesReceivedFromOfficial18Sliding(
            diff18: diff18,
            ch: ch,
            playedHolesInSameNine: nineHoles,
            startingNine: startingNine,
          );
        }
        expect(total, diff18,
            reason:
                'startingNine=${startingNine.name}, diff18=$diff18: total=$total debe = $diff18');
      }
    }
  });
}
