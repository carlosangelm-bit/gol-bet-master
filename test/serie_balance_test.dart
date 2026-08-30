// ─────────────────────────────────────────────────────────────────────────────
// EL BALANCE EN EL TIEMPO
//
// La cifra "+$500" no distingue dos historias muy distintas: un saldo que nunca
// bajó de cero, y uno que estuvo en −800 y se recuperó. La línea sí.
//
// Y lo que más importa de esta entrega no es el gráfico: es que NO duplique. El
// pintor y la geometría son los mismos que los del handicap, con una bandera de
// diferencia. Si fueran dos, habría dos sitios donde arreglar el mismo eje
// invertido.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/serie_balance.dart';
import 'package:golf_bet_master/widgets/grafico_balance.dart';
import 'package:golf_bet_master/widgets/grafico_tendencia.dart';

const yo = 'pid_yo', otro = 'pid_otro';

/// Una ronda del día [dia] que me deja [neto].
RoundResult _r(int dia, double neto, {String nombre = 'Sábado'}) => RoundResult(
      roundId: 'r$dia',
      roundName: nombre,
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 3, dia),
      holesPlayed: 18,
      playerIds: const [yo, otro],
      playerNames: const {yo: 'Carlos', otro: 'Rafa'},
      balances: {yo: neto, otro: -neto},
      pairBalances: const {},
      grossByPlayer: const {},
      netByPlayer: const {},
      stablefordByPlayer: const {},
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · el acumulado lleva las dos preguntas', () {
    test('CLAVE: la ALTURA es el saldo y el ESCALÓN es la ronda', () {
      // Parecían dos gráficos —acumulado y por ronda— y uno solo los da.
      final s = serieDeBalance(
          [_r(1, 100), _r(2, -50), _r(3, 200)], yo);
      expect(s.puntos.map((p) => p.acumulado), [100, 50, 250]);
      expect(s.puntos.map((p) => p.delaRonda), [100, -50, 200]);
      expect(s.total, 250);
    });

    test('el orden de entrada da igual', () {
      // Confiar en el orden de quien llama es pedir un fallo silencioso.
      final rondas = [_r(3, 200), _r(1, 100), _r(2, -50)];
      final s = serieDeBalance(rondas, yo);
      expect(s.puntos.map((p) => p.acumulado), [100, 50, 250]);
    });

    test('CLAVE: y el total coincide con la cifra que ya se enseñaba', () {
      // Si se separaran, la tarjeta diría un número y la línea acabaría en
      // otro. Es el contrapeso que ata el gráfico a lo que ya está en pantalla.
      final rondas = [_r(1, 100), _r(2, -50), _r(3, 200), _r(4, -25)];
      final suma = rondas.fold<double>(0, (a, r) => a + r.netoDe(yo));
      expect(serieDeBalance(rondas, yo).total, suma);
    });

    test('y es MI balance, no el de la ronda', () {
      final s = serieDeBalance([_r(1, 100)], otro);
      expect(s.total, -100);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · las rondas que no mueven el saldo', () {
    test('CLAVE: un cero es un tramo PLANO, que es lo que pasó', () {
      // En un gráfico por ronda un cero ocuparía el mismo ancho que un ±500 —
      // el mismo espacio para "no pasó nada" y para "me llevé quinientos".
      final s = serieDeBalance([_r(1, 100), _r(2, 0), _r(3, 0), _r(4, 50)], yo);
      expect(s.puntos.map((p) => p.acumulado), [100, 100, 100, 150]);
      expect(s.planas, 2);
      expect(s.puntos[1].plana, isTrue);
      expect(s.puntos[0].plana, isFalse);
    });

    test('y una cuenta ENTERA sin dinero no revienta', () {
      // Cuatro rondas sin apuestas: la serie existe, es plana, y el pintor
      // tiene que saber dibujarla sin dividir por cero.
      final s = serieDeBalance(
          [_r(1, 0), _r(2, 0), _r(3, 0), _r(4, 0)], yo);
      expect(s.suficiente, isTrue);
      expect(s.total, 0);
      final pts = posicionesDeSerie(
          s.puntos.map((p) => p.acumulado).toList(), const Size(200, 56),
          menosEsMejor: false);
      for (final p in pts) {
        expect(p.dy.isFinite, isTrue);
        expect(p.dy, inInclusiveRange(0, 56));
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · el umbral, por su propia razón', () {
    test('CLAVE: cuatro, y NO once', () {
      // En el handicap son once porque hasta la séptima ronda el índice lleva
      // un ajuste WHS que se retira solo. Aquí no hay andamiaje: cada punto es
      // un hecho desde la primera ronda. Copiar el once habría escondido un
      // gráfico correcto durante ocho rondas por un motivo que no aplica.
      expect(SerieDeBalance.minimoRondas, 4);
    });

    test('con tres no se dibuja, y se dice cuántas faltan', () {
      final s = serieDeBalance([_r(1, 100), _r(2, -50), _r(3, 200)], yo);
      expect(s.suficiente, isFalse);
      expect(s.faltan, 1);
    });

    test('CONTRAPESO: y con cuatro SÍ, o esto no serviría nunca', () {
      final s =
          serieDeBalance([_r(1, 1), _r(2, 2), _r(3, 3), _r(4, 4)], yo);
      expect(s.suficiente, isTrue);
      expect(s.faltan, 0);
    });

    test('sin rondas, faltan las cuatro', () {
      final s = serieDeBalance(const [], yo);
      expect(s.puntos, isEmpty);
      expect(s.faltan, SerieDeBalance.minimoRondas);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · el canal del DINERO, que aquí sí', () {
    test('CLAVE: verde al ganar, rojo al pagar', () {
      // Es la excepción que confirma la regla: estos tonos están reservados al
      // dinero, y esto es dinero. La tendencia del handicap los tiene
      // PROHIBIDOS por lo mismo.
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        expect(
            GraficoBalance.colorDe(
                serieDeBalance([_r(1, 100), _r(2, 100), _r(3, 100), _r(4, 100)],
                    yo),
                t),
            t.profit);
        expect(
            GraficoBalance.colorDe(
                serieDeBalance([_r(1, -100), _r(2, -100), _r(3, -100),
                    _r(4, -100)], yo),
                t),
            t.loss);
      }
    });

    test('y el cero tiene su propio token: es un resultado, no un vacío', () {
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        final s = serieDeBalance(
            [_r(1, 100), _r(2, -100), _r(3, 0), _r(4, 0)], yo);
        expect(s.total, 0);
        expect(GraficoBalance.colorDe(s, t), t.even);
      }
    });

    test('CONTRAPESO: ganar y pagar nunca son el mismo color', () {
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        expect(t.profit, isNot(t.loss));
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5 · EL CRITERIO QUE DECIDE SI ESTO SUMA O DUPLICA
  //
  // Si el balance trajera su propio pintor con su propia geometría, habría dos
  // sitios donde arreglar el mismo eje invertido. Lo que cambia entre los dos
  // gráficos es UNA BANDERA.
  // ───────────────────────────────────────────────────────────────────────────
  group('5 · una sola geometría, dos significados', () {
    const lienzo = Size(200, 56);
    final subiendo = [10.0, 20.0, 30.0];

    test('CLAVE: con dinero, MÁS va arriba', () {
      final pts = posicionesDeSerie(subiendo, lienzo, menosEsMejor: false);
      expect(pts.last.dy, lessThan(pts.first.dy),
          reason: 'menos y es más arriba en el lienzo');
    });

    test('CLAVE: y con handicap, MENOS va arriba', () {
      // La misma serie, la bandera al revés, el trazo del revés.
      final pts = posicionesDeSerie(subiendo, lienzo, menosEsMejor: true);
      expect(pts.last.dy, greaterThan(pts.first.dy));
    });

    test('CLAVE: las dos banderas dan trazos ESPEJO', () {
      // Es la propiedad de verdad: una sola función, dos lecturas.
      final a = posicionesDeSerie(subiendo, lienzo, menosEsMejor: false);
      final b = posicionesDeSerie(subiendo, lienzo, menosEsMejor: true);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].dx, b[i].dx, reason: 'el eje x no cambia');
        expect(a[i].dy + b[i].dy, closeTo(lienzo.height, 0.001),
            reason: 'y el y es el reflejo');
      }
    });

    test('la tendencia del handicap sigue usando la geometría compartida', () {
      // Si alguien le devolviera un pintor propio, este test no lo caza — pero
      // el de la tendencia sí, y aquí queda escrito que comparten.
      final pts = posicionesDeSerie([25.0, 20.0, 15.0], lienzo,
          menosEsMejor: true);
      expect(pts.last.dy, lessThan(pts.first.dy),
          reason: 'bajando el handicap, la línea sube');
    });

    test('todos los puntos caen dentro del lienzo, con las dos banderas', () {
      for (final bandera in [true, false]) {
        for (final p in posicionesDeSerie(
            [-800.0, -200.0, 0.0, 300.0, 500.0], lienzo,
            menosEsMejor: bandera)) {
          expect(p.dx, inInclusiveRange(0, lienzo.width));
          expect(p.dy, inInclusiveRange(0, lienzo.height));
        }
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('6 · lo que la cifra sola no cuenta', () {
    test('CLAVE: un +500 que estuvo en −800 se dice', () {
      // Dos historias con el mismo total. La cifra no las distingue.
      final malaRacha =
          serieDeBalance([_r(1, -800), _r(2, 400), _r(3, 500), _r(4, 400)], yo);
      final siempreArriba =
          serieDeBalance([_r(1, 100), _r(2, 100), _r(3, 100), _r(4, 200)], yo);
      expect(malaRacha.total, 500);
      expect(siempreArriba.total, 500);
      expect(malaRacha.cruzoElCero, isTrue);
      expect(siempreArriba.cruzoElCero, isFalse);
    });

    test('la mejor y la peor ronda son las del ESCALÓN, no del acumulado', () {
      final s =
          serieDeBalance([_r(1, 100), _r(2, -300), _r(3, 500), _r(4, 20)], yo);
      expect(s.mejor.delaRonda, 500);
      expect(s.peor.delaRonda, -300);
    });

    test('y el mínimo y el máximo son los del ACUMULADO', () {
      // Son dos preguntas distintas: la peor ronda y el peor momento.
      final s =
          serieDeBalance([_r(1, -800), _r(2, 400), _r(3, 500), _r(4, 400)], yo);
      expect(s.minimo, -800);
      expect(s.maximo, 500);
      expect(s.peor.delaRonda, -800);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 7 · ¿DESTAPA ESTO OTRO FALLO DE DATOS?
  //
  // El del handicap destapó siete rondas con diferencial imposible. La pregunta
  // era si el balance esconde algo parecido, porque sale del mismo sitio.
  //
  // La respuesta es que NO, y por un motivo que conviene dejar escrito: el
  // balance de una ronda incompleta es dinero REAL. Las apuestas se liquidaron
  // sobre los hoyos que se jugaron, así que no hay nada que descartar. Donde el
  // handicap necesitaba una guarda, aquí una guarda BORRARÍA dinero de verdad.
  // ───────────────────────────────────────────────────────────────────────────
  group('7 · una ronda incompleta SÍ cuenta aquí', () {
    test('CLAVE: nueve hoyos pagan lo que pactaron nueve', () {
      final nueve = RoundResult(
        roundId: 'r9',
        roundName: 'Nueve de la mañana',
        courseName: 'Los Encinos',
        playedAt: DateTime(2026, 3, 5),
        holesPlayed: 9,
        playerIds: const [yo, otro],
        playerNames: const {yo: 'Carlos', otro: 'Rafa'},
        balances: const {yo: 150, otro: -150},
        pairBalances: const {},
        grossByPlayer: const {},
        netByPlayer: const {},
        stablefordByPlayer: const {},
      );
      final s = serieDeBalance(
          [_r(1, 100), nueve, _r(6, 50), _r(7, -20)], yo);
      expect(s.total, 280, reason: 'los 150 de la ronda de nueve CUENTAN');
    });

    test('y no hay suelo que descarte nada', () {
      // A diferencia del handicap, aquí no hay un valor "imposible": una ronda
      // puede dejarte −2000 y es cierto.
      final s = serieDeBalance(
          [_r(1, -2000), _r(2, 10), _r(3, 10), _r(4, 10)], yo);
      expect(s.total, -1970);
      expect(s.puntos.first.delaRonda, -2000);
    });
  });
}
