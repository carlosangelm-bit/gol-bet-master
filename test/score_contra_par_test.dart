// ─────────────────────────────────────────────────────────────────────────────
// EL SCORE CONTRA EL PAR — la cadena entera, y dónde puede mentir
//
// «En el PGA, -7 va en rojo y el par en negro. Es lo primero que identifica a
// un leaderboard profesional, y hoy la columna dice 0 en blanco.»
//
// Para restar el par hay que TENERLO, y no se guardaba: el RoundResult tenía
// `courseName` —el nombre del campo— y el objeto con los pares por hoyo estaba
// delante en el momento de construirlo. Sexta vez en el proyecto que un dato
// horneado en un nombre acaba faltando.
//
// El par ahora viaja por cuatro sitios, y en cada uno se puede perder de una
// manera distinta:
//
//   RoundResult.parDeLaRonda → RondaDelTorneo.par → FilaDelTorneo → la tele
//
// Lo que más se comprueba aquí no es que la suma salga: es que cuando el par
// NO ESTÁ, no aparezca uno plausible en su sitio. Un 72 inventado daría un
// "-7" que no es el de nadie, y nadie se enteraría.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/leaderboard_publico.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/torneo.dart';

RoundResult _r(String id, Map<String, int> netos, {int? par, int hoyos = 18}) =>
    RoundResult(
      roundId: id,
      roundName: id,
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 5, int.parse(id.replaceAll(RegExp(r'\D'), ''))),
      holesPlayed: hoyos,
      parDeLaRonda: par,
      playerIds: netos.keys.toList(),
      playerNames: {for (final k in netos.keys) k: k.toUpperCase()},
      balances: const {},
      pairBalances: const {},
      grossByPlayer: {for (final e in netos.entries) e.key: e.value + 4},
      netByPlayer: netos,
      // Puntos Stableford para el caso que se puntúa así. Sin ellos la fila ni
      // siquiera entra en la tabla, que es correcto pero no es lo que se mide.
      stablefordByPlayer: {for (final e in netos.entries) e.key: 110 - e.value},
      torneoIds: const ['t1'],
    );

Torneo _t({
  MetodoDePuntuacion metodo = MetodoDePuntuacion.scoreNeto,
  Acumulacion acumulacion = Acumulacion.sumaSimple,
  int mejoresN = 2,
}) =>
    Torneo(
      id: 't1',
      nombre: 'Copa',
      metodo: metodo,
      acumulacion: acumulacion,
      mejoresN: mejoresN,
      minimoRondas: 1,
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · el par llega hasta la tabla', () {
    test('CLAVE: dos rondas de par 72, y el bajo par sale de la suma', () {
      // 70 + 71 = 141 golpes contra 144 de par: tres bajo par.
      final tabla = tablaDe(
        _t(),
        [
          _r('1', {'ana': 70}, par: 72),
          _r('2', {'ana': 71}, par: 72),
        ],
        nombres: {'ana': 'Ana'},
      );
      final fila = tabla.filas.first;
      expect(fila.parDeLasQueCuentan, 144);
      expect(fila.total, 141);

      final lb = LeaderboardPublico.desde(
          token: 'tok',
          ownerUid: 'u',
          torneo: _t(),
          tabla: tabla,
          cuando: DateTime(2026, 6, 1));
      expect(lb.tabla.first.bajoPar, -3);
    });

    test('CLAVE: una vuelta de nueve suma su par, no el del campo entero', () {
      // Es el error que daría −36: par 72 contra un score de nueve hoyos.
      final tabla = tablaDe(
        _t(),
        [_r('1', {'ana': 38}, par: 36, hoyos: 9)],
        nombres: {'ana': 'Ana'},
      );
      expect(tabla.filas.first.parDeLasQueCuentan, 36);

      final lb = LeaderboardPublico.desde(
          token: 'tok',
          ownerUid: 'u',
          torneo: _t(),
          tabla: tabla,
          cuando: DateTime(2026, 6, 1));
      expect(lb.tabla.first.bajoPar, 2, reason: 'dos sobre par, no −34');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2 · DONDE PUEDE MENTIR
  //
  // Los tres tests de aquí son el corazón del encargo. Un número plausible que
  // sustituye a uno que falta es el fallo más caro que tiene este proyecto, y
  // esta columna es un sitio perfecto para que ocurra.
  // ───────────────────────────────────────────────────────────────────────────
  group('2 · un par a medias NO produce un bajo par', () {
    test('CLAVE: si una ronda que cuenta no trae par, no hay columna', () {
      // Sumar solo las que lo traen daría "141 contra 72" = +69, o peor: un
      // −3 calculado sobre la mitad de las rondas, que parece correcto.
      final tabla = tablaDe(
        _t(),
        [
          _r('1', {'ana': 70}, par: 72),
          _r('2', {'ana': 71}), // ronda vieja, sin par
        ],
        nombres: {'ana': 'Ana'},
      );
      expect(tabla.filas.first.parDeLasQueCuentan, isNull);

      final lb = LeaderboardPublico.desde(
          token: 'tok',
          ownerUid: 'u',
          torneo: _t(),
          tabla: tabla,
          cuando: DateTime(2026, 6, 1));
      expect(lb.tabla.first.bajoPar, isNull,
          reason: 'mejor sin columna que con un número que no es de nadie');
    });

    test('CLAVE: con "mejores N", el par de las que CUENTAN, no el de todas',
        () {
      // Tres rondas, cuentan las dos mejores. Si el par se sumara sobre las
      // tres, el bajo par saldría contra 216 en vez de contra 144 — un −74 en
      // la pared.
      final tabla = tablaDe(
        _t(acumulacion: Acumulacion.mejoresDeN, mejoresN: 2),
        [
          _r('1', {'ana': 70}, par: 72),
          _r('2', {'ana': 71}, par: 72),
          _r('3', {'ana': 85}, par: 72),
        ],
        nombres: {'ana': 'Ana'},
      );
      expect(tabla.filas.first.parDeLasQueCuentan, 144,
          reason: 'dos rondas, no tres');
      expect(tabla.filas.first.total, 141);
    });

    test('CONTRAPESO: y el par sobrevive a que se marquen las que cuentan', () {
      // La marca se pone reconstruyendo cada RondaDelTorneo. Si esa
      // reconstrucción olvidara el par —que es exactamente lo que pasaba—, la
      // columna desaparecería SOLO con "mejores N", que es el caso menos
      // probado.
      final tabla = tablaDe(
        _t(acumulacion: Acumulacion.mejoresDeN, mejoresN: 2),
        [
          _r('1', {'ana': 70}, par: 72),
          _r('2', {'ana': 71}, par: 72),
        ],
        nombres: {'ana': 'Ana'},
      );
      for (final r in tabla.filas.first.rondas) {
        expect(r.par, 72, reason: r.roundId);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · y solo cuando la medida SON golpes', () {
    test('CLAVE: por dinero no hay bajo par, y tampoco medida', () {
      // La medida ya se ocultaba por ser dinero. El bajo par tiene que seguirla:
      // un "−3" junto a un hueco sería la parte del dinero que sí se escapó.
      final tabla = tablaDe(
        _t(metodo: MetodoDePuntuacion.dinero),
        [_r('1', {'ana': 70}, par: 72)],
        nombres: {'ana': 'Ana'},
      );
      final lb = LeaderboardPublico.desde(
          token: 'tok',
          ownerUid: 'u',
          torneo: _t(metodo: MetodoDePuntuacion.dinero),
          tabla: tabla,
          cuando: DateTime(2026, 6, 1));
      expect(lb.tabla.first.medida, isNull);
      expect(lb.tabla.first.bajoPar, isNull);
      expect(lb.ocultaLaMedida, isTrue);
    });

    test('CLAVE: por Stableford tampoco — más es mejor, y el par no entra', () {
      // 38 puntos contra par 72 daría "−34", que en Stableford no significa
      // nada. Es el caso donde el dato existe y aun así no se puede usar.
      final tabla = tablaDe(
        _t(metodo: MetodoDePuntuacion.stableford),
        [_r('1', {'ana': 70}, par: 72)],
        nombres: {'ana': 'Ana'},
      );
      final lb = LeaderboardPublico.desde(
          token: 'tok',
          ownerUid: 'u',
          torneo: _t(metodo: MetodoDePuntuacion.stableford),
          tabla: tabla,
          cuando: DateTime(2026, 6, 1));
      expect(lb.tabla.first.bajoPar, isNull);
    });

    test('el par sobrevive al viaje por Firestore', () {
      const f = FilaProyectada(
          puesto: 1, nombre: 'Ana', jugadas: 2, medida: 141, bajoPar: -3);
      expect(FilaProyectada.fromJson(f.toJson()).bajoPar, -3);
      // Y sin bajo par la clave ni siquiera se escribe: un documento no gana
      // claves vacías.
      const g = FilaProyectada(puesto: 1, nombre: 'Ana', jugadas: 2);
      expect(g.toJson().containsKey('bajoPar'), isFalse);
      expect(FilaProyectada.fromJson(g.toJson()).bajoPar, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4 · DE DÓNDE SALE EL PAR
  //
  // Los grupos de arriba prueban la cadena desde el RoundResult. Estos dos
  // prueban el ESLABÓN ANTERIOR, que es donde el dato se creaba mal o se
  // perdía: el cálculo desde la ronda y la vuelta desde Firestore.
  //
  // Hicieron falta porque un contrapeso NO MORDIÓ: poniendo `?? 72` en el
  // fromJson, todo lo de arriba seguía en verde. Los tests construían el
  // RoundResult a mano y nunca pasaban por ninguno de los dos caminos.
  // ───────────────────────────────────────────────────────────────────────────
  group('4 · el par se calcula de los hoyos jugados, y no se inventa', () {
    test('CLAVE: dieciocho hoyos de par 4 dan 72', () {
      final r = RoundResult.fromRound(_ronda(hoyos: 18));
      expect(r.parDeLaRonda, 72);
    });

    test('CLAVE: una vuelta de NUEVE da la mitad, no el par del campo', () {
      // El error que produciría un −34 en la pared: restar el par de dieciocho
      // a un score de nueve. El campo sigue teniendo par 72; la RONDA no.
      final r = RoundResult.fromRound(_ronda(hoyos: 9));
      expect(r.parDeLaRonda, 36);
    });

    test('CLAVE: un documento SIN par vuelve sin par, no con un 72', () {
      // Es el contrapeso que no mordía. Una ronda cerrada antes de esto no
      // tiene par guardado, y el respaldo más inocente —"pues 72, casi todos
      // los campos lo son"— produce un bajo par que no es el de nadie.
      final viejo = {
        'roundId': 'r1',
        'roundName': 'Sábado',
        'courseName': 'Los Encinos',
        'playedAt': DateTime(2026, 5, 1).toIso8601String(),
        'holesPlayed': 18,
        'playerIds': ['ana'],
        'playerNames': {'ana': 'Ana'},
        'balances': {'ana': 0},
        'pairBalances': {},
        'grossByPlayer': {'ana': 74},
      };
      expect(RoundResult.fromJson(viejo).parDeLaRonda, isNull);
    });

    test('y uno CON par lo conserva en el viaje', () {
      final ida = RoundResult.fromRound(_ronda(hoyos: 18));
      expect(RoundResult.fromJson(ida.toJson()).parDeLaRonda, 72);
    });
  });
}

/// Una ronda de [hoyos] hoyos, todos par 4.
///
/// El par de la ronda sale de `hoyosEnJuego`, que es la misma primitiva que usa
/// la tarjeta: si el par se calculara con otra aritmética, los dos números
/// podrían discrepar y nadie sabría cuál mirar.
Round _ronda({required int hoyos}) {
  final ps = [
    Player(id: 'ana', name: 'Ana'),
    Player(id: 'beto', name: 'Beto'),
  ];
  return Round(
    id: 'r1',
    name: 'Sábado',
    course: CourseInfo(
        name: 'Los Encinos',
        holes: List.generate(
            18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1))),
    players: ps,
    roundPlayers:
        ps.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
        id: 'g',
        name: 'G',
        format: PartidaFormat.oneVsOne,
        playerIds: ps.map((p) => p.id).toList(),
        modules: [
          BetModuleInstance.defaultFor(
              BetModuleType.skins, ps.map((p) => p.id).toList(),
              id: 'sk')
        ],
      ),
    ],
    scores: {
      for (final p in ps)
        p.id: {
          for (var h = 1; h <= hoyos; h++)
            h: HoleScore(playerId: p.id, hole: h, grossScore: 4),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 8, 1),
    totalHoles: hoyos,
    isFinished: true,
  );
}
