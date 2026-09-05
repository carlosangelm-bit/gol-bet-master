// ─────────────────────────────────────────────────────────────────────────────
// LA LÍNEA «5 3 1»
//
//     «En el argot del golf se dice "quedamos 5 3 1"… pero en la app no se ve
//      así.»
//
// Cada número es una apuesta viva y todas avanzan a la vez. Cada presión que se
// abre añade un número al final, entrando en 0:
//
//     Gana el 1º   1
//     Gana el 2º   2 0      ← nace una presión
//     Gana el 3º   3 1
//     Gana el 4º   4 2 0    ← nace otra
//     Gana el 5º   5 3 1
//
// Los datos ya estaban —repartidos en dos bloques y con otro vocabulario— y ya
// eran correctos. Esto no cambia ningún cálculo: es cómo se dice.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// Una ronda donde A gana [ganaA], B gana [ganaB] y el resto se empata.
///
/// [hasta] son los hoyos capturados, en orden de juego.
Round _r({
  List<int> ganaA = const [],
  List<int> ganaB = const [],
  int hasta = 18,
  NassauConfig? cfg,
  StartingNine inicio = StartingNine.front,
}) {
  int golpe(String p, int h) {
    if (ganaA.contains(h)) return p == 'A' ? 4 : 5;
    if (ganaB.contains(h)) return p == 'A' ? 5 : 4;
    return 4;
  }

  final orden = inicio == StartingNine.back
      ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
      : List.generate(18, (i) => i + 1);
  final jugados = orden.take(hasta).toSet();

  return Round(
    id: 'r',
    name: 'R',
    course: _curso,
    isFinished: hasta == 18,
    players: [Player(id: 'A', name: 'A'), Player(id: 'B', name: 'B')],
    roundPlayers: [
      RoundPlayer(playerId: 'A', handicapEnRonda: 0),
      RoundPlayer(playerId: 'B', handicapEnRonda: 0),
    ],
    betGroups: [
      BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.oneVsOne,
          playerIds: const ['A', 'B'],
          modules: [
            BetModuleInstance(
                id: 'n',
                type: BetModuleType.nassau,
                name: 'Nassau',
                participantIds: const ['A', 'B'],
                nassauConfig: cfg ?? _conPresiones()),
          ])
    ],
    scores: {
      for (final p in ['A', 'B'])
        p: {
          for (final h in jugados)
            h: HoleScore(playerId: p, hole: h, grossScore: golpe(p, h), putts: 2)
        }
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 9, 2),
    totalHoles: 18,
    startingNine: inicio,
  );
}

/// Presiones encadenadas: es lo que produce la secuencia del argot.
NassauConfig _conPresiones() => const NassauConfig(
      frontValue: 50,
      backValue: 50,
      totalValue: 100,
      pressEnabled: true,
      autoPressTrigger: 2,
      frontPressValue: 50,
      backPressValue: 50,
      allowMultiplePresses: true,
    );

List<LineaDelDuelo> _lineas(Round r) =>
    BetEngine.lineasDelDuelo(r, 'A', 'B', r.betGroups.first.modules.first);

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 1 · la secuencia del argot, hoyo a hoyo', () {
    // A gana los cinco primeros hoyos. Es exactamente el ejemplo de Carlos.
    List<int> tras(int hoyos) =>
        _lineas(_r(ganaA: const [1, 2, 3, 4, 5], hasta: hoyos)).first.numeros;

    test('CLAVE: gana el 1º → 1', () {
      expect(tras(1), [1]);
    });

    test('CLAVE: gana el 2º → 2 0, porque nace una presión', () {
      expect(tras(2), [2, 0]);
    });

    test('CLAVE: gana el 3º → 3 1', () {
      expect(tras(3), [3, 1]);
    });

    test('CLAVE: gana el 4º → 4 2 0, y nace otra', () {
      expect(tras(4), [4, 2, 0]);
    });

    test('CLAVE: gana el 5º → 5 3 1', () {
      expect(tras(5), [5, 3, 1]);
    });

    test('CLAVE: y la LONGITUD dice cuántas presiones se abrieron', () {
      // Es la tercera cosa que la línea cuenta sin decirla.
      expect(_lineas(_r(ganaA: const [1], hasta: 1)).first.presiones, 0);
      expect(_lineas(_r(ganaA: const [1, 2, 3, 4, 5], hasta: 5)).first.presiones, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 2 · una presión recién abierta es 0', () {
    test('CLAVE: entra en 0 el hoyo en que nace', () {
      expect(_lineas(_r(ganaA: const [1, 2], hasta: 2)).first.numeros.last, 0);
    });

    test('CLAVE: y una empatada a mitad es el MISMO 0, a propósito', () {
      // A se pone 2 arriba (nace la presión), y luego se reparten un hoyo cada
      // uno: la presión vuelve a 0 habiendo jugado dos hoyos.
      //
      // Es el mismo número porque en la apuesta significan lo mismo: nadie va
      // arriba. Lo que las separa es HISTORIA —cuándo nació— y no estado; la
      // línea es una línea de estado, y la historia está en el bloque y en el
      // subrótulo, que dice el hoyo de cada una.
      final l = _lineas(_r(ganaA: const [1, 2, 3], ganaB: const [4], hasta: 4)).first;
      expect(l.numeros.last, 0);
      expect(l.numeros.length, 2, reason: 'la presión sigue viva');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 3 · la línea es de QUIEN MIRA', () {
    test('CLAVE: los mismos hoyos, leídos desde el otro, salen negados', () {
      final r = _r(ganaA: const [1, 2, 3, 4, 5], hasta: 5);
      final mod = r.betGroups.first.modules.first;
      final desdeA = BetEngine.lineasDelDuelo(r, 'A', 'B', mod).first;
      final desdeB = BetEngine.lineasDelDuelo(r, 'B', 'A', mod).first;
      expect(desdeA.numeros, [5, 3, 1]);
      expect(desdeB.numeros, [-5, -3, -1]);
    });

    test('CLAVE: el signo hace falta porque el líder puede NO ser el mismo', () {
      // Es lo que rompe el «5 3 1» a secas. A se pone 2 arriba y nace la
      // presión para B — que la gana. La línea real es «+2 −2», y sin signo no
      // hay forma de escribirla sin nombrar a un jugador por número, que es el
      // bloque que ya existe.
      // A gana 1 y 2 → +2, y nace la presión para B en el hoyo 3. B gana el 3:
      // el segmento se queda en +1 para A, y la presión en −1 para A.
      final l = _lineas(_r(ganaA: const [1, 2], ganaB: const [3], hasta: 3)).first;
      expect(l.numeros.first, greaterThan(0), reason: 'A lleva el segmento');
      expect(l.numeros.last, lessThan(0), reason: 'B lleva la presión');
      expect(l.texto, '+1 −1');
    });

    test('CLAVE: escrita, lleva el signo delante y el cero desnudo', () {
      final r = _r(ganaA: const [1, 2, 3, 4, 5], hasta: 5);
      expect(_lineas(r).first.texto, '+5 +3 +1');
      final mod = r.betGroups.first.modules.first;
      expect(BetEngine.lineasDelDuelo(r, 'B', 'A', mod).first.texto, '−5 −3 −1');
      expect(_lineas(_r(ganaA: const [1, 2], hasta: 2)).first.texto, '+2 0');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('la línea es POR SEGMENTO', () {
    test('CLAVE: una para el F9 y otra para el B9', () {
      // «El 5 3 1 clásico es de una vuelta de nueve», y encaja con la apuesta:
      // una presión nace dentro de un segmento y muere al acabarlo.
      final l = _lineas(_r(ganaA: const [1, 2, 3, 10, 11]));
      expect(l, hasLength(2));
      expect(l[0].etiqueta, 'F9');
      expect(l[1].etiqueta, 'B9');
    });

    test('CLAVE: las presiones del F9 NO se cuelan en la línea del B9', () {
      // Con los nueve primeros terminados y el B9 empezado: el F9 ya está
      // liquidado y el B9 no tiene presiones que enseñar.
      final l = _lineas(_r(ganaA: const [1, 2, 3, 4, 5], hasta: 12));
      expect(l[0].presiones, 2, reason: 'las dos del F9');
      expect(l[1].numeros, [0],
          reason: 'el B9 va empatado y sin ninguna presión suya');
    });

    test('CLAVE: y al cerrarse el nueve, cada presión enseña lo que se liquidó',
        () {
      // En vivo la línea va «5 3 1»; con el nueve terminado dice «5 1 1»,
      // porque una presión CIERRA donde nace la siguiente. No son dos cuentas:
      // son dos momentos, y el bloque de presiones dice exactamente lo mismo.
      final enVivo = _lineas(_r(ganaA: const [1, 2, 3, 4, 5], hasta: 5)).first;
      final cerrado = _lineas(_r(ganaA: const [1, 2, 3, 4, 5])).first;
      expect(enVivo.numeros, [5, 3, 1]);
      expect(cerrado.numeros, [5, 1, 1]);
    });

    test('CLAVE: con presiones en LAS DOS vueltas, cada una lleva las suyas', () {
      // El caso que de verdad separa las dos líneas. En el F9 nacen dos
      // presiones; en el B9, una. Si las vueltas se fundieran, la línea del F9
      // llevaría tres números de presión en vez de dos.
      final l = _lineas(_r(
          ganaA: const [1, 2, 3, 4, 5, 10, 11, 12], hasta: 13));
      expect(l[0].presiones, 2, reason: 'las dos del F9, y solo esas');
      expect(l[1].presiones, greaterThan(0), reason: 'el B9 tiene la suya');
      expect(l[0].numeros.length + l[1].numeros.length,
          l[0].presiones + l[1].presiones + 2,
          reason: 'ningún número contado dos veces');
    });

    test('CLAVE: el B9 no aparece hasta que se juega', () {
      final l = _lineas(_r(ganaA: const [1, 2], hasta: 9));
      expect(l, hasLength(1));
      expect(l.single.etiqueta, 'F9');
    });

    test('CLAVE: en una ronda de nueve, la etiqueta sobra', () {
      final nueve = _r(ganaA: const [1, 2, 3, 4, 5], hasta: 5);
      final corta = nueve.copyWith(totalHoles: 9);
      final l = BetEngine.lineasDelDuelo(
          corta, 'A', 'B', corta.betGroups.first.modules.first);
      expect(l, hasLength(1));
      expect(l.single.etiqueta, isEmpty);
      expect(l.single.numeros, [5, 3, 1]);
    });

    test('CLAVE: saliendo por el 10, el primer nueve sigue siendo el primero',
        () {
      // La segmentación es LÓGICA: el primer nueve jugado es el F9 aunque sus
      // hoyos se numeren 10-18.
      final l = _lineas(_r(
          ganaA: const [10, 11, 12, 13, 14],
          hasta: 5,
          inicio: StartingNine.back));
      expect(l, hasLength(1));
      expect(l.single.numeros, [5, 3, 1]);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('lo que la línea NO es', () {
    test('CLAVE: el Total 18 no entra', () {
      // Es una apuesta viva, pero sin cadena de presiones: nunca añadiría ni
      // quitaría un número. Se queda en su bloque.
      final l = _lineas(_r(ganaA: const [1, 2, 3, 4, 5]));
      expect(l.every((x) => x.etiqueta != '18'), isTrue);
      expect(l, hasLength(2), reason: 'F9 y B9, no tres');
    });

    test('CLAVE: sin presiones configuradas, la línea es UN número', () {
      // Y no es gratis: `nassauPressLiveStatus` detecta presiones mire o no la
      // configuración —los tres sitios que ya lo usaban preguntan
      // `mod.pressEnabled` antes de llamarlo—. Sin esa guarda, un grupo que NO
      // juega presiones vería aparecer en su línea apuestas que nadie abrió.
      final l = _lineas(_r(
          ganaA: const [1, 2, 3],
          cfg: const NassauConfig(
              frontValue: 50, backValue: 50, totalValue: 100)));
      expect(l.first.numeros, [3]);
      expect(l.first.presiones, 0);
    });

    test('CLAVE: cada número es EL MISMO que enseña el bloque', () {
      // «Esto no cambia ningún cálculo: es vocabulario.» La forma de probarlo es
      // comparar la línea contra la fuente que pintan las tarjetas de presión,
      // número a número. Si algún día se separan, la línea diría una cosa y el
      // bloque de al lado otra — en la misma pantalla.
      final r = _r(ganaA: const [1, 2, 3, 4, 5], hasta: 12);
      final mod = r.betGroups.first.modules.first;
      final st = BetEngine.nassauPressLiveStatus(r, 'A', 'B', mod);
      final l = _lineas(r);
      expect(l[0].numeros, [st.front, ...st.frontPresses.map((p) => p.score)]);
      expect(l[1].numeros, [st.back, ...st.backPresses.map((p) => p.score)]);
    });

    test('CONTRAPESO: sin un solo hoyo jugado no hay línea', () {
      final r = _r(hasta: 0);
      expect(_lineas(r), isEmpty);
    });
  });
}
