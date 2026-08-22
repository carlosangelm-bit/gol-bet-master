// ─────────────────────────────────────────────────────────────────────────────
// EL RESUMEN DEL PERFIL
//
// El tablero de Inicio enseña tu balance histórico, tus rondas y contra quién
// juegas. Todo sale de aquí, así que aquí es donde se puede estar mintiendo.
//
// Los tests que importan no son los que confirman que sumar funciona —eso lo
// hace cualquier bucle—, son estos tres:
//
//   · Sin identidad NO se devuelven ceros. "+$0 · 0 rondas" y "no sé quién
//     eres" son afirmaciones distintas y la pantalla las tiene que poder
//     distinguir.
//   · Una ronda que jugaron OTROS no cuenta como tablas tuyas.
//   · El signo del cara a cara se invierte si tu id es el mayor del par, que es
//     donde se cuela un error de dirección: enseñar que le ganas a quien te
//     gana es peor que no enseñar nada.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/perfil_resumen.dart';
import 'package:golf_bet_master/models/round_result.dart';

// Ids elegidos para que el orden lexicográfico sea explícito: ana < beto < caro.
const ana = 'ana';
const beto = 'beto';
const caro = 'caro';

/// Un resultado a mano. [pares] usa la clave canónica 'menor|mayor' con el
/// valor visto por el menor.
RoundResult res({
  required String id,
  required DateTime cuando,
  required List<String> quienes,
  required Map<String, double> netos,
  Map<String, double> pares = const {},
  Map<String, int> gross = const {},
  String campo = 'Los Encinos',
}) =>
    RoundResult(
      roundId: id,
      roundName: 'Ronda $id',
      courseName: campo,
      playedAt: cuando,
      holesPlayed: 18,
      playerIds: quienes,
      playerNames: {for (final q in quienes) q: q.toUpperCase()},
      balances: netos,
      pairBalances: pares,
      grossByPlayer: gross,
    );

DateTime dia(int d) => DateTime(2026, 8, d);

void main() {
  _estadoDelTablero();

  group('1 · sin identidad no hay resumen, y no son ceros', () {
    final una = res(
        id: 'r1', cuando: dia(1), quienes: [ana, beto],
        netos: {ana: 100, beto: -100});

    test('miId nulo devuelve sinIdentidad', () {
      final r = resumenDe([una], miId: null);
      expect(r.identificado, isFalse);
      expect(r.hayHistorial, isFalse);
    });

    test('miId vacío también: un string vacío no es un jugador', () {
      expect(resumenDe([una], miId: '').identificado, isFalse);
    });

    test('y quien SÍ está identificado pero sin rondas se distingue', () {
      // El test que da valor a los dos de arriba. Los dos casos enseñan cero
      // rondas, pero uno dice "falta decir quién eres" y el otro "aún no has
      // jugado". Sin este, `identificado` podría estar siempre en false y los
      // dos primeros pasarían igual.
      final r = resumenDe([una], miId: caro);
      expect(r.identificado, isTrue);
      expect(r.rondas, 0);
    });
  });

  group('2 · solo cuentan las rondas que jugaste', () {
    test('una ronda de otros no entra ni como tablas', () {
      final r = resumenDe([
        res(id: 'mia', cuando: dia(1), quienes: [ana, beto],
            netos: {ana: 50, beto: -50}),
        res(id: 'ajena', cuando: dia(2), quienes: [beto, caro],
            netos: {beto: 30, caro: -30}),
      ], miId: ana);

      expect(r.rondas, 1, reason: 'la ajena no es una ronda mía');
      expect(r.tablas, 0, reason: 'no jugarla no es empatarla');
      expect(r.balanceTotal, 50);
    });

    test('el balance suma TODAS las mías, no solo las que se listan', () {
      // cuantasUltimas limita la lista, no los totales. Un tope silencioso en
      // el número grande sería un dato falso que depende de la presentación.
      final muchas = [
        for (var i = 1; i <= 6; i++)
          res(id: 'r$i', cuando: dia(i), quienes: [ana, beto],
              netos: {ana: 10, beto: -10}),
      ];
      final r = resumenDe(muchas, miId: ana, cuantasUltimas: 2);
      expect(r.ultimas.length, 2);
      expect(r.rondas, 6);
      expect(r.balanceTotal, 60);
    });
  });

  group('3 · el cara a cara respeta la dirección', () {
    // 'ana' < 'beto', así que la clave es 'ana|beto' y el valor es lo que ve ana.
    final ganaAna = res(
        id: 'r1', cuando: dia(1), quienes: [ana, beto],
        netos: {ana: 80, beto: -80}, pares: {'ana|beto': 80});

    test('desde el id menor el valor va directo', () {
      final r = resumenDe([ganaAna], miId: ana);
      expect(r.rival!.playerId, beto);
      expect(r.rival!.balance, 80, reason: 'ana le gana 80 a beto');
    });

    test('desde el id MAYOR se invierte', () {
      // Aquí es donde un error de dirección enseñaría que beto le gana a ana.
      final r = resumenDe([ganaAna], miId: beto);
      expect(r.rival!.playerId, ana);
      expect(r.rival!.balance, -80, reason: 'beto pierde 80 contra ana');
    });

    test('un par sin entrada da cero, no una excepción', () {
      final r = resumenDe([
        res(id: 'r1', cuando: dia(1), quienes: [ana, beto],
            netos: {ana: 0, beto: 0}),
      ], miId: ana);
      expect(r.rival!.balance, 0);
    });
  });

  group('4 · el rival es con quien más juegas, no a quien más le ganas', () {
    test('gana en rondas juntos aunque el dinero esté en otro', () {
      final r = resumenDe([
        // Con beto tres veces, calderilla.
        for (var i = 1; i <= 3; i++)
          res(id: 'b$i', cuando: dia(i), quienes: [ana, beto],
              netos: {ana: 5, beto: -5}, pares: {'ana|beto': 5}),
        // Con caro una vez, una fortuna.
        res(id: 'c1', cuando: dia(9), quienes: [ana, caro],
            netos: {ana: 900, caro: -900}, pares: {'ana|caro': 900}),
      ], miId: ana);

      expect(r.rival!.playerId, beto,
          reason: '"contra quién juegas" no es "a quién le ganas más"');
      expect(r.rival!.rondasJuntos, 3);
      expect(r.rival!.balance, 15);
    });

    test('el empate se desempata igual las dos veces', () {
      // Sin desempate estable la tarjeta cambiaría de rival entre dos aperturas
      // sin que nada hubiera pasado.
      final rondas = [
        res(id: 'r1', cuando: dia(1), quienes: [ana, beto], netos: {ana: 1}),
        res(id: 'r2', cuando: dia(2), quienes: [ana, caro], netos: {ana: 1}),
      ];
      final a = resumenDe(rondas, miId: ana).rival!.playerId;
      final b = resumenDe(rondas.reversed.toList(), miId: ana).rival!.playerId;
      expect(a, b, reason: 'el orden de entrada no debe decidir');
    });

    test('jugar solo no inventa un rival', () {
      final r = resumenDe([
        res(id: 'r1', cuando: dia(1), quienes: [ana], netos: {ana: 0}),
      ], miId: ana);
      expect(r.rival, isNull);
    });
  });

  group('5 · ganadas, perdidas y racha', () {
    List<RoundResult> conNetos(List<double> netos) => [
          for (var i = 0; i < netos.length; i++)
            res(id: 'r$i', cuando: dia(i + 1), quienes: [ana, beto],
                netos: {ana: netos[i], beto: -netos[i]}),
        ];

    test('se cuentan las tres categorías', () {
      final r = resumenDe(conNetos([10, -10, 0, 20]), miId: ana);
      expect((r.ganadas, r.perdidas, r.tablas), (2, 1, 1));
    });

    test('la racha cuenta hacia atrás desde la más reciente', () {
      // dia(3) y dia(4) son ganadas; dia(2) perdida. Racha = 2.
      final r = resumenDe(conNetos([10, -10, 30, 40]), miId: ana);
      expect(r.racha, 2);
    });

    test('perder seguido da racha negativa', () {
      final r = resumenDe(conNetos([10, -10, -30]), miId: ana);
      expect(r.racha, -2);
    });

    test('unas tablas recientes cortan la racha en cero', () {
      // Es la decisión: unas tablas no continúan una racha ni empiezan una.
      final r = resumenDe(conNetos([10, 10, 0]), miId: ana);
      expect(r.racha, 0);
    });

    test('el orden de entrada no altera la racha', () {
      // Si el cálculo dependiera del orden de la lista en vez de la fecha, esto
      // fallaría. Firestore no promete orden.
      final rondas = conNetos([-50, 10, 20]);
      final directo = resumenDe(rondas, miId: ana).racha;
      final revuelto = resumenDe(rondas.reversed.toList(), miId: ana).racha;
      expect(directo, 2);
      expect(revuelto, directo);
    });
  });

  group('6 · las últimas rondas se ordenan por fecha', () {
    test('la más reciente va primero, venga como venga', () {
      final r = resumenDe([
        res(id: 'vieja', cuando: dia(1), quienes: [ana], netos: {ana: 1}),
        res(id: 'nueva', cuando: dia(20), quienes: [ana], netos: {ana: 2}),
        res(id: 'media', cuando: dia(10), quienes: [ana], netos: {ana: 3}),
      ], miId: ana);
      expect(r.ultimas.map((u) => u.roundId).toList(),
          ['nueva', 'media', 'vieja']);
    });

    test('el gross ausente llega como null, no como cero', () {
      // Un cero en la columna de score se lee como "hizo 0", que es imposible.
      final r = resumenDe([
        res(id: 'r1', cuando: dia(1), quienes: [ana], netos: {ana: 0}),
      ], miId: ana);
      expect(r.ultimas.first.gross, isNull);
    });

    test('y presente llega tal cual', () {
      final r = resumenDe([
        res(id: 'r1', cuando: dia(1), quienes: [ana], netos: {ana: 0},
            gross: {ana: 82}),
      ], miId: ana);
      expect(r.ultimas.first.gross, 82);
    });
  });
}

// El estado vacío es el que miente. Estos tests son los que impiden que las tres
// situaciones distintas se colapsen en un "+$0 · 0 rondas" indistinguible.
void _estadoDelTablero() {
  group('7 · el estado vacío distingue tres cosas', () {
    test('sin identidad manda, aunque haya resultados', () {
      // Si hubiera resultados de otro, sumarlos y enseñarlos como tuyos sería
      // peor que no enseñar nada.
      expect(
          estadoDelTablero(
              identificado: false, conResultado: 9, rondasCerradas: 9),
          EstadoTablero.sinIdentidad);
    });

    test('rondas cerradas sin resultado es backfill pendiente, no cero', () {
      // El caso de estrenar la función: el histórico existe y no está calculado.
      expect(
          estadoDelTablero(
              identificado: true, conResultado: 0, rondasCerradas: 12),
          EstadoTablero.historialPendiente);
    });

    test('sin rondas cerradas el cero es cierto', () {
      expect(
          estadoDelTablero(
              identificado: true, conResultado: 0, rondasCerradas: 0),
          EstadoTablero.sinRondas);
    });

    test('con resultados se enseña el histórico', () {
      expect(
          estadoDelTablero(
              identificado: true, conResultado: 3, rondasCerradas: 12),
          EstadoTablero.listo,
          reason: 'parcial se enseña; el aviso de que falta va aparte');
    });
  });
}
