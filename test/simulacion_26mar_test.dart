// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

// ─── Datos del campo (B9 real: hoyos 10-18) ──────────────────────────────────
// player,h10,h11,h12,h13,h14,h15,h16,h17,h18
// PAR,   4,  5,  4,  4,  3,  4,  3,  5,  4  → total 36
// SI,    6,  4, 10, 14, 16,  8, 18,  2, 12

final _course26Mar = CourseInfo(name: 'B9 – 26 Mar', holes: [
  // F9 dummy (no se juegan, pero se necesitan para el cálculo de SI relativo)
  const CourseHole(hole: 1,  par: 4, strokeIndex: 1),
  const CourseHole(hole: 2,  par: 4, strokeIndex: 3),
  const CourseHole(hole: 3,  par: 3, strokeIndex: 5),
  const CourseHole(hole: 4,  par: 5, strokeIndex: 7),
  const CourseHole(hole: 5,  par: 4, strokeIndex: 9),
  const CourseHole(hole: 6,  par: 4, strokeIndex: 11),
  const CourseHole(hole: 7,  par: 3, strokeIndex: 13),
  const CourseHole(hole: 8,  par: 5, strokeIndex: 15),
  const CourseHole(hole: 9,  par: 4, strokeIndex: 17),
  // B9 real con el SI proporcionado
  const CourseHole(hole: 10, par: 4, strokeIndex: 6),
  const CourseHole(hole: 11, par: 5, strokeIndex: 4),
  const CourseHole(hole: 12, par: 4, strokeIndex: 10),
  const CourseHole(hole: 13, par: 4, strokeIndex: 14),
  const CourseHole(hole: 14, par: 3, strokeIndex: 16),
  const CourseHole(hole: 15, par: 4, strokeIndex: 8),
  const CourseHole(hole: 16, par: 3, strokeIndex: 18),
  const CourseHole(hole: 17, par: 5, strokeIndex: 2),
  const CourseHole(hole: 18, par: 4, strokeIndex: 12),
]);

// ─── Scores B9 ──────────────────────────────────────────────────────────────
// player,h10,h11,h12,h13,h14,h15,h16,h17,h18
final _scores = {
  'CAM':       [4, 5, 5, 5, 3, 5, 3, 5, 4],  // gross 39
  'KAWA':      [5, 6, 5, 4, 3, 5, 3, 5, 6],  // gross 42
  'FRANK':     [6, 8, 5, 6, 4, 5, 3, 6, 3],  // gross 46
  'RICH':      [8, 5, 8, 6, 4, 6, 4, 9, 4],  // gross 54
  'Alejandro': [6, 9, 4, 6, 5, 5, 4, 5, 5],  // gross 49
};

// ─── Ventajas manuales (manualHandicaps[receptor][dador] = strokes) ───────────
// Convención del motor: manualHandicaps[pA][pB] > 0 → pA recibe de pB
final _manuals = {
  'CAM':       <String, double>{},
  'KAWA':      <String, double>{'CAM': 7.0},
  'FRANK':     <String, double>{'CAM': 14.0, 'KAWA': 10.0, 'RICH': -10.0},
  'RICH':      <String, double>{'CAM': 9.0, 'KAWA': 2.0, 'FRANK': 10.0},
  'Alejandro': <String, double>{'CAM': 9.0, 'KAWA': 2.0, 'FRANK': 5.0},
  // RICH vs Alejandro: igualdad (0 strokes — no entry en _manuals)
};

// ─── Construcción del Round ──────────────────────────────────────────────────
Round _buildRound(List<BetGroup> groups) {
  final pids = ['CAM', 'KAWA', 'FRANK', 'RICH', 'Alejandro'];

  final rPlayers = pids.map((id) => RoundPlayer(
    playerId: id,
    handicapEnRonda: 0.0,  // no usamos HCP absoluto, todo via manualHandicaps
    manualHandicaps: Map<String, double>.from(_manuals[id] ?? {}),
  )).toList();

  final players = pids.map((id) => Player(id: id, name: id)).toList();

  final scoresMap = <String, Map<int, HoleScore>>{};
  for (final pid in pids) {
    final raw = _scores[pid]!;
    final holeMap = <int, HoleScore>{};
    for (int i = 0; i < raw.length; i++) {
      final hole = 10 + i;
      holeMap[hole] = HoleScore(playerId: pid, hole: hole, grossScore: raw[i]);
    }
    scoresMap[pid] = holeMap;
  }

  return Round(
    id: 'sim_26mar',
    name: 'Simulación 26 Mar',
    course: _course26Mar,
    players: players,
    roundPlayers: rPlayers,
    betGroups: groups,
    scores: scoresMap,
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2025, 3, 26),
    totalHoles: 18,
    startingNine: StartingNine.back,
  );
}

// ─── Helpers para crear módulos ───────────────────────────────────────────────
/// El match sobre los 18 con presiones: Nassau con los dos nueves a cero.
BetModuleInstance _matchMod(List<String> pids) =>
    BetModuleInstance.defaultFor(BetModuleType.nassau, pids).copyWith(
      nassauConfig: const NassauConfig(
        frontValue: 0,
        backValue: 0,
        totalValue: 100,
        pressEnabled: true,
        frontPressValue: 50,
        backPressValue: 50,
        autoPressTrigger: 2,
        mode: GrossNetMode.net,
      ),
    );

BetModuleInstance _medalMod(List<String> pids) =>
    BetModuleInstance.defaultFor(BetModuleType.medal, pids).copyWith(
      medalConfig: const MedalConfig(
        value: 100,
        mode: GrossNetMode.net,
        holes: 9,
      ),
    );

BetModuleInstance _puttsMod(List<String> pids) =>
    BetModuleInstance.defaultFor(BetModuleType.putts, pids).copyWith(
      puttsConfig: const PuttsConfig(
        value: 50,
        puttsMode: PuttsMode.total,
      ),
    );

// ─── Pares para Match ─────────────────────────────────────────────────────────
// Todos vs todos → 10 pares
final _allPairs = [
  ['CAM', 'KAWA'],
  ['CAM', 'FRANK'],
  ['CAM', 'RICH'],
  ['CAM', 'Alejandro'],
  ['KAWA', 'FRANK'],
  ['KAWA', 'RICH'],
  ['KAWA', 'Alejandro'],
  ['FRANK', 'RICH'],
  ['FRANK', 'Alejandro'],
  ['RICH', 'Alejandro'],
];

// ─── Utilidades de display ───────────────────────────────────────────────────
String _fmt(double v) => v >= 0 ? '+\$${v.toStringAsFixed(0)}' : '-\$${v.abs().toStringAsFixed(0)}';

// ─────────────────────────────────────────────────────────────────────────────
void main() {
  group('SIMULACIÓN 26 Mar – Resultados completos', () {

    late Round round;
    late List<LedgerEntry> allEntries;

    setUpAll(() {
      // Crear grupos: uno por par para Match, más un grupo de Medal y uno de Putts
      final matchGroups = _allPairs.asMap().entries.map((e) {
        final pids = e.value;
        return BetGroup(
          id: 'match_${e.key}',
          name: '${pids[0]} vs ${pids[1]}',
          format: PartidaFormat.oneVsOne,
          playerIds: pids,
          modules: [_matchMod(pids)],
        );
      }).toList();

      // Medal: allVsAll (todos vs todos, cada par independiente)
      final allPids = ['CAM', 'KAWA', 'FRANK', 'RICH', 'Alejandro'];
      final medalGroup = BetGroup(
        id: 'medal_all',
        name: 'Medal Neto Todos vs Todos',
        format: PartidaFormat.allInOnePot,
        playerIds: allPids,
        modules: [
          BetModuleInstance.defaultFor(BetModuleType.medal, allPids).copyWith(
            medalConfig: const MedalConfig(
              value: 100,
              mode: GrossNetMode.net,
              holes: 9,
            ),
            formatMode: BetFormatMode.allVsAll,  // cada par independiente
          ),
        ],
      );

      // Putts: allVsAll (por pares)
      final puttsGroup = BetGroup(
        id: 'putts_all',
        name: 'Putts Todos vs Todos',
        format: PartidaFormat.allInOnePot,
        playerIds: allPids,
        modules: [
          BetModuleInstance.defaultFor(BetModuleType.putts, allPids).copyWith(
            puttsConfig: const PuttsConfig(
              value: 50,
              puttsMode: PuttsMode.total,
            ),
            formatMode: BetFormatMode.allVsAll,
          ),
        ],
      );

      round = _buildRound([...matchGroups, medalGroup, puttsGroup]);
      allEntries = BetEngine.computeAll(round);
    });

    // ── STEP 1: Scores netos por jugador ──────────────────────────────────────
    test('1. Scores brutos y ventajas bilaterales', () {
      print('\n══════════════════════════════════════════════════════════════════');
      print('  SCORES BRUTOS (B9: hoyos 10-18)');
      print('══════════════════════════════════════════════════════════════════');
      
      final pids = ['CAM', 'KAWA', 'FRANK', 'RICH', 'Alejandro'];
      final holes = List.generate(9, (i) => 10 + i);
      final pars  = [4, 5, 4, 4, 3, 4, 3, 5, 4];
      
      // Header
      print('Jugador    | H10 H11 H12 H13 H14 H15 H16 H17 H18 | GROSS | +/-Par');
      print('-----------+---------------------------------------|-------|-------');
      for (final pid in pids) {
        final s = _scores[pid]!;
        final gross = s.fold(0, (a, b) => a + b);
        final par = pars.fold(0, (a, b) => a + b); // 36
        final rel = gross - par;
        final relStr = rel >= 0 ? '+$rel' : '$rel';
        final scoreStr = s.map((v) => v.toString().padLeft(3)).join(' ');
        print('${pid.padRight(10)} |$scoreStr   |   $gross  | $relStr');
      }
      print('PAR        |  4   5   4   4   3   4   3   5   4   |   36  |');
      
      print('\n══════════════════════════════════════════════════════════════════');
      print('  VENTAJAS MANUALES (strokes que recibe cada jugador)');
      print('══════════════════════════════════════════════════════════════════');
      print('Receptor   | vs CAM | vs KAWA | vs FRANK | vs RICH | vs Alej');
      print('-----------+--------+---------+----------+---------+--------');
      for (final pid in pids) {
        if (pid == 'CAM') { print('CAM        |   —    |    —    |    —     |    —    |   —'); continue; }
        final m = _manuals[pid]!;
        String cell(String opp) {
          if (opp == pid) return '   —  ';
          final v = m[opp];
          if (v == null) return '   0  ';
          if (v > 0) return '+${v.toStringAsFixed(0).padLeft(2)}    ';
          return '${v.toStringAsFixed(0).padLeft(3)}   ';
        }
        print('${pid.padRight(10)} | ${cell('CAM')} | ${cell('KAWA')} | ${cell('FRANK')} | ${cell('RICH')} | ${cell('Alejandro')}');
      }
    });

    // ── STEP 2: Medal neto todos vs todos ─────────────────────────────────────
    test('2. Medal: net todos vs todos (allVsAll)', () {
      print('\n══════════════════════════════════════════════════════════════════');
      print('  MEDAL NETO – TODOS vs TODOS (valor: \$100 por par)');
      print('══════════════════════════════════════════════════════════════════');
      
      final medalEntries = allEntries.where((e) => e.betType == BetModuleType.medal).toList();

      // Calcular net por par para mostrar la tabla
      // En allVsAll cada par usa netFor bilateral via _effectiveHcps (igual que 1v1)
      print('\n  Resultados Medal por par (net bilateral con manualHandicap):');
      print('  ──────────────────────────────────────────────────────────────');
      if (medalEntries.isEmpty) {
        print('  ⚠ Sin entries de Medal');
      } else {
        // Agrupar por par y mostrar
        final shown = <String>{};
        for (final e in medalEntries) {
          final key = [e.fromPlayerId, e.toPlayerId]..sort();
          final k = key.join('-');
          if (shown.contains(k)) continue;
          shown.add(k);
          print('  ${e.fromPlayerId.padRight(10)} paga \$${e.amount.toStringAsFixed(0)} a ${e.toPlayerId}  [${e.reason}]');
        }
        print('\n  (Total entries: ${medalEntries.length} pagos entre pares)');
      }

      // Resumen balance de Medal por jugador
      print('\n  Balance Medal por jugador:');
      final pids = ['CAM', 'KAWA', 'FRANK', 'RICH', 'Alejandro'];
      for (final pid in pids) {
        double bal = 0;
        for (final e in medalEntries) {
          if (e.toPlayerId == pid) {
            bal += e.amount;
          } else if (e.fromPlayerId == pid) bal -= e.amount;
        }
        final fmt = bal >= 0 ? '+\$${bal.toStringAsFixed(0)}' : '-\$${bal.abs().toStringAsFixed(0)}';
        print('  ${pid.padRight(10)}: $fmt');
      }
    });

    // ── STEP 3: Match + Presiones por par ─────────────────────────────────────
    test('3. Match + Presiones: resultado por par', () {
      print('\n══════════════════════════════════════════════════════════════════');
      print('  MATCH + PRESIONES (Match \$100, Press \$50 cada 2 hoyos abajo)');
      print('══════════════════════════════════════════════════════════════════');
      
      final matchEntries = allEntries.where((e) => e.betType == BetModuleType.nassau).toList();
      
      // Agrupar por par
      for (final pair in _allPairs) {
        final p1 = pair[0]; final p2 = pair[1];
        final pairEntries = matchEntries.where((e) =>
            (e.fromPlayerId == p1 && e.toPlayerId == p2) ||
            (e.fromPlayerId == p2 && e.toPlayerId == p1)).toList();
        
        if (pairEntries.isEmpty) {
          print('  $p1 vs $p2: AS (empate, sin pago)');
        } else {
          double balP1 = 0;
          for (final e in pairEntries) {
            if (e.toPlayerId == p1) {
              balP1 += e.amount;
            } else {
              balP1 -= e.amount;
            }
          }
          final winner = balP1 > 0 ? p1 : p2;
          final loser  = balP1 > 0 ? p2 : p1;
          final total  = balP1.abs();
          final details = pairEntries.map((e) {
            final w = e.toPlayerId;
            return '${e.reason}: \$${e.amount.toStringAsFixed(0)} → $w';
          }).join(', ');
          print('  $p1 vs $p2: $winner gana \$${total.toStringAsFixed(0)} ($details)');
        }
      }
    });

    // ── STEP 4: Putts ─────────────────────────────────────────────────────────
    test('4. Putts: nota sobre putts', () {
      print('\n══════════════════════════════════════════════════════════════════');
      print('  PUTTS (\$50 por par)');
      print('══════════════════════════════════════════════════════════════════');
      
      final puttsEntries = allEntries.where((e) => e.betType == BetModuleType.putts).toList();
      
      if (puttsEntries.isEmpty) {
        print('  ⚠ Sin datos de putts — los scores de la scorecard no incluyen putts.');
        print('  (El CSV solo tiene scores brutos, no putts separados)');
        print('  Putts = \$50 por par, necesita dato de putts por hoyo para calcular.');
      } else {
        for (final e in puttsEntries) {
          print('  ${e.fromPlayerId} → ${e.toPlayerId}  \$${e.amount.toStringAsFixed(0)}  (${e.reason})');
        }
      }
    });

    // ── STEP 5: Balance final por jugador ─────────────────────────────────────
    test('5. BALANCE FINAL por jugador (sin Putts)', () {
      print('\n══════════════════════════════════════════════════════════════════');
      print('  BALANCE FINAL POR JUGADOR');
      print('  (Match + Presiones + Medal | Putts excluido — sin datos)');
      print('══════════════════════════════════════════════════════════════════');
      
      final balances = LedgerEngine.playerBalances(round);
      final pids = ['CAM', 'KAWA', 'FRANK', 'RICH', 'Alejandro'];
      final sorted = pids.toList()..sort((a, b) => (balances[b] ?? 0).compareTo(balances[a] ?? 0));
      
      print('  Lugar  Jugador     Balance    Match+Press   Medal');
      print('  ─────────────────────────────────────────────────');
      
      final matchEntries = allEntries.where((e) => e.betType == BetModuleType.nassau).toList();
      final medalEntries = allEntries.where((e) => e.betType == BetModuleType.medal).toList();
      
      int lugar = 1;
      for (final pid in sorted) {
        double matchBal = 0, medalBal = 0;
        for (final e in matchEntries) {
          if (e.toPlayerId == pid) {
            matchBal += e.amount;
          } else if (e.fromPlayerId == pid) matchBal -= e.amount;
        }
        for (final e in medalEntries) {
          if (e.toPlayerId == pid) {
            medalBal += e.amount;
          } else if (e.fromPlayerId == pid) medalBal -= e.amount;
        }
        final total = balances[pid] ?? 0;
        final emoji = total > 0 ? '🟢' : (total < 0 ? '🔴' : '⚪');
        print('  $emoji  $lugar°  ${pid.padRight(10)}  ${_fmt(total).padLeft(8)}   ${_fmt(matchBal).padLeft(8)}    ${_fmt(medalBal).padLeft(8)}');
        lugar++;
      }
      
      // Verificar suma cero
      final sumTotal = pids.fold(0.0, (s, pid) => s + (balances[pid] ?? 0));
      print('\n  Suma total: ${sumTotal.toStringAsFixed(2)} (debe ser ~0)');
    });

    // ── STEP 6: Pagos mínimos ─────────────────────────────────────────────────
    test('6. Pagos mínimos a realizar', () {
      print('\n══════════════════════════════════════════════════════════════════');
      print('  PAGOS MÍNIMOS PARA LIQUIDAR');
      print('══════════════════════════════════════════════════════════════════');
      
      final debts = LedgerEngine.compute(round);
      if (debts.isEmpty) {
        print('  ✅ Todos en cero — sin pagos necesarios');
      } else {
        for (final d in debts) {
          print('  ${d.fromPlayerId.padRight(10)} → ${d.toPlayerId.padRight(10)}  \$${d.amount.toStringAsFixed(0)}');
        }
      }
      
      // Detalle break down de cada par
      print('\n  DETALLE MATCH+PRESS POR PAR:');
      print('  ──────────────────────────────────────────────');
      final matchEntries = allEntries.where((e) => e.betType == BetModuleType.nassau).toList();
      for (final pair in _allPairs) {
        final p1 = pair[0]; final p2 = pair[1];
        // Era `matchAutoPressLive`. El match sobre 18 es ahora un Nassau con
        // los dos nueves a cero, y su vista en vivo es la del Nassau.
        final live = BetEngine.nassauPressLiveStatus(round, p1, p2,
          BetModuleInstance.defaultFor(BetModuleType.nassau, pair).copyWith(
            nassauConfig: const NassauConfig(
              frontValue: 0, backValue: 0, totalValue: 100,
              pressEnabled: true, frontPressValue: 50, backPressValue: 50,
              autoPressTrigger: 2, mode: GrossNetMode.net,
            ),
          ),
        );
        final entries = matchEntries.where((e) =>
            (e.fromPlayerId == p1 && e.toPlayerId == p2) ||
            (e.fromPlayerId == p2 && e.toPlayerId == p1)).toList();
        
        if (entries.isEmpty) {
          print('  $p1 vs $p2: AS');
        } else {
          final total = entries.fold(0.0, (s, e) {
            if (e.toPlayerId == p1) return s + e.amount;
            return s - e.amount;
          });
          final winner = total > 0 ? p1 : p2;
          print('  $p1 vs $p2 → $winner gana \$${total.abs().toStringAsFixed(0)} (${entries.length} matches/presses)');
        }
      }
    });
  });
}
