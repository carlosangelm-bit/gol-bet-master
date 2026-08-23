// ─────────────────────────────────────────────────────────────────────────────
// LA LLAVE — el cuadro se deriva, solo la siembra se guarda
//
// Misma regla que la tabla: si el cuadro se guardara resuelto, corregir una
// ronda dejaría un campeón viejo sin avisar. Hay un test que lo comprueba
// cambiando el resultado y viendo cambiar al campeón.
//
// El caso que casi se me escapa, y que tiene test propio: cuatro amigos juegan
// UNA ronda. Eso resuelve los dos cuartos —bien— pero no puede resolver también
// la semifinal entre los dos ganadores, porque ese golf ya se jugó. Sin la
// cuenta de rondas gastadas, el cuadro entero se cerraba con una sola tarjeta.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';

const ana = 'pid_ana01', beto = 'pid_bet02', caro = 'pid_car03';
const dani = 'pid_dan04', eva = 'pid_eva05', fito = 'pid_fit06';
const gus = 'pid_gus07', hugo = 'pid_hug08';

/// Una ronda del torneo con el dinero que sacó cada uno.
RoundResult _r({
  required String id,
  required int dia,
  required Map<String, double> dinero,
  Map<String, int> stbl = const {},
  String torneo = 'tor_1',
}) =>
    RoundResult(
      roundId: id,
      roundName: 'Ronda $id',
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 3, dia),
      holesPlayed: 18,
      playerIds: dinero.keys.toList(),
      playerNames: {for (final k in dinero.keys) k: k},
      balances: dinero,
      pairBalances: const {},
      grossByPlayer: const {},
      netByPlayer: const {},
      stablefordByPlayer: stbl,
      bettingGroupIds: const [],
      torneoIds: [torneo],
    );

Torneo _t({
  List<String> participantes = const [ana, beto, caro, dani],
  List<String> siembra = const [],
  Map<String, String> desempates = const {},
  MetodoDePuntuacion metodo = MetodoDePuntuacion.dinero,
  FormatoDeTorneo formato = FormatoDeTorneo.eliminacion,
  FuenteDeRondas fuente = FuenteDeRondas.marcadas,
}) =>
    Torneo(
      id: 'tor_1',
      nombre: 'Match Play',
      formato: formato,
      fuente: fuente,
      metodo: metodo,
      participantes: participantes,
      siembra: siembra,
      desempates: desempates,
    );

void main() {
  seguimiento();

  group('1 · el orden de siembra: el 1 y el 2 solo se cruzan en la final', () {
    test('dos, cuatro y ocho plazas', () {
      expect(ordenDeSiembra(2), [1, 2]);
      expect(ordenDeSiembra(4), [1, 4, 2, 3]);
      expect(ordenDeSiembra(8), [1, 8, 4, 5, 2, 7, 3, 6]);
    });

    test('el 1 y el 2 caen en mitades distintas, con cualquier tamaño', () {
      for (final plazas in [4, 8, 16, 32]) {
        final orden = ordenDeSiembra(plazas);
        expect(orden, hasLength(plazas));
        // Cada sembrado aparece una vez y solo una.
        expect(orden.toSet(), hasLength(plazas));
        final mitad = plazas ~/ 2;
        expect(orden.indexOf(1) < mitad, isTrue,
            reason: 'el 1 va en la mitad de arriba');
        expect(orden.indexOf(2) >= mitad, isTrue,
            reason: 'el 2 en la de abajo: así solo se ven en la final');
      }
    });

    test('los dos de cada partido suman plazas+1: el 1 con el último', () {
      final orden = ordenDeSiembra(8);
      for (var i = 0; i < orden.length; i += 2) {
        expect(orden[i] + orden[i + 1], 9);
      }
    });
  });

  group('2 · el cuadro se arma con los inscritos', () {
    test('una liga no tiene cuadro, y lo dice', () {
      final l = llaveDe(_t(formato: FormatoDeTorneo.liga), const []);
      expect(l.vacia, isTrue);
      expect(l.motivo, contains('liga'));
    });

    test('sin inscritos no hay cuadro: se arma con quien se inscribió', () {
      final l = llaveDe(_t(participantes: const []), const []);
      expect(l.vacia, isTrue);
      expect(l.motivo, contains('participantes'));
    });

    test('con uno tampoco', () {
      expect(llaveDe(_t(participantes: const [ana]), const []).vacia, isTrue);
    });

    test('cuatro inscritos → dos cuartos y una final, sin byes', () {
      final l = llaveDe(_t(), const []);
      expect(l.plazas, 4);
      expect(l.byes, 0);
      expect(l.rondas, hasLength(2));
      expect(l.rondas[0], hasLength(2));
      expect(l.rondas[1], hasLength(1));
      // Sin rondas jugadas nadie pasa, y la final está esperando.
      expect(l.campeon, isNull);
      expect(l.rondas[1].first.esperando, isTrue);
    });

    test('cinco inscritos → ocho plazas y tres byes', () {
      final l = llaveDe(
          _t(participantes: const [ana, beto, caro, dani, eva]), const []);
      expect(l.plazas, 8);
      expect(l.byes, 3);
      expect(l.rondas, hasLength(3));
      // Tres pasan sin jugar, y el cuarto partido sí se juega.
      expect(l.rondas[0].where((e) => e.bye), hasLength(3));
      expect(l.rondas[0].where((e) => e.jugable), hasLength(1));
      // Los byes van a los primeros sembrados, que es para lo que sirve sembrar.
      final pasan = l.rondas[0].where((e) => e.bye).map((e) => e.ganador);
      expect(pasan, containsAll([ana, beto, caro]));
    });

    test('la siembra manda sobre el orden de la lista', () {
      // Con la lista tal cual, ana se cruza con dani. Sembrando al revés, no.
      final normal = llaveDe(_t(), const []);
      expect({normal.rondas[0][0].a, normal.rondas[0][0].b}, {ana, dani});

      final sembrado = llaveDe(
          _t(siembra: const [dani, caro, beto, ana]), const []);
      expect({sembrado.rondas[0][0].a, sembrado.rondas[0][0].b}, {dani, ana});
      expect({sembrado.rondas[0][1].a, sembrado.rondas[0][1].b}, {caro, beto});
    });

    test('una siembra con alguien que no está inscrito lo ignora', () {
      // Pasa al borrar un inscrito y no tocar la siembra. Colar a quien no se
      // inscribió sería justo el fallo que la lista explícita vino a arreglar.
      final l = llaveDe(
          _t(participantes: const [ana, beto], siembra: const [ana, hugo, beto]),
          const []);
      expect(l.plazas, 2);
      expect({l.rondas[0][0].a, l.rondas[0][0].b}, {ana, beto});
    });
  });

  group('3 · el partido lo resuelve la ronda que jugaron los dos', () {
    test('gana quien saca más dinero, y se dice con qué ronda', () {
      final l = llaveDe(
          _t(participantes: const [ana, beto]),
          [_r(id: 'r1', dia: 7, dinero: {ana: 300, beto: -300})]);
      final final_ = l.rondas[0][0];
      expect(final_.ganador, ana);
      expect(final_.perdedor, beto);
      expect(final_.roundId, 'r1');
      expect(final_.cuando, DateTime(2026, 3, 7));
      expect(final_.medidaA, 300);
      expect(l.campeon, ana);
    });

    test('con Stableford gana quien más puntos, no quien más dinero', () {
      // Es lo que hace que Stableford deje de ser un formato aparte: cambiar el
      // método cambia quién pasa, con los MISMOS datos.
      final ronda = _r(
          id: 'r1',
          dia: 7,
          dinero: {ana: 300, beto: -300},
          stbl: {ana: 30, beto: 36});
      expect(
          llaveDe(_t(participantes: const [ana, beto]), [ronda])
              .rondas[0][0]
              .ganador,
          ana);
      expect(
          llaveDe(
                  _t(
                      participantes: const [ana, beto],
                      metodo: MetodoDePuntuacion.stableford),
                  [ronda])
              .rondas[0][0]
              .ganador,
          beto);
    });

    test('con score neto gana el número MENOR', () {
      final ronda = RoundResult(
        roundId: 'r1',
        roundName: 'R',
        courseName: 'C',
        playedAt: DateTime(2026, 3, 7),
        holesPlayed: 18,
        playerIds: const [ana, beto],
        playerNames: const {ana: 'A', beto: 'B'},
        balances: const {},
        pairBalances: const {},
        grossByPlayer: const {},
        netByPlayer: const {ana: 74, beto: 71},
        stablefordByPlayer: const {},
        bettingGroupIds: const [],
        torneoIds: const ['tor_1'],
      );
      expect(
          llaveDe(
                  _t(
                      participantes: const [ana, beto],
                      metodo: MetodoDePuntuacion.scoreNeto),
                  [ronda])
              .rondas[0][0]
              .ganador,
          beto);
    });

    test('una ronda que no marcó el torneo no resuelve nada', () {
      final l = llaveDe(_t(participantes: const [ana, beto]),
          [_r(id: 'r1', dia: 7, dinero: {ana: 300, beto: -300}, torneo: 'otro')]);
      expect(l.rondas[0][0].ganador, isNull);
      expect(l.rondas[0][0].jugable, isTrue);
    });

    test('si solo jugó uno, el partido sigue pendiente', () {
      final l = llaveDe(_t(participantes: const [ana, beto]),
          [_r(id: 'r1', dia: 7, dinero: {ana: 100, caro: -100})]);
      expect(l.rondas[0][0].ganador, isNull);
    });

    test('vale la PRIMERA vez que se cruzan, no la mejor', () {
      // Elegir la ronda más favorable sería inventarse una regla. El partido se
      // juega una vez; lo de después es más golf.
      final l = llaveDe(_t(participantes: const [ana, beto]), [
        _r(id: 'r2', dia: 20, dinero: {ana: 500, beto: -500}),
        _r(id: 'r1', dia: 7, dinero: {ana: -300, beto: 300}),
      ]);
      expect(l.rondas[0][0].roundId, 'r1');
      expect(l.campeon, beto);
    });
  });

  group('4 · una ronda de cuatro resuelve dos partidos, no el cuadro entero',
      () {
    // El fallo que casi se cuela: sin la cuenta de rondas gastadas, la misma
    // tarjeta resolvía los dos cuartos Y la final.
    final unaSola = [
      _r(id: 'r1', dia: 7, dinero: {ana: 300, dani: -100, beto: 50, caro: -250}),
    ];

    test('los dos cuartos se resuelven con la misma ronda', () {
      final l = llaveDe(_t(), unaSola);
      expect(l.rondas[0][0].ganador, ana); // ana 300 > dani -100
      expect(l.rondas[0][1].ganador, beto); // beto 50 > caro -250
      expect(l.rondas[0][0].roundId, 'r1');
      expect(l.rondas[0][1].roundId, 'r1');
    });

    test('pero la final NO: ese golf ya se jugó', () {
      final l = llaveDe(_t(), unaSola);
      expect(l.campeon, isNull);
      expect(l.rondas[1].first.jugable, isTrue);
      expect({l.rondas[1].first.a, l.rondas[1].first.b}, {ana, beto});
    });

    test('la final se resuelve con la ronda siguiente', () {
      final l = llaveDe(_t(), [
        ...unaSola,
        _r(id: 'r2', dia: 14, dinero: {ana: -80, beto: 80}),
      ]);
      expect(l.campeon, beto);
      expect(l.rondas[1].first.roundId, 'r2');
    });

    test('vale otra ronda del MISMO día: la fecha no basta como criterio', () {
      final l = llaveDe(_t(), [
        ...unaSola,
        _r(id: 'r2', dia: 7, dinero: {ana: -80, beto: 80}),
      ]);
      expect(l.campeon, beto);
      expect(l.rondas[1].first.roundId, 'r2');
    });
  });

  group('5b · un hueco "por decidir" NO es un bye', () {
    test('con una semifinal sin jugar, el otro finalista no es campeón', () {
      // El fallo: en la ronda 0 un hueco vacío es un bye de verdad —ese sembrado
      // no existe— pero en una ronda posterior es "todavía no se sabe quién
      // viene". Tratarlo igual coronaba campeón a quien no jugó la final.
      final l = llaveDe(_t(), [
        _r(id: 's1', dia: 7, dinero: {ana: 300, dani: -300}),
      ]);
      expect(l.rondas[0][0].ganador, ana);
      expect(l.rondas[0][1].ganador, isNull, reason: 'la otra semi no se jugó');
      final finalDelCuadro = l.rondas[1].first;
      expect(finalDelCuadro.a, ana);
      expect(finalDelCuadro.b, isNull);
      expect(finalDelCuadro.bye, isFalse, reason: 'no es un bye: es una espera');
      expect(finalDelCuadro.esperando, isTrue);
      expect(finalDelCuadro.ganador, isNull);
      expect(l.campeon, isNull);
    });

    test('el bye de la primera ronda sí sigue siendo un bye', () {
      // El contrapeso: la corrección no puede haberse comido los byes.
      final l = llaveDe(
          _t(participantes: const [ana, beto, caro]), const []);
      expect(l.rondas[0].where((e) => e.bye), hasLength(1));
      expect(l.rondas[0].where((e) => e.bye).first.ganador, isNotNull);
    });
  });

  group('5 · no se puede ganar la final antes de la semifinal', () {
    test('una ronda vieja entre dos finalistas no resuelve la final', () {
      // Ana y Beto ya habían jugado en enero. Eso no es la final.
      final l = llaveDe(_t(), [
        _r(id: 'viejo', dia: 2, dinero: {ana: 900, beto: -900}),
        _r(id: 'c1', dia: 10, dinero: {ana: 300, dani: -300}),
        _r(id: 'c2', dia: 11, dinero: {beto: 200, caro: -200}),
      ]);
      expect(l.rondas[0][0].ganador, ana);
      expect(l.rondas[0][1].ganador, beto);
      expect(l.campeon, isNull, reason: 'la final está por jugarse');
    });

    test('y sí la resuelve una jugada después de los dos cuartos', () {
      final l = llaveDe(_t(), [
        _r(id: 'viejo', dia: 2, dinero: {ana: 900, beto: -900}),
        _r(id: 'c1', dia: 10, dinero: {ana: 300, dani: -300}),
        _r(id: 'c2', dia: 11, dinero: {beto: 200, caro: -200}),
        _r(id: 'fin', dia: 20, dinero: {ana: -50, beto: 50}),
      ]);
      expect(l.campeon, beto);
      expect(l.rondas[1].first.roundId, 'fin');
    });
  });

  group('6 · el empate no se resuelve solo', () {
    final empatan = [_r(id: 'r1', dia: 7, dinero: {ana: 0, beto: 0})];

    test('empatados: el partido se queda a la vista sin resolver', () {
      final l = llaveDe(_t(participantes: const [ana, beto]), empatan);
      final e = l.rondas[0][0];
      expect(e.empatado, isTrue);
      expect(e.ganador, isNull);
      expect(e.jugable, isFalse, reason: 'ya jugaron: no es que falte jugarlo');
      expect(l.campeon, isNull);
      expect(l.pendientesDeDesempate, hasLength(1));
    });

    test('el organizador lo decide y el cuadro sigue', () {
      final l = llaveDe(
          _t(
              participantes: const [ana, beto],
              desempates: {parKey(ana, beto): beto}),
          empatan);
      expect(l.rondas[0][0].ganador, beto);
      expect(l.rondas[0][0].desempatadoAMano, isTrue);
      expect(l.rondas[0][0].empatado, isFalse);
      expect(l.campeon, beto);
    });

    test('la clave del desempate no depende del orden de los dos', () {
      expect(parKey(ana, beto), parKey(beto, ana));
      // Así reordenar la siembra no le adjudica el desempate a otra pareja.
      final l = llaveDe(
          _t(
              participantes: const [ana, beto],
              siembra: const [beto, ana],
              desempates: {parKey(beto, ana): ana}),
          empatan);
      expect(l.rondas[0][0].ganador, ana);
    });

    test('un desempate a nombre de quien no juega ese partido se ignora', () {
      final l = llaveDe(
          _t(
              participantes: const [ana, beto],
              desempates: {parKey(ana, beto): caro}),
          empatan);
      expect(l.rondas[0][0].ganador, isNull);
      expect(l.rondas[0][0].empatado, isTrue);
    });
  });

  group('7 · el cuadro se DERIVA: corregir una ronda cambia el campeón', () {
    List<RoundResult> temporada(double dineroDeAna) => [
          _r(id: 'r1', dia: 7, dinero: {ana: dineroDeAna, beto: -dineroDeAna}),
        ];

    test('el mismo cuadro con la ronda corregida da otro campeón', () {
      final t = _t(participantes: const [ana, beto]);
      expect(llaveDe(t, temporada(300)).campeon, ana);
      // Se corrige la liquidación y el resultado se da la vuelta. Nadie
      // recalcula nada: el cuadro no estaba guardado.
      expect(llaveDe(t, temporada(-300)).campeon, beto);
    });
  });

  group('8 · qué se guarda y qué no', () {
    test('formato, siembra y desempates sobreviven el JSON', () {
      final t = _t(siembra: const [dani, ana, beto, caro],
          desempates: {parKey(ana, beto): ana});
      final ida = Torneo.fromJson(t.toJson());
      expect(ida.formato, FormatoDeTorneo.eliminacion);
      expect(ida.siembra, [dani, ana, beto, caro]);
      expect(ida.desempates[parKey(ana, beto)], ana);
    });

    test('un torneo de liga no engorda el documento', () {
      final j = Torneo(id: 't', nombre: 'Liga').toJson();
      expect(j.containsKey('formato'), isFalse);
      expect(j.containsKey('siembra'), isFalse);
      expect(j.containsKey('desempates'), isFalse);
      // Y se lee como liga, que es lo que había antes de que esto existiera.
      expect(Torneo.fromJson(j).formato, FormatoDeTorneo.liga);
    });

    test('el cuadro NO se guarda: no hay campo donde quepa', () {
      // La prueba de que la regla se cumple por construcción. Si algún día
      // alguien añade 'llave' al JSON, este test lo caza.
      final j = _t().toJson();
      expect(j.keys, isNot(contains('llave')));
      expect(j.keys, isNot(contains('campeon')));
      expect(j.keys, isNot(contains('ganadores')));
    });
  });

  group('9 · un cuadro necesita rondas marcadas', () {
    test('con otra fuente se dice por qué no, y a qué cambiar', () {
      final m = motivoSinCuadro(_t(fuente: FuenteDeRondas.rango));
      expect(m, isNotNull);
      expect(m, contains('Marcadas'));
    });

    test('con marcas y dos inscritos, adelante', () {
      expect(motivoSinCuadro(_t()), isNull);
    });

    test('con menos de dos inscritos, no', () {
      expect(motivoSinCuadro(_t(participantes: const [ana])), isNotNull);
    });

    test('pero la falta de inscritos no bloquea elegir el formato', () {
      // Es un "todavía no": bloquearlo obligaría a bajar al paso 3 a rellenar la
      // lista y volver a subir. Lo que sí bloquea es la fuente.
      expect(
          motivoSinCuadro(_t(participantes: const []), exigirInscritos: false),
          isNull);
      expect(
          motivoSinCuadro(_t(fuente: FuenteDeRondas.rango),
              exigirInscritos: false),
          isNotNull);
    });
  });

  group('10 · ocho jugadores, cuadro completo', () {
    test('tres rondas y un campeón', () {
      final ocho = [ana, beto, caro, dani, eva, fito, gus, hugo];
      final t = _t(participantes: ocho);
      final l = llaveDe(t, const []);
      expect(l.plazas, 8);
      expect(l.byes, 0);
      expect(l.rondas.map((r) => r.length), [4, 2, 1]);
      expect(nombreDeRondaDeLlave(4), 'Cuartos de final');
      expect(nombreDeRondaDeLlave(2), 'Semifinales');
      expect(nombreDeRondaDeLlave(1), 'Final');

      // Cada uno aparece exactamente una vez en la primera ronda.
      final enCuadro = l.rondas[0]
          .expand((e) => [e.a, e.b])
          .whereType<String>()
          .toList();
      expect(enCuadro.toSet(), ocho.toSet());
      expect(enCuadro, hasLength(8));
    });

    test('se resuelve entero con una ronda por partido', () {
      final ocho = [ana, beto, caro, dani, eva, fito, gus, hugo];
      // Gana siempre el primero de cada pareja según la siembra.
      final l0 = llaveDe(_t(participantes: ocho), const []);
      final rondas = <RoundResult>[];
      var dia = 1;
      var nivel = l0.rondas[0];
      var pasan = <String>[];
      for (final e in nivel) {
        rondas.add(_r(id: 'q$dia', dia: dia++,
            dinero: {e.a!: 100, e.b!: -100}));
        pasan.add(e.a!);
      }
      // Semifinales y final, con los que fueron pasando.
      for (var i = 0; i < 2; i++) {
        rondas.add(_r(id: 's$dia', dia: dia++,
            dinero: {pasan[i * 2]: 100, pasan[i * 2 + 1]: -100}));
      }
      rondas.add(_r(id: 'f$dia', dia: dia++,
          dinero: {pasan[0]: 100, pasan[2]: -100}));

      final l = llaveDe(_t(participantes: ocho), rondas);
      expect(l.campeon, pasan[0]);
      expect(l.jugables, isEmpty);
      expect(l.pendientesDeDesempate, isEmpty);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SEGUIMIENTO — las tres superficies que seguían hablando de liga
//
// Las tres eran la misma cosa: la lógica estaba en el formato y las superficies
// no la consultaban. Así que lo que se prueba aquí no son las pantallas una a
// una, sino la TABLA que ahora consultan: qué aplica a cada formato, qué método
// se usa de verdad, y cómo se resume un cuadro.
// ─────────────────────────────────────────────────────────────────────────────
void seguimiento() {
  group('11 · nunca un id crudo en pantalla', () {
    test('el inscrito que no ha jugado sale con guion, no con su id', () {
      // "Va 6uX3jmCVlYNxCJxWBJQe" en la primera pantalla dice "esto está a
      // medias" más alto que cualquier otra cosa.
      final tabla = tablaDe(
          Torneo(
              id: 'tor_1',
              nombre: 'T',
              fuente: FuenteDeRondas.marcadas,
              participantes: const [ana, beto]),
          const []);
      final nombres = [...tabla.filas, ...tabla.bajoMinimo].map((f) => f.nombre);
      expect(nombres, everyElement(sinNombre));
      expect(nombres, isNot(contains(ana)));
    });

    test('y con el directorio sale su nombre', () {
      // El contrapeso: sin esto, lo de arriba pasaría con una tabla vacía.
      final tabla = tablaDe(
          Torneo(
              id: 'tor_1',
              nombre: 'T',
              fuente: FuenteDeRondas.marcadas,
              participantes: const [ana, beto]),
          const [],
          nombres: const {ana: 'Rafael', beto: 'Alan'});
      expect([...tabla.filas, ...tabla.bajoMinimo].map((f) => f.nombre),
          containsAll(['Rafael', 'Alan']));
    });

    test('el que jugó pero ya no está en el directorio conserva su nombre', () {
      // RoundResult guarda el nombre del día a propósito: es un registro
      // histórico. Borrar a alguien del directorio no borra lo que jugó.
      final tabla = tablaDe(
          _t(participantes: const [ana, beto]),
          [_r(id: 'r1', dia: 7, dinero: {ana: 100, beto: -100})]);
      expect(tabla.filas.map((f) => f.nombre), isNot(contains(sinNombre)));
    });
  });

  group('12 · qué aplica a cada formato', () {
    test('en un cuadro no hay puestos, ni acumulación, ni mínimo', () {
      for (final s in [
        SeccionDelTorneo.puntosPorPuesto,
        SeccionDelTorneo.empateEnRonda,
        SeccionDelTorneo.acumulacion,
        SeccionDelTorneo.minimoRondas,
      ]) {
        expect(aplicaEnFormato(s, FormatoDeTorneo.eliminacion), isFalse,
            reason: s.name);
        expect(aplicaEnFormato(s, FormatoDeTorneo.liga), isTrue,
            reason: '${s.name} sí aplica a una liga');
      }
    });

    test('el método y el bote se quedan en las dos', () {
      // El método decide quién gana el partido, y el dinero cuenta igual.
      for (final f in FormatoDeTorneo.values) {
        expect(aplicaEnFormato(SeccionDelTorneo.metodo, f), isTrue);
        expect(aplicaEnFormato(SeccionDelTorneo.bote, f), isTrue);
        expect(aplicaEnFormato(SeccionDelTorneo.botePorJornada, f), isTrue);
        expect(aplicaEnFormato(SeccionDelTorneo.participantes, f), isTrue);
      }
    });

    test('la siembra solo en el cuadro', () {
      expect(aplicaEnFormato(SeccionDelTorneo.siembra, FormatoDeTorneo.liga),
          isFalse);
      expect(
          aplicaEnFormato(
              SeccionDelTorneo.siembra, FormatoDeTorneo.eliminacion),
          isTrue);
    });

    test('cada sección está decidida en los dos formatos', () {
      // Sin esto, añadir un valor al enum dejaría una sección sin criterio y el
      // editor la enseñaría —o la esconderia— por accidente.
      for (final s in SeccionDelTorneo.values) {
        for (final f in FormatoDeTorneo.values) {
          expect(() => aplicaEnFormato(s, f), returnsNormally,
              reason: '${s.name} en ${f.name}');
        }
      }
    });
  });

  group('13 · "por posición" no existe en un duelo', () {
    test('no se ofrece con eliminación, sí con liga', () {
      expect(metodosOfrecidos(FormatoDeTorneo.eliminacion),
          isNot(contains(MetodoDePuntuacion.posicion)));
      expect(metodosOfrecidos(FormatoDeTorneo.liga),
          MetodoDePuntuacion.values);
      // Y los otros tres siguen estando: no se ha vaciado la lista.
      expect(metodosOfrecidos(FormatoDeTorneo.eliminacion), hasLength(3));
    });

    test('el guardado con posición se RESUELVE por dinero, sin migrarlo', () {
      // Es el caso de Match Play CGM, creado antes de esta corrección. No se
      // reescribe el documento: se deriva. Sin migración no hay nada que salga
      // mal a medias.
      final viejo = _t(metodo: MetodoDePuntuacion.posicion);
      expect(viejo.metodo, MetodoDePuntuacion.posicion,
          reason: 'lo guardado no se toca');
      expect(metodoEfectivo(viejo), MetodoDePuntuacion.dinero);
      // Y el cuadro se resuelve con eso: gana quien más dinero sacó.
      final l = llaveDe(
          _t(participantes: const [ana, beto], metodo: MetodoDePuntuacion.posicion),
          [_r(id: 'r1', dia: 7, dinero: {ana: 300, beto: -300})]);
      expect(l.campeon, ana);
    });

    test('en una liga "por posición" sigue siendo por posición', () {
      final liga = _t(
          formato: FormatoDeTorneo.liga, metodo: MetodoDePuntuacion.posicion);
      expect(metodoEfectivo(liga), MetodoDePuntuacion.posicion);
    });

    test('los otros métodos no se tocan en ningún formato', () {
      for (final m in [
        MetodoDePuntuacion.dinero,
        MetodoDePuntuacion.scoreNeto,
        MetodoDePuntuacion.stableford,
      ]) {
        for (final f in FormatoDeTorneo.values) {
          expect(metodoEfectivo(_t(formato: f, metodo: m)), m);
        }
      }
    });
  });

  group('14 · el resumen de un cuadro dice en qué punto está', () {
    final nombres = {ana: 'Rafael', beto: 'Alan', caro: 'Caro', dani: 'Dani'};

    test('sin armar lo dice, y no enseña rondas ni posición', () {
      final r = resumenDeLlave(
          llaveDe(_t(participantes: const []), const []), nombres);
      expect(r, 'Cuadro sin armar');
    });

    test('recién armado: a quién le toca', () {
      final r = resumenDeLlave(
          llaveDe(_t(participantes: const [ana, beto]), const []), nombres);
      expect(r, 'Final · Rafael vs Alan');
    });

    test('con varios partidos abiertos dice cuántos más', () {
      final r = resumenDeLlave(llaveDe(_t(), const []), nombres);
      expect(r, contains('Semifinales'));
      expect(r, contains('y 1 partido más'));
    });

    test('terminado: el campeón', () {
      final r = resumenDeLlave(
          llaveDe(_t(participantes: const [ana, beto]),
              [_r(id: 'r1', dia: 7, dinero: {ana: 300, beto: -300})]),
          nombres);
      expect(r, 'Campeón: Rafael');
    });

    test('un empate sin resolver va PRIMERO: bloquea el cuadro', () {
      final r = resumenDeLlave(
          llaveDe(_t(), [
            _r(id: 'r1', dia: 7, dinero: {ana: 0, dani: 0}),
            _r(id: 'r2', dia: 8, dinero: {beto: 100, caro: -100}),
          ]),
          nombres);
      expect(r, startsWith('Hay que desempatar'));
      expect(r, contains('Rafael'));
    });

    test('nunca sale un id, ni con el directorio vacío', () {
      final r = resumenDeLlave(
          llaveDe(_t(participantes: const [ana, beto]), const []), const {});
      expect(r.contains(ana), isFalse);
      expect(r, contains(sinNombre));
    });
  });

  group('15 · el bote de un cuadro es del CAMPEÓN, no del líder', () {
    Torneo conBote({double entrada = 500}) => Torneo(
          id: 'tor_1',
          nombre: 'Match Play',
          formato: FormatoDeTorneo.eliminacion,
          fuente: FuenteDeRondas.marcadas,
          metodo: MetodoDePuntuacion.dinero,
          participantes: const [ana, beto, caro, dani],
          bote: BoteConfig(entrada: entrada),
        );

    test('sin campeón no cobra nadie, y se dice por qué', () {
      final t = conBote();
      final rondas = [_r(id: 'r1', dia: 7, dinero: {ana: 900, dani: -900})];
      final tabla = tablaDe(t, rondas);
      final bote = boteDe(t, tabla, campeon: llaveDe(t, rondas).campeon);
      expect(bote.total, 2000);
      expect(bote.lineas.every((l) => l.cobra == 0), isTrue);
      expect(bote.provisional, contains('gane la final'));
    });

    test('el que más dinero acumuló NO cobra si no gana la final', () {
      // Es el fallo que esto arregla: una cifra correcta a nombre de la persona
      // equivocada. Ana gana su semifinal por mucho y luego pierde la final.
      final t = conBote();
      final rondas = [
        _r(id: 's1', dia: 7, dinero: {ana: 900, dani: -900}),
        _r(id: 's2', dia: 8, dinero: {beto: 50, caro: -50}),
        _r(id: 'fin', dia: 20, dinero: {ana: -10, beto: 10}),
      ];
      final tabla = tablaDe(t, rondas);
      final llave = llaveDe(t, rondas);
      expect(llave.campeon, beto);
      // Ana lidera la tabla con mucha diferencia.
      expect(tabla.filas.first.playerId, ana);

      final bote = boteDe(t, tabla, campeon: llave.campeon);
      final cobraA = bote.lineas.firstWhere((l) => l.playerId == ana).cobra;
      final cobraB = bote.lineas.firstWhere((l) => l.playerId == beto).cobra;
      expect(cobraA, 0, reason: 'lidera la tabla, pero perdió la final');
      expect(cobraB, bote.total, reason: 'el campeón se lo lleva');
    });

    test('en una liga el bote sigue repartiéndose como siempre', () {
      // El contrapeso: la rama nueva no puede haberse comido la vieja.
      final t = Torneo(
        id: 'tor_1',
        nombre: 'Liga',
        fuente: FuenteDeRondas.marcadas,
        metodo: MetodoDePuntuacion.dinero,
        participantes: const [ana, beto],
        bote: const BoteConfig(entrada: 500),
      );
      final rondas = [_r(id: 'r1', dia: 7, dinero: {ana: 100, beto: -100})];
      final bote = boteDe(t, tablaDe(t, rondas));
      expect(bote.lineas.firstWhere((l) => l.playerId == ana).cobra,
          bote.total);
    });
  });
}
