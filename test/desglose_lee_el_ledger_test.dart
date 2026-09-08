// ─────────────────────────────────────────────────────────────────────────────
// EL CARRY PEDIDO Y LA APERTURA NO LLEGABAN AL DESGLOSE
//
// Ronda real, 7 Sep, CAM vs CAV. Carlos pulsó los dos botones y el desglose
// enseñó una sola línea:
//
//     Nassau   +$250      ← F9 $0 + B9 $100 + Total $100 + Presión H15 $50
//     Medal    +$100
//     NETO     +$350
//
// Faltaban $100: el carry pedido y la apertura.
//
// ── Determinado: se guardaban Y se liquidaban ───────────────────────────────
//
// Las dos preguntas eran «¿no se guardan?» o «¿se guardan y no se leen?». Se
// midió, y es la segunda: la ida y vuelta a JSON conserva las dos peticiones, el
// motor emite sus cinco asientos y `breakdownBetween` da $350 —con la ronda
// cerrada y sin cerrar—.
//
// Lo que fallaba era la capa siguiente. La tarjeta del desglose SOBREESCRIBÍA el
// balance del Nassau con una cuenta propia mientras la ronda estaba en curso, y
// esa cuenta sumaba a mano el F9, el B9, el total y las presiones cerradas. No
// sabía nada del carry pedido ni de la apertura.
//
// Su motivo escrito era falso: «computeAll solo liquida segmentos CERRADOS, así
// que a mitad del F9 el desglose saldría en $0». Medido: da $200.
//
// Era la SEXTA cuenta paralela del Nassau. Las otras cinco se unificaron en
// `valoresDelNassau`; esta calculaba el BALANCE en vez de los valores, así que
// se escapó del barrido por estructura.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/providers/round_provider.dart'
    show roundToJson, roundFromJson;

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// Lo pedido en la ronda del 7 de septiembre: el carry y la apertura.
const _lasDos = NassauConfig(
  frontValue: 50,
  backValue: 50,
  totalValue: 100,
  carryEnabled: true,
  pressEnabled: true,
  autoPressTrigger: 2,
  carryPedidoByPair: {'cam|cav': 'cav'},
  aperturaB9ByPair: {'cam|cav': true},
);

/// CAM vs CAV. CAM gana [ganaCam]; el resto empatado. [hasta] hoyos capturados.
Round _r({
  List<int> ganaCam = const [],
  NassauConfig cfg = _lasDos,
  bool cerrada = true,
  int hasta = 18,
  String? grupoGuardado,
}) =>
    Round(
      id: 'r',
      name: '7 Sep',
      course: _curso,
      isFinished: cerrada,
      players: [Player(id: 'cam', name: 'CAM'), Player(id: 'cav', name: 'CAV')],
      roundPlayers: [
        RoundPlayer(playerId: 'cam', handicapEnRonda: 0),
        RoundPlayer(playerId: 'cav', handicapEnRonda: 0),
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.oneVsOne,
            playerIds: const ['cam', 'cav'],
            savedGroupId: grupoGuardado,
            modules: [
              BetModuleInstance(
                  id: 'n',
                  type: BetModuleType.nassau,
                  name: 'Nassau',
                  participantIds: const ['cam', 'cav'],
                  nassauConfig: cfg),
            ])
      ],
      scores: {
        for (final p in ['cam', 'cav'])
          p: {
            for (int h = 1; h <= hasta; h++)
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore: ganaCam.contains(h) && p == 'cav' ? 5 : 4,
                  putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 7),
      totalHoles: 18,
    );

Map<BetModuleType, double> _desglose(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.breakdownBetween(r, 'cam', 'cav');
}

List<String> _motivos(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r).map((e) => e.reason).toList();
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIOS 1 y 2 · las dos apuestas llegan y se distinguen', () {
    // La ronda real: F9 empatado —el carry natural traslada— y CAM gana cuatro
    // del B9.
    Round real({bool cerrada = true}) =>
        _r(ganaCam: const [10, 11, 12, 13], cerrada: cerrada);

    test('CLAVE: el carry pedido es su propio asiento', () {
      expect(_motivos(real()), contains('Carry · un golpe más'));
    });

    test('CLAVE: y la apertura el suyo', () {
      expect(_motivos(real()), contains('Apertura 2ª vuelta'));
    });

    test('CLAVE: los motivos DICEN en qué se diferencian', () {
      // «Carry» a secas no distingue nada: las dos son el carry. Y dos apuestas
      // con el mismo importe sobre los mismos hoyos ya dieron una vez tres filas
      // idénticas y $3550 que nadie entendía.
      final m = _motivos(real());
      expect(m.toSet().length, m.length, reason: 'ningún motivo repetido');
      expect(m.firstWhere((x) => x.startsWith('Carry')), contains('golpe'));
    });

    test('CLAVE: el total es \$350, no \$250 — los \$100 que faltaban', () {
      expect(_desglose(real())[BetModuleType.nassau], 350);
    });

    test('CLAVE: y lo mismo EN VIVO, con la ronda sin cerrar', () {
      // Aquí estaba el fallo: solo se veía sin cerrar, porque la
      // sobreescritura solo actuaba entonces.
      expect(_desglose(real(cerrada: false))[BetModuleType.nassau], 350);
    });

    test('CLAVE: y también en un Nassau SIN presiones', () {
      // Un grupo que no juega presiones puede pedir carry igual, y esa
      // liquidación va por OTRA rama del motor —`_nassauPair` en vez de
      // `_nassauPressPair`—. Sin este caso, romper una de las dos ramas no lo
      // cazaba ninguna prueba.
      final r = _r(
          ganaCam: const [10, 11, 12, 13],
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              carryPedidoByPair: {'cam|cav': 'cav'},
              aperturaB9ByPair: {'cam|cav': true}));
      final m = _motivos(r);
      expect(m, contains('Carry · un golpe más'));
      expect(m, contains('Apertura 2ª vuelta'));
      expect(m.any((x) => x.contains('Press')), isFalse,
          reason: 'este grupo no juega presiones');
      // B9 $100 (con el traslado) + Total $100 + carry $50 + apertura $50.
      expect(_desglose(r)[BetModuleType.nassau], 300);
    });

    test('CONTRAPESO: sin pedir ninguna de las dos, son \$250', () {
      // Es la cifra que Carlos vio. Si esto no diera 250, el test de arriba no
      // probaría que las dos apuestas son las que faltaban.
      final r = _r(
          ganaCam: const [10, 11, 12, 13],
          cfg: const NassauConfig(
              frontValue: 50,
              backValue: 50,
              totalValue: 100,
              carryEnabled: true,
              pressEnabled: true,
              autoPressTrigger: 2));
      expect(_desglose(r)[BetModuleType.nassau], 250);
    });

    test('CLAVE: y el desglose las enseña UNA POR UNA, no solo la suma', () {
      // La fila es por TIPO: «Nassau +$350». Con cinco apuestas dentro, un solo
      // número obliga a sumar a mano — que es exactamente lo que hubo que hacer
      // para encontrar este fallo.
      final codigo = File('lib/screens/scorecard/scorecard_screen.dart')
          .readAsStringSync();
      expect(codigo, contains('_apuestasDe(betType)'));
      // Y salen del LEDGER, no de un recuento propio: es lo que se acaba de
      // pagar por tener una cuenta paralela.
      final i = codigo.indexOf('_apuestasDe(BetModuleType tipo)');
      expect(i, greaterThan(-1));
      final cuerpo = codigo.substring(i, codigo.indexOf('\n  }', i));
      expect(cuerpo, contains('LedgerEngine.entriesOf(round)'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('la cuenta paralela, retirada', () {
    test('CLAVE: su premisa era falsa — a mitad del F9 el ledger NO da 0', () {
      // «computeAll solo liquida segmentos CERRADOS, así que a mitad del F9 el
      // desglose saldría en $0 aunque alguien vaya 3UP.»
      final r = _r(ganaCam: const [1, 2, 3], hasta: 4, cerrada: false);
      expect(_desglose(r)[BetModuleType.nassau], 200,
          reason: 'F9 en curso \$50 + su presión \$50 + Total \$100');
    });

    test('CONTRAPESO: no queda ninguna cuenta propia del Nassau en la tarjeta',
        () {
      // Si volviera, volvería este fallo: el desglose diría un número y el
      // ledger otro, y el que se cobra es el del ledger.
      final codigo = File('lib/screens/scorecard/scorecard_screen.dart')
          .readAsStringSync();
      final enPantalla = codigo
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(enPantalla.contains('npBal'), isFalse);
      expect(enPantalla.contains('breakdown[BetModuleType.nassau] ='), isFalse);
    });

    test('CLAVE: en vivo y al cerrar dicen LO MISMO, por construcción', () {
      final r = _r(ganaCam: const [10, 11, 12, 13]);
      final vivo = _r(ganaCam: const [10, 11, 12, 13], cerrada: false);
      expect(_desglose(vivo), _desglose(r));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 3 · un panel ya usado no se ofrece igual', () {
    test('CLAVE: la petición sobrevive la ida y vuelta a JSON', () {
      // Si no, el panel volvería a su estado de oferta al recargar y nadie
      // sabría si lo pulsó.
      final back = roundFromJson(roundToJson(_r()));
      final n = back.betGroups.first.modules.first.nassau;
      expect(n.carryPedidoPor('cam', 'cav'), 'cav');
      expect(n.aperturaB9For('cam', 'cav'), isTrue);
    });

    test('CLAVE: los dos paneles tienen estado de YA PEDIDO', () {
      final codigo = File('lib/screens/scorecard/scorecard_screen.dart')
          .readAsStringSync();
      expect(codigo, contains("Text('CARRY PEDIDO'"));
      expect(codigo, contains('if (_yaAbierta)'));
    });

    test('CLAVE: y pedir una apuesta NO pierde el grupo guardado', () {
      // `_pedirCarry` y `_abrirApertura` reconstruían el BetGroup campo a campo
      // con cinco de sus seis campos: `savedGroupId` se iba a null en silencio,
      // y con él la forma de que un torneo diga «todas las rondas de Viernes
      // CGM». Quinta vez que este proyecto pierde un campo así.
      final g = _r(grupoGuardado: 'viernes-cgm').betGroups.first;
      expect(g.savedGroupId, 'viernes-cgm');
      // La operación que hacen los dos botones: cambiar los módulos.
      expect(g.copyWith(modules: g.modules).savedGroupId, 'viernes-cgm');

      final codigo = File('lib/screens/scorecard/scorecard_screen.dart')
          .readAsStringSync();
      final i = codigo.indexOf('void _abrirApertura(');
      final j = codigo.indexOf('void _pedirCarry(');
      for (final desde in [i, j]) {
        expect(desde, greaterThan(-1));
        final cuerpo = codigo.substring(desde, codigo.indexOf('\n  }', desde));
        expect(cuerpo, contains('g.copyWith(modules:'),
            reason: 'reconstruir a mano vuelve a perder savedGroupId');
        expect(cuerpo.contains('BetGroup('), isFalse);
      }
    });
  });
}
