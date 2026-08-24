// ─────────────────────────────────────────────────────────────────────────────
// LA VISTA DE INVITADO — el árbol donde más trabajo hace
//
// Es la pantalla que alguien abre desde WhatsApp sin tener la app, así que es la
// única cosa de este torneo que va a ver. Aquí el cuadro no es una comodidad: es
// el producto.
//
// Y esta pantalla no tenía NINGÚN test —lo llevaba marcado como "solo compila"
// desde que se construyó—. Ahora sí.
//
// Lo que se prueba, además del árbol: que un torneo SIN BOTE no hable de dinero
// en ninguna línea. Se juega así a menudo, y un "$0" con su explicación es peor
// que no decir nada.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/round_result.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/models/torneo_publicado.dart';
import 'package:golf_bet_master/screens/torneos/torneo_invitado_screen.dart';

const ana = 'pid_a', beto = 'pid_b', caro = 'pid_c', dani = 'pid_d';
const cuatro = [ana, beto, caro, dani];
const nombres = {
  ana: 'Rafael',
  beto: 'Alan',
  caro: 'Guillermo',
  dani: 'Alejandro'
};

RoundResult _r(String id, int dia, Map<String, double> dinero) => RoundResult(
      roundId: id,
      roundName: 'Sábado $dia',
      courseName: 'Los Encinos',
      playedAt: DateTime(2026, 3, dia),
      holesPlayed: 18,
      playerIds: dinero.keys.toList(),
      playerNames: {for (final k in dinero.keys) k: nombres[k] ?? k},
      balances: dinero,
      pairBalances: const {},
      grossByPlayer: const {},
      netByPlayer: const {},
      stablefordByPlayer: const {},
      bettingGroupIds: const [],
      torneoIds: const ['t1'],
    );

/// Publica un torneo de eliminación, con o sin bote.
TorneoPublicado _publicar({double entrada = 0, List<RoundResult>? rondas}) {
  final t = Torneo(
    id: 't1',
    nombre: 'Match Play CGM',
    formato: FormatoDeTorneo.eliminacion,
    fuente: FuenteDeRondas.marcadas,
    metodo: MetodoDePuntuacion.dinero,
    participantes: cuatro,
    bote: BoteConfig(entrada: entrada),
  );
  final rs = rondas ?? const <RoundResult>[];
  final tabla = tablaDe(t, rs);
  final llave = llaveDe(t, rs);
  return TorneoPublicado.desde(
    token: 'tok',
    ownerUid: 'uid',
    torneo: t,
    tabla: tabla,
    bote: boteDe(t, tabla, campeon: llave.campeon),
    jornadas: botesPorJornada(t, tabla),
    cuando: DateTime(2026, 4, 1),
    llave: llave,
    nombres: nombres,
  );
}

Future<List<String>> _montar(WidgetTester tester, TorneoPublicado copia,
    {double ancho = 390}) async {
  tester.view.physicalSize = Size(ancho, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final errores = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => errores.add(d.exceptionAsString());

  await tester.pumpWidget(MaterialApp(
    theme: GolfTheme.classic.toMaterial(),
    home: TorneoInvitadoScreen(copia: copia),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  FlutterError.onError = anterior;
  return errores;
}

String _pantalla(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join(' · ');

void main() {
  group('1 · el invitado ve el mismo ÁRBOL', () {
    testWidgets('con las fases como columnas y los nombres', (tester) async {
      final errores = await _montar(tester, _publicar());
      expect(errores, isEmpty);
      final txt = _pantalla(tester);
      expect(txt, contains('EL CUADRO'));
      expect(txt, contains('SEMIFINALES'));
      expect(txt, contains('FINAL'));
      for (final n in nombres.values) {
        expect(txt, contains(n), reason: n);
      }
      // La firma del árbol: rueda en horizontal.
      expect(
          tester
              .widgetList<Scrollable>(find.byType(Scrollable))
              .where((s) => s.axis == Axis.horizontal),
          isNotEmpty);
    });

    testWidgets('los huecos dicen de dónde salen, igual que en la app',
        (tester) async {
      await _montar(tester, _publicar());
      expect(find.textContaining('Ganador de Semifinales'), findsWidgets);
    });

    testWidgets('con la final jugada, el campeón cierra el árbol',
        (tester) async {
      final errores = await _montar(
          tester,
          _publicar(rondas: [
            _r('s1', 7, {ana: 300, dani: -300}),
            _r('s2', 8, {beto: 200, caro: -200}),
            _r('fin', 20, {ana: 500, beto: -500}),
          ]));
      expect(errores, isEmpty);
      expect(_pantalla(tester), contains('Rafael'));
      expect(find.text('🏆'), findsWidgets);
    });

    testWidgets('y dice CON QUÉ RONDA se resolvió cada partido',
        (tester) async {
      // Sin el motivo, el cuadro es un veredicto. Y el invitado es justo quien
      // no puede ir a mirar la ronda por su cuenta.
      await _montar(tester, _publicar(rondas: [
        _r('s1', 7, {ana: 300, dani: -300}),
      ]));
      expect(_pantalla(tester), contains('Se resolvió en Sábado 7'));
    });

    testWidgets('cabe a 320 px', (tester) async {
      final errores = await _montar(tester, _publicar(), ancho: 320);
      expect(errores, isEmpty);
    });
  });

  group('2 · CRITERIO 8: sin bote, ninguna línea habla de dinero', () {
    testWidgets('con entrada 0 no aparece el bote', (tester) async {
      final errores = await _montar(tester, _publicar(entrada: 0));
      expect(errores, isEmpty);
      final txt = _pantalla(tester);
      // Ni la cifra, ni el reparto, ni la explicación.
      expect(txt, isNot(contains('\$')));
      expect(txt.toLowerCase(), isNot(contains('bote')));
    });

    testWidgets('con entrada sí aparece: el contrapeso', (tester) async {
      // Sin este, lo de arriba pasaría con una pantalla que nunca enseña el
      // bote.
      final errores = await _montar(tester,
          _publicar(entrada: 500, rondas: [
            _r('s1', 7, {ana: 300, dani: -300}),
            _r('s2', 8, {beto: 200, caro: -200}),
            _r('fin', 20, {ana: 500, beto: -500}),
          ]));
      expect(errores, isEmpty);
      expect(_pantalla(tester).toLowerCase(), contains('bote'));
    });
  });

  group('3 · la instantánea lleva lo que el árbol necesita', () {
    test('la POSICIÓN de cada partido, que es lo que faltaba', () {
      // Sin ella no se puede saber qué dos partidos alimentan a cuál, y el árbol
      // se queda en lista. Es un número, no un id: la regla de qué NO va en la
      // instantánea sigue intacta.
      final copia = _publicar();
      final primera = copia.llave.where((p) => p.ronda == 0).toList();
      expect(primera, hasLength(2));
      expect(primera.map((p) => p.posicion), [0, 1]);
    });

    test('y sigue sin llevar ids ni roundId', () {
      final json = _publicar(rondas: [
        _r('ronda_secreta', 7, {ana: 300, dani: -300}),
      ]).toJson().toString();
      for (final prohibido in [ana, beto, caro, dani, 'ronda_secreta']) {
        expect(json.contains(prohibido), isFalse, reason: prohibido);
      }
      // Y el nombre de la ronda sí, que es el "por qué".
      expect(json.contains('Sábado 7'), isTrue);
    });

    test('la posición sobrevive el JSON', () {
      final ida = TorneoPublicado.fromJson('tok', _publicar().toJson());
      final primera = ida.llave.where((p) => p.ronda == 0).toList();
      expect(primera.map((p) => p.posicion), [0, 1]);
    });
  });
}
