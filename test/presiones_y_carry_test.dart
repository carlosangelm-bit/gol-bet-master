// ─────────────────────────────────────────────────────────────────────────────
// PRESIONES Y CARRY — las reglas del match play, fijadas
//
// Tres cambios que salen de la mecánica real del match play con presiones y de
// cómo lo juega el grupo de Carlos:
//
//   1 · El carry SOLO existe si el segmento anterior quedó empatado. Lo que se
//       traslada es dinero sin dueño; si el F9 lo ganó alguien, ya lo tiene.
//       Y TRASLADA: no multiplica. Ver el grupo 1.
//   2 · La PRESIÓN DE APERTURA: al entrar en la 2ª vuelta, cualquiera de los dos
//       abre una apuesta sobre los nueve traseros desde cero, por el mismo
//       importe. Y la pide CUALQUIERA, no solo el que pierde.
//   3 · Tres restricciones de la presión automática: ni en el 9 ni en el 18,
//       máximo una por nueve, y nunca sobre un segmento ya decidido.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/engines/bet_engine.dart';
import 'package:golf_bet_master/engines/ledger_engine.dart';

final _curso = CourseInfo(name: 'P72', holes: [
  for (int i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// [ganaA] son los hoyos que gana A; el resto se empatan.
Round _r({
  required List<int> ganaA,
  List<int> ganaB = const [],
  NassauConfig? cfg,
  int hoyosJugados = 18,
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
  final jugados = orden.take(hoyosJugados).toSet();

  return Round(
    id: 'r',
    name: 'R',
    course: _curso,
    isFinished: hoyosJugados == 18,
    players: [Player(id: 'A', name: 'A'), Player(id: 'B', name: 'B')],
    roundPlayers: [
      RoundPlayer(playerId: 'A', handicapEnRonda: 0),
      RoundPlayer(playerId: 'B', handicapEnRonda: 0),
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
                        frontValue: 50, backValue: 50, totalValue: 100)),
          ])
    ],
    scores: {
      for (final p in ['A', 'B'])
        p: {
          for (final h in jugados)
            h: HoleScore(
                playerId: p, hole: h, grossScore: golpe(p, h), putts: 2)
        }
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 8, 29),
    totalHoles: 18,
    startingNine: inicio,
  );
}

List<LedgerEntry> _asientos(Round r) {
  LedgerEngine.invalidateCache();
  return LedgerEngine.entriesOf(r);
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1 · EL CARRY NATURAL **TRASLADA**, NO MULTIPLICA
  //
  // Carlos revisó una ronda real de cinco —CAM, RICH, KAWA, AAM, Dylan— y en el
  // duelo CAM vs Dylan con carry vio F9 $50, B9 $100 y **Total $200**. Los $200
  // eran dinero cobrado de más, y estaban en producción.
  //
  //     «El carry natural solo traslada el valor de la apuesta del F9 al B9. Es
  //      decir, los 50 se pasan al B9 y vale 100, pero no toca el 100 del
  //      match.»
  //
  // El total de 18 es una apuesta APARTE y nadie la tocó.
  // ═══════════════════════════════════════════════════════════════════════════
  group('1 · el carry natural traslada', () {
    NassauConfig conCarry({double front = 50, double back = 50, double total = 100}) =>
        NassauConfig(
            frontValue: front,
            backValue: back,
            totalValue: total,
            carryEnabled: true);

    test('CLAVE: el F9 empatado pasa su valor al B9', () {
      // A y B empatan los nueve primeros; A gana el B9.
      final r = _r(ganaA: const [10, 11, 12], cfg: conCarry());
      final b9 = _asientos(r).firstWhere((e) => e.reason.contains('Back 9'));
      expect(b9.amount, 100, reason: '50 propios + 50 del F9');
    });

    test('CLAVE: y el TOTAL DE 18 NO SE MUEVE', () {
      // Este es el fallo: salía $200. Es una apuesta aparte.
      final r = _r(ganaA: const [10, 11, 12], cfg: conCarry());
      final t18 = _asientos(r).firstWhere((e) => e.reason.contains('Total 18'));
      expect(t18.amount, 100, reason: 'el carry no toca el match');
    });

    test('CLAVE: con F9 y B9 DISTINTOS se ve que suma y no multiplica', () {
      // Con 50 y 50 el ×2 acertaba el B9 por casualidad: 50×2 == 50+50. Con 30
      // y 50 se separan — 80 si traslada, 100 si multiplica— y es la única
      // forma de probar cuál de las dos cosas hace.
      final r = _r(
          ganaA: const [10, 11, 12], cfg: conCarry(front: 30, back: 50));
      final b9 = _asientos(r).firstWhere((e) => e.reason.contains('Back 9'));
      expect(b9.amount, 80, reason: '50 + 30, no 50 × 2');
    });

    test('CLAVE: con el F9 GANADO no traslada nada', () {
      // Lo que se mueve es dinero SIN DUEÑO. Si el F9 lo ganó alguien, ya está
      // adjudicado.
      final r = _r(ganaA: const [1, 2, 3, 10, 11, 12], cfg: conCarry());
      final b9 = _asientos(r).firstWhere((e) => e.reason.contains('Back 9'));
      expect(b9.amount, 50, reason: 'el F9 tuvo dueño');
    });

    test('CLAVE: sin carryEnabled no pasa nada aunque el F9 empate', () {
      final r = _r(ganaA: const [10, 11, 12]);
      final b9 = _asientos(r).firstWhere((e) => e.reason.contains('Back 9'));
      expect(b9.amount, 50);
    });

    test('CLAVE: la PRESIÓN automática del B9 tampoco se traslada', () {
      // Lo que se traslada es «el valor de la apuesta del F9». Una presión es su
      // propia apuesta con su propio importe: antes se multiplicaba también, y
      // eso era dinero de más encima del dinero de más.
      final cfg = NassauConfig(
          frontValue: 50,
          backValue: 50,
          totalValue: 100,
          carryEnabled: true,
          pressEnabled: true,
          autoPressTrigger: 2,
          frontPressValue: 25,
          backPressValue: 25);
      // F9 empatado; en el B9 A se pone 2 arriba y nace una presión.
      final r = _r(ganaA: const [10, 11], cfg: cfg);
      final st = BetEngine.nassauPressLiveStatus(
          r, 'A', 'B', r.betGroups.first.modules.first);
      expect(st.backVal, 100, reason: 'el segmento sí lleva el traslado');
      expect(st.backPressVal, 25, reason: 'la presión NO');
    });

    test('CONTRAPESO: la pantalla en vivo dice lo MISMO que la liquidación', () {
      // Había cinco sitios calculando esto por su cuenta y no estaban de
      // acuerdo. Si vuelven a separarse, el fallo se descubre cobrando.
      final r = _r(ganaA: const [10, 11, 12], cfg: conCarry(front: 30));
      final st = BetEngine.nassauLiveStatus(
          r, 'A', 'B', r.betGroups.first.modules.first);
      final b9 = _asientos(r).firstWhere((e) => e.reason.contains('Back 9'));
      final t18 = _asientos(r).firstWhere((e) => e.reason.contains('Total 18'));
      expect(st.backVal, b9.amount);
      expect(st.totalVal, t18.amount);
    });

    test('CLAVE: un F9 a medias no dispara el carry', () {
      // Un primer nueve sin terminar va 0-0 casi siempre. Sin esta condición la
      // pantalla anunciaría un carry en el hoyo 2.
      final v = BetEngine.valoresDelNassau(conCarry(),
          f9Completo: false, marcadorF9: 0);
      expect(v.carryNatural, isFalse);
      expect(v.back, 50);
    });
  });

  group('3 y 4 · la presión de apertura', () {
    NassauConfig conApertura() => const NassauConfig(
          frontValue: 50,
          backValue: 50,
          totalValue: 100,
          aperturaB9ByPair: {'A|B': true},
        );

    test('la pide CUALQUIERA: el modelo no pregunta quién va perdiendo', () {
      // Decisión de Carlos, contra la convención más extendida. Si algún día se
      // "corrige", este test lo dice.
      final cfg = conApertura();
      expect(cfg.aperturaB9For('A', 'B'), isTrue);
      expect(cfg.aperturaB9For('B', 'A'), isTrue,
          reason: 'la clave es del PAR, no de quién la pidió');
    });

    test('se liquida por el mismo importe que el segmento original', () {
      final r = _r(ganaA: const [10, 11, 12], cfg: conApertura());
      final ap = _asientos(r)
          .firstWhere((e) => e.reason.contains('Apertura 2ª vuelta'));
      expect(ap.amount, 50);
      expect(ap.toPlayerId, 'A', reason: 'A ganó los nueve traseros');
    });

    test('CRITERIO 4: es un asiento PROPIO, no se confunde con el B9', () {
      // El precedente: dos módulos con el mismo importe sobre los mismos hoyos
      // dieron tres filas idénticas y $3550 que nadie entendía.
      final r = _r(ganaA: const [10, 11, 12], cfg: conApertura());
      final razones =
          _asientos(r).where((e) => e.betType == BetModuleType.nassau).map((e) => e.reason).toList();
      expect(razones.where((x) => x.contains('Apertura')).length, 1);
      expect(razones.where((x) => x.contains('Back 9')).length, 1);
      expect(razones.toSet().length, razones.length,
          reason: 'ninguna razón repetida: cada apuesta se distingue');
    });

    test('sin abrirla no existe', () {
      final r = _r(ganaA: const [10, 11, 12]);
      expect(_asientos(r).any((e) => e.reason.contains('Apertura')), isFalse);
    });

    test('y en una ronda de nueve hoyos no aplica', () {
      // No hay segunda vuelta que abrir.
      final r = _r(ganaA: const [1, 2], cfg: conApertura(), hoyosJugados: 9);
      expect(_asientos(r).any((e) => e.reason.contains('Apertura')), isFalse);
    });
  });

  group('5, 6 y 7 · las restricciones de la presión automática', () {
    NassauConfig conPresiones({bool varias = true}) => NassauConfig(
          frontValue: 50,
          backValue: 50,
          totalValue: 100,
          pressEnabled: true,
          autoPressTrigger: 2,
          frontPressValue: 25,
          backPressValue: 25,
          allowMultiplePresses: varias,
        );

    test('5 · no se abre presión en el último hoyo del segmento', () {
      // A gana 7 y 8: al terminar el 8 va +2 y la presión nacería en el 9.
      final r = _r(ganaA: const [7, 8], cfg: conPresiones());
      final st = BetEngine.nassauPressLiveStatus(r, 'A', 'B', r.betGroups.first.modules.first);
      expect(st.frontPresses.any((p) => p.startHole == 9), isFalse,
          reason: 'dejaría toda la apuesta a un solo golpe');
    });

    test('y tampoco en el 18', () {
      final r = _r(ganaA: const [16, 17], cfg: conPresiones());
      final st = BetEngine.nassauPressLiveStatus(r, 'A', 'B', r.betGroups.first.modules.first);
      expect(st.backPresses.any((p) => p.startHole == 18), isFalse);
    });

    test('6 · máximo una por nueve cuando así se configura', () {
      // A gana 1 y 2 (presión en el 3) y luego 4 y 5 (dispararía otra).
      final r = _r(ganaA: const [1, 2, 4, 5], cfg: conPresiones(varias: false));
      final st = BetEngine.nassauPressLiveStatus(r, 'A', 'B', r.betGroups.first.modules.first);
      expect(st.frontPresses.length, 1);
    });

    test('y el contrapeso: con varias permitidas sí encadena', () {
      final r = _r(ganaA: const [1, 2, 4, 5], cfg: conPresiones());
      final st = BetEngine.nassauPressLiveStatus(r, 'A', 'B', r.betGroups.first.modules.first);
      expect(st.frontPresses.length, greaterThan(1));
    });

    test('el default del modelo es UNA por nueve', () {
      // Es como lo juega el grupo. Sigue siendo configurable.
      expect(const NassauConfig().allowMultiplePresses, isFalse);
    });

    test('7 · no se presiona un segmento ya decidido', () {
      // A gana los seis primeros: al terminar el 6 va +6 y quedan 3 hoyos, así
      // que el F9 está cerrado. Una presión ahí apuesta sobre algo que ya pasó.
      final r = _r(ganaA: const [1, 2, 3, 4, 5, 6], cfg: conPresiones());
      final st = BetEngine.nassauPressLiveStatus(r, 'A', 'B', r.betGroups.first.modules.first);
      for (final p in st.frontPresses) {
        final restantes = 9 - p.startHole + 1;
        expect(restantes, greaterThanOrEqualTo(1));
      }
      // La que nacería en el 7 con el segmento ya decidido no existe.
      expect(st.frontPresses.any((p) => p.startHole >= 7), isFalse);
    });
  });
}
