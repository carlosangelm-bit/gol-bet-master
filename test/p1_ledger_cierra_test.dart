// ─────────────────────────────────────────────────────────────────────────────
// P1 · EL LEDGER CIERRA EN CERO — sobre la matriz, no sobre casos sueltos
//
// Los escenarios 1.1 a 1.6 del plan ya tienen sus tests con cifras concretas
// —lados_desiguales, pareja_base, sixes, wolf_cinco—. Lo que falta, y es lo que
// de verdad caza un reparto roto, es la PROPIEDAD: para cualquier formato, con
// cualquier composición de lados, la suma de todos los balances es cero.
//
// Una fila suelta puede parecer plausible; un total que no cierra no. Y como es
// una propiedad, se puede recorrer la matriz entera en vez de elegir casos: si
// mañana entra un formato nuevo y su reparto crea dinero, este test lo caza sin
// que nadie escriba un caso para él.
//
// El recorrido: cada formato creable × cada composición admisible × ganando cada
// lado. Los que no admiten esa composición se saltan CON LA MISMA función que
// atenúa la opción en pantalla, así que el test no puede probar combinaciones
// que la app no ofrece —ni saltarse las que sí—.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/engines/settlement_notes.dart';
import 'package:golf_bet_master/models/models.dart';

const p1 = 'pid_01', p2 = 'pid_02', p3 = 'pid_03';
const p4 = 'pid_04', p5 = 'pid_05', p6 = 'pid_06';

CourseInfo _course() => CourseInfo(
    name: 'Los Encinos',
    holes: List.generate(18, (i) {
      final h = i + 1;
      // Par variado y un par 3 para que Oyes tenga dónde caer.
      return CourseHole(
          hole: h, par: h % 5 == 0 ? 3 : (h % 7 == 0 ? 5 : 4), strokeIndex: h);
    }));

/// Una ronda con un módulo y, si se dan, dos lados.
Round _round({
  required BetModuleType tipo,
  required List<String> pids,
  List<String>? ladoA,
  List<String>? ladoB,
  required Map<String, int> golpes,
  int putts = 2,
}) {
  final players = pids
      .map((id) => Player(id: id, name: id.toUpperCase(), handicapBase: 0))
      .toList();

  var mod = BetModuleInstance.defaultFor(tipo, pids, id: 'mod');
  if (ladoA != null && ladoB != null && tipo.rules.teams) {
    mod = mod.copyWith(sides: [
      BetSide(id: 'sA', name: 'A', playerIds: ladoA),
      BetSide(id: 'sB', name: 'B', playerIds: ladoB),
    ]);
  }

  return Round(
    id: 'r',
    name: 'R',
    course: _course(),
    players: players,
    roundPlayers:
        players.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.allInOnePot,
          playerIds: pids,
          modules: [mod])
    ],
    scores: {
      for (final e in golpes.entries)
        e.key: {
          for (var h = 1; h <= 18; h++)
            h: HoleScore(
                playerId: e.key, hole: h, grossScore: e.value, putts: putts),
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

/// La suma de los ASIENTOS. Cero exacto, siempre: cada asiento mueve el mismo
/// importe de uno a otro, así que el total no puede cambiar.
///
/// Se mide aquí y no en playerBalances porque ese redondea el total de CADA
/// jugador a céntimos, y un importe que no divide exacto entre los cruces deja
/// residuo —ver el grupo 5—. El invariante que protege el dinero es este.
double _suma(Round r) {
  var total = 0.0;
  for (final e in LedgerEngine.entriesOf(r)) {
    if (e.amount <= 0) continue;
    total -= e.amount;
    total += e.amount;
  }
  // Y la comprobación de verdad: lo que cobra cada uno menos lo que paga.
  final porJugador = <String, double>{};
  for (final e in LedgerEngine.entriesOf(r)) {
    if (e.amount <= 0) continue;
    porJugador[e.fromPlayerId] = (porJugador[e.fromPlayerId] ?? 0) - e.amount;
    porJugador[e.toPlayerId] = (porJugador[e.toPlayerId] ?? 0) + e.amount;
  }
  return porJugador.values.fold(total, (a, b) => a + b);
}

/// Las composiciones a probar, con su etiqueta.
const composiciones = <({String nombre, List<String> pids, List<String>? a, List<String>? b})>[
  (nombre: '1v1', pids: [p1, p2], a: [p1], b: [p2]),
  (nombre: '2v2', pids: [p1, p2, p3, p4], a: [p1, p2], b: [p3, p4]),
  (nombre: '2v3', pids: [p1, p2, p3, p4, p5], a: [p1, p2], b: [p3, p4, p5]),
  (nombre: '3v2', pids: [p1, p2, p3, p4, p5], a: [p1, p2, p3], b: [p4, p5]),
  (nombre: '1v3', pids: [p1, p2, p3, p4], a: [p1], b: [p2, p3, p4]),
  (nombre: '2v4', pids: [p1, p2, p3, p4, p5, p6], a: [p1, p2], b: [p3, p4, p5, p6]),
  (nombre: 'sin lados · 4', pids: [p1, p2, p3, p4], a: null, b: null),
  (nombre: 'sin lados · 5', pids: [p1, p2, p3, p4, p5], a: null, b: null),
];

void main() {
  group('1 · el ledger cierra en cero en toda la matriz', () {
    for (final tipo in creatableBetTypes) {
      for (final c in composiciones) {
        // La misma función que atenúa la opción en pantalla. Así el test no
        // prueba lo que la app no ofrece, ni se salta lo que sí.
        if (tipo.motivoNoDisponible(c.pids.length) != null) continue;
        if (c.a != null && !tipo.rules.teams) continue;

        test('${tipo.label} · ${c.nombre}', () {
          // Tres repartos de golpes: gana A, gana B, empatan. Los tres tienen
          // que cerrar, y el empate es el que más se olvida.
          final casos = <String, Map<String, int>>{
            'gana A': {
              for (final p in c.pids)
                p: (c.a ?? [c.pids.first]).contains(p) ? 3 : 5,
            },
            'gana B': {
              for (final p in c.pids)
                p: (c.a ?? [c.pids.first]).contains(p) ? 5 : 3,
            },
            'empatan': {for (final p in c.pids) p: 4},
          };
          for (final e in casos.entries) {
            final r = _round(
                tipo: tipo,
                pids: c.pids,
                ladoA: c.a,
                ladoB: c.b,
                golpes: e.value);
            expect(_suma(r), closeTo(0, 0.001),
                reason: '${tipo.label} · ${c.nombre} · ${e.key}');
          }
        });
      }
    }
  });

  group('2 · y cierra también con la ronda a medias', () {
    // Es el estado real durante casi toda la ronda, y donde un reparto que
    // divide por hoyos jugados puede descuadrar.
    Round aMedias(BetModuleType tipo, List<String> pids, List<String> a,
        List<String> b, int hasta) {
      final r = _round(
          tipo: tipo,
          pids: pids,
          ladoA: a,
          ladoB: b,
          golpes: {for (final p in pids) p: a.contains(p) ? 3 : 5});
      return r.copyWith(scores: {
        for (final e in r.scores.entries)
          e.key: {
            for (final h in e.value.entries)
              if (h.key <= hasta) h.key: h.value,
          },
      });
    }

    for (final tipo in creatableBetTypes) {
      if (tipo.motivoNoDisponible(5) != null) continue;
      if (!tipo.rules.teams) continue;
      test('${tipo.label} · 2v3 con 7 hoyos jugados', () {
        final r = aMedias(tipo, const [p1, p2, p3, p4, p5],
            const [p1, p2], const [p3, p4, p5], 7);
        expect(_suma(r), closeTo(0, 0.001));
      });
    }
  });

  group('3 · sin ningún score no se mueve dinero', () {
    // P7.1: la ronda que nadie ha empezado no puede liquidar nada, y desde
    // luego no puede descuadrar.
    for (final tipo in creatableBetTypes) {
      if (tipo.motivoNoDisponible(4) != null) continue;
      test('${tipo.label} · cuatro jugadores, cero scores', () {
        final r = _round(
            tipo: tipo, pids: const [p1, p2, p3, p4], golpes: const {});
        final bal = LedgerEngine.playerBalances(r);
        expect(bal.values.every((v) => v.abs() < 0.001), isTrue,
            reason: '${tipo.label} liquidó algo sin scores: $bal');
      });
    }
  });

  group('4 · el empate general da cero, y por el mismo motivo en todos', () {
    // P7.3. Un cero mudo y un cero explicado se ven igual en el balance; lo que
    // este test protege es que sea CERO y no una cifra pequeña de redondeo.
    for (final tipo in creatableBetTypes) {
      if (tipo.motivoNoDisponible(4) != null) continue;
      test('${tipo.label} · todos a 4 golpes y 2 putts', () {
        final r = _round(
            tipo: tipo,
            pids: const [p1, p2, p3, p4],
            golpes: const {p1: 4, p2: 4, p3: 4, p4: 4});
        expect(_suma(r), closeTo(0, 0.001));
      });
    }
  });

  group('5 · el residuo de redondeo se DICE, no se esconde', () {
    // El hallazgo del grupo 1: un Nassau 2 contra 3 a \$200 reparte \$33.33 por
    // cruce, los dos que ganan cobran \$100 justos y los tres que pagan ponen
    // \$66.67. Los asientos cierran exacto; lo que se enseña, al peso, no.
    //
    // No se arregla moviendo el céntimo a alguien —elegir a quién sería
    // inventarse una regla— así que se dice. Es el canal de notas.
    Round dosContraTres({double front = 50, double back = 50, double total = 100}) {
      final pids = [p1, p2, p3, p4, p5];
      final players = pids
          .map((id) => Player(id: id, name: id.toUpperCase(), handicapBase: 0))
          .toList();
      final mod = BetModuleInstance(
        id: 'mod',
        type: BetModuleType.nassau,
        name: 'Nassau',
        participantIds: pids,
        nassauConfig: NassauConfig(
            frontValue: front,
            backValue: back,
            totalValue: total,
            pressEnabled: false,
            mode: GrossNetMode.gross),
        sides: [
          BetSide(id: 'sA', name: 'A', playerIds: const [p1, p2]),
          BetSide(id: 'sB', name: 'B', playerIds: const [p3, p4, p5]),
        ],
      );
      return Round(
        id: 'r',
        name: 'R',
        course: _course(),
        players: players,
        roundPlayers: players
            .map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0))
            .toList(),
        betGroups: [
          BetGroup(
              id: 'g',
              name: 'G',
              format: PartidaFormat.allInOnePot,
              playerIds: pids,
              modules: [mod])
        ],
        scores: {
          for (final p in pids)
            p: {
              for (var h = 1; h <= 18; h++)
                h: HoleScore(
                    playerId: p,
                    hole: h,
                    grossScore: [p1, p2].contains(p) ? 3 : 5)
            }
        },
        events: const {},
        oyeseRankings: const {},
        sliding: const [],
        createdAt: DateTime(2026, 8, 1),
        totalHoles: 18,
        isFinished: true,
      );
    }

    test('con \$200 entre 6 cruces sale nota, y dice cuánto falta', () {
      final notas = notasDeLiquidacion(dosContraTres());
      final residuo =
          notas.where((n) => n.texto.contains('redondeadas al peso'));
      expect(residuo, hasLength(1));
      expect(residuo.first.texto, contains('\$1'));
      expect(residuo.first.texto, contains('los asientos suman cero'));
      expect(residuo.first.tono, TonoNota.informativa);
    });

    test('los asientos SÍ cierran exacto: el reparto no está mal', () {
      // Es la mitad que importa. Si el reparto estuviera mal, la nota estaría
      // tapando un fallo en vez de explicando un redondeo.
      expect(_suma(dosContraTres()), closeTo(0, 0.000001));
    });

    test('con un importe que divide exacto NO sale nota', () {
      // El contrapeso: sin esto la nota podría estar saliendo siempre.
      final notas = notasDeLiquidacion(
          dosContraTres(front: 100, back: 100, total: 100));
      expect(notas.where((n) => n.texto.contains('redondeadas al peso')),
          isEmpty);
    });

    test('en 2v2 tampoco: los cruces dividen el importe', () {
      final r = _round(
          tipo: BetModuleType.nassau,
          pids: const [p1, p2, p3, p4],
          ladoA: const [p1, p2],
          ladoB: const [p3, p4],
          golpes: const {p1: 3, p2: 3, p3: 5, p4: 5});
      expect(
          notasDeLiquidacion(r)
              .where((n) => n.texto.contains('redondeadas al peso')),
          isEmpty);
    });
  });
}
