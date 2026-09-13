// ─────────────────────────────────────────────────────────────────────────────
// «LO DE SIEMPRE» NO DEJABA CREAR NADA
//
// «En la sección "Lo de siempre" no hay botón para agregar.»
//
// Y era cierto: la única forma de tener algo ahí era crear una ronda entera con
// el asistente y guardarla. El camino al revés del que se espera, en uno de los
// tres botones principales de Inicio.
//
// ── Las tres determinaciones ────────────────────────────────────────────────
//
// 1 · NO hace falta el asistente. «Lo de siempre» enseña DOS clases de punto de
//     partida, y una de ellas —el GRUPO DE APUESTA— es exactamente lo que
//     Carlos describe: los jugadores de siempre y sus apuestas, sin campo ni
//     fecha. Su editor ya existía. Faltaba EL BOTÓN, no la pantalla.
//
// 2 · Y un grupo SÍ puede llevar importes por duelo, al revés de lo que yo
//     habría supuesto: `PairBetRule` guarda apuestas POR PAREJA y el grupo
//     conoce a sus jugadores habituales. La que no puede es la PLANTILLA DE
//     RONDA, cuyos overrides van atados a los ids de aquella ronda.
//
// 3 · Una sola pantalla desde los tres sitios que ya la abren.
//
// ── Y un defecto que no estaba reportado ────────────────────────────────────
//
// «Usar plantilla» hacía `Navigator.pop(template)` y los TRES llamadores la
// empujan sin esperar el resultado: el botón cerraba y no pasaba nada.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/models.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 2 · el camino de crear existe y es uno solo', () {
    final pantalla =
        File('lib/screens/templates/templates_screen.dart').readAsStringSync();

    test('CLAVE: hay botón de crear, en la barra y en el estado vacío', () {
      // Los dos, porque quien llega con plantillas ya guardadas no ve el vacío
      // y seguiría sin poder crear.
      expect('Crear lo de siempre'.allMatches(pantalla).length, 2,
          reason: 'uno en la barra y otro en el vacío');
      expect(pantalla, contains('void _crear(BuildContext context)'));
    });

    test('CLAVE: lleva al editor de grupos, no a un editor nuevo', () {
      // Determinación 1: la pantalla ya existía.
      expect(pantalla, contains('BettingGroupEditorScreen()'));
    });

    test('CLAVE: y se llega desde Inicio y desde Ajustes — la MISMA', () {
      // Determinación 3: una pantalla, tres entradas. Si cada sitio abriera la
      // suya, tendríamos dos caminos que divergen.
      for (final f in const [
        'lib/screens/home/home_screen.dart',
        'lib/screens/settings/settings_screen.dart',
        'lib/app_shell.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('TemplatesScreen()'),
            reason: '$f ya no lleva a la pantalla de «lo de siempre»');
      }
    });

    test('CLAVE: el vacío ya no manda a crear una ronda primero', () {
      // Decía solo el camino de ida y vuelta. Ahora la vía directa va primera y
      // el atajo desde una ronda se queda como lo que es.
      final i = pantalla.indexOf('Crear lo de siempre');
      final j = pantalla.indexOf('Guardar como plantilla');
      expect(i, greaterThan(-1));
      expect(j, greaterThan(i),
          reason: 'lo primero que se ofrece es crear, no guardar desde una ronda');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('CRITERIO 3 · lo creado se usa igual que lo guardado', () {
    test('CLAVE: un grupo SIN jugadores habituales sigue precargando apuestas',
        () {
      // El botón nuevo puede crear justo eso: las apuestas de siempre y la
      // gente que cambia. El atajo se RENDÍA —avisaba de jugadores que no
      // estaban y salía sin precargar nada—.
      //
      // Y el aviso solo tiene sentido cuando los TENÍA: un grupo que nunca los
      // tuvo no ha perdido a nadie.
      final codigo =
          File('lib/screens/setup/setup_screen.dart').readAsStringSync();
      expect(codigo, contains('if (nomina.isNotEmpty && _players.length < 2)'),
          reason: 'sin jugadores no es un fallo, es un punto de partida a medias');
      final i = codigo.indexOf('if (nomina.isNotEmpty && _players.length < 2)');
      final j = codigo.indexOf('_applyBettingGroup(bg);', i);
      expect(j, greaterThan(i),
          reason: 'las apuestas se precargan igual, no se sale antes');
    });

    test('CLAVE: «Usar plantilla» abre el asistente, no cierra y ya', () {
      final pantalla = File('lib/screens/templates/templates_screen.dart')
          .readAsStringSync();
      final i = pantalla.indexOf('void _useTemplate(');
      final cuerpo = pantalla.substring(i, pantalla.indexOf('\n  }', i));
      expect(cuerpo, contains('SetupScreen('));
      expect(cuerpo, contains('apuestasDePlantilla'));
      // Y NO devuelve un valor que nadie recoge.
      expect(cuerpo.contains('pop(template)'), isFalse);
    });

    test('CONTRAPESO: ningún sitio que abre la pantalla espera un resultado',
        () {
      // Es lo que hacía inútil el `pop`. Si alguien empezara a esperarlo,
      // habría dos formas de usar una plantilla.
      for (final f in const [
        'lib/screens/home/home_screen.dart',
        'lib/screens/settings/settings_screen.dart',
        'lib/app_shell.dart',
      ]) {
        final c = File(f).readAsStringSync();
        final i = c.indexOf('TemplatesScreen()');
        final antes = c.substring((i - 200).clamp(0, i), i);
        expect(antes.contains('await'), isFalse,
            reason: '$f espera un resultado que la pantalla ya no devuelve');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('DETERMINACIÓN 2 · dónde puede vivir un importe por duelo', () {
    test('CLAVE: un GRUPO puede, porque sabe quién juega', () {
      // `PairBetRule` guarda apuestas por pareja, con sus importes.
      final regla = PairBetRule(
        id: 'r',
        playerAId: 'ana',
        playerBId: 'beto',
        modules: [
          const BetModuleTemplate(
              type: BetModuleType.medal, medalConfig: MedalConfig(value: 25)),
        ],
      );
      final grupo = BettingGroup(
        id: 'g',
        name: 'Viernes',
        playerIds: const ['ana', 'beto'],
        pairRules: [regla],
        updatedAt: DateTime(2026, 9, 13),
      );
      expect(grupo.pairRules.single.modules.single.medal.value, 25);
      expect(grupo.activeRulesCount, 1);
    });

    test('CLAVE: y una PLANTILLA DE MÓDULO no — no sabe quién juega', () {
      // Es lo correcto: `BetModuleTemplate` es la configuración SIN jugadores,
      // así que no tiene dónde poner un importe por pareja. Los overrides se
      // ponen en la ronda, o en la regla por duelo del grupo.
      const plantilla = BetModuleTemplate(
          type: BetModuleType.medal, medalConfig: MedalConfig(value: 100));
      expect(plantilla.medal.value, 100);
      // Y al instanciarla, el módulo sale SIN excepciones por pareja: el
      // importe por duelo tiene que ponerse donde se sepa quién juega.
      final mod = plantilla.toInstance(
          id: 'x', participantIds: const ['ana', 'beto']);
      expect(mod.pairConfigOverrides, anyOf(isNull, isEmpty));
      expect(mod.medal.value, 100);
      expect(mod.overrideForPair('ana', 'beto'), isNull);
    });
  });
}
