// ── RONDA DE PRUEBA BEST BALL ─────────────────────────────────────────────────
// Genera una ronda completa con datos fijos para verificar cálculos
// Equipo A: CAM (HCP 9) + CAV (HCP 5)   → bb_team_sideA  HCP = 9*0.35+5*0.15 = 3.15+0.75 = 3.9 → 4
// Equipo B: AAM (HCP 13) + RAFA (HCP 20) → bb_team_sideB  HCP = 13*0.35+20*0.15 = 4.55+3 = 7.55 → 8
//
// Ventaja vs. el equipo con menos HCP (A=4):
//   Equipo A: 0 golpes de ventaja
//   Equipo B: 8-4 = 4 golpes de ventaja (en los 4 hoyos más difíciles)
//
// Scores brutos (9 hoyos), Par=36 (4-5-3-4-4-3-5-4-4):
//   Hoyo  SI  Par  CAM  CAV  BestA  AAM  RAFA  BestB
//    1    5    4    5    4     4      6    5      5
//    2   11    5    6    5     5      6    7      6
//    3   15    3    4    3     3      4    5      4
//    4    1    4    5    6     5      5    6      5
//    5    9    4    4    5     4      5    4      4
//    6   17    3    4    4     4      4    3      3
//    7    3    5    6    5     5      6    7      6
//    8   13    4    5    4     4      5    6      5
//    9    7    4    5    4     4      5    5      5
//
// BRUTO Total: A= 4+5+3+5+4+4+5+4+4 = 38  B= 5+6+4+5+4+3+6+5+5 = 43
//
// NETO (ventaja vs base=0 para A, vs base=4 para B aplicando golpes en SI ≤ 4):
//   Equipo B recibe 4 golpes: en hoyos SI=1(H4), SI=3(H7), SI=5(H1), SI=7(H9)
//   H4: B bestBruto=5 → recibe 1 → neto=4
//   H7: B bestBruto=6 → recibe 1 → neto=5
//   H1: B bestBruto=5 → recibe 1 → neto=4
//   H9: B bestBruto=5 → recibe 1 → neto=4
//   Resto: neto=bruto
//
// Nassau NET Front 9:
//   H1: A=4 B=4 → empate
//   H2: A=5 B=6 → A gana
//   H3: A=3 B=4 → A gana
//   H4: A=5 B=4 → B gana
//   H5: A=4 B=4 → empate
//   H6: A=4 B=3 → B gana
//   H7: A=5 B=5 → empate
//   H8: A=4 B=5 → A gana
//   H9: A=4 B=4 → empate
//   Front9: A gana H2,H3,H8 (3pts) B gana H4,H6 (2pts) → A +1
//   Total18: A=38(neto) B=39(neto=43-4) → A gana total
//   (Solo front9 en ronda de 9 hoyos)
//   Resultado: Equipo A +1 front → cobra 50 + 100 total = ganancia
// ─────────────────────────────────────────────────────────────────────────────

import 'package:uuid/uuid.dart';
import '../models/models.dart';

const _uuid = Uuid();

Round createTestBestBallRound() {
  // ── Jugadores reales ──
  const camId   = 'test_cam';
  const cavId   = 'test_cav';
  const aamId   = 'test_aam';
  const rafaId  = 'test_rafa';

  // ── IDs de equipos virtuales ──
  const sideAId  = 'test_sideA';
  const sideBId  = 'test_sideB';
  final bbTeamAId = 'bb_team_$sideAId';
  final bbTeamBId = 'bb_team_$sideBId';

  final cam  = Player(id: camId,  name: 'CAM',  handicapBase: 9,  colorIndex: 0);
  final cav  = Player(id: cavId,  name: 'CAV',  handicapBase: 5,  colorIndex: 1);
  final aam  = Player(id: aamId,  name: 'AAM',  handicapBase: 13, colorIndex: 2);
  final rafa = Player(id: rafaId, name: 'RAFA', handicapBase: 20, colorIndex: 3);

  // HCP de equipo: 35% menor + 15% mayor (redondeado)
  // Equipo A: CAV=5, CAM=9 → 5*0.35 + 9*0.15 = 1.75 + 1.35 = 3.1 → 3
  // Equipo B: AAM=13, RAFA=20 → 13*0.35 + 20*0.15 = 4.55 + 3.0 = 7.55 → 8
  final bbTeamA = Player(
    id: bbTeamAId, name: 'Equipo A',
    handicapBase: 3, colorIndex: 0,
    isVirtual: true, teamMemberIds: [camId, cavId],
  );
  final bbTeamB = Player(
    id: bbTeamBId, name: 'Equipo B',
    handicapBase: 8, colorIndex: 2,
    isVirtual: true, teamMemberIds: [aamId, rafaId],
  );

  // ── Módulo Nassau con lados Best Ball ──
  final nassauModuleId = _uuid.v4();
  final nassauModule = BetModuleInstance(
    id: nassauModuleId,
    type: BetModuleType.nassau,
    name: 'Nassau',
    participantIds: [bbTeamAId, bbTeamBId],
    nassauConfig: const NassauConfig(
      frontValue: 50, backValue: 50, totalValue: 100,
      mode: GrossNetMode.net,
    ),
    sides: [
      BetSide(id: sideAId, name: 'Equipo A', playerIds: [camId, cavId], playMode: TeamPlayMode.bestBall),
      BetSide(id: sideBId, name: 'Equipo B', playerIds: [aamId, rafaId], playMode: TeamPlayMode.bestBall),
    ],
  );

  final betGroup = BetGroup(
    id: _uuid.v4(),
    name: 'Partida Principal',
    format: PartidaFormat.allInOnePot,
    playerIds: [bbTeamAId, bbTeamBId],
    modules: [nassauModule],
  );

  // ── RoundPlayers (handicap en ronda = handicap base en campo estándar) ──
  final roundPlayers = [
    RoundPlayer(playerId: camId,     handicapEnRonda: 9),
    RoundPlayer(playerId: cavId,     handicapEnRonda: 5),
    RoundPlayer(playerId: aamId,     handicapEnRonda: 13),
    RoundPlayer(playerId: rafaId,    handicapEnRonda: 20),
    RoundPlayer(playerId: bbTeamAId, handicapEnRonda: 3),
    RoundPlayer(playerId: bbTeamBId, handicapEnRonda: 8),
  ];

  // ── Scores brutos de 9 hoyos ──
  //  Hoyo  CAM  CAV  AAM  RAFA
  //   1     5    4    6    5
  //   2     6    5    6    7
  //   3     4    3    4    5
  //   4     5    6    5    6
  //   5     4    5    5    4
  //   6     4    4    4    3
  //   7     6    5    6    7
  //   8     5    4    5    6
  //   9     5    4    5    5
  final rawScores = <String, Map<int, List<int>>>{
    camId:  {1:[5,1], 2:[6,2], 3:[4,1], 4:[5,2], 5:[4,1], 6:[4,1], 7:[6,2], 8:[5,2], 9:[5,2]},
    cavId:  {1:[4,2], 2:[5,1], 3:[3,1], 4:[6,2], 5:[5,2], 6:[4,1], 7:[5,2], 8:[4,1], 9:[4,2]},
    aamId:  {1:[6,2], 2:[6,2], 3:[4,1], 4:[5,2], 5:[5,2], 6:[4,2], 7:[6,2], 8:[5,2], 9:[5,2]},
    rafaId: {1:[5,2], 2:[7,2], 3:[5,1], 4:[6,2], 5:[4,2], 6:[3,1], 7:[7,2], 8:[6,2], 9:[5,2]},
  };

  final scores = <String, Map<int, HoleScore>>{};
  for (final pid in [camId, cavId, aamId, rafaId, bbTeamAId, bbTeamBId]) {
    scores[pid] = {};
  }
  rawScores.forEach((pid, holes) {
    holes.forEach((hole, gp) {
      scores[pid]![hole] = HoleScore(playerId: pid, hole: hole, grossScore: gp[0], putts: gp[1]);
    });
  });

  return Round(
    id: _uuid.v4(),
    name: 'Prueba Best Ball',
    course: CourseInfo.standard,
    players: [cam, cav, aam, rafa, bbTeamA, bbTeamB],
    roundPlayers: roundPlayers,
    betGroups: [betGroup],
    scores: scores,
    events: {for (final pid in [camId, cavId, aamId, rafaId, bbTeamAId, bbTeamBId]) pid: {}},
    oyeseRankings: {},
    sliding: [],
    createdAt: DateTime.now(),
    startingNine: StartingNine.front,
    totalHoles: 9,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// VERIFICACIÓN MATEMÁTICA (para consola)
// ─────────────────────────────────────────────────────────────────────────────
String verifyBestBallCalculations(Round round) {
  final sb = StringBuffer();
  sb.writeln('═══════════════════════════════════════════════');
  sb.writeln('VERIFICACIÓN RONDA BEST BALL TEST');
  sb.writeln('═══════════════════════════════════════════════');

  // Campo estándar: SI por hoyo
  final course = CourseInfo.standard;
  final pars   = {for (final h in course.holes) h.hole: h.par};
  final sis    = {for (final h in course.holes) h.hole: h.strokeIndex};

  // Equipos virtuales
  final bbTeams = round.players.where((p) => p.isVirtual && p.id.startsWith('bb_team_')).toList();

  // Handicaps en ronda
  final hcps = {for (final rp in round.roundPlayers) rp.playerId: rp.handicapEnRonda};

  // Base del duelo = menor HCP entre los equipos virtuales
  final teamHcps = bbTeams.map((t) => hcps[t.id] ?? 0.0).toList()..sort();
  final baseHcp  = teamHcps.first;

  sb.writeln('\n── Equipos ──');
  for (final t in bbTeams) {
    final memberNames = t.teamMemberIds.map((id) {
      final p = round.players.firstWhere((pp) => pp.id == id, orElse: () => Player(id: id, name: id));
      return '${p.name}(${hcps[id]?.toStringAsFixed(0) ?? "-"})';
    }).join(' + ');
    sb.writeln('  ${t.name}: $memberNames → HCP equipo=${hcps[t.id]?.toStringAsFixed(0)}');
  }
  sb.writeln('  Base HCP (duelo) = $baseHcp');

  sb.writeln('\n── Scores brutos y netos por hoyo ──');
  sb.writeln('H  SI  Par  ${bbTeams.map((t) => '${t.name}Bruto ${t.name}Neto').join('  ')}');
  for (int h = 1; h <= round.totalHoles; h++) {
    final par = pars[h] ?? 4;
    final si  = sis[h]  ?? 18;
    final row = StringBuffer('$h  $si   $par  ');

    for (final team in bbTeams) {
      // Mejor bruto del equipo
      final memberScores = team.teamMemberIds
          .map((id) => round.getScore(id, h))
          .where((s) => s.hasScore)
          .map((s) => s.grossScore!)
          .toList();
      if (memberScores.isEmpty) { row.write('  -        -     '); continue; }
      memberScores.sort();
      final bestBruto = memberScores.first;

      // Mejor neto del equipo
      int? bestNeto;
      for (final memberId in team.teamMemberIds) {
        final sc = round.getScore(memberId, h);
        if (!sc.hasScore) continue;
        final memberHcp = hcps[memberId] ?? 0.0;
        final diff = (memberHcp - baseHcp).round().clamp(0, 18);
        final strokesHere = diff >= si ? 1 : 0;
        final net = sc.grossScore! - strokesHere;
        if (bestNeto == null || net < bestNeto) bestNeto = net;
      }

      row.write('  $bestBruto(${bestBruto - par >= 0 ? '+' : ''}${bestBruto - par})      ${bestNeto ?? '-'}(${(bestNeto ?? par) - par >= 0 ? '+' : ''}${(bestNeto ?? par) - par})  ');
    }
    sb.writeln(row);
  }

  // Totales brutos
  sb.writeln('\n── Totales brutos ──');
  for (final team in bbTeams) {
    int total = 0;
    for (int h = 1; h <= round.totalHoles; h++) {
      final memberScores = team.teamMemberIds
          .map((id) => round.getScore(id, h))
          .where((s) => s.hasScore)
          .map((s) => s.grossScore!)
          .toList();
      if (memberScores.isNotEmpty) {
        memberScores.sort();
        total += memberScores.first;
      }
    }
    final par = course.holes.take(round.totalHoles).fold(0, (s, h) => s + h.par);
    sb.writeln('  ${team.name}: $total (${total - par >= 0 ? '+' : ''}${total - par} vs par $par)');
  }

  // Totales netos
  sb.writeln('\n── Totales netos ──');
  for (final team in bbTeams) {
    int totalNeto = 0;
    for (int h = 1; h <= round.totalHoles; h++) {
      final si = sis[h] ?? 18;
      int? bestNeto;
      for (final memberId in team.teamMemberIds) {
        final sc = round.getScore(memberId, h);
        if (!sc.hasScore) continue;
        final memberHcp = hcps[memberId] ?? 0.0;
        final diff = (memberHcp - baseHcp).round().clamp(0, 18);
        final strokesHere = diff >= si ? 1 : 0;
        final net = sc.grossScore! - strokesHere;
        if (bestNeto == null || net < bestNeto) bestNeto = net;
      }
      totalNeto += bestNeto ?? 0;
    }
    sb.writeln('  ${team.name}: $totalNeto neto');
  }

  // Nassau por hoyo
  sb.writeln('\n── Nassau Neto hoyo a hoyo ──');
  int scoreA = 0, scoreB = 0;
  final teamA = bbTeams.firstWhere((t) => t.name == 'Equipo A', orElse: () => bbTeams.first);
  final teamB = bbTeams.firstWhere((t) => t.name == 'Equipo B', orElse: () => bbTeams.last);
  for (int h = 1; h <= round.totalHoles; h++) {
    final si = sis[h] ?? 18;
    int? netoA, netoB;
    for (final team in [teamA, teamB]) {
      int? bestNeto;
      for (final memberId in team.teamMemberIds) {
        final sc = round.getScore(memberId, h);
        if (!sc.hasScore) continue;
        final memberHcp = hcps[memberId] ?? 0.0;
        final diff = (memberHcp - baseHcp).round().clamp(0, 18);
        final strokesHere = diff >= si ? 1 : 0;
        final net = sc.grossScore! - strokesHere;
        if (bestNeto == null || net < bestNeto) bestNeto = net;
      }
      if (team == teamA) {
        netoA = bestNeto;
      } else {
        netoB = bestNeto;
      }
    }
    final winner = netoA == null || netoB == null
        ? 'N/A'
        : netoA < netoB ? 'A' : netoB < netoA ? 'B' : 'EMPATE';
    if (winner == 'A') scoreA++;
    if (winner == 'B') scoreB++;
    sb.writeln('  H$h SI=$si: A=${netoA ?? '-'} vs B=${netoB ?? '-'} → $winner');
  }
  sb.writeln('\n── Nassau Result (Front9) ──');
  sb.writeln('  A ganó $scoreA hoyos, B ganó $scoreB hoyos');
  final winner = scoreA > scoreB ? 'EQUIPO A' : scoreB > scoreA ? 'EQUIPO B' : 'EMPATE';
  sb.writeln('  GANADOR FRONT9: $winner');
  sb.writeln('═══════════════════════════════════════════════');
  return sb.toString();
}
