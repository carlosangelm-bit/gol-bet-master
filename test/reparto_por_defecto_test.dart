// ─────────────────────────────────────────────────────────────────────────────
// EL DEFAULT DEL REPARTO PASA A "TODOS CONTRA TODOS"
//
// Decisión de Carlos, y su razonamiento queda en BetCount.repartoPorDefecto:
// es lo que el chip llevaba prometiendo, sin ancla las ventajas pactadas par a
// par valen tal cual, y el pote es el formato especial y no el normal.
//
// Lo que estos tests protegen, que son los cinco criterios:
//
//   1 · Una ronda nueva sin tocar los chips construye allVsAll.
//   2 · El chip resaltado y lo construido salen del MISMO sitio.
//   3 · Lo guardado con onePot se sigue leyendo como onePot. Cambiar el reparto
//       de una ronda cerrada sería reescribir dinero ya pagado.
//   4 · Skins conserva onePot, y está escrito por qué.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/bet_recipe.dart';
import 'package:golf_bet_master/providers/organizador_provider.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/betting_group_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/setup/setup_screen.dart';
import 'package:golf_bet_master/services/player_service.dart';

const _gente = ['CAM', 'AAM', 'KAWA', 'Dylan'];

void main() {
  group('1 y 4 · el default, y la excepción escrita', () {
    test('todo lo que admite reparto va a allVsAll, menos Skins', () {
      for (final c in BetCount.values) {
        if (!c.admiteBote) continue;
        final esperado = c == BetCount.skins
            ? BetFormatMode.onePot
            : BetFormatMode.allVsAll;
        expect(c.repartoPorDefecto, esperado, reason: c.name);
      }
    });

    test('Skins se queda en pote porque el bote ES el formato', () {
      // No es una excepción por gusto: SkinsConfig.carryOver acumula el hoyo
      // empatado al siguiente. En allVsAll el motor juega N duelos con SU
      // carry cada uno, así que el arrastre se multiplica por pareja. Es otro
      // juego, no el mismo repartido de otra forma.
      expect(BetCount.skins.repartoPorDefecto, BetFormatMode.onePot);
      expect(const SkinsConfig().carryOver, isNotNull,
          reason: 'el arrastre existe y es lo que sostiene el argumento');
    });

    test('y Oyeses NO es la excepción, aunque tenga forma de bote por hoyo', () {
      // Se miró aparte: no tiene arrastre, y el motor resuelve el zapato en los
      // dos modos. Sin arrastre, par a par es la lectura natural.
      expect(BetCount.oyes.repartoPorDefecto, BetFormatMode.allVsAll);
    });
  });

  group('3 · lo ya jugado no se toca', () {
    test('un módulo guardado con onePot se lee como onePot', () {
      final j = {
        'id': 'm',
        'type': 'medal',
        'name': 'Medal',
        'participantIds': <String>[],
        'formatMode': 'onePot',
      };
      expect(BetModuleInstance.fromJson(j).formatMode, BetFormatMode.onePot);
    });

    test('y uno sin el campo también: el respaldo sigue siendo onePot', () {
      // Rondas anteriores a que el campo existiera. Cambiar ESTE respaldo sí
      // reescribiría dinero ya pagado, así que no se toca.
      final j = {
        'id': 'm',
        'type': 'medal',
        'name': 'Medal',
        'participantIds': <String>[],
      };
      expect(BetModuleInstance.fromJson(j).formatMode, BetFormatMode.onePot);
    });

    test('el default del MODELO sigue siendo onePot, y es a propósito', () {
      // El cambio es del default del asistente, no del modelo: el modelo lo usa
      // para deserializar lo viejo.
      const vacio = BetModuleInstance(
          id: '', type: BetModuleType.medal, name: '', participantIds: []);
      expect(vacio.formatMode, BetFormatMode.onePot);
    });
  });

  group('2 · lo que se construye es lo que el chip enseña', () {
    testWidgets('sin tocar ningún chip, el módulo sale allVsAll',
        (tester) async {
      // Extremo a extremo por el asistente: elegir gente, elegir Score total, y
      // NO tocar "cómo se cobra". Es el camino de Carlos.
      final mods = await _hastaModulos(tester, 'Score total');
      expect(mods, isNotEmpty, reason: 'el flujo tiene que crear el módulo');
      final medal =
          mods.where((m) => m.type == BetModuleType.medal).toList();
      expect(medal, isNotEmpty);
      for (final m in medal) {
        expect(m.formatMode, BetFormatMode.allVsAll);
      }
    });

    testWidgets('y con Skins sale en pote, sin tocar nada tampoco',
        (tester) async {
      // El contrapeso: si el cambio se hubiera aplicado a todo por igual, este
      // saldría allVsAll y el arrastre se multiplicaría por pareja.
      final mods = await _hastaModulos(tester, 'Skins');
      final skins = mods.where((m) => m.type == BetModuleType.skins).toList();
      expect(skins, isNotEmpty);
      for (final m in skins) {
        expect(m.formatMode, BetFormatMode.onePot);
      }
    });
  });
}

/// Recorre el asistente hasta que los módulos están construidos, eligiendo
/// [conteo] en "¿Qué se cuenta?" y sin tocar nada más.
Future<List<BetModuleInstance>> _hastaModulos(
    WidgetTester tester, String conteo) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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
      ChangeNotifierProvider(create: (_) => TorneoProvider()),
      ChangeNotifierProvider(create: (_) => PerfilProvider()),
      ChangeNotifierProvider<PlayerProvider>.value(
          value: PlayerProvider()
            ..sembrar([
              for (final n in _gente)
                PlayerWithLink(
                    player: Player(id: 'pid_$n', name: n, handicapBase: 12))
            ])),
    ],
    child: const MaterialApp(home: SetupScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 200));

  Future<void> siguiente() async {
    final sig = find.text('Siguiente →');
    if (sig.evaluate().isEmpty) return;
    await tester.ensureVisible(sig.first);
    await tester.pump();
    await tester.tap(sig.first);
    await tester.pumpAndSettle();
  }

  // Campo → Jugadores
  await siguiente();
  for (final n in _gente) {
    final fila = find.text(n);
    if (fila.evaluate().isEmpty) continue;
    await tester.ensureVisible(fila.first);
    await tester.pump();
    await tester.tap(fila.first);
    await tester.pump();
  }
  // Jugadores → Compiten → Qué se cuenta
  await siguiente();
  await siguiente();

  // Elegir el conteo y SALIR del paso: al salir corre _sincronizarModulos.
  final chip = find.text(conteo);
  if (chip.evaluate().isNotEmpty) {
    await tester.ensureVisible(chip.first);
    await tester.pump();
    await tester.tap(chip.first);
    await tester.pumpAndSettle();
  }
  await siguiente();

  final estado = tester.state(find.byType(SetupScreen));
  // ignore: avoid_dynamic_calls
  return (estado as dynamic).modulosDeLaRonda as List<BetModuleInstance>;
}
