// ─────────────────────────────────────────────────────────────────────────────
// EL CARRY PEDIDO — no es un multiplicador, es VENTAJA
//
// Carlos revisó una ronda real de cinco y corrigió la regla entera:
//
//     «El carry solo lo puedo pedir si voy perdiendo. Si lo pido, el jugador que
//      pide el carry recibe un golpe extra de ventaja en esa apuesta aparte. Si
//      en el B9 le tocaban 3 golpes de ventaja, con el carry le tocarían 4.
//      Entonces en el carry se juega una apuesta con 3 golpes de ventaja y otra
//      con 4.»
//
// Dos apuestas simultáneas sobre los mismos nueve hoyos, del mismo importe, con
// ventajas distintas. Lo que había era un multiplicador ×2/×3/×4, que se retiró:
// con esta regla no multiplica nada.
//
// El mecanismo se parece a la apertura de 2ª vuelta —una apuesta paralela sobre
// los mismos hoyos— y no al factor que había.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// Una ronda de 18 con dos jugadores.
///
/// [golpesA] y [golpesB] son el score de cada hoyo, 1..18.
/// [hcpA]/[hcpB] fijan la ventaja: B recibe (hcpB − hcpA) golpes.
Round _r({
  required Map<int, int> golpesA,
  required Map<int, int> golpesB,
  double hcpA = 0,
  double hcpB = 0,
  NassauConfig? cfg,
}) =>
    Round(
      id: 'r',
      name: 'R',
      course: _curso,
      isFinished: true,
      players: [Player(id: 'A', name: 'A'), Player(id: 'B', name: 'B')],
      roundPlayers: [
        RoundPlayer(playerId: 'A', handicapEnRonda: hcpA),
        RoundPlayer(playerId: 'B', handicapEnRonda: hcpB),
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.allInOnePot,
            playerIds: const ['A', 'B'],
            modules: [
              BetModuleInstance(
                  id: 'n',
                  type: BetModuleType.nassau,
                  name: 'Nassau',
                  participantIds: const ['A', 'B'],
                  nassauConfig: cfg ??
                      const NassauConfig(
                          frontValue: 50,
                          backValue: 50,
                          totalValue: 100,
                          carryEnabled: true)),
            ])
      ],
      scores: {
        'A': {
          for (final e in golpesA.entries)
            e.key: HoleScore(playerId: 'A', hole: e.key, grossScore: e.value, putts: 2)
        },
        'B': {
          for (final e in golpesB.entries)
            e.key: HoleScore(playerId: 'B', hole: e.key, grossScore: e.value, putts: 2)
        },
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 2),
      totalHoles: 18,
      startingNine: StartingNine.front,
    );

/// Todos empatan salvo los hoyos que se digan.
Map<int, int> _par({List<int> pierde = const []}) =>
    {for (int h = 1; h <= 18; h++) h: pierde.contains(h) ? 5 : 4};

List<LedgerEntry> _asientos(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r);
}

BetModuleInstance _mod(Round r) => r.betGroups.first.modules.first;

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 3 · solo lo puede pedir quien va perdiendo', () {
    test('CLAVE: lo pide el que PERDIÓ la primera vuelta, y solo él', () {
      // A gana el hoyo 1 → B perdió el F9.
      final r = _r(golpesA: _par(), golpesB: _par(pierde: [1]));
      expect(BetEngine.quienPuedePedirCarry(r, 'A', 'B', _mod(r)), 'B');
      // Y se lee igual con los ids al revés: la respuesta es la persona.
      expect(BetEngine.quienPuedePedirCarry(r, 'B', 'A', _mod(r)), 'B');
    });

    test('CLAVE: con el F9 EMPATADO no lo puede pedir NADIE', () {
      // No hay perdedor. Lo que corre es el carry natural, que se aplica solo.
      final r = _r(golpesA: _par(), golpesB: _par(pierde: [10]));
      expect(BetEngine.quienPuedePedirCarry(r, 'A', 'B', _mod(r)), isNull);
    });

    test('CLAVE: con el F9 a medias tampoco: no se sabe quién pierde', () {
      final golpes = {for (int h = 1; h <= 8; h++) h: 4};
      final r = _r(golpesA: golpes, golpesB: {...golpes, 1: 5});
      expect(BetEngine.quienPuedePedirCarry(r, 'A', 'B', _mod(r)), isNull);
    });

    test('CLAVE: y no se puede pedir dos veces', () {
      final r = _r(
          golpesA: _par(),
          golpesB: _par(pierde: [1]),
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              carryPedidoByPair: {'A|B': 'B'}));
      expect(BetEngine.quienPuedePedirCarry(r, 'A', 'B', _mod(r)), isNull);
    });

    test('sin carry en el módulo, no se ofrece', () {
      final r = _r(
          golpesA: _par(),
          golpesB: _par(pierde: [1]),
          cfg: const NassauConfig(frontValue: 50, backValue: 50, totalValue: 100));
      expect(BetEngine.quienPuedePedirCarry(r, 'A', 'B', _mod(r)), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 2 · una apuesta paralela con un golpe más, del mismo valor',
      () {
    NassauConfig pedidoPor(String quien) => NassauConfig(
        frontValue: 50,
        backValue: 50,
        totalValue: 100,
        carryEnabled: true,
        carryPedidoByPair: {'A|B': quien});

    test('CLAVE: vale LO MISMO que el B9 — no el doble', () {
      // «La apuesta del carry vale lo mismo.»
      final r = _r(
          golpesA: _par(pierde: [10, 11, 12]),
          golpesB: _par(pierde: [1]),
          cfg: pedidoPor('B'));
      final carry =
          _asientos(r).firstWhere((e) => e.reason.contains('Carry'));
      expect(carry.amount, 50);
    });

    test('CLAVE: el golpe extra se lo lleva EL QUE LO PIDIÓ', () {
      // B no recibe ventaja (mismo handicap). Con el carry recibe 1 golpe, y ese
      // golpe cae en el hoyo más difícil del nueve —el SI 1, que aquí es el 10—.
      //
      // En el B9: A y B empatan todos los hoyos salvo el 10, que lo gana A por
      // uno. La apuesta NORMAL la gana A. La del CARRY la empata B con su golpe
      // en el 10, así que no la paga nadie.
      final r = _r(
          golpesA: _par(),
          golpesB: _par(pierde: [1, 10]),
          cfg: pedidoPor('B'));
      final razones = _asientos(r).map((e) => e.reason).toList();
      expect(razones.any((x) => x.contains('Back 9')), isTrue,
          reason: 'la normal la gana A');
      expect(razones.any((x) => x.contains('Carry')), isFalse,
          reason: 'la del carry la empata B con su golpe extra');
    });

    test('CLAVE: y si lo pide el otro, el golpe es del otro', () {
      // Mismos scores, distinto solicitante. Ahora el golpe extra es de A, que
      // ya iba ganando el B9: la gana también en la del carry.
      final r = _r(
          golpesA: _par(),
          golpesB: _par(pierde: [1, 10]),
          cfg: pedidoPor('A'));
      final carry = _asientos(r).firstWhere((e) => e.reason.contains('Carry'));
      expect(carry.toPlayerId, 'A');
    });

    test('CLAVE: son los MISMOS nueve hoyos que el B9, no dieciocho', () {
      // A gana el F9 por el hoyo 1 y pierde el B9 por el 10. Si la apuesta del
      // carry cogiera los dieciocho quedaría empatada y no pagaría nadie.
      final r = _r(
          golpesA: _par(pierde: [10]),
          golpesB: _par(pierde: [1]),
          cfg: pedidoPor('B'));
      final carry = _asientos(r).firstWhere((e) => e.reason.contains('Carry'));
      expect(carry.toPlayerId, 'B', reason: 'B ganó los nueve traseros');
    });

    test('CONTRAPESO: sin pedirlo, la apuesta no existe', () {
      final r = _r(golpesA: _par(), golpesB: _par(pierde: [1, 10]));
      expect(_asientos(r).any((e) => e.reason.contains('Carry')), isFalse);
    });

    test('CONTRAPESO: y en una ronda de nueve hoyos tampoco', () {
      // No hay segunda vuelta sobre la que jugarla.
      final golpes = {for (int h = 1; h <= 9; h++) h: 4};
      final r = _r(
          golpesA: golpes,
          golpesB: {...golpes, 1: 5},
          cfg: pedidoPor('B'));
      expect(_asientos(r).any((e) => e.reason.contains('Carry')), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('LO QUE CARLOS PREGUNTÓ · el que no tiene ventaja', () {
    test('CLAVE: quien recibía 0 golpes, con carry recibe 1', () {
      // «¿Con carry recibe 1? Presumiblemente sí.» Sí: la regla es «un golpe
      // más», y un golpe más que cero es uno. Sale solo de sumar sobre la
      // ventaja CON SIGNO en vez de sobre su valor absoluto.
      final r = _r(golpesA: _par(), golpesB: _par(pierde: [1]));
      // B es el de handicap más bajo o igual: no recibe nada.
      expect(BetEngine.strokesP1ReceivesFromP2(r, 'B', 'A'), 0);

      final conCarry = _r(
          golpesA: _par(),
          golpesB: _par(pierde: [1, 10]),
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              carryPedidoByPair: {'A|B': 'B'}));
      // El golpe cae en el SI 1 del segundo nueve —el hoyo 10— y le empata a B
      // el único hoyo que perdía. Sin el golpe, esa apuesta la ganaría A.
      expect(_asientos(conCarry).any((e) => e.reason.contains('Carry')), isFalse,
          reason: 'empatada: el golpe extra existió');
    });

    test('CLAVE: y al que DABA golpes le queda uno menos que dar', () {
      // El caso simétrico, que la misma línea resuelve.
      //
      // B tiene 2 de handicap más que A. Esa ventaja es de DIECIOCHO hoyos y se
      // parte: la vuelta de inicio se lleva 1 y la trasera 1. Así que en el B9 B
      // juega con UN golpe, en el hoyo 10 —el más difícil de esa vuelta—.
      //
      // A pide el carry, así que en la apuesta del carry B se queda con CERO.
      final cfg = const NassauConfig(
          frontValue: 50,
          backValue: 50,
          totalValue: 100,
          carryEnabled: true,
          carryPedidoByPair: {'A|B': 'A'});
      // B pierde en bruto solo el hoyo 10 (y el 1, para que A gane el F9 y el
      // carry se pueda pedir).
      final r = _r(
          golpesA: _par(),
          golpesB: _par(pierde: [1, 10]),
          hcpA: 0,
          hcpB: 2,
          cfg: cfg);
      final rz = _asientos(r).map((e) => e.reason).toList();
      expect(rz.any((x) => x.contains('Back 9')), isFalse,
          reason: 'la NORMAL queda en tablas: el golpe de B empata el hoyo 10');
      expect(rz.any((x) => x.contains('Carry')), isTrue,
          reason: 'la del CARRY la gana A: a B le quedó un golpe menos');
    });

    test('CLAVE: el golpe se suma al reparto de la VUELTA, no al de dieciocho',
        () {
      // El caso que separa las dos cuentas, y que la primera versión de esto
      // tenía mal.
      //
      // B tiene 1 de handicap más que A. Esa ventaja es de DIECIOCHO y se
      // parte: la vuelta de inicio se lleva 1 y la trasera CERO. Así que en el
      // B9 B juega parejo, y con el carry recibe UN golpe — el del hoyo 10.
      //
      // Si el uno se sumara a la ventaja de dieciocho, serían 2 → la trasera se
      // llevaría 1 y con el carry DOS, y B empataría también el hoyo 11.
      final r = _r(
          golpesA: _par(),
          golpesB: _par(pierde: [1, 10, 11]),
          hcpA: 0,
          hcpB: 1,
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              carryPedidoByPair: {'A|B': 'B'}));
      final carry = _asientos(r).firstWhere((e) => e.reason.contains('Carry'));
      expect(carry.toPlayerId, 'A',
          reason: 'con UN golpe B empata el 10 y pierde el 11');
    });

    test('CLAVE: el golpe extra cae DENTRO de esos nueve', () {
      // Sumar uno a la ventaja de dieciocho no da un golpe más aquí: con
      // ventaja 1 ese golpe cae en el SI 1 del campo, que está en la PRIMERA
      // vuelta. Se comprueba con el caso que lo distingue: A y B parejos, B
      // pide carry, y B pierde en bruto el hoyo 10 —SI 1 de la vuelta trasera—.
      //
      // Si el golpe fuera al reparto de DIECIOCHO, B no recibiría nada en esta
      // vuelta y perdería la apuesta del carry. Con el reparto de la VUELTA,
      // recibe su golpe en el 10 y la empata.
      final r = _r(
          golpesA: _par(),
          golpesB: _par(pierde: [1, 10]),
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              carryPedidoByPair: {'A|B': 'B'}));
      expect(_asientos(r).any((e) => e.reason.contains('Carry')), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 5 · las dos apuestas se ven POR SEPARADO', () {
    test('CLAVE: dos asientos distintos, no uno a doble precio', () {
      // Es la lección de las seis apuestas que faltaban, y la del precedente de
      // los $3550: dos apuestas con el mismo importe sobre los mismos hoyos
      // tienen que poder distinguirse sin contar cuál es cuál.
      final r = _r(
          golpesA: _par(pierde: [10, 11, 12]),
          golpesB: _par(pierde: [1]),
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              carryPedidoByPair: {'A|B': 'B'}));
      final razones = _asientos(r)
          .where((e) => e.betType == BetModuleType.nassau)
          .map((e) => e.reason)
          .toList();
      expect(razones.where((x) => x.contains('Back 9')).length, 1);
      expect(razones.where((x) => x.contains('Carry')).length, 1);
      expect(razones.toSet().length, razones.length,
          reason: 'ninguna razón repetida');
    });

    test('CLAVE: y el motivo dice EN QUÉ se diferencian', () {
      // «Carry» a secas no distingue nada: las dos son el carry. Lo que las
      // separa es la ventaja, y eso es lo que tiene que leerse.
      final r = _r(
          golpesA: _par(pierde: [10, 11, 12]),
          golpesB: _par(pierde: [1]),
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              carryPedidoByPair: {'A|B': 'B'}));
      final carry = _asientos(r).firstWhere((e) => e.reason.contains('Carry'));
      expect(carry.reason, contains('golpe'));
    });
  });
}
