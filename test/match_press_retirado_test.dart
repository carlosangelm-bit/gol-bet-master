// ─────────────────────────────────────────────────────────────────────────────
// MATCH + PRESS, RETIRADO ENTERO
//
//     «Match + Press debería dejar de existir, ya que las configuraciones que
//      acabamos de trabajar y las que aplican a Match + Press, todas viven en
//      Nassau.»
//
// Y es cierto: Match + Press es un Nassau sin partición en vueltas.
//
//     Nassau  F9 $0 · B9 $0 · Total $100 · Presiones $50
//
// ── Lo que costaba tenerlo ──────────────────────────────────────────────────
//
// Dos sitios por cada regla. El multiplicador del carry hubo que retirarlo de
// las dos configuraciones; la línea «5 3 1» habría que escribirla dos veces; y
// el motor de ventajas tenía que ELEGIR cuál de los dos representaba el duelo
// cuando la partida llevaba ambos.
//
// ── Antes se retiró a medias, y por eso este fichero cambió de sentido ──────
//
// Hubo una retirada anterior: fuera del catálogo, vivo en el motor «porque las
// rondas guardadas tienen que liquidar igual». Eso dejaba TODO el coste en pie y
// solo quitaba la puerta. Esta vez sale entero, sin migración: nadie lo tiene
// configurado, y si un documento guardado deja de leerse se vuelve a crear como
// un Nassau con los nueves en cero.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';

const p1 = 'p1', p2 = 'p2';

final _curso = CourseInfo(
    name: 'T',
    holes: List.generate(
        18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));

/// p1 gana los seis primeros hoyos; el resto se empatan.
Round _ronda(NassauConfig cfg) => Round(
      id: 'r',
      name: 'R',
      course: _curso,
      isFinished: true,
      players: [Player(id: p1, name: 'P1'), Player(id: p2, name: 'P2')],
      roundPlayers: [
        RoundPlayer(playerId: p1, handicapEnRonda: 0),
        RoundPlayer(playerId: p2, handicapEnRonda: 0),
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.oneVsOne,
            playerIds: const [p1, p2],
            modules: [
              BetModuleInstance(
                  id: 'm',
                  type: BetModuleType.nassau,
                  name: 'Match',
                  participantIds: const [p1, p2],
                  nassauConfig: cfg),
            ])
      ],
      scores: {
        p1: {
          for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: p1, hole: h, grossScore: h <= 6 ? 3 : 4)
        },
        p2: {
          for (var h = 1; h <= 18; h++)
            h: HoleScore(playerId: p2, hole: h, grossScore: 4)
        },
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 2),
      totalHoles: 18,
    );

/// Lo que era Match + Press: $100 al match, presiones de $50, trigger 2.
const _match = NassauConfig(
  frontValue: 0,
  backValue: 0,
  totalValue: 100,
  pressEnabled: true,
  autoPressTrigger: 2,
  frontPressValue: 50,
  backPressValue: 50,
  allowMultiplePresses: true,
  mode: GrossNetMode.gross,
);

String _leer(String ruta) => File(ruta).readAsStringSync();

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 2 · no queda nada del tipo', () {
    test('CLAVE: el valor desapareció del enum', () {
      // Y con él la deserialización, el motor y las pantallas. Si volviera,
      // volvería el coste de dos sitios por regla.
      expect(BetModuleType.values.map((t) => t.name),
          isNot(contains('matchAutoPress')));
      expect(() => BetModuleType.values.byName('matchAutoPress'), throwsArgumentError);
    });

    test('CLAVE: y el catálogo ya no esconde ningún tipo', () {
      // Había un filtro `isCreatable` para retirarlo de las hojas dejándolo
      // vivo. Se fue con él: todo lo que existe se puede crear.
      expect(creatableBetTypes, BetModuleType.values);
    });

    test('CLAVE: el módulo guardado NO se lee, y es la decisión', () {
      // Sin migración, a propósito. Un JSON con el tipo viejo cae al tipo por
      // defecto en vez de reventar; el grupo lo vuelve a crear como Nassau con
      // los nueves en cero, que son dos toques.
      final viejo = {
        'id': 'm',
        'type': 'matchAutoPress',
        'name': 'Match',
        'participantIds': [p1, p2],
        'matchAutoPressConfig': {'matchValue': 100.0, 'pressValue': 50.0},
      };
      final back = BetModuleInstance.fromJson(viejo);
      expect(back.type, isNot(BetModuleType.nassau),
          reason: 'no se convierte solo: no hay migración');
      expect(back.toJson().containsKey('matchAutoPressConfig'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 1 · el Nassau con los nueves a cero ES el match', () {
    test('CLAVE: paga el match sobre los 18, no tres apuestas', () {
      final e = BetEngine.computeAll(_ronda(_match));
      final razones = e.map((x) => x.reason).toList();
      expect(razones.where((r) => r.contains('Total 18')).length, 1);
      // El F9 y el B9 no pagan: valen cero, así que no producen asiento. Se
      // compara el SEGMENTO —la razón entera— y no un `contains`, porque la
      // etiqueta de una presión lleva dentro el nombre de su nueve:
      // «Press H3–H4 (Nassau Front 9)».
      expect(razones, isNot(contains('Nassau Front 9')));
      expect(razones, isNot(contains('Nassau Back 9')));
      // Y ningún asiento de cero pesos: una línea que no paga se lee como algo
      // que salió mal.
      expect(e.every((x) => x.amount > 0), isTrue);
      expect(e.firstWhere((x) => x.reason.contains('Total 18')).amount, 100);
    });

    test('CLAVE: y las presiones se juegan', () {
      // p1 se pone 2 arriba en el hoyo 2 → nace una presión.
      final e = BetEngine.computeAll(_ronda(_match));
      expect(e.any((x) => x.reason.contains('Press')), isTrue);
    });

    test('CLAVE: la línea «5 3 1» la hereda sin escribirla dos veces', () {
      // Era una de las dos cosas que quedaban por hacer en el otro motor.
      final r = _ronda(_match);
      final l = BetEngine.lineasDelDuelo(
          r, p1, p2, r.betGroups.first.modules.first);
      expect(l, isNotEmpty);
      expect(l.first.numeros.first, greaterThan(0));
    });

    test('CONTRAPESO: con los nueves EN VALOR sí paga los tres', () {
      // Si no, el test de arriba no probaría que el cero es lo que los apaga.
      final e = BetEngine.computeAll(_ronda(const NassauConfig(
          frontValue: 50,
          backValue: 50,
          totalValue: 100,
          mode: GrossNetMode.gross)));
      final razones = e.map((x) => x.reason).toList();
      expect(razones.any((r) => r.contains('Front 9')), isTrue);
      expect(razones.any((r) => r.contains('Total 18')), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 3 · lo que no aplica se DICE', () {
    test('CLAVE: el estado se deduce de los importes, no de una bandera', () {
      // Dos formas de decir lo mismo acaban discrepando, y la que manda al
      // liquidar es siempre el importe.
      expect(_match.soloElMatch, isTrue);
      expect(const NassauConfig().soloElMatch, isFalse);
    });

    test('CLAVE: el carry natural no aplica — no hay F9 del que trasladar', () {
      final v = BetEngine.valoresDelNassau(
          _match.copyWith(carryEnabled: true),
          f9Completo: true,
          marcadorF9: 0);
      expect(v.carryNatural, isFalse);
      expect(v.back, 0);
      expect(v.total, 100, reason: 'el match no se toca');
    });

    test('CLAVE: y tampoco se puede PEDIR carry', () {
      final r = _ronda(_match.copyWith(carryEnabled: true));
      expect(
          BetEngine.quienPuedePedirCarry(
              r, p1, p2, r.betGroups.first.modules.first),
          isNull);
    });

    test('CLAVE: la apertura de 2ª vuelta tampoco: valdría cero', () {
      final r = _ronda(_match.copyWith(aperturaB9ByPair: const {'p1|p2': true}));
      expect(BetEngine.computeAll(r).any((e) => e.reason.contains('Apertura')),
          isFalse);
    });

    test('CLAVE: y la pantalla lo explica en vez de esconderlo', () {
      // Un bloque que desaparece sin motivo se lee como un fallo.
      final codigo = _leer('lib/screens/scorecard/scorecard_screen.dart');
      expect(codigo, contains('match sobre los 18 hoyos, sin '));
      expect(codigo, contains('La presión de la 2ª vuelta no aplica'));
      final editor = _leer('lib/widgets/bet_module_edit_sheet.dart');
      expect(editor, contains('Solo el match (18)'),
          reason: 'el atajo: nadie que quiera un match piensa en poner ceros');
      expect(editor, contains('no aplican con un solo '));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 4 · la guarda de las presiones', () {
    test('CLAVE: sin presiones configuradas no se detecta ninguna', () {
      // Este método las detectaba mirara o no la configuración, y confiaba en
      // que cada llamador preguntase antes. Una guarda que hay que repetir en
      // cada llamador no es una guarda: es una costumbre.
      final r = _ronda(_match.copyWith(pressEnabled: false));
      final st = BetEngine.nassauPressLiveStatus(
          r, p1, p2, r.betGroups.first.modules.first);
      expect(st.frontPresses, isEmpty);
      expect(st.backPresses, isEmpty);
    });

    test('CONTRAPESO: con presiones configuradas SÍ se detectan', () {
      final r = _ronda(_match);
      final st = BetEngine.nassauPressLiveStatus(
          r, p1, p2, r.betGroups.first.modules.first);
      expect(st.frontPresses, isNotEmpty);
    });
  });
}
