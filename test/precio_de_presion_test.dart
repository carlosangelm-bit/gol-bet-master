// ─────────────────────────────────────────────────────────────────────────────
// «PRESIONAR»: SUBIR EL PRECIO DE LAS PRESIONES DEL B9
//
//     «Solo al terminar el F9, un jugador puede modificar el valor de la
//      presión para el B9, en este caso a 100. Eso no modifica el valor de las
//      presiones generadas en los F9.»
//     «Las presiones del F9 quedan en 50. Las del B9 que se abran, ahora
//      valdrán 100.»
//
// No abre una apuesta: cambia el PRECIO de las presiones que ese nueve genere.
// Lo que se construyó antes como «apertura de 2ª vuelta» es otra cosa —una
// apuesta paralela sobre los nueve traseros— y sigue en pie.
//
// De aquí sale que un Nassau tenga CUATRO cifras y no tres.
//
// ── Las dos que quedaban por determinar ─────────────────────────────────────
//
//   · ¿Cualquiera de los dos, o hace falta acuerdo? → HACE FALTA ACUERDO. Las
//     presiones saltan solas, al ir dos abajo, y ninguno de los dos elige
//     cuándo. Quien va perdiendo al terminar el F9 podría poner 500 y arrastrar
//     al otro a una apuesta que no pidió. El carry y la apertura los paga quien
//     los pide; esto lo paga el otro también.
//
//   · ¿Presionar dos veces lleva a \$200? → NO. Lo que se fija es un precio, no
//     un multiplicador: puesto dos veces, vale el segundo. Y la ventana se abre
//     una sola vez, al terminar el F9.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';
import 'package:golf_bet_master/models/models.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

const _cfg = NassauConfig(
  frontValue: 50,
  backValue: 50,
  totalValue: 100,
  pressEnabled: true,
  autoPressTrigger: 2,
  frontPressValue: 50,
  backPressValue: 50,
);

/// CAM vs CAV. [ganaCav] los hoyos que CAV gana; [hasta] los hoyos anotados.
Round _r({
  List<int> ganaCav = const [],
  int hasta = 18,
  Map<String, PrecioDePresion> pacto = const {},
}) =>
    Round(
      id: 'r',
      name: 'El turn',
      course: _curso,
      isFinished: hasta == 18,
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
            modules: [
              BetModuleInstance(
                  id: 'n',
                  type: BetModuleType.nassau,
                  name: 'Nassau',
                  participantIds: const ['cam', 'cav'],
                  nassauConfig: _cfg.copyWith(precioPresionB9ByPair: pacto)),
            ])
      ],
      scores: {
        for (final p in ['cam', 'cav'])
          p: {
            for (int h = 1; h <= hasta; h++)
              h: HoleScore(
                  playerId: p,
                  hole: h,
                  grossScore: ganaCav.contains(h) && p == 'cam' ? 5 : 4,
                  putts: 2)
          }
      },
      events: const {},
      oyeseRankings: const {},
      sliding: const [],
      createdAt: DateTime(2026, 9, 13),
      totalHoles: 18,
    );

BetModuleInstance _mod(Round r) => r.betGroups.first.modules.first;

Map<String, PrecioDePresion> _pactado(double v) => {
      NassauConfig.carryPairKey('cam', 'cav'):
          PrecioDePresion(valor: v, propuestoPor: 'cam', aceptadoPor: 'cav'),
    };

Map<String, PrecioDePresion> _propuesto(double v) => {
      NassauConfig.carryPairKey('cam', 'cav'):
          PrecioDePresion(valor: v, propuestoPor: 'cam'),
    };

List<LedgerEntry> _asientos(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r);
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · el precio sube solo para el B9', () {
    // CAV gana 1 y 2 → CAM va 2 abajo → presión en el F9, desde el hoyo 3.
    // CAV gana también el 5, así que esa presión TIENE ganador: una presión
    // empatada no emite asiento, y sin ganador no hay dinero que comparar.
    // Lo mismo en el B9: 10 y 11 la disparan, el 14 la resuelve.
    const guion = [1, 2, 5, 10, 11, 14];

    test('CLAVE: pactado a 100, la presión del B9 vale 100', () {
      final sin = BetEngine.nassauPressLiveStatus(
          _r(ganaCav: guion), 'cam', 'cav', _mod(_r(ganaCav: guion)));
      expect(sin.backPressVal, 50);

      final r = _r(ganaCav: guion, pacto: _pactado(100));
      final con = BetEngine.nassauPressLiveStatus(r, 'cam', 'cav', _mod(r));
      expect(con.backPressVal, 100);
    });

    test('CLAVE: y las del F9 se quedan en 50', () {
      final r = _r(ganaCav: guion, pacto: _pactado(100));
      final st = BetEngine.nassauPressLiveStatus(r, 'cam', 'cav', _mod(r));
      expect(st.frontPressVal, 50,
          reason: 'es literalmente la condición: no modifica las del F9');
      expect(st.frontPresses, isNotEmpty, reason: 'hubo presión en el F9');
      expect(st.backPresses, isNotEmpty, reason: 'y otra en el B9');
    });

    test('CLAVE: el dinero liquidado lo refleja, \$50 más', () {
      double aCav(Round r) => _asientos(r)
          .where((e) => e.reason.contains('Press'))
          .fold(0.0, (s, e) => s + (e.toPlayerId == 'cav' ? e.amount : -e.amount));

      final base = aCav(_r(ganaCav: guion));
      final subido = aCav(_r(ganaCav: guion, pacto: _pactado(100)));
      expect(subido - base, 50,
          reason: 'una presión del B9 que valía 50 ahora vale 100');
    });

    test('CONTRAPESO: propuesto y sin aceptar no vale nada', () {
      final r = _r(ganaCav: guion, pacto: _propuesto(100));
      final st = BetEngine.nassauPressLiveStatus(r, 'cam', 'cav', _mod(r));
      expect(st.backPressVal, 50,
          reason: 'sube el precio de una apuesta que el otro no elige abrir');
    });

    test('CONTRAPESO: y presionar dos veces no lleva a \$200', () {
      // Es un precio, no un multiplicador: puesto dos veces, vale el segundo.
      final r = _r(ganaCav: guion, pacto: _pactado(100));
      final otraVez = _r(ganaCav: guion, pacto: _pactado(100));
      final st = BetEngine.nassauPressLiveStatus(otraVez, 'cam', 'cav', _mod(r));
      expect(st.backPressVal, 100);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('2 · la ventana es el turn, y es una sola', () {
    PorQueNoSePuedePactar v(Round r) =>
        BetEngine.ventanaDelPrecioDePresion(r, 'cam', 'cav', _mod(r));

    test('CLAVE: con el F9 completo y el B9 sin empezar, sí', () {
      expect(v(_r(ganaCav: const [1, 2], hasta: 9)).si, isTrue);
    });

    test('CLAVE: a mitad del F9, no — y lo dice', () {
      final no = v(_r(ganaCav: const [1, 2], hasta: 5));
      expect(no.si, isFalse);
      expect(no.motivo, 'Al terminar el F9.');
    });

    test('CLAVE: con el B9 empezado, tampoco', () {
      final no = v(_r(ganaCav: const [1, 2], hasta: 11));
      expect(no.si, isFalse);
      expect(no.motivo, contains('ya empezó'));
    });

    test('CONTRAPESO: sin presiones no hay precio que pactar', () {
      final r = _r(ganaCav: const [1, 2], hasta: 9);
      final sinPress = r.copyWith(betGroups: [
        r.betGroups.first.copyWith(modules: [
          _mod(r).copyWith(nassauConfig: _cfg.copyWith(pressEnabled: false)),
        ])
      ]);
      expect(
          BetEngine.ventanaDelPrecioDePresion(
                  sinPress, 'cam', 'cav', _mod(sinPress))
              .motivo,
          contains('no juega presiones'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('3 · el pacto sobrevive al guardado', () {
    test('CLAVE: ida y vuelta por JSON con quién propuso y quién aceptó', () {
      final j = _cfg.copyWith(precioPresionB9ByPair: _pactado(100)).toJson();
      final vuelta = NassauConfig.fromJson(Map<String, dynamic>.from(j));
      final p = vuelta.precioPresionB9Para('cam', 'cav')!;
      expect(p.valor, 100);
      expect(p.propuestoPor, 'cam');
      expect(p.aceptadoPor, 'cav');
      expect(p.enPie, isTrue);
    });

    test('CONTRAPESO: y una propuesta sin aceptar vuelve sin aceptar', () {
      final j = _cfg.copyWith(precioPresionB9ByPair: _propuesto(100)).toJson();
      final vuelta = NassauConfig.fromJson(Map<String, dynamic>.from(j));
      expect(vuelta.precioPresionB9Para('cam', 'cav')!.enPie, isFalse);
    });
  });
}
