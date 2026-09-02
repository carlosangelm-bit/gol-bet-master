// ─────────────────────────────────────────────────────────────────────────────
// LAS RONDAS DE NUEVE HOYOS Y EL ÍNDICE
//
// «¿Por qué las rondas de diferenciales casi todas agarra las de 9 hoyos?»
//
// No era casualidad ni estadística: era ARITMÉTICA. El diferencial es
// `(113/Slope) × (RBA − CR)`. Con nueve hoyos la app partía el CR a la mitad y
// el RBA es la mitad, pero el multiplicador `113/Slope` NO se parte porque el
// Slope es una pendiente, no un total.
//
// Así que un nueve daba alrededor de la MITAD del diferencial que la misma
// calidad de juego daría en dieciocho — y como WHS coge los ocho mejores de
// veinte, los nueves ganaban siempre.
//
// ── El comentario que decía que estaba resuelto ──────────────────────────────
//
// En el código había escrito: «para rondas de 9 hoyos se dobla el diferencial
// (estándar WHS)». No doblaba nada. Describía una intención que nunca se
// escribió, y es la forma más difícil de encontrar un fallo: el comentario
// afirma que el caso está atendido.
//
// ── Y ningún test lo cubría ─────────────────────────────────────────────────
//
// El arreglo entró sin romper una sola de las 2521 pruebas. No porque fuera
// inocuo: porque no había ninguna que metiera un nueve en `calculateIndex`.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/services/handicap_service.dart';

/// Un diferencial, con los hoyos que se quieran.
ScoreDifferential _d({
  required String id,
  required int dia,
  required double diff,
  int hoyos = 18,
  double cr = 71.7,
  int slope = 149,
  int gross = 90,
}) =>
    ScoreDifferential(
      roundId: id,
      roundName: id,
      playedAt: DateTime(2026, 7, dia),
      differential: diff,
      grossScore: gross,
      adjustedGrossScore: gross,
      courseRating: cr,
      slopeRating: slope,
      parTotal: hoyos == 9 ? 36 : 72,
      holesPlayed: hoyos,
      courseName: 'Los Encinos',
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · el sesgo era aritmético, y se puede medir', () {
    test('CLAVE: un nueve da la MITAD del diferencial de la misma calidad', () {
      // Es la demostración del fallo, no una ilustración. Mismo tee, misma
      // calidad de juego: 18 golpes por encima del rating en dieciocho, nueve
      // por encima en nueve.
      final de18 = HandicapService.calculateScoreDifferential(
          rba: 90, courseRating: 71.7, slopeRating: 149, holesPlayed: 18);
      final de9 = HandicapService.calculateScoreDifferential(
          rba: 47, courseRating: 35.9, slopeRating: 149, holesPlayed: 9);

      expect(de18, closeTo(13.9, 0.1));
      expect(de9, closeTo(8.4, 0.1));
      // Y aquí está el sesgo: el nueve es mucho más bajo, así que gana la
      // selección de los ocho mejores siempre.
      expect(de9, lessThan(de18 * 0.7),
          reason: 'un nueve compite con ventaja contra un dieciocho');
    });

    test('CLAVE: y sumar dos nueves da EXACTAMENTE el de dieciocho', () {
      // La aritmética de por qué WHS combina en vez de doblar:
      //   d₁ + d₂ = (113/S)(r₁−CR₉) + (113/S)(r₂−CR₉) = (113/S)(RBA₁₈ − CR₁₈)
      // No es una aproximación: es la misma expresión.
      final ida = HandicapService.calculateScoreDifferential(
          rba: 47, courseRating: 35.85, slopeRating: 149, holesPlayed: 9);
      final vuelta = HandicapService.calculateScoreDifferential(
          rba: 43, courseRating: 35.85, slopeRating: 149, holesPlayed: 9);
      final entera = HandicapService.calculateScoreDifferential(
          rba: 90, courseRating: 71.7, slopeRating: 149, holesPlayed: 18);
      expect(ida + vuelta, closeTo(entera, 0.2));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · los nueves se combinan antes de seleccionar', () {
    test('CLAVE: dos nueves ocupan UNA plaza, no dos', () {
      // Es la razón de que el emparejamiento vaya antes de recortar a veinte:
      // la ventana se cuenta sobre diferenciales de dieciocho.
      final r = HandicapService.calculateIndex([
        _d(id: 'n1', dia: 14, diff: 9.2, hoyos: 9),
        _d(id: 'n2', dia: 21, diff: 6.2, hoyos: 9),
        _d(id: 'd1', dia: 24, diff: 7.8),
      ]);
      expect(r.totalRounds, 2, reason: 'un combinado más un dieciocho');
      // Y el combinado vale la SUMA, que es lo que compite de verdad.
      final combinado =
          r.allDifferentials.firstWhere((d) => d.holesPlayed == 18 && d.roundId.contains('+'));
      expect(combinado.differential, closeTo(15.4, 0.01));
    });

    test('CLAVE: el combinado se fecha con la ronda MÁS RECIENTE', () {
      // El diferencial de dieciocho no existía hasta que se jugó la segunda.
      // Fecharlo con la primera lo metería antes de tiempo en la ventana.
      final c = HandicapService.combinarNueves(
        _d(id: 'n1', dia: 14, diff: 9.2, hoyos: 9),
        _d(id: 'n2', dia: 21, diff: 6.2, hoyos: 9),
      );
      expect(c.playedAt, DateTime(2026, 7, 21));
      expect(c.holesPlayed, 18);
      // Y dice de qué dos rondas salió: si no, se lee como una ronda de
      // dieciocho que nadie jugó.
      expect(c.roundId, 'n1+n2');
      expect(c.roundName, contains('+'));
    });

    test('CLAVE: se combinan en el ORDEN en que se jugaron', () {
      // No los dos mejores ni los dos peores: el primero con el segundo. Elegir
      // qué nueves se emparejan sería elegir el índice.
      final e = HandicapService.emparejarNueves([
        _d(id: 'c', dia: 28, diff: 8.5, hoyos: 9),
        _d(id: 'a', dia: 14, diff: 9.2, hoyos: 9),
        _d(id: 'b', dia: 21, diff: 6.2, hoyos: 9),
        _d(id: 'd', dia: 30, diff: 5.0, hoyos: 9),
      ]);
      final ids = e.paraElIndice.map((d) => d.roundId).toList();
      expect(ids, ['a+b', 'c+d']);
      expect(e.sinPareja, isNull);
    });

    test('CLAVE: el nueve IMPAR no se usa, y es el más reciente', () {
      // El que espera pareja es el último que se jugó, no uno de hace meses.
      final e = HandicapService.emparejarNueves([
        _d(id: 'a', dia: 14, diff: 9.2, hoyos: 9),
        _d(id: 'b', dia: 21, diff: 6.2, hoyos: 9),
        _d(id: 'c', dia: 28, diff: 8.5, hoyos: 9),
      ]);
      expect(e.paraElIndice.map((d) => d.roundId), ['a+b']);
      expect(e.sinPareja?.roundId, 'c');
    });

    test('CLAVE: y el índice LO DICE — criterio 2', () {
      // Una ronda jugada que no aparece en ningún sitio se lee como un fallo de
      // guardado, que es la forma en que este proyecto ha perdido datos ya.
      final r = HandicapService.calculateIndex([
        _d(id: 'a', dia: 14, diff: 9.2, hoyos: 9),
        _d(id: 'b', dia: 21, diff: 6.2, hoyos: 9),
        _d(id: 'c', dia: 28, diff: 8.5, hoyos: 9),
      ]);
      expect(r.nueveSinPareja?.roundId, 'c');
    });

    test('CONTRAPESO: con solo dieciochos nada cambia y no hay nada que decir',
        () {
      // El criterio que protege lo construido: una cuenta sin nueves tiene que
      // dar el mismo índice que antes.
      final diffs = [
        for (var i = 1; i <= 20; i++) _d(id: 'd$i', dia: i, diff: 10.0 + i * 0.1)
      ];
      final r = HandicapService.calculateIndex(diffs);
      expect(r.totalRounds, 20);
      expect(r.nueveSinPareja, isNull);
      expect(r.allDifferentials.every((d) => !d.roundId.contains('+')), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3 · EL CASO REAL
  //
  // Las cinco rondas del reporte, con sus diferenciales tal como se ven en la
  // pantalla. Antes, los tres nueves entraban en los ocho mejores por ser bajos;
  // ahora dos se combinan en uno de dieciocho y el tercero espera.
  // ───────────────────────────────────────────────────────────────────────────
  group('3 · las cinco rondas del reporte', () {
    List<ScoreDifferential> lasCinco() => [
          _d(id: '28jul', dia: 28, diff: 8.5, hoyos: 9),
          _d(id: '24jul', dia: 24, diff: 7.8),
          _d(id: '21jul', dia: 21, diff: 6.2, hoyos: 9),
          _d(id: '17jul', dia: 17, diff: 12.4),
          _d(id: '14jul', dia: 14, diff: 9.2, hoyos: 9),
        ];

    test('CLAVE: los tres nueves ya no compiten como tres rondas bajas', () {
      final r = HandicapService.calculateIndex(lasCinco());
      // Cinco rondas se convierten en tres: dos dieciochos más un combinado.
      expect(r.totalRounds, 3);
      final combinado = r.allDifferentials
          .where((d) => d.roundId.contains('+'))
          .single;
      // 14 jul + 21 jul, en orden de juego: 9,2 + 6,2 = 15,4.
      expect(combinado.roundId, '14jul+21jul');
      expect(combinado.differential, closeTo(15.4, 0.01));
      // Y el del 28 espera pareja.
      expect(r.nueveSinPareja?.roundId, '28jul');
    });

    test('CON POCAS RONDAS el índice puede BAJAR, y no es un fallo', () {
      // Esto se escribió esperando lo contrario, y merece quedar escrito.
      //
      // Con cinco rondas, combinar los nueves deja TRES diferenciales en vez de
      // cinco — y el ajuste de la tabla WHS por pocas rondas es más grande con
      // tres que con cinco. Ese ajuste mueve el índice más que el sesgo que se
      // acaba de quitar, así que baja.
      //
      // O sea: con pocas rondas el índice está dominado por el andamiaje de la
      // tabla, no por el juego —que es exactamente lo que dice la serie de
      // tendencia al negarse a dibujar antes de la séptima ronda—. La dirección
      // solo significa algo con la ventana llena.
      final conSesgo = HandicapService.calculateIndex([
        for (final d in lasCinco())
          _d(
              id: d.roundId,
              dia: d.playedAt.day,
              diff: d.differential,
              hoyos: 18),
      ]);
      final sinSesgo = HandicapService.calculateIndex(lasCinco());
      expect(conSesgo.tableAdjustment, isNot(sinSesgo.tableAdjustment),
          reason: 'el ajuste cambia porque cambia el número de rondas');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4 · DONDE EL SESGO SE MIDE DE VERDAD: con la ventana llena
  //
  // Con veinte diferenciales el ajuste de la tabla es cero, así que lo que se
  // ve es solo el efecto del sesgo. Y lo que hay que comprobar no es la
  // dirección del índice: es QUÉ ENTRA en los ocho mejores.
  // ───────────────────────────────────────────────────────────────────────────
  group('4 · con la ventana llena, ningún nueve entra en los ocho', () {
    /// Catorce dieciochos normales y seis nueves. Los nueves llevan
    /// diferenciales BAJOS, que es la situación del reporte.
    List<ScoreDifferential> catorceYSeis() => [
          for (var i = 1; i <= 14; i++)
            _d(id: 'd$i', dia: i, diff: 13.0 + i * 0.1),
          for (var i = 0; i < 6; i++)
            _d(id: 'n$i', dia: 15 + i, diff: 6.0 + i * 0.1, hoyos: 9),
        ];

    test('CLAVE: los usados son todos de dieciocho hoyos', () {
      final r = HandicapService.calculateIndex(catorceYSeis());
      expect(r.usedDifferentials, isNotEmpty);
      for (final d in r.usedDifferentials) {
        expect(d.holesPlayed, 18, reason: d.roundId);
      }
    });

    test('CONTRAPESO: y con el sesgo, los ocho mejores eran los nueves', () {
      // La reproducción del fallo. Si esto NO diera nueves, el test de arriba
      // no estaría comprobando nada: pasaría con cualquier implementación.
      final conSesgo = HandicapService.calculateIndex([
        for (final d in catorceYSeis())
          _d(
              id: d.roundId,
              dia: d.playedAt.day,
              diff: d.differential,
              // Es lo que hacía el cálculo viejo: meterlos en la misma bolsa.
              hoyos: 18),
      ]);
      final bajos = conSesgo.usedDifferentials
          .where((d) => d.roundId.startsWith('n'))
          .length;
      expect(bajos, 6, reason: 'los seis nueves ocupaban seis de los ocho');
    });

    test('CLAVE: y el índice SUBE, con la ventana llena', () {
      // Aquí sí: sin el ajuste de la tabla de por medio, quitar el sesgo tiene
      // que subir el índice.
      final conSesgo = HandicapService.calculateIndex([
        for (final d in catorceYSeis())
          _d(
              id: d.roundId,
              dia: d.playedAt.day,
              diff: d.differential,
              hoyos: 18),
      ]);
      final sinSesgo = HandicapService.calculateIndex(catorceYSeis());
      expect(sinSesgo.index!, greaterThan(conSesgo.index!),
          reason: 'los nueves bajaban el índice y ya no');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5 · DESDE UNA RONDA DE VERDAD
  //
  // Los grupos de arriba le pasan los números a la fórmula. Este pasa por
  // `calculateFromRound`, que es donde vive el partido del CR — y donde un
  // contrapeso NO MORDIÓ: quitando el `cr / 2.0`, todo seguía verde porque
  // ninguna prueba entraba por ahí.
  // ───────────────────────────────────────────────────────────────────────────
  group('5 · el diferencial de una ronda de nueve, calculado', () {
    Round _ronda({required int hoyos, required int golpesPorHoyo}) {
      final tee = const TeeInfo(
          name: 'Blancas', courseRating: 71.7, slopeRating: 149, parTotal: 72);
      final ps = [Player(id: 'ana', name: 'Ana')];
      return Round(
        id: 'r$hoyos',
        name: 'Ronda de $hoyos',
        course: CourseInfo(
            name: 'Los Encinos',
            holes: List.generate(
                18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1))),
        players: ps,
        roundPlayers: [
          RoundPlayer(playerId: 'ana', handicapEnRonda: 0, tee: tee),
        ],
        betGroups: [
          BetGroup(
              id: 'g',
              name: 'G',
              format: PartidaFormat.oneVsOne,
              playerIds: const ['ana'],
              modules: [
                BetModuleInstance.defaultFor(BetModuleType.skins, const ['ana'],
                    id: 'sk')
              ]),
        ],
        scores: {
          'ana': {
            for (var h = 1; h <= hoyos; h++)
              h: HoleScore(
                  playerId: 'ana', hole: h, grossScore: golpesPorHoyo),
          },
        },
        events: const {},
        oyeseRankings: const {},
        sliding: const [],
        createdAt: DateTime(2026, 7, 28),
        totalHoles: hoyos,
        isFinished: true,
      );
    }

    test('CLAVE: con nueve hoyos el CR se parte, y el Slope NO', () {
      // Es el dato del reporte: «CR 35.9 · Slope 149». El CR es la mitad porque
      // es un total; el Slope no, porque es una pendiente. Las dos cosas son
      // correctas por separado — el fallo era compararlo con un dieciocho.
      final d = HandicapService.calculateFromRound(
          round: _ronda(hoyos: 9, golpesPorHoyo: 5), playerId: 'ana')!;
      expect(d.courseRating, closeTo(35.85, 0.01));
      expect(d.slopeRating, 149);
      expect(d.holesPlayed, 9, reason: 'y se marca como nueve, o no se empareja');
    });

    test('CLAVE: y el de dieciocho usa el CR entero', () {
      final d = HandicapService.calculateFromRound(
          round: _ronda(hoyos: 18, golpesPorHoyo: 5), playerId: 'ana')!;
      expect(d.courseRating, closeTo(71.7, 0.01));
      expect(d.holesPlayed, 18);
    });

    test('CLAVE: el nueve da la MITAD del diferencial del dieciocho', () {
      // La misma calidad de juego —cinco golpes en cada hoyo— en nueve y en
      // dieciocho. Es la demostración del sesgo desde una ronda de verdad.
      final n = HandicapService.calculateFromRound(
          round: _ronda(hoyos: 9, golpesPorHoyo: 5), playerId: 'ana')!;
      final d = HandicapService.calculateFromRound(
          round: _ronda(hoyos: 18, golpesPorHoyo: 5), playerId: 'ana')!;
      expect(n.differential, closeTo(d.differential / 2, 0.15),
          reason: 'de ahí que ganara siempre los ocho mejores');
    });

    test('CLAVE: dos nueves iguales suman el diferencial del dieciocho', () {
      // El cierre del círculo: lo que WHS hace al combinar devuelve exactamente
      // el diferencial de la ronda entera.
      final n = HandicapService.calculateFromRound(
          round: _ronda(hoyos: 9, golpesPorHoyo: 5), playerId: 'ana')!;
      final d = HandicapService.calculateFromRound(
          round: _ronda(hoyos: 18, golpesPorHoyo: 5), playerId: 'ana')!;
      final combinado = HandicapService.combinarNueves(n, n);
      expect(combinado.differential, closeTo(d.differential, 0.15));
      expect(combinado.holesPlayed, 18);
    });
  });
}
