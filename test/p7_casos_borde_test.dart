// ─────────────────────────────────────────────────────────────────────────────
// P7 · CASOS BORDE DE DATOS
//
// Estados que son difíciles de montar a mano y fáciles de olvidar: la ronda que
// nadie empezó, la que va a medias, el empate general, el jugador sin handicap,
// el torneo con un solo inscrito.
//
// El criterio en todos es el mismo, y es lo que separa un cero explicado de un
// cero mudo: la app puede no poder liquidar, pero tiene que DECIR por qué. Un
// cero sin explicación se lee como un fallo.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/engines/settlement_notes.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';

const a = 'pid_a1', b = 'pid_b2', c = 'pid_c3', d = 'pid_d4';
const cuatro = [a, b, c, d];

CourseInfo _course() => CourseInfo(
    name: 'Los Encinos',
    holes: List.generate(18,
        (i) => CourseHole(hole: i + 1, par: i % 5 == 4 ? 3 : 4, strokeIndex: i + 1)));

Round _round({
  List<BetModuleType> tipos = const [BetModuleType.skins],
  Map<String, int> golpes = const {},
  Map<String, double> handicaps = const {},
  int hastaHoyo = 18,
  int putts = 2,
  Map<String, String>? nombres,
}) {
  final players = cuatro
      .map((id) => Player(
          id: id,
          name: nombres?[id] ?? id.toUpperCase(),
          handicapBase: handicaps[id] ?? 0))
      .toList();
  return Round(
    id: 'r',
    name: 'R',
    course: _course(),
    players: players,
    roundPlayers: players
        .map((p) => RoundPlayer(
            playerId: p.id, handicapEnRonda: handicaps[p.id] ?? 0))
        .toList(),
    betGroups: [
      BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: cuatro,
          modules: [
            for (final t in tipos)
              BetModuleInstance.defaultFor(t, cuatro, id: 'm_${t.name}')
          ])
    ],
    scores: {
      for (final e in golpes.entries)
        e.key: {
          for (var h = 1; h <= hastaHoyo; h++)
            h: HoleScore(
                playerId: e.key, hole: h, grossScore: e.value, putts: putts),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 8, 1),
    totalHoles: 18,
    isFinished: hastaHoyo == 18,
  );
}

void main() {
  group('7.1 · ronda sin ningún score: no liquida, y lo dice', () {
    test('ningún balance se mueve', () {
      final r = _round(
          tipos: const [
            BetModuleType.skins,
            BetModuleType.nassau,
            BetModuleType.snake,
            BetModuleType.rabbit,
          ],
          golpes: const {});
      final bal = LedgerEngine.playerBalances(r);
      expect(bal.values.every((v) => v.abs() < 0.001), isTrue, reason: '$bal');
    });

    test('y las apuestas que tienen algo que decir lo dicen', () {
      // Snake y Rabbit son las que producen cero asientos con el cálculo
      // CORRECTO, y por eso existe el canal de notas.
      final notas = notasDeLiquidacion(_round(
          tipos: const [BetModuleType.snake, BetModuleType.rabbit],
          golpes: const {}));
      expect(notas, isNotEmpty);
      // Con la ronda sin empezar, el tono es provisional: "todavía" no es lo
      // mismo que "en toda la ronda".
      expect(notas.any((n) => n.tono == TonoNota.provisional), isTrue,
          reason: notas.map((n) => '${n.tono.name}: ${n.texto}').join(' | '));
    });
  });

  group('7.2 · ronda a medias: provisional, y lo dice', () {
    test('con 9 de 18 hoyos la nota lo marca provisional', () {
      final notas = notasDeLiquidacion(_round(
          tipos: const [BetModuleType.snake],
          golpes: {for (final p in cuatro) p: 4},
          hastaHoyo: 9,
          putts: 1));
      expect(notas, isNotEmpty);
      expect(notas.first.tono, TonoNota.provisional);
      expect(notas.first.texto, contains('9'),
          reason: 'tiene que decir cuántos hoyos faltan');
    });

    test('y el dinero de lo jugado ya cuenta', () {
      // Provisional no significa cero: los nueve hoyos jugados se liquidan.
      final r = _round(
          tipos: const [BetModuleType.skins],
          golpes: {a: 3, b: 5, c: 5, d: 5},
          hastaHoyo: 9);
      expect(LedgerEngine.playerBalances(r)[a]! > 0, isTrue);
    });
  });

  group('7.3 · todos empatan: cero explicado, no cero mudo', () {
    test('el balance es cero exacto', () {
      final r = _round(
          tipos: const [
            BetModuleType.skins,
            BetModuleType.nassau,
            BetModuleType.medal,
          ],
          golpes: {for (final p in cuatro) p: 4});
      final bal = LedgerEngine.playerBalances(r);
      expect(bal.values.every((v) => v.abs() < 0.001), isTrue, reason: '$bal');
    });

    test('y Snake dice que nadie llegó al umbral, no se queda mudo', () {
      final notas = notasDeLiquidacion(_round(
          tipos: const [BetModuleType.snake],
          golpes: {for (final p in cuatro) p: 4},
          putts: 1));
      expect(notas, hasLength(1));
      expect(notas.first.texto, contains('Nadie'));
      expect(notas.first.tono, TonoNota.informativa,
          reason: 'la ronda está completa: ya no es provisional');
    });
  });

  group('7.5 · jugador sin handicap: el neto no se rompe', () {
    test('con handicap 0 frente a uno con 18, el neto se aplica', () {
      final r = _round(
          tipos: const [BetModuleType.medal],
          golpes: {a: 90, b: 90, c: 90, d: 90},
          handicaps: const {a: 0, b: 18, c: 0, d: 0});
      // Con el mismo bruto, el de 18 de handicap gana en neto.
      final bal = LedgerEngine.playerBalances(r);
      expect(bal[b]! > 0, isTrue, reason: '$bal');
      expect(bal.values.fold(0.0, (s, v) => s + v), closeTo(0, 0.001));
    });

    test('con TODOS a cero no revienta ni deja NaN', () {
      final r = _round(
          tipos: const [BetModuleType.medal, BetModuleType.nassau],
          golpes: {a: 3, b: 4, c: 5, d: 6},
          handicaps: const {});
      final bal = LedgerEngine.playerBalances(r);
      expect(bal.values.every((v) => v.isFinite), isTrue, reason: '$bal');
    });
  });

  group('7.4 · nombres duplicados: se detecta', () {
    test('dos jugadores con el mismo nombre se cuentan como dos', () {
      // No se fusionan por nombre —agrupar por nombre sería peligroso— pero
      // tampoco desaparece uno.
      final r = _round(
          tipos: const [BetModuleType.skins],
          golpes: {a: 3, b: 5, c: 5, d: 5},
          nombres: const {a: 'Carlos', b: 'Carlos'});
      expect(r.players.map((p) => p.id).toSet(), hasLength(4));
      final bal = LedgerEngine.playerBalances(r);
      expect(bal.keys, hasLength(4));
      // Y cada uno con su cifra: la de A no es la de B.
      expect(bal[a] == bal[b], isFalse);
    });

    test('el torneo avisa de los nombres repetidos entre inscritos', () {
      final rs = [
        RoundResult(
          roundId: 'r1',
          roundName: 'R',
          courseName: 'C',
          playedAt: DateTime(2026, 3, 7),
          holesPlayed: 18,
          playerIds: const [a, b],
          playerNames: const {a: 'Carlos', b: 'Carlos'},
          balances: const {a: 100, b: -100},
          pairBalances: const {},
          grossByPlayer: const {},
          netByPlayer: const {},
          stablefordByPlayer: const {},
          bettingGroupIds: const [],
          torneoIds: const ['t1'],
        )
      ];
      final t = Torneo(
          id: 't1',
          nombre: 'Liga',
          fuente: FuenteDeRondas.marcadas,
          metodo: MetodoDePuntuacion.dinero,
          participantes: const [a, b]);
      final tabla = tablaDe(t, rs);
      // Dos filas con el mismo nombre: no se fusionan, y el aviso existe.
      expect(tabla.filas.where((f) => f.nombre == 'Carlos'), hasLength(2));
      expect(tabla.nombresDuplicados, isNotEmpty);
    });
  });

  group('7.6 · torneo con un solo inscrito: no corona campeón', () {
    test('el cuadro no se arma, y dice por qué', () {
      final t = Torneo(
          id: 't1',
          nombre: 'Match Play',
          formato: FormatoDeTorneo.eliminacion,
          fuente: FuenteDeRondas.marcadas,
          participantes: const [a]);
      final l = llaveDe(t, const []);
      expect(l.vacia, isTrue);
      expect(l.campeon, isNull);
      expect(l.motivo, contains('dos'));
    });

    test('y la liga con uno solo no le paga el bote sin jugar', () {
      final t = Torneo(
          id: 't1',
          nombre: 'Liga',
          fuente: FuenteDeRondas.marcadas,
          metodo: MetodoDePuntuacion.dinero,
          participantes: const [a],
          bote: const BoteConfig(entrada: 500));
      final tabla = tablaDe(t, const []);
      final bote = boteDe(t, tabla);
      // Sin rondas jugadas nadie cobra, aunque sea el único.
      expect(bote.lineas.every((l) => l.cobra == 0), isTrue);
      expect(bote.provisional, isNotNull);
    });
  });
}
