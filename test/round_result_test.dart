// ─────────────────────────────────────────────────────────────────────────────
// ROUND RESULT — derivar el dinero de una ronda de verdad
//
// El resumen del perfil se prueba aparte con resultados a mano. Esto prueba lo
// otro: que derivarlos de un Round coincide con lo que el ledger cobra.
//
// Es la lección del scramble. Aquel test montaba una forma que la app nunca
// produce y pasaba en verde mientras la pantalla fallaba. Así que aquí la ronda
// se monta como las monta el resto de la suite —módulos por defecto, ledger
// real— y se comprueba contra LedgerEngine, no contra números que yo escriba.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

const a1 = 'a1', a2 = 'a2', b1 = 'b1', b2 = 'b2';
const todos = [a1, a2, b1, b2];

CourseInfo _course() => CourseInfo(
    name: 'Los Encinos',
    holes: List.generate(
        18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

Round _round({
  List<BetModuleInstance>? mods,
  Map<String, int>? gross,
  List<Player>? players,
  List<BetSide>? sides,
}) {
  final g = gross ?? {a1: 4, a2: 5, b1: 5, b2: 6};
  final ps = players ?? todos.map((i) => Player(id: i, name: i.toUpperCase())).toList();
  return Round(
    id: 'r1', name: 'Sábado', course: _course(),
    players: ps,
    roundPlayers:
        ps.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'grp', name: 'G',
          format: PartidaFormat.oneVsOne,
          playerIds: ps.map((p) => p.id).toList(),
          modules: mods ??
              [BetModuleInstance.defaultFor(BetModuleType.skins, todos, id: 'sk')]),
    ],
    scores: {
      for (final e in g.entries)
        e.key: {
          for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: e.key, hole: h, grossScore: e.value),
        },
    },
    events: const {}, oyeseRankings: const {}, sliding: const [],
    createdAt: DateTime(2026, 8, 1), totalHoles: 18,
    isFinished: true,
  );
}

void main() {
  group('1 · el neto coincide con el que cobra el ledger', () {
    test('jugador por jugador, sin reescribir los números a mano', () {
      final r = _round();
      final delLedger = LedgerEngine.playerBalances(r);
      final res = RoundResult.fromRound(r);

      expect(delLedger.values.any((v) => v != 0), isTrue,
          reason: 'sin dinero en juego el test pasaría por ausencia');

      for (final pid in todos) {
        expect(res.netoDe(pid), delLedger[pid],
            reason: 'el neto de $pid debe ser el mismo');
      }
    });

    test('la suma de todos los netos es cero: el dinero no se crea', () {
      final res = RoundResult.fromRound(_round());
      final suma = res.balances.values.fold(0.0, (s, v) => s + v);
      expect(suma.abs() < 0.01, isTrue, reason: 'suma = $suma');
    });
  });

  group('2 · el cara a cara guardado coincide con el calculado', () {
    test('cada par, en las dos direcciones', () {
      final r = _round();
      final res = RoundResult.fromRound(r);
      var algunoNoCero = false;

      for (var i = 0; i < todos.length; i++) {
        for (var j = i + 1; j < todos.length; j++) {
          final a = todos[i], b = todos[j];
          final esperado = LedgerEngine.balanceBetween(r, a, b);
          if (esperado != 0) algunoNoCero = true;
          expect(res.netoEntre(a, b), esperado, reason: '$a vs $b');
          // Y leído del otro lado, invertido. Aquí se caza un error de
          // dirección en la convención 'menor|mayor'.
          expect(res.netoEntre(b, a), -esperado, reason: '$b vs $a');
        }
      }
      expect(algunoNoCero, isTrue,
          reason: 'todos a cero haría que la aserción no probara nada');
    });
  });

  group('3 · solo personas', () {
    test('los jugadores virtuales de un scramble no entran', () {
      // Un equipo virtual lleva el score del lado, pero no tiene ficha ni
      // balance que enseñar en el perfil de nadie.
      final virt = Player(
          id: 'eqA', name: 'Equipo A', isVirtual: true,
          teamMemberIds: const [a1, a2]);
      final r = _round(
        players: [
          Player(id: a1, name: 'A1'), Player(id: a2, name: 'A2'),
          Player(id: b1, name: 'B1'), Player(id: b2, name: 'B2'), virt,
        ],
      );
      final res = RoundResult.fromRound(r);
      expect(res.playerIds, isNot(contains('eqA')));
      expect(res.playerNames.containsKey('eqA'), isFalse);
      expect(res.playerIds.length, 4);
    });
  });

  group('4 · el score y los hoyos', () {
    test('el gross total sale de los hoyos anotados', () {
      final res = RoundResult.fromRound(_round(gross: {a1: 4}));
      expect(res.grossByPlayer[a1], 72, reason: '4 × 18');
      expect(res.holesPlayed, 18);
    });

    test('quien no anotó no aparece con cero', () {
      // Un cero en la columna de score se lee como "hizo 0", que es imposible.
      final res = RoundResult.fromRound(_round(gross: {a1: 4}));
      expect(res.grossByPlayer.containsKey(b1), isFalse);
      expect(res.playerIds, contains(b1),
          reason: 'no anotar no es no jugar');
    });

    test('nueve hoyos se distinguen de dieciocho', () {
      final r = _round();
      // Se borran los hoyos 10-18 de todos.
      for (final pid in todos) {
        r.scores[pid]!.removeWhere((h, _) => h > 9);
      }
      expect(RoundResult.fromRound(r).holesPlayed, 9);
    });
  });

  group('5 · el viaje a JSON y de vuelta', () {
    test('no pierde nada de lo que el tablero lee', () {
      final original = RoundResult.fromRound(_round());
      final vuelta = RoundResult.fromJson(
          Map<String, dynamic>.from(original.toJson()));

      expect(vuelta.roundId, original.roundId);
      expect(vuelta.courseName, 'Los Encinos');
      expect(vuelta.playerIds, original.playerIds);
      expect(vuelta.holesPlayed, original.holesPlayed);
      for (final pid in todos) {
        expect(vuelta.netoDe(pid), original.netoDe(pid));
        expect(vuelta.grossByPlayer[pid], original.grossByPlayer[pid]);
      }
      expect(vuelta.netoEntre(a1, b1), original.netoEntre(a1, b1));
    });

    test('un documento incompleto no revienta al leerse', () {
      // Los documentos viejos y los a medio escribir existen. Un perfil que se
      // cae al abrirse es peor que un perfil incompleto.
      final vuelta = RoundResult.fromJson(const {});
      expect(vuelta.roundId, '');
      expect(vuelta.playerIds, isEmpty);
      expect(vuelta.netoDe(a1), 0);
    });
  });
}
