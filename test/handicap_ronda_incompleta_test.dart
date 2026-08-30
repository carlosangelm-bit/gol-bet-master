// ─────────────────────────────────────────────────────────────────────────────
// LA RONDA INCOMPLETA QUE PRODUCÍA UN DIFERENCIAL DE −27
//
// El fallo llevaba semanas en los datos y nadie lo había visto: el índice salía
// como un número suelto —"0.0"— y un cero no llama la atención. Lo destapó
// dibujar la serie.
//
// Eran TRES fallos encadenados, y el tercero es el que hacía el daño:
//
//   1 · El mínimo de hoyos era la MITAD. WHS pide catorce de dieciocho.
//   2 · Los hoyos sin anotar sumaban CERO al total.
//   3 · Y ese total se comparaba contra el rating de la ronda ENTERA. Diez
//       hoyos suman 46, el campo vale 72, y el jugador "hizo" 26 bajo par sin
//       haber jugado.
//
// De ahí el resto en cadena: diferenciales de −27 a −37, promedio −17,2 e
// índice 0.0 — que no es que el jugador fuera scratch, es el suelo de un
// cálculo roto.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/services/handicap_service.dart';

const _tee = TeeInfo(
    name: 'Blancas', courseRating: 72.0, slopeRating: 113, parTotal: 72);

final _campo = CourseInfo(name: 'Los Encinos', holes: [
  for (var i = 1; i <= 18; i++) CourseHole(hole: i, par: 4, strokeIndex: i),
]);

/// Una ronda con [hoyos] anotados a [golpes] cada uno.
///
/// [desde] es el primer hoyo: 10 reproduce la salida por el diez de la ronda
/// del 28 de agosto.
Round _ronda({
  required int hoyos,
  int golpes = 5,
  int desde = 1,
  int totalHoles = 18,
  double handicap = 18,
}) {
  final anotados = [for (var i = 0; i < hoyos; i++) ((desde + i - 1) % 18) + 1];
  return Round(
    id: 'r1',
    name: 'Ronda de prueba',
    course: _campo,
    isFinished: true,
    players: [Player(id: 'p1', name: 'Carlos')],
    roundPlayers: [
      RoundPlayer(playerId: 'p1', handicapEnRonda: handicap, tee: _tee),
    ],
    betGroups: const [],
    scores: {
      'p1': {
        for (final h in anotados)
          h: HoleScore(playerId: 'p1', hole: h, grossScore: golpes, putts: 2),
      }
    },
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 8, 28),
    totalHoles: totalHoles,
    startingNine: desde >= 10 ? StartingNine.back : StartingNine.front,
  );
}

ScoreDifferential? _diff(Round r) =>
    HandicapService.calculateFromRound(round: r, playerId: 'p1');

/// Un diferencial ya guardado, para probar la guarda sobre datos existentes.
ScoreDifferential _guardado(int dia, double d) => ScoreDifferential(
      roundId: 'r$dia',
      roundName: 'Ronda $dia',
      playedAt: DateTime(2026, 8, dia),
      differential: d,
      grossScore: 90,
      adjustedGrossScore: 90,
      courseRating: 72,
      slopeRating: 113,
      parTotal: 72,
      holesPlayed: 18,
      courseName: 'Los Encinos',
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · una ronda incompleta NO produce diferencial', () {
    test('REGRESIÓN: la del 28 de agosto, con salida por el 10', () {
      // Es la ronda real que destapó todo: pocos hoyos capturados, y la app la
      // trataba como dieciocho completos.
      expect(_diff(_ronda(hoyos: 10, desde: 10)), isNull,
          reason: 'diez hoyos no son una ronda de dieciocho');
    });

    test('CLAVE: el mínimo es CATORCE, no la mitad', () {
      // WHS Regla 3.2. Antes bastaba con nueve.
      expect(HandicapService.minimoHoyos18, 14);
      expect(_diff(_ronda(hoyos: 13)), isNull);
      expect(_diff(_ronda(hoyos: 14)), isNotNull,
          reason: 'y justo en el mínimo SÍ cuenta');
    });

    test('en una ronda de nueve, siete', () {
      expect(HandicapService.minimoHoyos9, 7);
      expect(_diff(_ronda(hoyos: 6, totalHoles: 9)), isNull);
      expect(_diff(_ronda(hoyos: 7, totalHoles: 9)), isNotNull);
    });

    test('CONTRAPESO: una ronda completa sigue contando, claro', () {
      // Sin esto, un `return null` fijo pasaría todo lo de arriba y el índice
      // no se calcularía nunca.
      final d = _diff(_ronda(hoyos: 18, golpes: 5));
      expect(d, isNotNull);
      expect(d!.holesPlayed, 18);
    });

    test('y la lista dice cuántos hoyos se anotaron DE VERDAD', () {
      // Antes decía "18 H" de una ronda de diez, porque contaba los hoyos que
      // la ronda decía tener, no los que tenían score.
      final d = _diff(_ronda(hoyos: 15));
      expect(d!.holesPlayed, 15);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · los hoyos que faltan van a PAR NETO, no a cero', () {
    test('CLAVE: quince hoyos no dan el gross de quince hoyos', () {
      // Es el fallo que hacía el daño. Con hoyos a cero, quince hoyos a 5
      // suman 75 y se comparan contra un campo de 72: −3 sin haber jugado tres
      // hoyos. Con par neto, los tres que faltan suman lo que le tocaría.
      final d = _diff(_ronda(hoyos: 15, golpes: 5, handicap: 18))!;
      // 15 × 5 = 75, más tres hoyos a par(4) + 1 golpe = 5 cada uno.
      expect(d.grossScore, 90);
    });

    test('CLAVE: y el diferencial deja de ser imposible', () {
      final d = _diff(_ronda(hoyos: 14, golpes: 5, handicap: 18))!;
      expect(d.differential, greaterThan(ScoreDifferential.suelo));
      expect(d.esImposible, isFalse);
    });

    // ── EL CUARTO FALLO, cazado por la aritmética de la prueba de arriba ────
    //
    // Los quince hoyos daban 93 en vez de 90, y no era el test: un jugador de
    // handicap 18 recibía DOS golpes en cada hoyo, cuando le toca uno. El
    // reparto trataba el resto cero como "los dieciocho hoyos" y sumaba una
    // vuelta de más, así que fallaba justo en los múltiplos exactos de 18.
    //
    // Importa porque de ahí sale el tope de doble bogey neto del RBA: con un
    // golpe de más por hoyo, el score ajustado sale más bajo de lo que debe.
    test('CLAVE: handicap 18 da UN golpe por hoyo, no dos', () {
      // 18 hoyos a 5 golpes, todos por debajo del tope: el gross es el gross.
      // Lo que se comprueba es el par neto de los que faltan, que es donde el
      // reparto se ve.
      final d = _diff(_ronda(hoyos: 15, golpes: 5, handicap: 18))!;
      // 15 × 5 = 75 · tres hoyos a par 4 + UN golpe = 5 cada uno · total 90.
      expect(d.grossScore, 90, reason: 'con dos golpes por hoyo daría 93');
    });

    test('y handicap 36 da dos, no tres', () {
      final d = _diff(_ronda(hoyos: 15, golpes: 5, handicap: 36))!;
      // Tres hoyos a par 4 + DOS golpes = 6 cada uno · 75 + 18 = 93.
      expect(d.grossScore, 93);
    });

    test('CONTRAPESO: y el resto se sigue repartiendo por stroke index', () {
      // Con 19, el SI 1 recibe dos y los demás uno. Sin el resto, todos
      // recibirían lo mismo y el stroke index no serviría para nada.
      final h18 = _diff(_ronda(hoyos: 15, golpes: 5, handicap: 18))!;
      final h19 = _diff(_ronda(hoyos: 15, golpes: 5, handicap: 19))!;
      expect(h19.grossScore, greaterThanOrEqualTo(h18.grossScore));
    });

    test('el par neto depende del handicap, no es el par a secas', () {
      // Un jugador de 36 recibe dos golpes en algunos hoyos; el par neto de un
      // hoyo que no jugó tiene que reflejarlo.
      final bajo = _diff(_ronda(hoyos: 14, golpes: 5, handicap: 0))!;
      final alto = _diff(_ronda(hoyos: 14, golpes: 5, handicap: 36))!;
      expect(alto.grossScore, greaterThan(bajo.grossScore));
    });

    test('CONTRAPESO: con los 18 anotados, el par neto no añade nada', () {
      // Sin esto, un relleno que se aplicara siempre inflaría todas las rondas.
      final d = _diff(_ronda(hoyos: 18, golpes: 5))!;
      expect(d.grossScore, 90, reason: '18 × 5, ni un golpe más');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · la guarda del diferencial imposible', () {
    test('CLAVE: −27 no lo juega nadie', () {
      expect(_guardado(28, -27.0).esImposible, isTrue);
      expect(_guardado(25, -31.0).esImposible, isTrue);
      expect(_guardado(18, -37.0).esImposible, isTrue);
    });

    test('CLAVE: pero un diferencial NEGATIVO sí existe', () {
      // Un jugador de handicap positivo que firma por debajo del rating del
      // campo produce un negativo legítimo. Cortar en cero habría descartado
      // datos buenos y escondido el fallo de otra forma.
      expect(_guardado(1, -4.2).esImposible, isFalse);
      expect(_guardado(2, -9.9).esImposible, isFalse);
      expect(ScoreDifferential.suelo, -10.0);
    });

    test('CRITERIO 3: los imposibles no entran al índice', () {
      // Es lo que repara una cuenta SIN migrar nada: los diferenciales están
      // guardados en Firestore, así que arreglar el cálculo solo arregla las
      // rondas futuras.
      final buenos = [for (var i = 1; i <= 10; i++) _guardado(i, 15.0 + i * 0.1)];
      final conBasura = [...buenos, _guardado(28, -27.0), _guardado(25, -31.0)];

      final r = HandicapService.calculateIndex(conBasura);
      expect(r.index, isNotNull);
      expect(r.index, greaterThan(0),
          reason: 'el 0.0 era el suelo de un cálculo roto, no un scratch');
      expect(r.index, HandicapService.calculateIndex(buenos).index,
          reason: 'la basura no cambia el resultado');
    });

    test('y las descartadas se DICEN, no desaparecen', () {
      // Una ronda que no cuenta tiene que poder verse como tal. Desaparecer sin
      // más es lo que dejó este fallo semanas escondido.
      final r = HandicapService.calculateIndex([
        for (var i = 1; i <= 10; i++) _guardado(i, 15.0),
        _guardado(28, -27.0),
      ]);
      expect(r.descartadas, hasLength(1));
      expect(r.descartadas.first.differential, -27.0);
      expect(r.allDifferentials.any((d) => d.esImposible), isFalse,
          reason: 'y no se cuelan en el cálculo');
    });

    test('CONTRAPESO: sin basura no se descarta nada', () {
      // Sin esto, una guarda que descartara de más pasaría lo de arriba.
      final r = HandicapService.calculateIndex(
          [for (var i = 1; i <= 10; i++) _guardado(i, 15.0)]);
      expect(r.descartadas, isEmpty);
      expect(r.totalRounds, 10);
    });

    test('y una cuenta ENTERA de basura no revienta', () {
      // El caso extremo: todo descartado. Tiene que quedarse sin índice, no
      // lanzar ni devolver cero.
      final r = HandicapService.calculateIndex(
          [for (var i = 1; i <= 5; i++) _guardado(i, -30.0)]);
      expect(r.index, isNull);
      expect(r.totalRounds, 0);
      expect(r.descartadas, hasLength(5));
    });
  });
}
