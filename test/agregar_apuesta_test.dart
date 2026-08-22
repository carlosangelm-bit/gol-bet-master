// ─────────────────────────────────────────────────────────────────────────────
// LAS HOJAS DE "AGREGAR APUESTA" OFRECEN TODO LO CREABLE
//
// Séptima superficie de esta clase en la sesión. Había TRES hojas de "Agregar
// apuesta" y cada una enumeraba los tipos a mano en dos listas literales, así
// que la de Inicio ofrecía seis de once: Snake, Rabbit y Wolf no llegaron nunca,
// y Bola Baja / Bola Alta llevaba tiempo sin aparecer.
//
// Lo que hace que no vuelva a pasar es el switch exhaustivo de BetFamily —el
// compilador no deja añadir un tipo sin decir en qué sección va— pero eso no
// cubre lo que de verdad falló: que una PANTALLA no consuma la fuente. Eso solo
// lo caza montándola.
//
// Y hay una lección previa detrás: en el propio Setup, encima de la lista
// literal, había un comentario que decía "añadir uno nuevo sí sigue exigiendo
// meterlo aquí, o queda inalcanzable desde Setup". Predijo el fallo exacto. Un
// comentario que avisa no sustituye a una estructura que impide, y ninguno de
// los dos sustituye a un test que monta la pantalla.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/providers/round_provider.dart';
import 'package:golf_bet_master/providers/auth_provider.dart';
import 'package:golf_bet_master/providers/player_provider.dart';
import 'package:golf_bet_master/providers/handicap_provider.dart';
import 'package:golf_bet_master/providers/perfil_provider.dart';
import 'package:golf_bet_master/providers/user_profile_provider.dart';
import 'package:golf_bet_master/screens/home/home_screen.dart';

const cuatro = ['a', 'b', 'c', 'd'];

Round _round({List<String> pids = cuatro}) {
  final course = CourseInfo(
      name: 'T',
      holes: List.generate(
          18, (i) => CourseHole(hole: i + 1, par: 4, strokeIndex: i + 1)));
  return Round(
    id: 'r', name: 'Sábado', course: course,
    players: pids.map((i) => Player(id: i, name: i.toUpperCase())).toList(),
    roundPlayers:
        pids.map((i) => RoundPlayer(playerId: i, handicapEnRonda: 0)).toList(),
    betGroups: [
      BetGroup(
          id: 'g', name: 'Partida Principal',
          format: PartidaFormat.allInOnePot,
          playerIds: pids, modules: const []),
    ],
    scores: const {}, events: const {}, oyeseRankings: const {},
    sliding: const [],
    createdAt: DateTime(2026, 1, 1), totalHoles: 18,
  );
}

/// Monta Inicio con una ronda en curso y abre la hoja de "Agregar apuesta".
Future<void> _abrirHoja(WidgetTester tester, Round round) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<RoundProvider>.value(
          value: RoundProvider()..startRound(round)),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => PlayerProvider()),
      ChangeNotifierProvider(create: (_) => HandicapProvider()),
      ChangeNotifierProvider(create: (_) => PerfilProvider()),
      ChangeNotifierProvider(create: (_) => UserProfileProvider()),
    ],
    child: const MaterialApp(home: HomeScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 100));

  final boton = find.textContaining('adir apuesta');
  expect(boton, findsWidgets,
      reason: 'la puerta a la hoja tiene que estar alcanzable desde Inicio');
  await tester.ensureVisible(boton.first);
  await tester.pump();
  await tester.tap(boton.first);
  await tester.pumpAndSettle();
}

void main() {
  group('1 · la fuente única cubre el enum', () {
    test('cada tipo creable está en exactamente una sección', () {
      final enSecciones = <BetModuleType>[];
      for (final s in betTypeSections) {
        enSecciones.addAll(s.tipos);
      }
      expect(enSecciones.toSet().length, enSecciones.length,
          reason: 'ningún tipo en dos secciones');
      expect(enSecciones.toSet(), creatableBetTypes.toSet());
    });

    test('nada retirado se ofrece', () {
      for (final s in betTypeSections) {
        for (final t in s.tipos) {
          expect(t.isCreatable, isTrue, reason: t.label);
        }
      }
    });

    test('no hay secciones vacías', () {
      // Retirar el último tipo de una familia no puede dejar una cabecera
      // huérfana en pantalla.
      for (final s in betTypeSections) {
        expect(s.tipos, isNotEmpty, reason: s.familia.label);
      }
    });

    test('los tres formatos nuevos están, y Bola Baja / Bola Alta también', () {
      // Los cuatro que faltaban en la hoja de Inicio. Nombrados a propósito:
      // este test tiene que fallar de forma reconocible si vuelve a pasar.
      final todos = betTypeSections.expand((s) => s.tipos).toSet();
      for (final t in [
        BetModuleType.snake,
        BetModuleType.rabbit,
        BetModuleType.wolf,
        BetModuleType.nassauLowHigh,
      ]) {
        expect(todos, contains(t), reason: t.label);
      }
    });
  });

  group('2 · la hoja de Inicio ofrece TODO lo creable', () {
    testWidgets('una fila por tipo, ninguno de menos', (tester) async {
      // El test que reproduce el bug reportado. Antes salían seis de once.
      await _abrirHoja(tester, _round());

      for (final t in creatableBetTypes) {
        expect(find.text(t.label), findsWidgets,
            reason: '${t.label} se puede crear y la hoja no lo ofrece');
      }
    });

    testWidgets('y las cabeceras de sección salen de la familia',
        (tester) async {
      await _abrirHoja(tester, _round());
      for (final f in BetFamily.values) {
        expect(find.text(f.label), findsWidgets, reason: f.label);
      }
    });
  });

  group('3 · Wolf se atenúa con su motivo cuando no hay cuatro', () {
    testWidgets('con 4 jugadores se ofrece', (tester) async {
      await _abrirHoja(tester, _round());
      expect(find.text('Wolf'), findsWidgets);
      expect(find.textContaining('exactamente con 4'), findsNothing,
          reason: 'con cuatro no hay nada que explicar');
    });

    testWidgets('con 3 sigue en la lista pero dice por qué no', (tester) async {
      // Atenuado y explicado, no desaparecido: una opción que se esconde no
      // enseña el modelo. Es la misma convención del selector de Setup.
      await _abrirHoja(tester, _round(pids: const ['a', 'b', 'c']));
      expect(find.text('Wolf'), findsWidgets);
      expect(find.textContaining('exactamente con 4'), findsWidgets);
    });

    testWidgets('y los demás siguen ofreciéndose con 3', (tester) async {
      // El contrapeso: si la puerta cerrara todo, el test de arriba pasaría
      // igual y la hoja quedaría inútil con 3 jugadores.
      await _abrirHoja(tester, _round(pids: const ['a', 'b', 'c']));
      for (final t in [BetModuleType.skins, BetModuleType.snake,
        BetModuleType.rabbit]) {
        expect(find.text(t.label), findsWidgets, reason: t.label);
      }
    });
  });

  group('4 · la familia se declara, no se adivina', () {
    test('Bola Baja / Bola Alta es match play', () {
      // Estaba mal en las tres comprobaciones escritas a mano: se quedaba con
      // el color de "otras apuestas" porque las tres listaban solo nassau y
      // matchAutoPress.
      expect(BetModuleType.nassauLowHigh.family, BetFamily.matchPlay);
    });

    test('los tres formatos nuevos son "otras"', () {
      for (final t in [BetModuleType.snake, BetModuleType.rabbit,
        BetModuleType.wolf]) {
        expect(t.family, BetFamily.otras, reason: t.label);
      }
    });

    test('todo tipo tiene familia sin lanzar', () {
      for (final t in BetModuleType.values) {
        expect(() => t.family, returnsNormally, reason: t.name);
      }
    });
  });
}
