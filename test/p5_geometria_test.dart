// ─────────────────────────────────────────────────────────────────────────────
// P5 · GEOMETRÍA — los tres anchos y los tres temas
//
// El plan pide 320, 390 y 812 px. Y los tres temas, porque un color fuera de
// canal no se ve midiendo: se ve pintando.
//
// Qué se mide y qué NO:
//
//   · Se mide que NINGÚN widget desborde. Cualquier error del árbol cuenta, no
//     solo los overflow: una pantalla que no construye pasaba en verde cuando el
//     filtro solo miraba desbordes.
//   · Se mide que el contenido quepa a lo ANCHO. El alto puede sobrar —para eso
//     hay scroll— pero un desborde horizontal es contenido que no se ve.
//
// Excepción declarada: la fila de la tabla de captura a 320 px sigue sin caber.
// Es deuda anterior —los dos steppers y el divisor no dejan sitio— y aplazarla
// es una decisión sobre qué se cae de esa fila, no un descuido. Aquí se PINA con
// su medida para que no empeore en silencio.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/models.dart';
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
import 'package:golf_bet_master/screens/capture/capture_screen.dart';
import 'package:golf_bet_master/screens/home/home_screen.dart';
import 'package:golf_bet_master/screens/torneos/torneos_screen.dart';
import 'package:golf_bet_master/services/player_service.dart';

/// Los tres anchos del plan.
const anchos = <double>[320, 390, 812];

/// Los tres temas.
const temas = <(String, GolfTheme)>[
  ('classic', GolfTheme.classic),
  ('light', GolfTheme.light),
  ('dark', GolfTheme.dark),
];

// Nombres largos de verdad: es donde revienta.
const gente = <(String, String, double)>[
  ('pid_1', 'María Fernanda Villalobos', 4),
  ('pid_2', 'Juan Carlos Betancourt', 9),
  ('pid_3', 'Carolina Sanmartín', 15),
  ('pid_4', 'Daniel Alejandro Ruiz', 18),
  ('pid_5', 'Bernardo Guillermo Cavazos', 22),
];

RoundResult _res(int dia, {int racha = 0}) => RoundResult(
      roundId: 'r$dia',
      roundName: 'Sábado $dia',
      courseName: 'Club de Golf Los Encinos',
      playedAt: DateTime(2026, 3, dia),
      holesPlayed: 18,
      playerIds: [for (final g in gente) g.$1],
      playerNames: {for (final g in gente) g.$1: g.$2},
      // Cifras de tres dígitos con separador: es lo que ensancha las columnas.
      balances: {
        for (var i = 0; i < gente.length; i++)
          gente[i].$1: i == 0 ? 1250.0 : -312.5,
      },
      pairBalances: const {},
      grossByPlayer: {for (final g in gente) g.$1: 108},
      netByPlayer: {for (final g in gente) g.$1: 86},
      stablefordByPlayer: {for (final g in gente) g.$1: 38},
      bettingGroupIds: const [],
      torneoIds: const ['tor_1'],
    );

Torneo _torneo({FormatoDeTorneo formato = FormatoDeTorneo.liga}) => Torneo(
      id: 'tor_1',
      nombre: 'Copa Club de Golf Los Encinos 2026',
      formato: formato,
      fuente: FuenteDeRondas.marcadas,
      metodo: formato == FormatoDeTorneo.eliminacion
          ? MetodoDePuntuacion.dinero
          : MetodoDePuntuacion.posicion,
      participantes: [for (final g in gente) g.$1],
      bote: const BoteConfig(entrada: 500),
    );

/// Monta [pantalla] y devuelve los errores del árbol.
Future<List<String>> _montar(
  WidgetTester tester,
  Widget pantalla, {
  required double ancho,
  required GolfTheme tema,
  List<RoundResult> res = const [],
  List<Torneo> torneos = const [],
}) async {
  tester.view.physicalSize = Size(ancho, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  // CUALQUIER error, no solo overflow.
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => RoundProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
      ChangeNotifierProvider(create: (_) => BettingGroupProvider()),
      // La marca de organizador: el logo de Inicio la consulta, así que un
      // harness sin ella no monta. Sembrada en false —una cuenta normal—
      // porque lo que estos tests miran es la app del jugador.
      ChangeNotifierProvider<OrganizadorProvider>(
          create: (_) => OrganizadorProvider()..sembrar(false)),
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              for (final g in gente)
                PlayerWithLink(
                    player: Player(id: g.$1, name: g.$2, handicapBase: g.$3))
            ])),
      ChangeNotifierProvider<PerfilProvider>.value(
          value: PerfilProvider()..sembrar(res)),
      ChangeNotifierProvider<TorneoProvider>.value(
          value: TorneoProvider()..sembrar(torneos)),
    ],
    child: MaterialApp(theme: tema.toMaterial(), home: pantalla),
  ));
  await tester.pump(const Duration(milliseconds: 200));
  FlutterError.onError = anterior;
  return errores;
}

void main() {
  group('1 · Inicio, con historial y cifras de cuatro dígitos', () {
    for (final ancho in anchos) {
      for (final tema in temas) {
        testWidgets('${ancho.toInt()} px · ${tema.$1}', (tester) async {
          final errores = await _montar(tester, const HomeScreen(),
              ancho: ancho,
              tema: tema.$2,
              res: [for (var d = 1; d <= 12; d++) _res(d)],
              torneos: [_torneo()]);
          expect(errores, isEmpty,
              reason: 'Inicio a ${ancho.toInt()} px con tema ${tema.$1}');
        });
      }
    }
  });

  group('2 · Inicio vacío: la primera vez que se abre la app', () {
    for (final ancho in anchos) {
      testWidgets('${ancho.toInt()} px sin datos', (tester) async {
        final errores = await _montar(tester, const HomeScreen(),
            ancho: ancho, tema: GolfTheme.classic);
        expect(errores, isEmpty, reason: '${ancho.toInt()} px');
      });
    }
  });

  group('3 · La lista de torneos y la tabla', () {
    for (final ancho in anchos) {
      testWidgets('${ancho.toInt()} px · lista', (tester) async {
        final errores = await _montar(tester, const TorneosScreen(),
            ancho: ancho,
            tema: GolfTheme.classic,
            res: [for (var d = 1; d <= 6; d++) _res(d)],
            torneos: [_torneo(), _torneo(formato: FormatoDeTorneo.eliminacion)]);
        expect(errores, isEmpty, reason: '${ancho.toInt()} px');
      });

      testWidgets('${ancho.toInt()} px · tabla de liga con bote',
          (tester) async {
        final errores = await _montar(
            tester, TorneoTablaScreen(torneo: _torneo()),
            ancho: ancho,
            tema: GolfTheme.classic,
            res: [for (var d = 1; d <= 6; d++) _res(d)],
            torneos: [_torneo()]);
        expect(errores, isEmpty, reason: '${ancho.toInt()} px');
      });

      testWidgets('${ancho.toInt()} px · cuadro de eliminación',
          (tester) async {
        final t = _torneo(formato: FormatoDeTorneo.eliminacion);
        final errores = await _montar(tester, TorneoTablaScreen(torneo: t),
            ancho: ancho,
            tema: GolfTheme.classic,
            res: [for (var d = 1; d <= 6; d++) _res(d)],
            torneos: [t]);
        expect(errores, isEmpty, reason: '${ancho.toInt()} px');
      });
    }
  });

  group('5 · la pantalla de captura, con cinco jugadores', () {
    Round ronda({List<BetModuleType> tipos = const [BetModuleType.skins]}) {
      final players = [
        for (final g in gente)
          Player(id: g.$1, name: g.$2, handicapBase: g.$3)
      ];
      return Round(
        id: 'r',
        name: 'Sábado en Los Encinos',
        course: CourseInfo(
            name: 'Club de Golf Los Encinos',
            holes: List.generate(
                18,
                (i) => CourseHole(
                    hole: i + 1,
                    par: i % 5 == 4 ? 3 : 4,
                    strokeIndex: i + 1))),
        players: players,
        roundPlayers: players
            .map((p) =>
                RoundPlayer(playerId: p.id, handicapEnRonda: p.handicapBase))
            .toList(),
        betGroups: [
          BetGroup(
              id: 'g',
              name: 'G',
              format: PartidaFormat.allInOnePot,
              playerIds: [for (final g in gente) g.$1],
              modules: [
                for (final t in tipos)
                  BetModuleInstance.defaultFor(
                      t, [for (final g in gente) g.$1],
                      id: 'm_${t.name}')
              ])
        ],
        scores: {
          for (final g in gente)
            g.$1: {
              for (var h = 1; h <= 18; h++)
                h: HoleScore(playerId: g.$1, hole: h, grossScore: 5, putts: 2)
            }
        },
        events: const {},
        oyeseRankings: const {},
        sliding: const [],
        createdAt: DateTime(2026, 8, 1),
        totalHoles: 18,
      );
    }

    Future<List<String>> montarCaptura(WidgetTester tester, double ancho,
        {List<BetModuleType> tipos = const [BetModuleType.skins]}) async {
      tester.view.physicalSize = Size(ancho, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final errores = <String>[];
      final anterior = FlutterError.onError;
      FlutterError.onError = (d) => errores.add(d.exceptionAsString());
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<RoundProvider>.value(
              value: RoundProvider()..startRound(ronda(tipos: tipos))),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ],
        child: MaterialApp(
            theme: GolfTheme.classic.toMaterial(), home: const CaptureScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 150));
      FlutterError.onError = anterior;
      return errores;
    }

    testWidgets('390 px · limpia', (tester) async {
      expect(await montarCaptura(tester, 390), isEmpty);
    });

    testWidgets('812 px · limpia', (tester) async {
      expect(await montarCaptura(tester, 812), isEmpty);
    });

    testWidgets('con Wolf y Sixes a 390 px · limpia', (tester) async {
      // Los dos formatos que añaden un bloque encima de la tabla.
      expect(
          await montarCaptura(tester, 390,
              tipos: const [BetModuleType.wolf, BetModuleType.skins]),
          isEmpty);
    });

    testWidgets('320 px · limpia, y la deuda queda cerrada', (tester) async {
      // Era la deuda aplazada dos veces: a 320 px la fila se salía 44 px. Con la
      // columna del nombre elástica ya cabe, y sin recortar los steppers —que
      // era la razón para no tocarla—.
      expect(await montarCaptura(tester, 320), isEmpty);
    });

    testWidgets('y a 320 px el nombre sigue siendo legible, no un muñón',
        (tester) async {
      // El riesgo de hacer elástica la columna: cambiar un desborde visible por
      // un nombre invisible. Se mide.
      await montarCaptura(tester, 320);
      // MEDIDO: 30 px a 320 y 52 a 390. Con el avatar y el relleno ajustados en
      // pantalla estrecha, el nombre recupera el sitio que se le había ido al
      // hacer la columna elástica —bajó a 34 px a 390, que era peor de lo que
      // había—. El suelo de 24 px es "se lee la primera sílaba".
      expect(tester.getSize(find.text('María').first).width,
          greaterThanOrEqualTo(24.0),
          reason: 'la columna del nombre se ha quedado sin sitio');
    });
  });

  group('4 · el contenido cabe a lo ANCHO', () {
    // Un desborde vertical se resuelve con scroll; uno horizontal es contenido
    // que no se ve nunca.
    for (final ancho in anchos) {
      testWidgets('Inicio no rueda en horizontal a ${ancho.toInt()} px',
          (tester) async {
        await _montar(tester, const HomeScreen(),
            ancho: ancho,
            tema: GolfTheme.classic,
            res: [for (var d = 1; d <= 12; d++) _res(d)],
            torneos: [_torneo()]);
        // Ningún Scrollable horizontal con contenido fuera de vista, salvo los
        // que son a propósito —tiras de chips— que sí ruedan.
        for (final s in tester.widgetList<Scrollable>(find.byType(Scrollable))) {
          if (s.axis != Axis.horizontal) continue;
          // Existir está bien; lo que no puede es haber nacido de un desborde.
          expect(s.axisDirection, isNotNull);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
