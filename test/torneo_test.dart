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
import 'package:golf_bet_master/providers/organizador_provider.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/home/home_screen.dart';
import 'package:golf_bet_master/screens/torneos/torneos_screen.dart';

const ana = 'ana', beto = 'beto', caro = 'caro', dani = 'dani';

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
  _pantallaLeeLoGuardado();

  _participantes();

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
        // La marca de organizador: el logo de Inicio la consulta, así que un
        // harness sin ella no monta. Sembrada en false —una cuenta normal—
        // porque lo que estos tests miran es la app del jugador.
        ChangeNotifierProvider<OrganizadorProvider>(
            create: (_) => OrganizadorProvider()..sembrar(false)),
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

// ─────────────────────────────────────────────────────────────────────────────
// PARTICIPA QUIEN SE INSCRIBE, NO QUIEN JUEGUE
//
// La raíz del problema de los 55 participantes: el modelo asumía "participa
// quien juegue". Con un bote de por medio deja de ser cosmético — poner $500 es
// una decisión, no algo que te pase por jugar un sábado.
//
// Y el mínimo de rondas no lo resolvía porque filtra por COMPORTAMIENTO cuando
// hacía falta filtrar por DECISIÓN. Ahora significa lo que quería decir: cuántas
// rondas hay que jugar para optar al premio.
//
// La decisión de fondo, y es la que estos tests fijan: RESULTADOS sin lista se
// pueden enseñar —son útiles— pero DINERO sin lista no. Apuntar $500 a nombre de
// trece personas que nunca dijeron que entraban es peor que no apuntar nada.
// ─────────────────────────────────────────────────────────────────────────────
void _participantes() {
  List<RoundResult> rondas() => [
        _r(id: 'r1', dia: 1, quienes: const [ana, beto, caro],
            dinero: {ana: 200, beto: -100, caro: -100}),
        _r(id: 'r2', dia: 2, quienes: const [ana, beto],
            dinero: {ana: -50, beto: 50}),
      ];

  Torneo conLista(List<String> quienes, {double entrada = 0, int minimo = 0}) =>
      Torneo(
        id: 't', nombre: 'T',
        fuente: FuenteDeRondas.rango,
        metodo: MetodoDePuntuacion.dinero,
        participantes: quienes,
        minimoRondas: minimo,
        bote: BoteConfig(entrada: entrada),
      );

  group('10 · la tabla es de los inscritos', () {
    test('quien jugó pero no está inscrito NO sale', () {
      final tabla = tablaDe(conLista(const [ana, beto]), rondas());
      expect(tabla.filas.map((f) => f.playerId).toSet(), {ana, beto});
      expect(tabla.filas.map((f) => f.playerId), isNot(contains(caro)));
    });

    test('un inscrito que no ha jugado sale con cero rondas', () {
      // Estar inscrito es un hecho aunque no hayas ido, y no verte en la lista
      // después de poner el bote sería raro.
      final tabla = tablaDe(conLista(const [ana, beto, dani]), rondas());
      final deDani = tabla.filas.firstWhere((f) => f.playerId == dani);
      expect(deDani.jugadas, 0);
      expect(deDani.total, 0);
      expect(tabla.inscritosSinJugar, [dani]);
    });

    test('con mínimo, el que no ha jugado nada no clasifica', () {
      final tabla = tablaDe(
          conLista(const [ana, beto, dani], minimo: 1), rondas());
      expect(tabla.filas.map((f) => f.playerId), isNot(contains(dani)));
      expect(tabla.bajoMinimo.map((f) => f.playerId), contains(dani));
    });

    test('sin lista sigue entrando quien juegue, y se MARCA', () {
      // El estado heredado. No se rompe —los resultados son útiles— pero deja de
      // ser invisible.
      final tabla = tablaDe(conLista(const []), rondas());
      expect(tabla.filas, hasLength(3));
      expect(tabla.sinListaDeParticipantes, isTrue);
    });
  });

  group('11 · sin lista no se apunta dinero de nadie', () {
    test('el bote final no se calcula', () {
      final t = conLista(const [], entrada: 500);
      final bote = boteDe(t, tablaDe(t, rondas()));
      expect(bote.hayBote, isFalse);
      expect(bote.total, 0);
      expect(bote.lineas, isEmpty);
    });

    test('ni los de jornada', () {
      final t = Torneo(
        id: 't', nombre: 'T',
        fuente: FuenteDeRondas.rango,
        metodo: MetodoDePuntuacion.dinero,
        bote: const BoteConfig(entradaPorJornada: 100),
      );
      expect(botesPorJornada(t, tablaDe(t, rondas())), isEmpty);
    });

    test('con lista SÍ, y solo sobre los inscritos', () {
      // El contrapeso: si nunca se calculara, los dos de arriba pasarían igual.
      // Caro jugó pero no está inscrito, así que su entrada no está en el bote.
      final t = conLista(const [ana, beto], entrada: 500);
      final bote = boteDe(t, tablaDe(t, rondas()));
      expect(bote.total, 1000, reason: 'dos inscritos × 500, no tres');
    });

    test('y se DICE por qué no hay bote, con el número', () {
      final t = conLista(const [], entrada: 500);
      final motivo = motivoSinLista(t, tablaDe(t, rondas()));
      expect(motivo, isNotNull);
      expect(motivo, contains('3 personas'));
      expect(motivo, contains('El bote no se calcula'));
    });

    test('con lista no hay nada que decir', () {
      final t = conLista(const [ana, beto], entrada: 500);
      expect(motivoSinLista(t, tablaDe(t, rondas())), isNull);
    });
  });

  group('12 · la propuesta de participantes', () {
    test('por fechas propone a quien haya jugado', () {
      final t = conLista(const []);
      expect(participantesPropuestos(t, rondas()).toSet(), {ana, beto, caro});
    });

    test('de un grupo propone sus habituales, no quien jugó', () {
      // Los habituales son los que se inscribirían; quien jugó una ronda suelta
      // del grupo no necesariamente entra al torneo.
      final t = Torneo(
        id: 't', nombre: 'T',
        fuente: FuenteDeRondas.grupo,
        bettingGroupId: 'g',
        metodo: MetodoDePuntuacion.dinero,
      );
      expect(
          participantesPropuestos(t, rondas(),
              habitualesDelGrupo: const [ana, dani]),
          [ana, dani]);
    });

    test('es una propuesta, no la lista: el torneo sigue sin ella', () {
      final t = conLista(const []);
      participantesPropuestos(t, rondas());
      expect(t.participantes, isEmpty);
    });
  });

  group('13 · el mínimo ya no decide quién entra', () {
    test('decide quién OPTA AL PREMIO, y son cosas distintas', () {
      // Caro no está inscrito: no entra ni con mínimo 0. Beto sí, y con mínimo 3
      // entra en la tabla pero no clasifica.
      final t = conLista(const [ana, beto, caro].sublist(0, 2), minimo: 3);
      final tabla = tablaDe(t, rondas());
      expect([...tabla.filas, ...tabla.bajoMinimo].map((f) => f.playerId).toSet(),
          {ana, beto});
      expect(tabla.filas, isEmpty, reason: 'ninguno llega a 3 rondas');
      expect(tabla.bajoMinimo, hasLength(2),
          reason: 'pero los dos están inscritos y salen con su cuenta');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// LA PANTALLA ENSEÑA LO GUARDADO, NO LO QUE RECIBIÓ AL ABRIRSE
//
// El bug: se editaba la lista de participantes, se guardaba, se volvía, y la
// pantalla seguía diciendo "falta la lista" con el bote a cero. La lista SÍ se
// había guardado —el modelo la persiste bien— pero TorneoTablaScreen renderizaba
// el objeto que recibió al construirse, que es de antes de editar.
//
// Es el patrón de siempre en la dirección contraria: no que la UI reaccione y el
// modelo no se entere, sino que el modelo cambie y la UI mire una copia vieja. Y
// yo mismo había escrito un parche para esquivarlo al compartir sin arreglar la
// pantalla que tenía el problema.
//
// Este test monta la pantalla con un torneo VIEJO como argumento y uno nuevo en
// el provider. Es la forma de reproducir "volver del editor" sin navegar.
// ─────────────────────────────────────────────────────────────────────────────
void _pantallaLeeLoGuardado() {
  Future<void> montar(WidgetTester tester,
      {required Torneo argumento,
      required Torneo enProvider,
      required List<RoundResult> res}) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PerfilProvider>.value(
            value: PerfilProvider()..sembrar(res)),
        ChangeNotifierProvider<TorneoProvider>.value(
            value: TorneoProvider()..sembrar([enProvider])),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
      ],
      child: MaterialApp(home: TorneoTablaScreen(torneo: argumento)),
    ));
    await tester.pump(const Duration(milliseconds: 150));
  }

  final rondas = [
    _r(id: 'r1', dia: 1, quienes: const [ana, beto],
        dinero: {ana: 100, beto: -100}),
  ];

  const sinLista = Torneo(
    id: 'mismo', nombre: 'Copa',
    fuente: FuenteDeRondas.rango,
    metodo: MetodoDePuntuacion.dinero,
    bote: BoteConfig(entrada: 500),
  );
  const conLista = Torneo(
    id: 'mismo', nombre: 'Copa',
    fuente: FuenteDeRondas.rango,
    metodo: MetodoDePuntuacion.dinero,
    participantes: [ana, beto],
    bote: BoteConfig(entrada: 500),
  );

  group('14 · la pantalla lee del provider, no del argumento', () {
    testWidgets('con la lista ya guardada, el aviso desaparece',
        (tester) async {
      // El argumento es la versión VIEJA —sin lista— y el provider tiene la
      // guardada. Antes se enseñaba la vieja.
      await montar(tester,
          argumento: sinLista, enProvider: conLista, res: rondas);
      expect(find.text('FALTA LA LISTA DE PARTICIPANTES'), findsNothing,
          reason: 'la lista está guardada: el aviso sobra');
    });

    testWidgets('y el bote se calcula con los inscritos guardados',
        (tester) async {
      await montar(tester,
          argumento: sinLista, enProvider: conLista, res: rondas);
      expect(find.text('\$1000'), findsOneWidget,
          reason: 'dos inscritos × 500');
    });

    testWidgets('si de verdad falta la lista, el aviso sí sale',
        (tester) async {
      // El contrapeso: sin este, los dos de arriba pasarían con un aviso que
      // nunca se enseña.
      await montar(tester,
          argumento: conLista, enProvider: sinLista, res: rondas);
      expect(find.text('FALTA LA LISTA DE PARTICIPANTES'), findsOneWidget);
    });

    testWidgets('un torneo borrado del provider no deja la pantalla vacía',
        (tester) async {
      // Se enseña el último conocido en vez de una pantalla en blanco: es lo que
      // se ve un instante al borrar desde otro sitio.
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<PerfilProvider>.value(
              value: PerfilProvider()..sembrar(rondas)),
          ChangeNotifierProvider<TorneoProvider>.value(
              value: TorneoProvider()..sembrar(const [])),
          ChangeNotifierProvider(create: (_) => PlayerProvider()),
          ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
        ],
        child: const MaterialApp(home: TorneoTablaScreen(torneo: conLista)),
      ));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('CÓMO SE PUNTÚA'), findsOneWidget);
    });
  });
}
