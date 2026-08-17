// ─────────────────────────────────────────────────────────────────────────────
// scoring_players_test.dart — quién anota, y por qué containsKey no lo sabe
//
// El contador de captura marcaba "0/18 hoyos" con hoyos capturados. La causa no
// estaba en el motor, ni en el modelo, ni en la serialización, ni en la ruta de
// escritura: estaba en el consumidor más superficial que existe, un contador
// que lee scores recién escritos por la misma pantalla.
//
//     round.players.where((p) => round.scores.containsKey(p.id))
//
// Ese predicado pasa a cualquiera que tenga CONTENEDOR de scores, aunque esté
// vacío. Setup siembra un contenedor por jugador de la ronda, así que en cuanto
// alguien tiene contenedor sin llegar a anotar nunca, cualquier
// every(...hasScore) sobre esa lista es falso para siempre.
//
// Estaba copiado en 19 sitios de 6 archivos.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';

const va = 'team_A', vb = 'team_B';
const reales = ['cam', 'aam', 'cav', 'rafa'];

CourseInfo _course() => CourseInfo(name: 'T',
    holes: List.generate(18,
        (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Ronda por equipos como la produce Setup: players lleva reales y virtuales,
/// roundPlayers solo a quien anota.
Round _ronda({
  required Map<String, Map<int, HoleScore>> scores,
  bool conRoundPlayers = true,
  List<String>? roundPlayerIds,
}) =>
    Round(
      id: 'r', name: 'R', course: _course(),
      players: [
        for (final i in reales) Player(id: i, name: i.toUpperCase()),
        Player(id: va, name: 'Equipo A', isVirtual: true,
            teamMemberIds: const ['cam', 'aam']),
        Player(id: vb, name: 'Equipo B', isVirtual: true,
            teamMemberIds: const ['cav', 'rafa']),
      ],
      roundPlayers: !conRoundPlayers
          ? const []
          : (roundPlayerIds ?? const [va, vb])
              .map((i) => RoundPlayer(playerId: i, handicapEnRonda: 12))
              .toList(),
      betGroups: const [],
      scores: scores, events: const {}, oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 1, 1), totalHoles: 18,
    );

Map<int, HoleScore> _hoyos(String pid, int hasta, int gross) =>
    {for (var h = 1; h <= hasta; h++)
      h: HoleScore(playerId: pid, hole: h, grossScore: gross)};

/// La cuenta que hace el contador de captura.
int _contador(Round r) {
  var c = 0;
  for (var h = 1; h <= 18; h++) {
    if (r.scoringPlayers.every((p) => r.getScore(p.id, h).hasScore)) c++;
  }
  return c;
}

void main() {
  group('el contador cuenta lo capturado', () {
    test('3 hoyos capturados dan 3, no 0', () {
      final r = _ronda(scores: {
        va: _hoyos(va, 3, 4),
        vb: _hoyos(vb, 3, 5),
      });
      expect(_contador(r), 3);
    });

    test('y sigue dando 3 aunque los reales tengan contenedor vacío', () {
      // ESTE es el caso que rompía. Con containsKey, los cuatro reales entraban
      // en la lista, ninguno tenía score, y el every fallaba en los 18 hoyos.
      final r = _ronda(scores: {
        va: _hoyos(va, 3, 4),
        vb: _hoyos(vb, 3, 5),
        for (final i in reales) i: <int, HoleScore>{},
      });
      expect(_contador(r), 3,
          reason: 'un contenedor vacío no convierte a nadie en anotador');
    });

    test('los 18 capturados dan 18', () {
      final r = _ronda(scores: {
        va: _hoyos(va, 18, 4),
        vb: _hoyos(vb, 18, 5),
        for (final i in reales) i: <int, HoleScore>{},
      });
      expect(_contador(r), 18);
    });

    test('sin capturar nada da 0, no 18', () {
      // El otro extremo: si scoringPlayers saliera vacía, every sobre lista
      // vacía es true y el contador diría 18/18 desde el hoyo 1.
      final r = _ronda(scores: {va: {}, vb: {}});
      expect(_contador(r), 0);
    });
  });

  group('resiste que roundPlayers esté mal', () {
    // Los tests que valen no son los que confirman lo que crees. Estos montan
    // las dos hipótesis de por qué el arreglo anterior seguía fallando, COMO SI
    // fueran ciertas, y exigen que el contador acierte igual.

    test('aunque roundPlayers incluya a los cuatro reales', () {
      // Hipótesis A: la exclusión de Setup no se aplicó y los reales siguen
      // declarados. Con la versión basada en roundPlayers esto daba 0.
      final r = _ronda(
        scores: {
          va: _hoyos(va, 3, 4), vb: _hoyos(vb, 3, 5),
          for (final i in reales) i: <int, HoleScore>{},
        },
        roundPlayerIds: [...reales, va, vb],
      );
      expect(r.roundPlayers.length, 6);
      expect(_contador(r), 3, reason: 'los reales no están anotando');
      expect(r.scoringPlayers.map((p) => p.id), [va, vb]);
    });

    test('aunque los virtuales NO estén en roundPlayers', () {
      // Hipótesis B: los que anotan quedaron fuera de la declaración, así que
      // la lista contenía cuatro personas sin score.
      final r = _ronda(
        scores: {va: _hoyos(va, 3, 4), vb: _hoyos(vb, 3, 5)},
        roundPlayerIds: reales,
      );
      expect(r.roundPlayers.map((rp) => rp.playerId), reales);
      expect(_contador(r), 3);
      expect(r.scoringPlayers.map((p) => p.id), [va, vb]);
    });

    test('aunque roundPlayers esté completamente vacío', () {
      final r = _ronda(
        scores: {va: _hoyos(va, 3, 4), vb: _hoyos(vb, 3, 5)},
        conRoundPlayers: false,
      );
      expect(_contador(r), 3);
    });

    test('best ball: el virtual del equipo no bloquea el contador', () {
      // Caso que estaba roto en silencio y nadie había mirado: en best ball
      // anotan los reales y el virtual bb_team_X tiene contenedor sembrado que
      // no se llena nunca. Con containsKey o con roundPlayers, 0/18 SIEMPRE.
      final r = _ronda(
        scores: {
          for (final i in reales) i: _hoyos(i, 3, 4),
          'bb_team_A': <int, HoleScore>{},
          'bb_team_B': <int, HoleScore>{},
        },
        roundPlayerIds: [...reales, 'bb_team_A', 'bb_team_B'],
      );
      expect(_contador(r), 3);
      expect(r.scoringPlayers.map((p) => p.id), reales);
    });
  });

  group('scoringPlayers', () {
    test('son quienes anotan de hecho, no los que tienen clave', () {
      final r = _ronda(scores: {
        va: _hoyos(va, 1, 4), vb: _hoyos(vb, 1, 5),
        for (final i in reales) i: <int, HoleScore>{},
      });
      expect(r.scores.keys.length, 6);
      expect(r.scoringPlayers.map((p) => p.id), [va, vb]);
    });

    test('sin empezar la ronda se cae a la declaración', () {
      // Nadie ha anotado todavía, así que la observación no sirve. Hay que
      // devolver a alguien: every sobre lista vacía es true y los 18 hoyos
      // saldrían completos desde el principio.
      final r = _ronda(scores: {va: {}, vb: {}});
      expect(r.scoringPlayers.map((p) => p.id), [va, vb]);
      expect(_contador(r), 0);
    });

    test('un hoyo a medias no cuenta como completo', () {
      // Que el contador sea robusto no debe volverlo optimista.
      final r = _ronda(scores: {
        va: _hoyos(va, 3, 4),
        vb: _hoyos(vb, 2, 5), // le falta el 3
      });
      expect(_contador(r), 2);
    });

    test('nunca devuelve a alguien que no esté en players', () {
      final r = _ronda(scores: {va: {}, vb: {}});
      for (final p in r.scoringPlayers) {
        expect(r.players.map((x) => x.id), contains(p.id));
      }
    });

    test('no se confunde con realPlayers: son preguntas distintas', () {
      // scoringPlayers = quién lleva tarjeta. realPlayers = quién es persona.
      // En scramble son conjuntos disjuntos.
      final r = _ronda(scores: {va: _hoyos(va, 1, 4), vb: _hoyos(vb, 1, 5)});
      expect(r.scoringPlayers.map((p) => p.id), [va, vb]);
      expect(r.realPlayers.map((p) => p.id), reales);
    });
  });
}
