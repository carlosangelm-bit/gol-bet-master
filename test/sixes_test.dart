// ─────────────────────────────────────────────────────────────────────────────
// SIXES / HOLLYWOOD — tres bloques y las parejas rotan
//
// Lo que más protege es el test de la rotación: al acabar el 18, cada uno tiene
// que haber jugado un bloque con cada uno de los otros tres. Si la rotación no
// cierra, el formato deja de ser lo que dice ser y nadie lo nota mirando un
// bloque suelto.
//
// Lo segundo: que el dinero de cada bloque valga lo configurado EN TOTAL. Un
// bloque a $50 mueve $50, no $200. Es el mismo reparto por cruces que el Nassau
// por equipos —se llama a teamCrossAmount, no se reimplementa— y aquí se
// comprueba que además cierra en cero.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/engines/sixes_engine.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/models/models.dart';

const a = 'pid_aa01', b = 'pid_bb02', c = 'pid_cc03', d = 'pid_dd04';
const cuatro = [a, b, c, d];

CourseInfo _course([int hoyos = 18]) => CourseInfo(
    name: 'Los Encinos',
    holes: List.generate(
        hoyos, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// Una ronda de Sixes con los scores dados por hoyo y jugador.
Round _round({
  Map<String, Map<int, int>> scores = const {},
  int hoyosPorBloque = 6,
  int totalHoles = 18,
  double value = 50,
  List<String> pids = cuatro,
}) {
  final players =
      pids.map((id) => Player(id: id, name: id.toUpperCase())).toList();
  final mod = BetModuleInstance(
    id: 'mod_sixes',
    type: BetModuleType.sixes,
    name: 'Sixes',
    participantIds: pids,
    sixesConfig:
        SixesConfig(value: value, hoyosPorBloque: hoyosPorBloque),
  );
  return Round(
    id: 'r1',
    name: 'Sábado',
    course: _course(totalHoles < 18 ? 18 : totalHoles),
    players: players,
    roundPlayers:
        players.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'grp',
          name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: pids,
          modules: [mod])
    ],
    scores: {
      for (final e in scores.entries)
        e.key: {
          for (final h in e.value.entries)
            h.key: HoleScore(playerId: e.key, hole: h.key, grossScore: h.value),
        },
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 8, 1),
    totalHoles: totalHoles,
    isFinished: true,
  );
}

/// Scores planos: cada jugador con el mismo golpe en todos los hoyos.
Map<String, Map<int, int>> _planos(Map<String, int> golpes, {int hasta = 18}) =>
    {
      for (final e in golpes.entries)
        e.key: {for (var h = 1; h <= hasta; h++) h: e.value},
    };

BetModuleInstance _mod(Round r) => r.betGroups.first.modules.first;

void main() {
  group('1 · la rotación cierra: todos juegan con todos', () {
    test('los tres bloques son las tres parejas posibles', () {
      // Campo a campo: dos registros con listas distintas nunca son iguales,
      // aunque las listas tengan lo mismo.
      for (final caso in [
        (1, [a, b], [c, d]),
        (2, [a, c], [b, d]),
        (3, [a, d], [b, c]),
      ]) {
        final (x, y) = SixesEngine.parejasDelBloque(cuatro, caso.$1);
        expect(x, caso.$2, reason: 'bloque ${caso.$1} lado A');
        expect(y, caso.$3, reason: 'bloque ${caso.$1} lado B');
      }
    });

    test('al acabar, cada uno jugó un bloque con cada uno de los otros tres',
        () {
      // Es lo que hace que el formato exista con cuatro: tres bloques y tres
      // maneras de partir cuatro en dos parejas.
      final companeros = {for (final p in cuatro) p: <String>{}};
      for (var bl = 1; bl <= 3; bl++) {
        final (x, y) = SixesEngine.parejasDelBloque(cuatro, bl);
        for (final lado in [x, y]) {
          companeros[lado[0]]!.add(lado[1]);
          companeros[lado[1]]!.add(lado[0]);
        }
      }
      for (final p in cuatro) {
        expect(companeros[p], cuatro.where((x) => x != p).toSet(),
            reason: '$p no jugó con todos');
      }
    });

    test('nadie repite compañero', () {
      final vistos = <String>[];
      for (var bl = 1; bl <= 3; bl++) {
        final (x, y) = SixesEngine.parejasDelBloque(cuatro, bl);
        for (final lado in [x, y]) {
          final clave = ([...lado]..sort()).join('|');
          expect(vistos, isNot(contains(clave)), reason: clave);
          vistos.add(clave);
        }
      }
      expect(vistos, hasLength(6));
    });

    test('cada bloque parte a los cuatro sin dejar a nadie fuera', () {
      for (var bl = 1; bl <= 3; bl++) {
        final (x, y) = SixesEngine.parejasDelBloque(cuatro, bl);
        expect([...x, ...y].toSet(), cuatro.toSet(), reason: 'bloque $bl');
        expect(x, hasLength(2));
        expect(y, hasLength(2));
      }
    });
  });

  group('2 · en qué bloque cae cada hoyo', () {
    test('con bloques de 6, en una ronda de 18', () {
      for (final h in [1, 3, 6]) {
        expect(SixesEngine.bloqueDelHoyo(h, 6), 1, reason: '$h');
      }
      for (final h in [7, 10, 12]) {
        expect(SixesEngine.bloqueDelHoyo(h, 6), 2, reason: '$h');
      }
      for (final h in [13, 17, 18]) {
        expect(SixesEngine.bloqueDelHoyo(h, 6), 3, reason: '$h');
      }
    });

    test('con bloques de 3 los tres acaban en el 9', () {
      expect(SixesEngine.bloqueDelHoyo(3, 3), 1);
      expect(SixesEngine.bloqueDelHoyo(4, 3), 2);
      expect(SixesEngine.bloqueDelHoyo(9, 3), 3);
      // Y el 10 ya no cuenta: los tres bloques acabaron.
      expect(SixesEngine.bloqueDelHoyo(10, 3), isNull);
    });

    test('los hoyos que sobran NO se meten en el último bloque', () {
      // Repartirlos alargaría el tercer bloque en silencio, y ese bloque vale
      // el mismo dinero que los otros dos.
      expect(SixesEngine.bloqueDelHoyo(16, 5), isNull);
      expect(SixesEngine.bloqueDelHoyo(15, 5), 3);
    });

    test('el bloque se sugiere de la longitud de la ronda', () {
      expect(SixesEngine.bloqueSugerido(18), 6);
      expect(SixesEngine.bloqueSugerido(9), 3);
      // Y una ronda absurdamente corta no divide por cero.
      expect(SixesEngine.bloqueSugerido(2), 1);
    });

    test('quién es tu compañero en un hoyo concreto', () {
      // Es la pregunta del hoyo 7: "¿con quién voy ahora?".
      expect(SixesEngine.companeroEn(cuatro, a, 3, 6), b);
      expect(SixesEngine.companeroEn(cuatro, a, 7, 6), c);
      expect(SixesEngine.companeroEn(cuatro, a, 13, 6), d);
      expect(SixesEngine.companeroEn(cuatro, a, 19, 6), isNull);
    });
  });

  group('3 · cada bloque se resuelve por su cuenta', () {
    test('gana la pareja con más hoyos en SU tramo, no en la ronda', () {
      // A+B arrasan el bloque 1; en el 2 y el 3 están separados, así que el
      // resultado del bloque 1 no arrastra nada.
      final scores = <String, Map<int, int>>{
        a: {for (var h = 1; h <= 18; h++) h: h <= 6 ? 3 : 5},
        b: {for (var h = 1; h <= 18; h++) h: h <= 6 ? 3 : 5},
        c: {for (var h = 1; h <= 18; h++) h: h <= 6 ? 5 : 4},
        d: {for (var h = 1; h <= 18; h++) h: h <= 6 ? 5 : 4},
      };
      final r = _round(scores: scores);
      final bl = SixesEngine.bloques(r, cuatro, _mod(r));
      expect(bl, hasLength(3));
      expect(bl[0].ganadores, [a, b]);
      expect(bl[0].ganadosA, 6);
      // Bloques 2 y 3: A+C vs B+D y A+D vs B+C. Con A=B=5 y C=D=4 la mejor
      // bola de los dos lados es 4 en ambos, así que empatan todos los hoyos.
      expect(bl[1].sinLiquidar, SixesSinLiquidar.empatado);
      expect(bl[2].sinLiquidar, SixesSinLiquidar.empatado);
    });

    test('un bloque sin ningún score no liquida, y lo dice', () {
      final r = _round(scores: _planos({a: 4, b: 4, c: 5, d: 5}, hasta: 6));
      final bl = SixesEngine.bloques(r, cuatro, _mod(r));
      expect(bl[0].resuelto, isTrue);
      expect(bl[1].sinLiquidar, SixesSinLiquidar.sinJugar);
      expect(bl[1].marcador, '—');
    });

    test('un bloque fuera de la ronda se marca aparte de uno sin jugar', () {
      // Son dos cosas distintas: "no lo habéis jugado" y "esos hoyos no
      // existen". Un mensaje único no informaría de ninguna.
      final r = _round(totalHoles: 9, hoyosPorBloque: 6);
      final bl = SixesEngine.bloques(r, cuatro, _mod(r));
      expect(bl[2].sinLiquidar, SixesSinLiquidar.fueraDeLaRonda);
    });

    test('el marcador del bloque cuenta hoyos, no golpes', () {
      final r = _round(scores: _planos({a: 3, b: 3, c: 5, d: 5}));
      final bl = SixesEngine.bloques(r, cuatro, _mod(r));
      expect(bl[0].marcador, '6–0');
      expect(bl[0].jugados, 6);
      expect(bl[0].empatados, 0);
    });
  });

  group('4 · el dinero: cada bloque vale lo configurado EN TOTAL', () {
    test('un bloque a \$50 mueve \$50, no \$200', () {
      final r = _round(
          value: 50, scores: _planos({a: 3, b: 3, c: 5, d: 5}, hasta: 6));
      final bal = LedgerEngine.playerBalances(r);
      expect(bal[a], closeTo(25, 0.001));
      expect(bal[b], closeTo(25, 0.001));
      expect(bal[c], closeTo(-25, 0.001));
      expect(bal[d], closeTo(-25, 0.001));
      expect(bal.values.fold(0.0, (s, v) => s + v), closeTo(0, 0.001));
    });

    test('los tres bloques se cobran por separado', () {
      // A gana los tres bloques con distinto compañero; los otros tres pierden
      // uno cada uno y ganan... nada. A se lleva 3 × 25.
      final scores = <String, Map<int, int>>{
        a: {for (var h = 1; h <= 18; h++) h: 3},
        b: {for (var h = 1; h <= 18; h++) h: 6},
        c: {for (var h = 1; h <= 18; h++) h: 6},
        d: {for (var h = 1; h <= 18; h++) h: 6},
      };
      final r = _round(value: 50, scores: scores);
      final bal = LedgerEngine.playerBalances(r);
      // A gana los tres bloques: cobra 25 en cada uno.
      expect(bal[a], closeTo(75, 0.001));
      // Su compañero de cada bloque también cobra 25 en ese bloque, y pierde
      // 25 en los otros dos: queda a -25.
      for (final p in [b, c, d]) {
        expect(bal[p], closeTo(-25, 0.001), reason: p);
      }
      expect(bal.values.fold(0.0, (s, v) => s + v), closeTo(0, 0.001));
    });

    test('un bloque empatado no se cobra y NO se acumula al siguiente', () {
      // Acumular cambiaría de pareja a mitad de apuesta: el importe lo cobraría
      // gente que no jugó ese bloque.
      final scores = <String, Map<int, int>>{
        // Bloque 1 (A+B vs C+D) empatado a 4. Bloque 2 (A+C vs B+D) lo gana
        // A+C porque A baja a 3 y los otros tres se quedan en 4.
        a: {for (var h = 1; h <= 12; h++) h: h <= 6 ? 4 : 3},
        b: {for (var h = 1; h <= 12; h++) h: 4},
        c: {for (var h = 1; h <= 12; h++) h: 4},
        d: {for (var h = 1; h <= 12; h++) h: 4},
      };
      final r = _round(value: 50, scores: scores);
      final bl = SixesEngine.bloques(r, cuatro, _mod(r));
      expect(bl[0].sinLiquidar, SixesSinLiquidar.empatado);
      final bal = LedgerEngine.playerBalances(r);
      // Solo se movió el bloque 2, y por su importe: 50 en total.
      final ganado =
          bal.values.where((v) => v > 0).fold(0.0, (s, v) => s + v);
      expect(ganado, closeTo(50, 0.001));
    });

    test('con el monto a cero no se apunta nada', () {
      final r =
          _round(value: 0, scores: _planos({a: 3, b: 3, c: 5, d: 5}));
      expect(SixesEngine.liquidar(r, cuatro, _mod(r)), isEmpty);
    });

    test('el motivo del asiento nombra el bloque Y el tramo', () {
      // "Bloque 2" a secas obliga a recordar de qué hoyos hablaba.
      final r = _round(scores: _planos({a: 3, b: 3, c: 5, d: 5}, hasta: 6));
      final e = SixesEngine.liquidar(r, cuatro, _mod(r)).first;
      expect(e.reason, contains('Bloque 1'));
      expect(e.reason, contains('hoyos 1-6'));
      expect(e.betType, BetModuleType.sixes);
    });
  });

  group('5 · el catálogo lo atenúa fuera de rango', () {
    test('cuatro y solo cuatro', () {
      expect(BetModuleType.sixes.motivoNoDisponible(4), isNull);
      for (final n in [2, 3, 5, 6]) {
        expect(BetModuleType.sixes.motivoNoDisponible(n), isNotNull,
            reason: '$n');
      }
    });

    test('el motivo se genera, y distingue pocos de muchos', () {
      final pocos = BetModuleType.sixes.motivoNoDisponible(3)!;
      final muchos = BetModuleType.sixes.motivoNoDisponible(5)!;
      expect(pocos, contains('se juega con 4 jugadores'));
      expect(pocos, isNot(muchos));
      // Con cinco se nombra el swing man, que es lo que el manual hace y esta
      // apuesta no.
      expect(muchos, contains('swing man'));
    });

    test('no se pacta por duelo, y se dice a dónde ir', () {
      expect(BetModuleType.sixes.sePactaPorDuelo, isFalse);
      expect(BetModuleType.sixes.motivoSinDuelo, contains('Agregar apuesta'));
    });

    test('está en el catálogo creable y en una sola sección', () {
      expect(creatableBetTypes, contains(BetModuleType.sixes));
      final enSecciones = [
        for (final s in betTypeSections) ...s.tipos,
      ].where((x) => x == BetModuleType.sixes);
      expect(enSecciones, hasLength(1));
    });

    test('tiene etiqueta, icono y descripción de verdad', () {
      expect(BetModuleType.sixes.label, 'Sixes');
      expect(BetModuleType.sixes.icon, isNotEmpty);
      expect(BetModuleType.sixes.description, contains('rotan'));
    });
  });

  group('6 · los bloques se dimensionan con la ronda', () {
    test('a 18 hoyos salen bloques de 6; a 9, de 3', () {
      // Sin que nadie lo toque: es la respuesta a "tres bloques de seis no caben
      // en nueve hoyos".
      final r18 = BetRecipe.build(
          cuenta: BetCount.sixes, participantIds: cuatro, holesInRound: 18);
      expect(r18.ok, isTrue);
      expect(r18.module!.sixes.hoyosPorBloque, 6);

      final r9 = BetRecipe.build(
          cuenta: BetCount.sixes, participantIds: cuatro, holesInRound: 9);
      expect(r9.ok, isTrue);
      expect(r9.module!.sixes.hoyosPorBloque, 3);
    });

    test('con nueve hoyos y bloques de 3 la rotación sigue cerrando', () {
      final r = _round(
          totalHoles: 9,
          hoyosPorBloque: 3,
          scores: _planos({a: 3, b: 3, c: 5, d: 5}, hasta: 9));
      final bl = SixesEngine.bloques(r, cuatro, _mod(r));
      expect(bl.every((x) => x.jugados == 3), isTrue);
      expect(bl[0].ganadores, [a, b]);
      // Y los tres bloques existen de verdad: ninguno fuera de la ronda.
      expect(bl.where((x) => x.sinLiquidar == SixesSinLiquidar.fueraDeLaRonda),
          isEmpty);
    });

    test('la receta rechaza cinco jugadores con el motivo del catálogo', () {
      final r = BetRecipe.build(
          cuenta: BetCount.sixes,
          participantIds: const [a, b, c, d, 'pid_ee05'],
          holesInRound: 18);
      expect(r.ok, isFalse);
      expect(r.rechazo, contains('swing man'));
    });

    test('no ofrece Front/Back: los bloques YA son su partición', () {
      final div = BetRecipe.divisionDe(BetCount.sixes, holesInRound: 18);
      expect(div.hayEleccion, isFalse);
      expect(div.elegida, BetDivision.unaSolaApuesta);
      expect(div.explicacion, contains('bloques'));
    });
  });

  group('7 · el viaje a JSON', () {
    test('la config sobrevive, y no engorda con los valores por defecto', () {
      const cfg = SixesConfig(value: 80, hoyosPorBloque: 3);
      final j = cfg.toJson();
      expect(j['hoyosPorBloque'], 3);
      expect(j.containsKey('tieRule'), isFalse, reason: 'push es el default');
      final ida = SixesConfig.fromJson(j);
      expect(ida.value, 80);
      expect(ida.hoyosPorBloque, 3);
      expect(ida.tieRule, TieRule.push);
    });

    test('el módulo entero va y vuelve', () {
      final mod = BetModuleInstance.defaultFor(BetModuleType.sixes, cuatro,
          id: 'm1');
      final ida = BetModuleInstance.fromJson(mod.toJson());
      expect(ida.type, BetModuleType.sixes);
      expect(ida.sixes.value, 50);
      expect(ida.sixes.hoyosPorBloque, 6);
    });

    test('una config vieja sin el campo se lee con el default', () {
      expect(SixesConfig.fromJson(const {'value': 50}).hoyosPorBloque, 6);
    });
  });
}
