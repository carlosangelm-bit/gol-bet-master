// ─────────────────────────────────────────────────────────────────────────────
// EL TORNEO ES UNA VISTA SOBRE RONDAS QUE YA EXISTEN
//
// La tabla se DERIVA, nunca se guarda. Es la lección del RoundResult desfasado:
// el tablero de Inicio guardó los balances al cerrar y, cuando la liquidación se
// corrigió, esos números se quedaron viejos sin avisar. Aquí no puede pasar, y
// hay un test que lo comprueba cambiando una ronda.
//
// El test que el encargo pide explícitamente —criterio 3— es el de "mejores 10
// de 20 clasifica distinto que suma simple con los MISMOS datos". Es el que
// justifica que la opción exista: si diera lo mismo, sobraría.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/home/home_screen.dart';

const ana = 'ana', beto = 'beto', caro = 'caro';

RoundResult _r({
  required String id,
  required int dia,
  List<String> quienes = const [ana, beto],
  Map<String, double> dinero = const {},
  Map<String, int> neto = const {},
  Map<String, int> stbl = const {},
  List<String> grupos = const [],
}) =>
    RoundResult(
      roundId: id,
      roundName: 'Ronda $id',
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 3, dia),
      holesPlayed: 18,
      playerIds: quienes,
      playerNames: {for (final q in quienes) q: q.toUpperCase()},
      balances: dinero,
      pairBalances: const {},
      grossByPlayer: const {},
      netByPlayer: neto,
      stablefordByPlayer: stbl,
      bettingGroupIds: grupos,
    );

Torneo _t({
  FuenteDeRondas fuente = FuenteDeRondas.rango,
  MetodoDePuntuacion metodo = MetodoDePuntuacion.posicion,
  Acumulacion acumulacion = Acumulacion.sumaSimple,
  int mejoresN = 10,
  int minimoRondas = 0,
  ReglaDeEmpate empate = ReglaDeEmpate.reparten,
  List<int> puntos = const [10, 6, 4, 2, 1],
  String? grupo,
  DateTime? desde,
  DateTime? hasta,
  List<String> roundIds = const [],
}) =>
    Torneo(
      id: 'tt', nombre: 'Torneo',
      fuente: fuente, metodo: metodo, acumulacion: acumulacion,
      mejoresN: mejoresN, minimoRondas: minimoRondas, empate: empate,
      puntosPorPuesto: puntos, bettingGroupId: grupo,
      desde: desde, hasta: hasta, roundIds: roundIds,
    );

void main() {
  _alcanzable();

  group('1 · el criterio 3: mejores N clasifica DISTINTO que suma simple', () {
    // Ana juega 20 sábados y saca 3 puntos en cada uno: 60 sumando.
    // Beto juega 10 y saca 8 en cada uno: 80 sumando... así que sumando gana
    // Beto. Se ajusta para que sumando gane ANA y con mejores 10 gane BETO,
    // que es el caso que el encargo describe: sumar premia al que más juega.
    List<RoundResult> temporada() => [
          // Ana: 20 rondas de 4 puntos → 80 sumando, 40 con las mejores 10.
          for (var i = 1; i <= 20; i++)
            _r(id: 'a$i', dia: i, quienes: const [ana], dinero: {ana: 4}),
          // Beto: 10 rondas de 7 puntos → 70 sumando, 70 con las mejores 10.
          for (var i = 1; i <= 10; i++)
            _r(id: 'b$i', dia: i, quienes: const [beto], dinero: {beto: 7}),
        ];

    test('con suma simple gana quien más juega', () {
      final tabla = tablaDe(
          _t(metodo: MetodoDePuntuacion.dinero), temporada());
      expect(tabla.filas.first.playerId, ana);
      expect(tabla.filas.first.total, 80);
      expect(tabla.filas[1].total, 70);
    });

    test('con mejores 10 de 20 gana quien mejor juega', () {
      // MISMOS datos, otra clasificación. Es lo que justifica la opción.
      final tabla = tablaDe(
          _t(
              metodo: MetodoDePuntuacion.dinero,
              acumulacion: Acumulacion.mejoresDeN,
              mejoresN: 10),
          temporada());
      expect(tabla.filas.first.playerId, beto);
      expect(tabla.filas.first.total, 70);
      expect(tabla.filas[1].total, 40, reason: 'a Ana solo le cuentan 10');
    });

    test('y se puede ver CUÁLES de las suyas contaron', () {
      // Sin esto la tabla es un número sin explicación: el jugador quiere saber
      // qué diez le contaron.
      final tabla = tablaDe(
          _t(
              metodo: MetodoDePuntuacion.dinero,
              acumulacion: Acumulacion.mejoresDeN,
              mejoresN: 10),
          temporada());
      final deAna = tabla.filas.firstWhere((f) => f.playerId == ana);
      expect(deAna.jugadas, 20);
      expect(deAna.contadas, 10);
      // Y en orden de fecha, no de puntos: la tabla cuenta la temporada.
      expect(deAna.rondas.first.fecha.isAfter(deAna.rondas.last.fecha), isTrue);
    });

    test('mejores N mayor que las jugadas no recorta nada', () {
      final tabla = tablaDe(
          _t(
              metodo: MetodoDePuntuacion.dinero,
              acumulacion: Acumulacion.mejoresDeN,
              mejoresN: 50),
          temporada());
      expect(tabla.filas.firstWhere((f) => f.playerId == ana).total, 80);
    });
  });

  group('2 · la tabla se DERIVA: si una ronda cambia, cambia', () {
    test('corregir el dinero de una ronda mueve la clasificación', () {
      // El criterio 4. No hay nada guardado que pueda quedarse viejo: se vuelve
      // a llamar y sale otra cosa.
      final antes = [
        _r(id: 'r1', dia: 1, dinero: {ana: 100, beto: -100}),
      ];
      final t = _t(metodo: MetodoDePuntuacion.dinero);
      expect(tablaDe(t, antes).filas.first.playerId, ana);

      final despues = [
        _r(id: 'r1', dia: 1, dinero: {ana: -100, beto: 100}),
      ];
      expect(tablaDe(t, despues).filas.first.playerId, beto);
    });

    test('quitar una ronda del rango la saca de la tabla', () {
      final rondas = [
        _r(id: 'r1', dia: 5, dinero: {ana: 100}),
        _r(id: 'r2', dia: 25, dinero: {ana: 100}),
      ];
      final t = _t(hasta: DateTime(2026, 3, 10));
      expect(tablaDe(t, rondas).rondas, 1);
    });
  });

  group('3 · las fuentes de rondas', () {
    final rondas = [
      _r(id: 'r1', dia: 5, dinero: {ana: 1}, grupos: const ['viernes']),
      _r(id: 'r2', dia: 15, dinero: {ana: 1}, grupos: const ['viernes']),
      _r(id: 'r3', dia: 25, dinero: {ana: 1}, grupos: const ['otro']),
      _r(id: 'r4', dia: 28, dinero: {ana: 1}),
    ];

    test('manual: solo las marcadas', () {
      // Se compara como CONJUNTO: rondasDelTorneo es un filtro y no promete
      // orden —ordenar es trabajo de tablaDe—. Fijar el orden aquí ataría el
      // test a un detalle que la función no garantiza.
      final t = _t(fuente: FuenteDeRondas.manual, roundIds: const ['r1', 'r3']);
      expect(rondasDelTorneo(t, rondas).map((r) => r.roundId).toSet(),
          {'r1', 'r3'});
    });

    test('rango: todas las del tramo, del grupo que sean', () {
      final t = _t(
          fuente: FuenteDeRondas.rango,
          desde: DateTime(2026, 3, 10),
          hasta: DateTime(2026, 3, 26));
      expect(rondasDelTorneo(t, rondas).map((r) => r.roundId).toSet(),
          {'r2', 'r3'});
    });

    test('el "hasta" incluye el día entero', () {
      // Una ronda de la mañana del 25 no puede quedar fuera de un torneo que
      // llega "hasta el 25".
      final t = _t(
          fuente: FuenteDeRondas.rango, hasta: DateTime(2026, 3, 25));
      expect(rondasDelTorneo(t, rondas).map((r) => r.roundId), contains('r3'));
    });

    test('grupo: solo las de ese grupo guardado', () {
      final t = _t(fuente: FuenteDeRondas.grupo, grupo: 'viernes');
      expect(rondasDelTorneo(t, rondas).map((r) => r.roundId).toSet(),
          {'r1', 'r2'});
    });

    test('grupo Y rango a la vez, que es el uso real', () {
      // "Todas las de Viernes CGM entre marzo y noviembre".
      final t = _t(
          fuente: FuenteDeRondas.grupo,
          grupo: 'viernes',
          desde: DateTime(2026, 3, 10));
      expect(rondasDelTorneo(t, rondas).map((r) => r.roundId).toSet(), {'r2'});
    });

    test('una ronda sin grupo guardado no entra en un torneo de grupo', () {
      final t = _t(fuente: FuenteDeRondas.grupo, grupo: 'viernes');
      expect(rondasDelTorneo(t, rondas).map((r) => r.roundId),
          isNot(contains('r4')));
    });
  });

  group('4 · los métodos de puntuación', () {
    final rondas = [
      _r(
          id: 'r1', dia: 1,
          quienes: const [ana, beto, caro],
          dinero: {ana: 200, beto: -50, caro: -150},
          neto: {ana: 70, beto: 75, caro: 80},
          stbl: {ana: 40, beto: 36, caro: 30}),
    ];

    test('por posición: la tabla de puntos, no el dinero', () {
      final tabla = tablaDe(_t(metodo: MetodoDePuntuacion.posicion), rondas);
      expect(tabla.filas.map((f) => f.total).toList(), [10, 6, 4]);
      expect(tabla.filas.first.playerId, ana);
    });

    test('el puesto que se sale de la tabla no puntúa', () {
      final tabla = tablaDe(
          _t(metodo: MetodoDePuntuacion.posicion, puntos: const [10, 6]),
          rondas);
      expect(tabla.filas.last.total, 0);
    });

    test('por dinero: los puntos SON el dinero, y perder resta', () {
      final tabla = tablaDe(_t(metodo: MetodoDePuntuacion.dinero), rondas);
      expect(tabla.filas.first.total, 200);
      expect(tabla.filas.last.total, -150);
    });

    test('por score neto: MENOS es mejor y la tabla se ordena al revés', () {
      // El error fácil: ordenar todos los métodos igual. Aquí el primero es el
      // del número más BAJO.
      final tabla = tablaDe(_t(metodo: MetodoDePuntuacion.scoreNeto), rondas);
      expect(tabla.filas.first.playerId, ana);
      expect(tabla.filas.first.total, 70);
      expect(tabla.filas.last.total, 80);
    });

    test('por Stableford: más es mejor', () {
      final tabla = tablaDe(_t(metodo: MetodoDePuntuacion.stableford), rondas);
      expect(tabla.filas.first.playerId, ana);
      expect(tabla.filas.first.total, 40);
    });

    test('una ronda sin el score no se puntúa, y se DICE', () {
      // El caso de las rondas cerradas antes de que RoundResult guardara el
      // score. Una tabla corta se lee como una tabla, no como un dato que falta.
      final sinScore = [_r(id: 'x', dia: 1, dinero: {ana: 10})];
      final tabla = tablaDe(_t(metodo: MetodoDePuntuacion.stableford), sinScore);
      expect(tabla.rondas, 0);
      expect(tabla.rondasSinDato, 1);
      expect(tabla.vacia, isTrue);
    });

    test('y por dinero esa misma ronda sí cuenta', () {
      // El contrapeso: el problema es del dato que falta, no de la ronda.
      final sinScore = [_r(id: 'x', dia: 1, dinero: {ana: 10})];
      final tabla = tablaDe(_t(metodo: MetodoDePuntuacion.dinero), sinScore);
      expect(tabla.rondas, 1);
      expect(tabla.rondasSinDato, 0);
    });
  });

  group('5 · los empates de una ronda', () {
    final empatados = [
      _r(
          id: 'r1', dia: 1,
          quienes: const [ana, beto, caro],
          dinero: {ana: 100, beto: 100, caro: -200}),
    ];

    test('reparten: la suma de puntos de la ronda no cambia', () {
      // Es lo que hace que repartir sea lo estándar: 10 y 6 entre dos son 8 y 8,
      // así que la ronda sigue repartiendo 10+6+4 = 20.
      final tabla = tablaDe(
          _t(metodo: MetodoDePuntuacion.posicion, empate: ReglaDeEmpate.reparten),
          empatados);
      expect(tabla.filas.where((f) => f.total == 8), hasLength(2));
      expect(tabla.filas.fold(0.0, (s, f) => s + f.total), 20);
    });

    test('mejor puesto: reparte más puntos de los que hay', () {
      final tabla = tablaDe(
          _t(
              metodo: MetodoDePuntuacion.posicion,
              empate: ReglaDeEmpate.mejorPuesto),
          empatados);
      expect(tabla.filas.where((f) => f.total == 10), hasLength(2));
      expect(tabla.filas.fold(0.0, (s, f) => s + f.total), 24);
    });

    test('peor puesto: reparte menos', () {
      final tabla = tablaDe(
          _t(
              metodo: MetodoDePuntuacion.posicion,
              empate: ReglaDeEmpate.peorPuesto),
          empatados);
      expect(tabla.filas.where((f) => f.total == 6), hasLength(2));
    });

    test('los empatados comparten PUESTO en la ronda', () {
      final tabla = tablaDe(_t(metodo: MetodoDePuntuacion.posicion), empatados);
      final deAna = tabla.filas.firstWhere((f) => f.playerId == ana);
      final deBeto = tabla.filas.firstWhere((f) => f.playerId == beto);
      expect(deAna.rondas.single.puesto, 1);
      expect(deBeto.rondas.single.puesto, 1);
      expect(tabla.filas.firstWhere((f) => f.playerId == caro)
          .rondas.single.puesto, 3,
          reason: 'el tercero es tercero, no segundo');
    });

    test('y comparten puesto en la TABLA si empatan en el total', () {
      final tabla = tablaDe(_t(metodo: MetodoDePuntuacion.posicion), empatados);
      expect(tabla.filas[0].puesto, 1);
      expect(tabla.filas[1].puesto, 1);
      expect(tabla.filas[2].puesto, 3);
    });
  });

  group('6 · el mínimo de rondas', () {
    final rondas = [
      for (var i = 1; i <= 5; i++)
        _r(id: 'a$i', dia: i, quienes: const [ana], dinero: {ana: 10}),
      _r(id: 'b1', dia: 1, quienes: const [beto], dinero: {beto: 100}),
    ];

    test('sin mínimo, todos en la tabla', () {
      final tabla = tablaDe(_t(metodo: MetodoDePuntuacion.dinero), rondas);
      expect(tabla.filas, hasLength(2));
      expect(tabla.bajoMinimo, isEmpty);
    });

    test('con mínimo 3, el de una ronda sale APARTE, no desaparece', () {
      // Esconderlo sería peor: quien jugó una ronda quiere ver su ronda.
      final tabla = tablaDe(
          _t(metodo: MetodoDePuntuacion.dinero, minimoRondas: 3), rondas);
      expect(tabla.filas.map((f) => f.playerId), [ana]);
      expect(tabla.bajoMinimo.map((f) => f.playerId), [beto]);
      expect(tabla.bajoMinimo.single.total, 100,
          reason: 'y con su total, que es el dato que quiere ver');
    });

    test('el mínimo cuenta rondas JUGADAS, no las que suman', () {
      // Con mejores N las peores no suman, pero se jugaron. Si el mínimo mirara
      // las que suman, subir mejoresN cambiaría quién clasifica.
      final tabla = tablaDe(
          _t(
              metodo: MetodoDePuntuacion.dinero,
              acumulacion: Acumulacion.mejoresDeN,
              mejoresN: 2,
              minimoRondas: 5),
          rondas);
      expect(tabla.filas.map((f) => f.playerId), [ana]);
      expect(tabla.filas.single.contadas, 2);
      expect(tabla.filas.single.jugadas, 5);
    });
  });

  group('7 · las combinaciones sin sentido se atenúan con su motivo', () {
    test('mejores N en un torneo de una ronda', () {
      expect(motivoSinAcumulacion(Acumulacion.mejoresDeN, 1),
          contains('una sola ronda'));
      expect(motivoSinAcumulacion(Acumulacion.mejoresDeN, 5), isNull);
      expect(motivoSinAcumulacion(Acumulacion.sumaSimple, 1), isNull);
    });

    test('un mínimo mayor que las rondas dejaría la tabla vacía', () {
      expect(motivoSinMinimo(10, 5), contains('nadie saldría'));
      expect(motivoSinMinimo(3, 5), isNull);
    });

    test('puntuar por score sin rondas que lo tengan guardado', () {
      final sinScore = [_r(id: 'x', dia: 1, dinero: {ana: 1})];
      final conScore = [_r(id: 'y', dia: 2, neto: {ana: 70}, stbl: {ana: 36})];

      expect(motivoSinMetodo(MetodoDePuntuacion.stableford, sinScore),
          contains('Ninguna'));
      expect(motivoSinMetodo(MetodoDePuntuacion.stableford, conScore), isNull);
      // Y con algunas sí y otras no, se dice cuántas.
      expect(
          motivoSinMetodo(
              MetodoDePuntuacion.stableford, [...sinScore, ...conScore]),
          contains('Solo 1 de 2'));
    });

    test('los métodos que no necesitan score nunca se atenúan', () {
      final sinScore = [_r(id: 'x', dia: 1, dinero: {ana: 1})];
      for (final m in [MetodoDePuntuacion.dinero, MetodoDePuntuacion.posicion]) {
        expect(motivoSinMetodo(m, sinScore), isNull, reason: m.label);
      }
    });
  });

  group('8 · el viaje a JSON', () {
    test('conserva las cuatro decisiones', () {
      final t = Torneo(
        id: 'x', nombre: 'Temporada 26',
        fuente: FuenteDeRondas.grupo,
        bettingGroupId: 'viernes',
        desde: DateTime(2026, 3, 1),
        hasta: DateTime(2026, 11, 30),
        metodo: MetodoDePuntuacion.stableford,
        acumulacion: Acumulacion.mejoresDeN,
        mejoresN: 12,
        minimoRondas: 6,
        empate: ReglaDeEmpate.peorPuesto,
        puntosPorPuesto: const [15, 10, 7, 5, 3, 1],
      );
      final v = Torneo.fromJson(Map<String, dynamic>.from(t.toJson()));
      expect(v.fuente, FuenteDeRondas.grupo);
      expect(v.bettingGroupId, 'viernes');
      expect(v.metodo, MetodoDePuntuacion.stableford);
      expect(v.acumulacion, Acumulacion.mejoresDeN);
      expect((v.mejoresN, v.minimoRondas), (12, 6));
      expect(v.empate, ReglaDeEmpate.peorPuesto);
      expect(v.puntosPorPuesto, const [15, 10, 7, 5, 3, 1]);
      expect(v.desde, DateTime(2026, 3, 1));
    });

    test('un torneo por defecto no escribe lo que no se tocó', () {
      final j = const Torneo(id: 'x', nombre: 'T').toJson();
      expect(j.containsKey('minimoRondas'), isFalse);
      expect(j.containsKey('cerrado'), isFalse);
      expect(j.containsKey('roundIds'), isFalse);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Y EL TORNEO ES ALCANZABLE
//
// Tres veces en esta sesión escribí código correcto que nunca llegó a ser
// alcanzable desde la app. Este test existe por eso: comprueba que hay una
// puerta desde Inicio y que la pantalla se abre y pinta la tabla.
// ─────────────────────────────────────────────────────────────────────────────
void _alcanzable() {
  Future<void> montarInicio(WidgetTester tester,
      {List<Torneo> torneos = const [], List<RoundResult> res = const []}) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RoundProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => HandicapProvider()),
        ChangeNotifierProvider<PerfilProvider>.value(
            value: PerfilProvider()..sembrar(res)),
        ChangeNotifierProvider(create: (_) => UserProfileProvider()),
        ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
        ChangeNotifierProvider<TorneoProvider>.value(
            value: TorneoProvider()..sembrar(torneos)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 150));
  }

  group('9 · se llega desde Inicio y la tabla se pinta', () {
    testWidgets('hay una puerta en la cabecera', (tester) async {
      await montarInicio(tester);
      expect(find.byTooltip('Torneos'), findsOneWidget,
          reason: 'sin puerta, el torneo es código inalcanzable');
    });

    testWidgets('y abre la pantalla de torneos', (tester) async {
      await montarInicio(tester);
      await tester.tap(find.byTooltip('Torneos'));
      await tester.pumpAndSettle();
      expect(find.text('Torneos'), findsWidgets);
      expect(find.textContaining('Ningún torneo todavía'), findsOneWidget);
    });

    testWidgets('con un torneo, la tabla clasifica y se puede abrir',
        (tester) async {
      final res = [
        _r(id: 'r1', dia: 1, quienes: const [ana, beto],
            dinero: {ana: 100, beto: -100}),
        _r(id: 'r2', dia: 2, quienes: const [ana, beto],
            dinero: {ana: -50, beto: 50}),
      ];
      await montarInicio(tester,
          torneos: [_t(metodo: MetodoDePuntuacion.dinero)], res: res);
      await tester.tap(find.byTooltip('Torneos'));
      await tester.pumpAndSettle();

      expect(find.text('Torneo'), findsWidgets);
      expect(find.textContaining('2 rondas'), findsWidgets);
      // Ana va +50, Beto −50: la tarjeta lo dice sin entrar.
      expect(find.textContaining('Va ANA'), findsOneWidget);

      await tester.tap(find.textContaining('Va ANA'));
      await tester.pumpAndSettle();
      // Y dentro, las reglas a la vista y los dos jugadores.
      expect(find.text('CÓMO SE PUNTÚA'), findsOneWidget);
      expect(find.text('ANA'), findsWidgets);
      expect(find.text('BETO'), findsWidgets);
    });
  });
}
