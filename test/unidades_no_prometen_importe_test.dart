// ─────────────────────────────────────────────────────────────────────────────
// LA PANTALLA DE ANOTAR NO PROMETE UN IMPORTE
//
// La apuesta decía «Birdie único \$100» y la hoja de anotar decía:
//
//     ✓ Birdie único                    $25
//       Valor: $25    se configura en la apuesta
//
// ── Y el 25 no venía de ningún sitio ────────────────────────────────────────
//
// No era un valor obsoleto ni una búsqueda mal hecha: era un MAPA FIJO en el
// código —todos los tipos de unidad a 25.0— que nunca leyó la apuesta. La
// frase «se configura en la apuesta» señalaba precisamente al sitio donde
// decía otra cosa.
//
// ── El arreglo no es leer bien el número: es que NO HAY un número ───────────
//
//     «Si el importe puede diferir por duelo, una sola cifra en la pantalla de
//      anotar no puede ser cierta.»
//
// Una unidad se acredita contra TODOS los rivales a la vez, y cada duelo puede
// llevar su excepción (`pairConfigOverrides`). Birdie único puede valer \$100
// contra uno y \$25 contra otro.
//
// Así que la hoja registra QUÉ ocurrió. Y lo que enseña es cierto para todos
// los duelos: un número cuando todos coinciden, un rango cuando no.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

const _tres = ['cam', 'cav', 'rafa'];

/// Unidades de la partida. Birdie único a $100 y el resto a $25, como la
/// apuesta real; [porDuelo] son las excepciones por pareja.
Round _r({Map<String, Map<String, dynamic>>? porDuelo}) => Round(
      id: 'r',
      name: 'R',
      course: _curso,
      isFinished: false,
      players: [for (final p in _tres) Player(id: p, name: p.toUpperCase())],
      roundPlayers: [
        for (final p in _tres) RoundPlayer(playerId: p, handicapEnRonda: 0)
      ],
      betGroups: [
        BetGroup(
            id: 'g',
            name: 'G',
            format: PartidaFormat.allInOnePot,
            playerIds: _tres,
            modules: [
              BetModuleInstance(
                id: 'u',
                type: BetModuleType.units,
                name: 'Unidades',
                participantIds: _tres,
                unitsConfig: UnitsConfig(eventValues: {
                  for (final e in UnitEventType.values) e: 25.0,
                  UnitEventType.birdieUnico: 100.0,
                }),
                pairConfigOverrides: porDuelo,
              ),
            ])
      ],
      scores: {
        for (final p in _tres)
          p: {
            for (int h = 1; h <= 18; h++)
              h: HoleScore(playerId: p, hole: h, grossScore: 4, putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 12),
      totalHoles: 18,
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 3 · lo que se muestra es cierto para TODOS los duelos', () {
    test('CLAVE: sin excepciones, un solo importe — y es el de la apuesta', () {
      // El fallo de origen: la apuesta decía 100 y la pantalla 25.
      expect(
          BetEngine.importesDeUnidad(_r(), 'cam', UnitEventType.birdieUnico),
          [100.0]);
      expect(BetEngine.importesDeUnidad(_r(), 'cam', UnitEventType.birdie),
          [25.0]);
    });

    test('CLAVE: con DOS duelos de importes distintos, salen los dos', () {
      // CAM vs CAV con excepción de \$25; CAM vs RAFA sin excepción, o sea los
      // \$100 de la apuesta. Una cifra sola mentiría para uno de los dos.
      final r = _r(porDuelo: {'cam__cav': const {'allEvents': 25.0}});
      expect(BetEngine.importesDeUnidad(r, 'cam', UnitEventType.birdieUnico),
          [25.0, 100.0]);
    });

    test('CLAVE: y coincide con lo que el LEDGER cobra, duelo por duelo', () {
      // La prueba de que el rango no es una cuenta paralela: son los mismos
      // importes que se pagan al liquidar.
      final base = _r(porDuelo: {'cam__cav': const {'allEvents': 25.0}});
      final r = base.copyWith(events: {
        'cam': {
          18: [
            HoleEvent(
                playerId: 'cam', hole: 18, type: UnitEventType.birdieUnico)
          ]
        }
      });
      LedgerEngine.invalidateCache();
      final cobrados = LedgerEngine.entriesOf(r)
          .where((e) => e.toPlayerId == 'cam')
          .map((e) => e.amount)
          .toSet()
          .toList()
        ..sort();
      expect(cobrados,
          BetEngine.importesDeUnidad(r, 'cam', UnitEventType.birdieUnico));
    });

    test('CLAVE: la excepción del duelo pisa TODOS los tipos de ese duelo', () {
      // Es la regla de unidades: el override fija un valor único para todos los
      // eventos de ese par. Si el rango no lo respetara, diría un importe que
      // nadie paga.
      final r = _r(porDuelo: {'cam__cav': const {'allEvents': 25.0}});
      expect(BetEngine.importesDeUnidad(r, 'cam', UnitEventType.birdie),
          [25.0], reason: 'los dos duelos pagan 25 aquí');
    });

    test('CONTRAPESO: quien no juega unidades no tiene importes', () {
      final r = _r();
      expect(BetEngine.importesDeUnidad(r, 'nadie', UnitEventType.birdie),
          isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 2 · no queda ninguna promesa de importe', () {
    final codigo =
        File('lib/screens/capture/capture_screen.dart').readAsStringSync();
    final enPantalla = codigo
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('CLAVE: el mapa fijo de \$25 se fue', () {
      // Era la fuente del número. Mientras exista, algo puede volver a leerlo.
      expect(enPantalla.contains('for (final e in UnitEventType.values) e: 25.0'),
          isFalse);
      expect(enPantalla.contains('quickValues'), isFalse);
    });

    test('CLAVE: y la frase que señalaba a la apuesta también', () {
      // «se configura en la apuesta» rematando un 25 que la apuesta no decía.
      expect(enPantalla.contains('se configura en la apuesta'), isFalse);
    });

    test('CLAVE: el importe sale del motor, no de la pantalla', () {
      expect(enPantalla, contains('BetEngine.importesDeUnidad('));
    });

    test('CLAVE: y con varios importes se dice que cada duelo tiene el suyo',
        () {
      expect(enPantalla, contains('importes.length > 1'));
      expect(codigo, contains('Cada duelo tiene su importe'));
    });
  });
}
