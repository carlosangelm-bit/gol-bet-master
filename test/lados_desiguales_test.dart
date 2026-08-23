// ─────────────────────────────────────────────────────────────────────────────
// LADOS DESIGUALES — el dinero de un 2 contra 3
//
// Es la clase de cosa donde un reparto pensado para lados iguales da una cifra
// PLAUSIBLE y equivocada, como el bote del cuadro pagando al líder de la tabla.
// La aritmética es simple: si la pareja gana $300, cada uno cobra $150 y cada
// uno de los tres paga $100.
//
// Lo que se comprueba no es la formación —eso va en formaciones_test— sino la
// liquidación: que el total movido sea exactamente lo apostado, que nadie del
// lado ganador cobre de más, y que la suma de todos los balances sea cero.
//
// La última es la que caza los errores de reparto: un ledger que no cierra en
// cero está creando o destruyendo dinero, y eso no se ve mirando una fila.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';

const p1 = 'pid_par1', p2 = 'pid_par2';
const r1 = 'pid_res1', r2 = 'pid_res2', r3 = 'pid_res3';

CourseInfo _course() => CourseInfo(
    name: 'Los Encinos',
    holes: List.generate(
        18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Una ronda 2 contra 3 donde la PAREJA gana los tres segmentos del Nassau.
///
/// El Nassau por equipos vale lo configurado EN TOTAL: F+B+T = 100+100+100 =
/// $300 si la pareja se lleva los tres.
Round _round({
  required List<String> ladoA,
  required List<String> ladoB,
  double front = 100,
  double back = 100,
  double total = 100,
  Map<String, int>? golpes,
}) {
  final todos = [...ladoA, ...ladoB];
  // La pareja anota 4 en todos los hoyos; el resto, 5. Gana la pareja en los
  // tres segmentos sin empates.
  final g = golpes ?? {for (final p in todos) p: ladoA.contains(p) ? 4 : 5};
  final players =
      todos.map((id) => Player(id: id, name: id.toUpperCase())).toList();

  final mod = BetModuleInstance(
    id: 'mod_nassau',
    type: BetModuleType.nassau,
    name: 'Nassau',
    participantIds: todos,
    sides: [
      BetSide(id: 'sA', name: 'Pareja', playerIds: ladoA),
      BetSide(id: 'sB', name: 'Resto', playerIds: ladoB),
    ],
    nassauConfig: NassauConfig(
      frontValue: front,
      backValue: back,
      totalValue: total,
      pressEnabled: false,
      // Bruto: el reparto del dinero es lo que se prueba, no la ventaja.
      mode: GrossNetMode.gross,
    ),
  );

  return Round(
    id: 'r1',
    name: 'Sábado',
    course: _course(),
    players: players,
    roundPlayers:
        players.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'grp',
          name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: todos,
          modules: [mod]),
    ],
    scores: {
      for (final p in todos)
        p: {
          for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: p, hole: h, grossScore: g[p]!),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 8, 1),
    totalHoles: 18,
    isFinished: true,
  );
}

void main() {
  group('1 · 2 contra 3: la aritmética del libro', () {
    final round = _round(ladoA: const [p1, p2], ladoB: const [r1, r2, r3]);
    final balances = LedgerEngine.playerBalances(round);

    test('la pareja gana \$300 en total, no \$300 cada uno', () {
      // Un duelo por equipos vale lo configurado EN TOTAL: se comporta igual que
      // un jugador contra otro. Multiplicarlo por los cruces sería mover $1800.
      final ganado = balances[p1]! + balances[p2]!;
      expect(ganado, closeTo(300, 0.001));
    });

    test('cada uno de la pareja cobra \$150', () {
      expect(balances[p1], closeTo(150, 0.001));
      expect(balances[p2], closeTo(150, 0.001));
    });

    test('cada uno de los tres paga \$100', () {
      for (final r in [r1, r2, r3]) {
        expect(balances[r], closeTo(-100, 0.001), reason: r);
      }
    });

    test('el ledger cierra en CERO: no se crea ni se destruye dinero', () {
      // Es el que caza los errores de reparto. Una fila puede parecer plausible;
      // un total que no cierra en cero no.
      final suma = balances.values.fold(0.0, (s, v) => s + v);
      expect(suma, closeTo(0, 0.001));
    });

    test('nadie del lado ganador paga, ni nadie del perdedor cobra', () {
      expect(balances[p1]! > 0 && balances[p2]! > 0, isTrue);
      for (final r in [r1, r2, r3]) {
        expect(balances[r]! < 0, isTrue, reason: r);
      }
    });
  });

  group('2 · el reparto no depende del tamaño de los lados', () {
    /// Lo apostado, movido, para una composición cualquiera.
    (double, double) _mueve(List<String> a, List<String> b) {
      final balances = LedgerEngine.playerBalances(_round(ladoA: a, ladoB: b));
      final ganado = a.fold(0.0, (s, p) => s + (balances[p] ?? 0));
      final suma = balances.values.fold(0.0, (s, v) => s + v);
      return (ganado, suma);
    }

    test('2v3, 2v2, 3v2, 1v3 y 2v1 mueven los mismos \$300', () {
      // Es lo que hace que un lado de tres no sea "más dinero": el importe es
      // del duelo, no del jugador.
      for (final caso in [
        (const [p1, p2], const [r1, r2, r3]),
        (const [p1, p2], const [r1, r2]),
        (const [p1, p2, r3], const [r1, r2]),
        (const [p1], const [r1, r2, r3]),
        (const [p1, p2], const [r1]),
      ]) {
        final (ganado, suma) = _mueve(caso.$1, caso.$2);
        expect(ganado, closeTo(300, 0.001),
            reason: '${caso.$1.length}v${caso.$2.length}');
        expect(suma, closeTo(0, 0.001),
            reason: 'no cierra en ${caso.$1.length}v${caso.$2.length}');
      }
    });

    test('con un lado de tres, cada uno paga MENOS que si fueran dos', () {
      // La consecuencia real de jugar contra más gente: el mismo premio se
      // reparte entre más bolsillos. Si saliera igual, el importe se estaría
      // multiplicando por el tamaño del lado.
      final tres = LedgerEngine.playerBalances(
          _round(ladoA: const [p1, p2], ladoB: const [r1, r2, r3]));
      final dos = LedgerEngine.playerBalances(
          _round(ladoA: const [p1, p2], ladoB: const [r1, r2]));
      expect(tres[r1]!.abs(), lessThan(dos[r1]!.abs()));
      expect(tres[r1], closeTo(-100, 0.001));
      expect(dos[r1], closeTo(-150, 0.001));
    });
  });

  group('3 · el importe del cruce, en aislado', () {
    test('reparte el total exacto entre los cruces, con lados desiguales', () {
      // 300 entre 2×3 = 50 por cruce. Cada ganador recibe 3×50 = 150; cada
      // perdedor paga 2×50 = 100.
      final cruce = BetEngine.teamCrossAmount(300, 2, 3);
      expect(cruce, closeTo(50, 0.001));
      expect(cruce * 3, closeTo(150, 0.001));
      expect(cruce * 2, closeTo(100, 0.001));
      expect(cruce * 2 * 3, closeTo(300, 0.001));
    });

    test('un lado vacío no mueve dinero en vez de dividir por cero', () {
      expect(BetEngine.teamCrossAmount(300, 0, 3), 0);
      expect(BetEngine.teamCrossAmount(300, 2, 0), 0);
    });
  });

  group('4 · el best ball de un lado de tres usa su MEJOR bola', () {
    test('el lado de tres gana el hoyo con la bola de uno solo', () {
      // Es lo que compensa la desigualdad, y es la razón por la que 2 contra 3
      // no está tan desequilibrado: basta con que uno de los tres acierte.
      final round = _round(
        ladoA: const [p1, p2],
        ladoB: const [r1, r2, r3],
        golpes: const {p1: 5, p2: 5, r1: 6, r2: 6, r3: 4},
      );
      final balances = LedgerEngine.playerBalances(round);
      // Gana el lado de tres: cada uno cobra 100 y cada uno de la pareja paga
      // 150.
      expect(balances[r3], closeTo(100, 0.001));
      expect(balances[p1], closeTo(-150, 0.001));
      expect(balances.values.fold(0.0, (s, v) => s + v), closeTo(0, 0.001));
    });
  });
}
