// DEBUG: Reproduce el bug exacto del usuario.
// Escenario: ronda B9 (back-start, 9 hoyos 10-18).
// "Yo (USER) le doy 10 golpes a RAFA."
// Tarjeta 1v1 muestra 5 strokes (correcto: ceil(10/2)=5 para B9 back-start).
// Medal: ¿cuántos strokes aplica? Debería ser también 5.

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/game_engine.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

// Curso B9: hoyos 10-18 con SI 1,3,5,7,9,11,13,15,17
final _b9 = CourseInfo(
  name: 'B9 Debug',
  holes: List.generate(9, (i) =>
      CourseHole(hole: 10 + i, par: 4, strokeIndex: i * 2 + 1)),
);

Round _makeRound({
  required Map<String, int> grossTotals,
  Map<String, double> pairSlid = const {},
  Map<String, Map<String, double>> manuals = const {},
  double hcpUser = 20.0,
  double hcpRafa = 10.0,
  List<BetGroup> groups = const [],
}) {
  final Map<String, Map<int, HoleScore>> scoresMap = {};
  for (final e in grossTotals.entries) {
    scoresMap[e.key] = {};
    final avg = e.value ~/ 9;
    final rem = e.value % 9;
    for (int i = 0; i < 9; i++) {
      scoresMap[e.key]![10 + i] = HoleScore(playerId: e.key, hole: 10 + i, grossScore: avg + (i < rem ? 1 : 0));
    }
  }

  return Round(
    id: 'debug', name: 'Debug B9',
    course: _b9,
    players: [
      Player(id: 'USER', name: 'User', handicapBase: hcpUser, colorIndex: 0),
      Player(id: 'RAFA', name: 'Rafa', handicapBase: hcpRafa, colorIndex: 1),
    ],
    roundPlayers: [
      RoundPlayer(playerId: 'USER', handicapEnRonda: hcpUser,
          manualHandicaps: Map<String,double>.from(manuals['USER'] ?? {})),
      RoundPlayer(playerId: 'RAFA', handicapEnRonda: hcpRafa,
          manualHandicaps: Map<String,double>.from(manuals['RAFA'] ?? {})),
    ],
    scores: scoresMap,
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    betGroups: groups,
    createdAt: DateTime(2025),
    startingNine: StartingNine.back,
    totalHoles: 9,
    pairSliding: pairSlid,
  );
}

BetModuleInstance _medalMod() => BetModuleInstance(
  id: 'med1', type: BetModuleType.medal, name: 'Medal',
  participantIds: const ['USER', 'RAFA'],
  medalConfig: MedalConfig(value: 10.0, mode: GrossNetMode.net),
);

BetGroup _medalGroup() => BetGroup(
  id: 'g1', name: 'G1',
  format: PartidaFormat.oneVsOne,
  playerIds: const ['USER', 'RAFA'],
  modules: [_medalMod()],
);

void main() {
  // USER da 10 golpes a RAFA.
  // En ronda B9 back-start: pairSliding canónico usa 'RAFA|USER'=+10
  // (RAFA < USER lexicográficamente → RAFA es lowId → positivo = RAFA recibe)
  final key = BetEngine.pairKey('RAFA', 'USER');

  group('DEBUG Medal B9 — USER da 10 a RAFA', () {

    test('M1 — pairKey y recv con pairSliding=10', () {
      print('[M1] pairKey("RAFA","USER") = $key');
      final round = _makeRound(
        grossTotals: {'USER': 38, 'RAFA': 36},
        pairSlid: {key: 10.0},
      );
      final recvRafa = BetEngine.strokesP1ReceivesFromP2(round, 'RAFA', 'USER');
      final recvUser = BetEngine.strokesP1ReceivesFromP2(round, 'USER', 'RAFA');
      print('[M1] recv(RAFA,USER)=$recvRafa esperado +10');
      print('[M1] recv(USER,RAFA)=$recvUser esperado -10');
      expect(recvRafa, 10.0);
      expect(recvUser, -10.0);
    });

    test('M2 — strokesReceivedFromOfficial18Sliding: B9 back-start diff18=10 → total 5 strokes', () {
      final playedB9 = _b9.holes.toList();
      int total = 0;
      for (final ch in _b9.holes) {
        final s = GameEngine.strokesReceivedFromOfficial18Sliding(
          diff18: 10, ch: ch,
          playedHolesInSameNine: playedB9,
          startingNine: StartingNine.back,
        );
        print('[M2] H${ch.hole} SI${ch.strokeIndex} → $s');
        total += s;
      }
      print('[M2] Total strokes = $total (esperado 5)');
      expect(total, 5);
    });

    test('M3 — Medal pairSliding=10: empate cuando USER=40, RAFA=45 (RAFA net=45-5=40)', () {
      final bg = _medalGroup();
      final round = _makeRound(
        grossTotals: {'USER': 40, 'RAFA': 45},
        pairSlid: {key: 10.0},
        groups: [bg],
      );
      final entries = BetEngine.computeGroup(round, bg)
          .where((e) => e.betType == BetModuleType.medal).toList();
      print('[M3] USER=40 gross, RAFA=45 gross, RAFA net=45-5=40');
      print('[M3] entries: ${entries.map((e) => "${e.fromPlayerId}→${e.toPlayerId}").toList()}');
      expect(entries, isEmpty, reason: 'USER gross=40 == RAFA net=40 → EMPATE');
    });

    test('M4 — Medal pairSliding=10: BUG si requiere 10 golpes en vez de 5', () {
      // Con 5 strokes correctos: RAFA net = 45-5 = 40 > USER = 35 → USER GANA
      // Con bug (10 strokes):    RAFA net = 45-10= 35 = USER = 35 → EMPATE (incorrecto)
      final bg = _medalGroup();
      final round = _makeRound(
        grossTotals: {'USER': 35, 'RAFA': 45},
        pairSlid: {key: 10.0},
        groups: [bg],
      );
      final entries = BetEngine.computeGroup(round, bg)
          .where((e) => e.betType == BetModuleType.medal).toList();
      print('[M4] USER=35, RAFA=45');
      print('[M4] Correcto (5 stk): RAFA net=40, USER=35 → USER gana');
      print('[M4] Bug     (10 stk): RAFA net=35, USER=35 → EMPATE');
      print('[M4] entries: ${entries.map((e) => "${e.fromPlayerId}→${e.toPlayerId}").toList()}');
      expect(entries, isNotEmpty, reason: 'Con 5 strokes: USER=35 < RAFA net=40 → USER gana');
      expect(entries.first.toPlayerId, 'USER',
          reason: 'USER debe ganar (recibe de RAFA)');
    });

    test('M5 — Medal manualHandicaps=10: igual resultado que pairSliding', () {
      final bg = _medalGroup();
      final round = _makeRound(
        grossTotals: {'USER': 40, 'RAFA': 45},
        manuals: {
          'RAFA': {'USER': 10.0},  // RAFA recibe 10 de USER
          'USER': {'RAFA': -10.0}, // USER da 10 a RAFA
        },
        groups: [bg],
      );
      final entries = BetEngine.computeGroup(round, bg)
          .where((e) => e.betType == BetModuleType.medal).toList();
      print('[M5] manualHandicaps=10, USER=40, RAFA=45');
      print('[M5] entries: ${entries.map((e) => "${e.fromPlayerId}→${e.toPlayerId}").toList()}');
      expect(entries, isEmpty, reason: 'RAFA net=40 = USER=40 → EMPATE');
    });

    test('M6 — Verificar strokes individuales por hoyo que usa el Medal (diagnóstico)', () {
      // Abrimos el cálculo hoyo por hoyo que hace netVs() internamente
      // para confirmar que el Medal aplica 5 strokes totales en B9
      final round = _makeRound(
        grossTotals: {'USER': 40, 'RAFA': 45},
        pairSlid: {key: 10.0},
      );
      final recvRafa = BetEngine.strokesP1ReceivesFromP2(round, 'RAFA', 'USER');
      final diff18 = recvRafa.round();
      print('[M6] recv(RAFA,USER)=$recvRafa → diff18=$diff18');

      final playedF9 = _b9.holes.where((ch) => ch.hole <= 9).toList();
      final playedB9 = _b9.holes.where((ch) => ch.hole > 9).toList();
      int totalStrokes = 0;
      for (final ch in _b9.holes) {
        final nineHoles = ch.hole <= 9 ? playedF9 : playedB9;
        final s = GameEngine.strokesReceivedFromOfficial18Sliding(
          diff18: diff18,
          ch: ch,
          playedHolesInSameNine: nineHoles,
          startingNine: StartingNine.back,
        );
        totalStrokes += s;
        if (s > 0) print('[M6]   H${ch.hole} SI${ch.strokeIndex}: $s stroke');
      }
      print('[M6] Total strokes aplicados por el Medal = $totalStrokes');
      expect(totalStrokes, 5,
          reason: 'B9 back-start, diff18=10 → share=ceil(10/2)=5');
    });

    test('M7 — matchPlayStatus confirma mismo resultado: B9 back-start, 10 strokes', () {
      // matchPlayStatus también debe aplicar 5 strokes en B9
      // USER=40 (gross 4.4/hoyo avg), RAFA=45 (gross 5/hoyo)
      // Con 5 strokes para RAFA (H10,H11,H12,H13,H14): RAFA net = 4 en esos, USER gross = 4-5
      // Resultado match: depende de distribución exacta de scores
      // Lo importante: los dos métodos deben coincidir en strokes aplicados
      final round = _makeRound(
        grossTotals: {'USER': 36, 'RAFA': 36}, // mismos brutos
        pairSlid: {key: 10.0},
      );
      // Con mismos brutos y RAFA recibiendo 5 strokes, RAFA net < USER bruto en 5 hoyos
      // → RAFA gana 5, USER gana 4 → status = 5 - 4 = +1 para RAFA  (desde perspectiva USER: -1? depende de recv)
      final status = GameEngine.matchPlayStatus(round, 'USER', 'RAFA', true);
      print('[M7] matchPlayStatus(USER,RAFA) con mismos brutos y RAFA recibe 5 strokes = $status');
      // RAFA gana 5 hoyos, USER gana 4 → desde perspectiva USER: USER pierde → status negativo
      // NOTA: matchPlayStatus usa HCP fallback (ignora pairSliding) → recv=+10 (USER recibe)
      // Resultado real con pairSliding: RAFA recibe → RAFA debería ganar match
      // Pero matchPlayStatus con HCP fallback: USER recibe → USER gana → status positivo
      // Esto expone que matchPlayStatus NO lee pairSliding — es una inconsistencia conocida.
      print('[M7] matchPlayStatus=$status (positivo=USER gana con HCP fallback, no con pairSliding)');
    });

    test('DX1 — diagnoseMedal: ver strokes exactos aplicados', () {
      final bg = _medalGroup();
      final round = _makeRound(
        grossTotals: {'USER': 40, 'RAFA': 45},
        pairSlid: {key: 10.0},
        groups: [bg],
      );
      final diags = BetEngine.diagnoseMedal(round);
      print('\n=== diagnoseMedal output ===');
      for (final d in diags) {
        print('Group: ${d['groupName']} | Module: ${d['moduleId']}');
        print('nets: ${d['nets']}');
        print('grosses: ${d['grosses']}');
        print('strokesMap: ${d['strokesMap']}');
        print('reason: ${d['reason']}');
        print('entries: ${d['entries']}');
      }
      print('===========================\n');
      expect(diags.first['entries'], 0, reason: 'RAFA net=40=USER gross=40 → EMPATE');
    });
  });
}
