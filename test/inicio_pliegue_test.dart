// ─────────────────────────────────────────────────────────────────────────────
// LA PANTALLA DE INICIO — lo que cabe arriba del pliegue es lo que existe
//
// «Creo que esta pantalla no sirve. Si aparece después del login, no le veo
// mucho sentido.»
//
// El hero ocupaba más de media pantalla de un iPhone para decir el nombre de
// una app que el usuario acaba de abrir, con tres chips que no navegaban. Y lo
// que importa quedaba debajo.
//
// ── El coste se midió solo ──────────────────────────────────────────────────
//
// El índice pasó de 6,0 a 4,7 en veinte rondas y nadie lo vio, porque vivía en
// una tarjeta pequeña debajo del hero. Ese es el fallo que estos tests fijan: no
// que la pantalla sea bonita, sino que el dato esté ARRIBA.
//
// ── Por qué se mide en píxeles y no se mira ─────────────────────────────────
//
// «Verificado en un móvil real, no solo en ventana estrecha.» Cierto, y eso lo
// hace una persona. Lo que un test puede hacer —y hace aquí— es medir la
// GEOMETRÍA: montar a 390×844, que es un iPhone, y comprobar que los rectángulos
// de lo que importa caen dentro de la ventana. Un elemento a 900 px de altura no
// se ve, se mire en el aparato que se mire.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/home/home_screen.dart';
import 'package:golf_bet_master/services/handicap_service.dart';
import 'package:golf_bet_master/widgets/grafico_tendencia.dart';

/// Un iPhone. No una ventana estrecha: el alto es el que decide.
const _iPhone = Size(390, 844);

CourseInfo _campo() => CourseInfo(
      name: 'Los Encinos',
      holes: List.generate(
          18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)),
    );

Round _ronda() {
  final ps = [
    Player(id: 'ana', name: 'Ana Robles'),
    Player(id: 'beto', name: 'Beto Lara'),
  ];
  return Round(
    id: 'r1',
    name: 'Sábado en Los Encinos',
    course: _campo(),
    players: ps,
    roundPlayers:
        ps.map((p) => RoundPlayer(playerId: p.id, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'g',
          name: 'G',
          format: PartidaFormat.oneVsOne,
          playerIds: ps.map((p) => p.id).toList(),
          modules: [
            BetModuleInstance.defaultFor(
                BetModuleType.skins, ps.map((p) => p.id).toList(),
                id: 'sk')
          ]),
    ],
    scores: const {},
    events: const {},
    oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 9, 1),
    totalHoles: 18,
  );
}

/// Veinte diferenciales que bajan: es lo que hace que la tendencia tenga forma.
///
/// Con menos de once puntos la serie se niega a dibujar —lo decidió su propio
/// test, porque hasta la séptima ronda el índice se mueve por el ajuste de la
/// tabla WHS y no por el juego—. Así que veinte, que es lo que tiene la cuenta
/// real.
List<ScoreDifferential> _diferenciales(int n) => [
      for (var i = 0; i < n; i++)
        ScoreDifferential(
          roundId: 'r$i',
          roundName: 'Ronda $i',
          playedAt: DateTime(2026, 1, 1).add(Duration(days: i * 7)),
          // De 9,0 a 4,7: baja, como bajó de verdad.
          differential: 9.0 - i * 0.22,
          grossScore: 88 - i,
          adjustedGrossScore: 88 - i,
          courseRating: 72.0,
          slopeRating: 128,
          parTotal: 72,
          holesPlayed: 18,
          courseName: 'Los Encinos',
        ),
    ];

Future<void> _montar(WidgetTester tester,
    {Round? round, int diferenciales = 0}) async {
  tester.view.physicalSize = _iPhone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final prov = RoundProvider();
  //  persiste en SharedPreferences, que en el harness es un no-op
  // silencioso. Es el mismo camino que usa la app, así que la pantalla recibe
  // exactamente el estado que recibiría de verdad.
  // startRound es el MISMO camino que usa la app: persiste en
  // SharedPreferences, que en el harness es un no-op silencioso. Sembrar el
  // campo a mano habría dejado la pantalla en un estado que no existe.
  if (round != null) prov.startRound(round);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<RoundProvider>.value(value: prov),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => PlayerProvider()..sembrar(const [])),
      ChangeNotifierProvider(
          create: (_) => HandicapProvider()
            ..sembrar(
                HandicapIndexResult(
                    index: diferenciales >= 3 ? 4.7 : null,
                    totalRounds: diferenciales,
                    usedDifferentials: _diferenciales(diferenciales),
                    allDifferentials: _diferenciales(diferenciales)))),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
      ChangeNotifierProvider(create: (_) => PerfilProvider()),
      ChangeNotifierProvider(create: (_) => TorneoProvider()),
      ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
    ],
    child: const MaterialApp(home: HomeScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Si [f] está dentro de la ventana, sin desplazar.
void _sinDesplazar(WidgetTester tester, Finder f, {required String que}) {
  expect(f, findsWidgets, reason: '$que no está en la pantalla');
  final r = tester.getRect(f.first);
  expect(r.bottom, lessThanOrEqualTo(_iPhone.height),
      reason: '$que acaba en ${r.bottom.round()} px, y la pantalla mide '
          '${_iPhone.height.round()}');
  expect(r.top, greaterThanOrEqualTo(0), reason: '$que empieza por encima');
}

/// Las líneas de serie que se están pintando.
List<CustomPaint> _lineas(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .where((w) => w.painter is PintorDeSerie)
    .toList();

String _texto(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');

void main() {
  group('1 · sin ronda: empezar una es lo primero', () {
    testWidgets('CLAVE: el botón de nueva ronda cabe arriba del pliegue',
        (tester) async {
      await _montar(tester);
      _sinDesplazar(tester, find.text('Nueva Ronda'), que: 'Nueva Ronda');
    });

    testWidgets('CLAVE: y el ÍNDICE también, sin bajar', (tester) async {
      // El criterio 3, y el dato que cambió sin que nadie lo viera.
      await _montar(tester);
      _sinDesplazar(tester, find.text('ÍNDICE'), que: 'el índice');
    });

    testWidgets('CLAVE: y el bloque del dinero también', (tester) async {
      // El bloque del balance tiene cuatro estados y solo uno es un número: sin
      // rondas cerradas enseña por qué no hay cifra, que es correcto. Lo que
      // este test fija es que ESE BLOQUE, en el estado que toque, cabe arriba
      // — porque es el sitio donde la cifra va a aparecer.
      await _montar(tester);
      _sinDesplazar(tester, find.text('Falta decir quién eres'),
          que: 'el bloque del dinero');
    });

    testWidgets('CLAVE: la acción va ANTES del estado, no después',
        (tester) async {
      // «La ronda primero.» No basta con que las dos cosas quepan: el orden
      // dice qué se hace y qué se consulta.
      await _montar(tester);
      final accion = tester.getRect(find.text('Nueva Ronda'));
      final indice = tester.getRect(find.text('ÍNDICE'));
      expect(accion.top, lessThan(indice.top),
          reason: 'la acción primero, el estado debajo');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2 · EL ÍNDICE CON SU FORMA
  //
  // «4,7 de 20 rondas, no el 6,0 de hace unas entregas. Cambió y no lo habíamos
  // visto.» Una cifra sola no dice si estás bajando.
  //
  // Este grupo hizo falta porque un contrapeso NO MORDIÓ: quitando el dibujo de
  // la tendencia, todo seguía verde. En el harness la cuenta no tenía
  // diferenciales, así que la línea no se dibujaba de ninguna manera y no había
  // nada que romper.
  // ───────────────────────────────────────────────────────────────────────────
  group('2 · el índice se ve con su tendencia, no solo la cifra', () {
    testWidgets('CLAVE: con veinte rondas, la línea está', (tester) async {
      await _montar(tester, diferenciales: 20);
      expect(find.text('4.7'), findsOneWidget);
      expect(find.text('de 20 rondas'), findsOneWidget);
      // Y su forma al lado: la serie del handicap, la misma que Ajustes.
      expect(_lineas(tester), isNotEmpty,
          reason: 'la cifra sola no dice si baja');
    });

    testWidgets('CLAVE: y cabe arriba del pliegue, con la línea puesta',
        (tester) async {
      // Añadir la forma no puede haber empujado la cifra debajo del pliegue.
      await _montar(tester, diferenciales: 20);
      _sinDesplazar(tester, find.text('ÍNDICE'), que: 'el índice con su línea');
      _sinDesplazar(tester, find.text('4.7'), que: 'la cifra');
    });

    testWidgets('CONTRAPESO: sin rondas no hay línea', (tester) async {
      await _montar(tester);
      expect(_lineas(tester), isEmpty);
      expect(find.text('sin rondas'), findsOneWidget);
    });

    testWidgets('CLAVE: con NUEVE rondas tampoco — hay puntos, no bastan',
        (tester) async {
      // Este es el caso que separa «tiene puntos» de «tiene SUFICIENTES», y
      // hay que buscarlo con cuidado porque son dos umbrales distintos:
      //
      //   · antes de la ronda 7 no hay NINGÚN punto —el índice lleva el ajuste
      //     de la tabla WHS, que se retira solo—
      //   · y con menos de 5 puntos la serie se niega a dibujar
      //
      // Con nueve diferenciales hay tres puntos (las rondas 7, 8 y 9): la lista
      // no está vacía y aun así no basta. Es la única ventana donde el
      // contrapeso muerde, y con 0 y 20 no mordía.
      await _montar(tester, diferenciales: 9);
      expect(find.text('de 9 rondas'), findsOneWidget);
      expect(_lineas(tester), isEmpty,
          reason: 'tres puntos describen el andamiaje, no el juego');
    });
  });

  group('3 · el hero se fue, y con él los chips que no llevaban a nada', () {
    testWidgets('CLAVE: ni el nombre de la app repetido ni el eslogan',
        (tester) async {
      await _montar(tester);
      final txt = _texto(tester);
      // El eslogan del hero: media pantalla para decir lo que el usuario ya
      // sabe, porque acaba de abrir la app.
      expect(txt, isNot(contains('La forma inteligente')));
      // El nombre SÍ sigue, una vez, en la cabecera fina que siempre estuvo.
      // Lo que se fue es la segunda copia debajo.
      expect(find.text('Golf Bet Master'), findsOneWidget);
    });

    testWidgets('CLAVE: los tres chips decorativos no existen',
        (tester) async {
      // El criterio 4. No navegaban a ningún sitio: o llevan a algo, o se van.
      await _montar(tester);
      for (final chip in ['Golf', 'Apuestas', 'Resultados']) {
        expect(find.text(chip), findsNothing, reason: chip);
      }
    });
  });

  group('4 · con ronda en curso: seguirla es lo primero', () {
    testWidgets('CLAVE: la ronda se ve sin desplazar', (tester) async {
      // El criterio 1. Con una ronda abierta, lo que se quiere es volver a
      // ella; todo lo demás puede esperar debajo.
      await _montar(tester, round: _ronda());
      _sinDesplazar(tester, find.text('Sábado en Los Encinos'),
          que: 'la ronda en curso');
    });

    testWidgets('CONTRAPESO: y entonces la acción de empezar NO está',
        (tester) async {
      // Sin esto, una pantalla que enseñara las dos cosas pasaría los tests de
      // arriba y ofrecería empezar una ronda con una abierta.
      await _montar(tester, round: _ronda());
      expect(find.text('Nueva Ronda'), findsNothing);
    });
  });
}
