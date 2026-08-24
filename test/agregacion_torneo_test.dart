// ─────────────────────────────────────────────────────────────────────────────
// LA AGREGACIÓN DEL TORNEO — qué rondas cuentan, y desde dónde
//
// La tabla sale de tablaDe(t, resultados), y esos resultados son los del que
// mira. El resultado de una ronda se escribe al CERRARLA, en la colección de
// quien cierra, y cerrar una ronda en vivo está reservado al dueño.
//
// De ahí sale la propiedad que hace que esto funcione sin colección nueva: si el
// organizador es dueño de las rondas de su torneo, sus resultados caen donde la
// tabla los busca. Lo que se prueba aquí es lo que se puede probar sin red: que
// la tabla agrega N rondas de N grupos distintos, y que la marca es lo que
// decide —no quién jugó—.
//
// La frontera de permisos se prueba con el emulador, en test_rules/run.mjs
// bloque 12.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/models/torneo_publicado.dart';
import 'package:golf_bet_master/models/torneo_seguido.dart';

/// Un grupo de cuatro con su ronda cerrada, como la que cierra el organizador.
RoundResult _grupo(int n, {String torneo = 'tor_1'}) {
  final gente = [for (var i = 0; i < 4; i++) 'pid_g${n}_$i'];
  return RoundResult(
    roundId: 'ronda_g$n',
    roundName: 'Grupo $n',
    courseName: 'Los Encinos',
    playedAt: DateTime(2026, 5, 10),
    holesPlayed: 18,
    playerIds: gente,
    playerNames: {for (final g in gente) g: g.toUpperCase()},
    // El primero de cada grupo gana; los otros tres pagan.
    balances: {
      for (var i = 0; i < gente.length; i++) gente[i]: i == 0 ? 300.0 : -100.0
    },
    pairBalances: const {},
    grossByPlayer: const {},
    netByPlayer: const {},
    stablefordByPlayer: const {},
    bettingGroupIds: const [],
    torneoIds: [torneo],
  );
}

Torneo _t({List<String>? participantes, double entrada = 0}) => Torneo(
      id: 'tor_1',
      nombre: 'Torneo del club',
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.dinero,
      participantes: participantes ??
          [for (var n = 1; n <= 5; n++) for (var i = 0; i < 4; i++) 'pid_g${n}_$i'],
      bote: BoteConfig(entrada: entrada),
    );

void main() {
  group('1 · cinco grupos, veinte personas: la tabla los agrega', () {
    final rondas = [for (var n = 1; n <= 5; n++) _grupo(n)];

    test('las cinco rondas cuentan', () {
      final tabla = tablaDe(_t(), rondas);
      expect(tabla.rondas, 5);
      // Y los veinte están, cada uno con su cifra.
      expect(tabla.filas.length + tabla.bajoMinimo.length, 20);
    });

    test('los cinco ganadores empatan arriba, con 300 cada uno', () {
      final tabla = tablaDe(_t(), rondas);
      final arriba = tabla.filas.where((f) => f.total == 300);
      expect(arriba, hasLength(5));
      expect(arriba.every((f) => f.puesto == 1), isTrue,
          reason: 'cinco que ganaron su grupo comparten el primer puesto');
    });

    test('la suma de la tabla es cero: nadie inventa dinero', () {
      final tabla = tablaDe(_t(), rondas);
      final suma = [...tabla.filas, ...tabla.bajoMinimo]
          .fold(0.0, (s, f) => s + f.total);
      expect(suma, closeTo(0, 0.001));
    });

    test('una ronda sin cerrar no está: la tabla solo ve resultados', () {
      // Es la propiedad que hace que "cerrar" sea la puerta. Una ronda a medio
      // jugar no tiene RoundResult, así que no puede contar.
      final tabla = tablaDe(_t(), rondas.take(3).toList());
      expect(tabla.rondas, 3);
    });
  });

  group('2 · la MARCA decide, no quién jugó', () {
    test('una ronda de otro torneo no entra', () {
      final mias = [_grupo(1), _grupo(2)];
      final ajena = _grupo(3, torneo: 'otro_torneo');
      final tabla = tablaDe(_t(), [...mias, ajena]);
      expect(tabla.rondas, 2);
      // Su gente SÍ aparece —están inscritos— pero con CERO: lo que no entra es
      // el dinero de una ronda que no es de este torneo. Aparecer inscrito y no
      // haber jugado es un estado legítimo; que te cuenten una ronda ajena, no.
      final delTres = [...tabla.filas, ...tabla.bajoMinimo]
          .where((f) => f.playerId.startsWith('pid_g3'));
      expect(delTres, hasLength(4));
      expect(delTres.every((f) => f.total == 0), isTrue,
          reason: 'una ronda de otro torneo movió cifras aquí');
      expect(delTres.every((f) => f.jugadas == 0), isTrue);
    });

    test('una ronda sin marca tampoco', () {
      final sinMarca = RoundResult(
        roundId: 'suelta',
        roundName: 'Sábado cualquiera',
        courseName: 'C',
        playedAt: DateTime(2026, 5, 10),
        holesPlayed: 18,
        playerIds: const ['pid_g1_0'],
        playerNames: const {'pid_g1_0': 'A'},
        balances: const {'pid_g1_0': 5000},
        pairBalances: const {},
        grossByPlayer: const {},
        netByPlayer: const {},
        stablefordByPlayer: const {},
        bettingGroupIds: const [],
      );
      final tabla = tablaDe(_t(), [_grupo(1), sinMarca]);
      expect(tabla.rondas, 1);
      // Y los 5000 no se cuelan en el total de nadie.
      expect(tabla.filas.every((f) => f.total.abs() <= 300), isTrue);
    });

    test('una ronda marcada para DOS torneos cuenta en los dos', () {
      final doble = RoundResult(
        roundId: 'doble',
        roundName: 'Cuenta doble',
        courseName: 'C',
        playedAt: DateTime(2026, 5, 11),
        holesPlayed: 18,
        playerIds: const ['pid_g1_0', 'pid_g1_1'],
        playerNames: const {'pid_g1_0': 'A', 'pid_g1_1': 'B'},
        balances: const {'pid_g1_0': 100, 'pid_g1_1': -100},
        pairBalances: const {},
        grossByPlayer: const {},
        netByPlayer: const {},
        stablefordByPlayer: const {},
        bettingGroupIds: const [],
        torneoIds: const ['tor_1', 'tor_2'],
      );
      expect(rondasDelTorneo(_t(), [doble]), hasLength(1));
      final otro = Torneo(
          id: 'tor_2',
          nombre: 'El otro',
          fuente: FuenteDeRondas.marcadas,
          participantes: const ['pid_g1_0', 'pid_g1_1']);
      expect(rondasDelTorneo(otro, [doble]), hasLength(1));
    });
  });

  group('4 · LA LIGA: solo cuenta lo publicado por gente inscrita', () {
    // Es la comprobación que la regla de Firestore NO puede hacer —no sabe si
    // quien publica jugó esa ronda— así que se hace aquí, donde sí está la lista
    // de inscritos. Quitarla dejaría que cualquiera con el enlace metiera una
    // fila en la tabla de otro.
    RoundResult publicado(String roundId, String pid, double dinero) =>
        RoundResult(
          roundId: roundId,
          roundName: 'Ronda de $pid',
          courseName: 'C',
          playedAt: DateTime(2026, 5, 12),
          holesPlayed: 18,
          playerIds: [pid],
          playerNames: {pid: pid},
          balances: {pid: dinero},
          pairBalances: const {},
          grossByPlayer: const {},
          netByPlayer: const {},
          stablefordByPlayer: const {},
          bettingGroupIds: const [],
          torneoIds: const ['tor_1'],
        );

    // El directorio del organizador: id de jugador → nombre. Es lo que permite
    // emparejar, porque el uid de la cuenta de quien publica NO es un id de
    // jugador y compararlos descartaba todo.
    const dir = {
      'pid_luis': 'Luis Herrera',
      'pid_ana': 'Ana Ruiz',
      'pid_a': 'Rafael',
      'pid_b': 'Alan',
      'pid_c': 'Memo',
    };

    test('el resultado de un inscrito cuenta, emparejado por NOMBRE', () {
      final t = _t(participantes: const ['pid_luis', 'pid_ana']);
      final buenos = resultadosQueCuentan(
          t,
          [
            ResultadoPublicado(
              jugadorNombre: 'Luis Herrera',
              resultado: publicado('r1', 'pid_luis', 100)
            ),
          ],
          nombres: dir);
      expect(buenos, hasLength(1));
    });

    test('y da igual cómo lo escriba: acentos, mayúsculas y espacios', () {
      final t = _t(participantes: const ['pid_luis']);
      for (final variante in [
        'luis herrera',
        '  LUIS   HERRERA ',
        'Luís Herrera',
      ]) {
        final buenos = resultadosQueCuentan(
            t,
            [ResultadoPublicado(jugadorNombre: variante, resultado: publicado('r', 'pid_luis', 1))],
            nombres: dir);
        expect(buenos, hasLength(1), reason: variante);
      }
    });

    test('el de un NO inscrito se descarta', () {
      final t = _t(participantes: const ['pid_luis']);
      final buenos = resultadosQueCuentan(
          t,
          [
            ResultadoPublicado(
              jugadorNombre: 'Carlos Colado',
              resultado: publicado('r2', 'pid_x', 9999)
            ),
          ],
          nombres: dir);
      expect(buenos, isEmpty);
    });

    test('sin nombre reclamado se descarta: no hay con qué emparejar', () {
      final t = _t(participantes: const ['pid_luis']);
      final buenos = resultadosQueCuentan(
          t,
          [ResultadoPublicado(jugadorNombre: '', resultado: publicado('r', 'pid_luis', 1))],
          nombres: dir);
      expect(buenos, isEmpty);
    });

    test('sin lista de inscritos NO cuenta ninguno', () {
      final t = _t(participantes: const []);
      final buenos = resultadosQueCuentan(
          t,
          [ResultadoPublicado(jugadorNombre: 'Luis Herrera', resultado: publicado('r1', 'pid_luis', 1))],
          nombres: dir);
      expect(buenos, isEmpty);
    });

    test('sin directorio tampoco: no se puede resolver ningún nombre', () {
      // El organizador sin directorio cargado no puede emparejar nada, y aceptar
      // lo que llegue sería peor que no aceptar nada.
      final t = _t(participantes: const ['pid_luis']);
      expect(
          resultadosQueCuentan(t, [
            ResultadoPublicado(jugadorNombre: 'Luis Herrera', resultado: publicado('r', 'pid_luis', 1))
          ]),
          isEmpty);
    });

    test('la liga completa: cada uno cierra la suya y la tabla las cuenta', () {
      final t = _t(participantes: const ['pid_a', 'pid_b', 'pid_c']);
      final publicados = [
        ResultadoPublicado(jugadorNombre: 'Rafael', resultado: publicado('ra', 'pid_a', 100)),
        ResultadoPublicado(jugadorNombre: 'Alan', resultado: publicado('rb', 'pid_b', 50)),
        ResultadoPublicado(jugadorNombre: 'Memo', resultado: publicado('rc', 'pid_c', -150)),
      ];
      final tabla =
          tablaDe(t, resultadosQueCuentan(t, publicados, nombres: dir));
      expect(tabla.rondas, 3);
      expect(tabla.filas.first.playerId, 'pid_a');
    });

    test('un uid de cuenta NUNCA cuenta como inscrito', () {
      // Era el fallo: escritoPor es un uid y participantes son ids de jugador, así
      // que compararlos descartaba TODO en silencio. Este test lo fija.
      final t = _t(participantes: const ['pid_luis']);
      final buenos = resultadosQueCuentan(
          t,
          [
            ResultadoPublicado(
              jugadorNombre: 'uid_firebase_abc123',
              resultado: publicado('r', 'pid_luis', 1)
            )
          ],
          nombres: dir);
      expect(buenos, isEmpty);
    });
  });

  group('5 · unir sin contar dos veces', () {
    RoundResult r(String id, String pid, double d) => RoundResult(
          roundId: id,
          roundName: id,
          courseName: 'C',
          playedAt: DateTime(2026, 5, 12),
          holesPlayed: 18,
          playerIds: [pid],
          playerNames: {pid: pid},
          balances: {pid: d},
          pairBalances: const {},
          grossByPlayer: const {},
          netByPlayer: const {},
          stablefordByPlayer: const {},
          bettingGroupIds: const [],
          torneoIds: const ['tor_1'],
        );

    test('una ronda que está en las dos listas cuenta UNA vez', () {
      // Pasa de verdad: el organizador cierra una ronda suya y además está
      // publicada porque alguien la sigue. Sin deduplicar, el dinero saldría al
      // doble.
      final propios = [r('compartida', 'pid_a', 100)];
      final publicados = [r('compartida', 'pid_a', 100), r('otra', 'pid_b', 50)];
      final unidos = resultadosUnidos(propios, publicados);
      expect(unidos, hasLength(2));
      expect(unidos.where((x) => x.roundId == 'compartida'), hasLength(1));
    });

    test('gana lo PROPIO: es lo que el dueño cerró con sus manos', () {
      final propios = [r('x', 'pid_a', 100)];
      final publicados = [r('x', 'pid_a', 999)];
      final unidos = resultadosUnidos(propios, publicados);
      expect(unidos, hasLength(1));
      expect(unidos.first.balances['pid_a'], 100);
    });

    test('con una lista vacía devuelve la otra', () {
      expect(resultadosUnidos(const [], [r('a', 'p', 1)]), hasLength(1));
      expect(resultadosUnidos([r('a', 'p', 1)], const []), hasLength(1));
      expect(resultadosUnidos(const [], const []), isEmpty);
    });
  });

  group('6 · el torneo seguido es una REFERENCIA, no una copia', () {
    test('lleva lo justo para marcar y publicar', () {
      final s = TorneoSeguido(
          torneoId: 'tor_1',
          token: 'tok_abc',
          ownerUid: 'uid_org',
          nombre: 'Copa de Primavera',
          desde: DateTime(2026, 3, 1),
          jugadorNombre: 'Luis Herrera');
      expect(s.utilizable, isTrue);
      final ida = TorneoSeguido.fromJson(s.toJson());
      expect(ida.token, 'tok_abc');
      expect(ida.ownerUid, 'uid_org');
      expect(ida.nombre, 'Copa de Primavera');
      expect(ida.jugadorNombre, 'Luis Herrera');
    });

    test('SIN nombre reclamado no es utilizable', () {
      // Y no es una restricción técnica: sin nombre el resultado no se puede
      // emparejar con ningún inscrito, así que publicarlo sería escribir algo que
      // nadie va a contar. Mejor no ofrecerlo.
      final sinNombre = TorneoSeguido(
          torneoId: 'tor_1',
          token: 'tok',
          ownerUid: 'uid',
          nombre: 'X',
          desde: DateTime(2026, 1, 1));
      expect(sinNombre.utilizable, isFalse);
    });

    test('sin token o sin dueño NO es utilizable: no se puede publicar', () {
      final sinToken = TorneoSeguido(
          torneoId: 'tor_1',
          token: '',
          ownerUid: 'uid',
          nombre: 'X',
          desde: DateTime(2026, 1, 1),
          jugadorNombre: 'Luis');
      expect(sinToken.utilizable, isFalse);
    });

    test('el id del documento del resultado es determinista', () {
      // Es lo que hace que corregir una ronda actualice en vez de duplicar, y la
      // regla lo exige.
      const r = ResultadoDeTorneo(
          torneoId: 'tor_1',
          roundId: 'ronda_9',
          token: 'tok',
          torneoOwnerUid: 'uid',
          escritoPor: 'yo',
          resultado: {});
      expect(r.docId, 'tor_1_ronda_9');
    });
  });

  group('7 · el id del torneo viaja en la instantánea, y es la identidad', () {
    // Sin esto se usaba el token como identidad de un torneo seguido, y la tabla
    // del organizador consulta por SU id: lo escrito y lo consultado no
    // coincidían. Se localizó leyendo el código, antes de que apareciera.
    test('la instantánea lleva el id, y no engorda si está vacío', () {
      final t = Torneo(
          id: 'tor_liga_2026',
          nombre: 'Copa de Primavera',
          fuente: FuenteDeRondas.marcadas,
          participantes: const ['pid_a']);
      final tabla = tablaDe(t, const []);
      final copia = TorneoPublicado.desde(
        token: 'tok_x',
        ownerUid: 'uid_org',
        torneo: t,
        tabla: tabla,
        bote: boteDe(t, tabla),
        jornadas: botesPorJornada(t, tabla),
        cuando: DateTime(2026, 4, 1),
      );
      expect(copia.torneoId, 'tor_liga_2026');
      expect(copia.toJson()['torneoId'], 'tor_liga_2026');
      // Y sobrevive el viaje, que es lo que el seguidor necesita.
      expect(TorneoPublicado.fromJson('tok_x', copia.toJson()).torneoId,
          'tor_liga_2026');
    });

    test('una instantánea vieja llega sin id, y se trata como tal', () {
      // No se inventa nada: sin id, seguir crearía una referencia que no
      // funcionaría, así que la pantalla dice qué hace falta.
      final vieja = TorneoPublicado.fromJson('tok', const {'nombre': 'X'});
      expect(vieja.torneoId, isEmpty);
    });

    test('el id del torneo NO es un id de jugador ni un roundId', () {
      // La regla de qué no va en la instantánea sigue en pie: lo excluido son los
      // ids que identifican PERSONAS y RONDAS. Este es el id del propio objeto
      // que se comparte.
      final t = Torneo(
          id: 'tor_1',
          nombre: 'T',
          fuente: FuenteDeRondas.marcadas,
          participantes: const ['pid_secreto']);
      final rs = [
        RoundResult(
          roundId: 'ronda_secreta',
          roundName: 'Sábado',
          courseName: 'C',
          playedAt: DateTime(2026, 3, 7),
          holesPlayed: 18,
          playerIds: const ['pid_secreto'],
          playerNames: const {'pid_secreto': 'ANA'},
          balances: const {'pid_secreto': 100},
          pairBalances: const {},
          grossByPlayer: const {},
          netByPlayer: const {},
          stablefordByPlayer: const {},
          bettingGroupIds: const [],
          torneoIds: const ['tor_1'],
        )
      ];
      final tabla = tablaDe(t, rs, nombres: const {'pid_secreto': 'ANA'});
      final json = TorneoPublicado.desde(
        token: 'tok',
        ownerUid: 'uid',
        torneo: t,
        tabla: tabla,
        bote: boteDe(t, tabla),
        jornadas: botesPorJornada(t, tabla),
        cuando: DateTime(2026, 4, 1),
      ).toJson().toString();
      expect(json.contains('tor_1'), isTrue, reason: 'el id del torneo sí va');
      expect(json.contains('pid_secreto'), isFalse);
      expect(json.contains('ronda_secreta'), isFalse);
    });
  });

  group('3 · a escala de 25 grupos', () {
    test('cien personas, veinticinco rondas, y la tabla cuadra', () {
      final rondas = [for (var n = 1; n <= 25; n++) _grupo(n)];
      final t = _t(participantes: [
        for (var n = 1; n <= 25; n++)
          for (var i = 0; i < 4; i++) 'pid_g${n}_$i'
      ]);
      final tabla = tablaDe(t, rondas);
      expect(tabla.rondas, 25);
      expect(tabla.filas.length + tabla.bajoMinimo.length, 100);
      final suma = [...tabla.filas, ...tabla.bajoMinimo]
          .fold(0.0, (s, f) => s + f.total);
      expect(suma, closeTo(0, 0.001));
    });

    test('con bote, cada uno aporta una vez y el total es el que puso', () {
      // Cien personas a $200 son $20.000, y ni un peso más: el bote se cobra por
      // INSCRITO, no por ronda jugada.
      final t = _t(
          participantes: [
            for (var n = 1; n <= 25; n++)
              for (var i = 0; i < 4; i++) 'pid_g${n}_$i'
          ],
          entrada: 200);
      final rondas = [for (var n = 1; n <= 25; n++) _grupo(n)];
      final bote = boteDe(t, tablaDe(t, rondas));
      expect(bote.total, closeTo(20000, 0.001));
      expect(bote.lineas, hasLength(100));
      expect(bote.lineas.every((l) => l.aporta == 200), isTrue);
    });

    test('y un inscrito que no jugó sigue en la lista', () {
      // Con cien personas siempre falta alguien, y no verse después de pagar la
      // entrada sería lo peor que puede hacer esta pantalla.
      final t = _t(participantes: [
        for (var i = 0; i < 4; i++) 'pid_g1_$i',
        'pid_no_vino',
      ]);
      final tabla = tablaDe(t, [_grupo(1)]);
      final ids =
          [...tabla.filas, ...tabla.bajoMinimo].map((f) => f.playerId);
      expect(ids, contains('pid_no_vino'));
    });
  });
}
