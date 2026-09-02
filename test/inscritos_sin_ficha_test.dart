// ─────────────────────────────────────────────────────────────────────────────
// LOS 47 INSCRITOS SIN NOMBRE
//
// El portal abrió Copa CGM 2026 —47 inscritos reales— y enseñó «Ficha no
// encontrada» en las cuarenta y siete filas, sin nombre y sin handicap.
//
// ── Qué es, medido contra producción ────────────────────────────────────────
//
// «Determina qué es un participante que no resuelve: ¿un id sin ficha, un
// nombre sin id, o un formato viejo?»
//
// Ninguno de los tres, y la sonda contra producción tuvo que decirlo porque la
// primera lectura —«son fichas del catálogo global sin vincular»— era falsa.
// Los 47 de Copa CGM 2026, contados:
//
//     10  en su directorio          → ya salían con nombre
//      0  en el catálogo `players`  → la hipótesis, y no resolvía a NADIE
//     28  solo dentro de una ronda  → el caso mayoritario
//      9  en ningún sitio           → huérfanos de verdad
//
// Los 37 sin ficha llevan ids UUID con guiones —los que genera el aparato— y
// no ids de Firestore de veinte caracteres: nunca pasaron por `players`. Son
// jugadores creados dentro de una ronda, y el torneo se llenó con `fuente:
// rango`, o sea barriendo rondas.
//
// ── Y el nombre estaba en casa ──────────────────────────────────────────────
//
// `RoundResult.playerNames` guarda id → nombre del día jugado, y la tabla del
// torneo YA lo lee para no enseñar «—» en la pared. Esta pantalla no lo
// consultaba: la lógica existía y la capa siguiente no la leía, otra vez.
//
// ── Cuatro estados, no un bool ──────────────────────────────────────────────
//
// Con un bool, «jugó y no tiene ficha» y «no existe» se veían igual — y el
// primero es 28 de 47. Y el handicap de un nombre sacado de una ronda no se
// sabe: se enseña «—», porque el 0 que salía antes es indistinguible del
// handicap de un scratch.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/models/inscritos.dart';
import 'package:golf_bet_master/models/models.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/services/player_service.dart';

Torneo _torneo(List<String> ids) =>
    Torneo(id: 't1', nombre: 'Copa CGM 2026', participantes: ids);

PlayerWithLink _delDirectorio(String id, String nombre, double hcp) =>
    PlayerWithLink(
        player: Player(id: id, name: nombre, handicapBase: hcp));

({Player ficha, bool mia}) _global(String id, String nombre, double hcp,
        {bool mia = false}) =>
    (ficha: Player(id: id, name: nombre, handicapBase: hcp), mia: mia);

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · CRITERIO 1: un inscrito con ficha tiene nombre y handicap', () {
    test('CLAVE: del directorio, como siempre', () {
      final f = filasDeInscritos(
          _torneo(['p1']), [_delDirectorio('p1', 'Ana Robles', 12.4)]);
      expect(f.single.nombre, 'Ana Robles');
      expect(f.single.handicap, 12.4);
      expect(f.single.origen, OrigenDeLaFicha.directorio);
      expect(f.single.editable, isTrue);
    });

    test('CLAVE: y del CATÁLOGO GLOBAL — el caso de los 47', () {
      // Es el fallo entero: la cuenta no lo tiene vinculado y la ficha existe.
      final f = filasDeInscritos(
        _torneo(['p9']),
        const [],
        globales: {'p9': _global('p9', 'Guillermo Lozano', 18.0)},
      );
      expect(f.single.nombre, 'Guillermo Lozano');
      expect(f.single.handicap, 18.0, reason: 'y su handicap, no un cero');
      expect(f.single.origen, OrigenDeLaFicha.global);
    });

    test('CLAVE: el DIRECTORIO manda sobre el catálogo', () {
      // El organizador pudo haber editado el handicap en su directorio, y la
      // ficha global puede llevar otro. Gana el suyo.
      final f = filasDeInscritos(
        _torneo(['p1']),
        [_delDirectorio('p1', 'Ana Robles', 12.4)],
        globales: {'p1': _global('p1', 'Ana R.', 20.0)},
      );
      expect(f.single.nombre, 'Ana Robles');
      expect(f.single.handicap, 12.4);
    });

    test('CLAVE: y de una RONDA jugada — 28 de los 47', () {
      // El caso mayoritario, el que ninguna de las tres hipótesis cubría.
      final f = filasDeInscritos(
        _torneo(['4742385a-1ee9-4b14-9be1-880d84b5c7b7']),
        const [],
        nombresDeRondas: const {
          '4742385a-1ee9-4b14-9be1-880d84b5c7b7': 'Dylan'
        },
      );
      expect(f.single.nombre, 'Dylan');
      expect(f.single.origen, OrigenDeLaFicha.rondas);
    });

    test('CLAVE: pero su handicap NO se inventa', () {
      // Un RoundResult no lleva handicap. Poner 0 sería un valor plausible
      // tapando uno que falta — el fallo que ya ha aparecido varias veces.
      final f = filasDeInscritos(_torneo(['u1']), const [],
          nombresDeRondas: const {'u1': 'Gonzalo'});
      expect(f.single.handicapConocido, isFalse);
      expect(f.single.editable, isFalse);
    });

    test('CLAVE: el ORDEN de preferencia — directorio, catálogo, ronda', () {
      // El directorio manda porque es donde el organizador editó el handicap;
      // el nombre de una ronda es el de ESE día y pudo cambiar.
      final f = filasDeInscritos(
        _torneo(['p1', 'p9']),
        [_delDirectorio('p1', 'Ana Robles', 12.4)],
        globales: {'p9': _global('p9', 'Del catálogo', 7.0)},
        nombresDeRondas: const {'p1': 'ANA VIEJA', 'p9': 'De la ronda'},
      );
      expect(f[0].nombre, 'Ana Robles');
      expect(f[0].origen, OrigenDeLaFicha.directorio);
      expect(f[1].nombre, 'Del catálogo');
      expect(f[1].origen, OrigenDeLaFicha.global);
    });

    test('CLAVE: el RECUENTO de Copa CGM 2026, tal y como lo midió la sonda',
        () {
      // 10 + 0 + 28 + 9 = 47. Es la prueba de que el arreglo cubre el caso
      // real y no una versión cómoda de él.
      final directorio = [
        for (var i = 0; i < 10; i++) _delDirectorio('d$i', 'Del directorio $i', 15)
      ];
      final deRondas = {
        for (var i = 0; i < 28; i++) 'r$i': 'Jugó $i',
      };
      final ids = [
        ...directorio.map((x) => x.player.id),
        ...deRondas.keys,
        for (var i = 0; i < 9; i++) 'h$i',
      ];
      final f = filasDeInscritos(_torneo(ids), directorio,
          nombresDeRondas: deRondas);
      expect(f, hasLength(47));
      int cuantos(OrigenDeLaFicha o) =>
          f.where((x) => x.origen == o).length;
      expect(cuantos(OrigenDeLaFicha.directorio), 10);
      expect(cuantos(OrigenDeLaFicha.global), 0);
      expect(cuantos(OrigenDeLaFicha.rondas), 28);
      expect(cuantos(OrigenDeLaFicha.sinFicha), 9);
      // Lo que Carlos ve: 38 con nombre, 9 sin él y con su motivo.
      expect(f.where((x) => x.origen != OrigenDeLaFicha.sinFicha).length, 38);
    });

    test('CLAVE: el RELLENO de la tabla no cuenta como nombre', () {
      // La tabla del torneo cae en «—» cuando no sabe quién es alguien. Si ese
      // «—» pasara por nombre, los 9 huérfanos saldrían marcados como
      // resueltos: nombre «—», ningún aviso y ningún motivo que leer.
      final f = filasDeInscritos(_torneo(['h1', 'h2']), const [],
          nombresDeRondas: const {'h1': sinNombre, 'h2': '   '});
      expect(f.every((x) => x.origen == OrigenDeLaFicha.sinFicha), isTrue);
      expect(f.first.nombre, contains('Sin ficha'));
    });

    test('CONTRAPESO: y los 47 no se convierten en 47 nombres inventados', () {
      // Sin ficha en ningún sitio sigue siendo huérfano de verdad. Si esto
      // resolviera algo, el test de arriba no probaría nada.
      final f = filasDeInscritos(_torneo(['fantasma']), const []);
      expect(f.single.origen, OrigenDeLaFicha.sinFicha);
      expect(f.single.handicap, 0);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · CRITERIO 2: si no la tiene, se dice por qué y qué hacer', () {
    test('CLAVE: el nombre de la huérfana lleva su ID', () {
      // «Con 47 iguales, saber el motivo es lo único que permite arreglarlo.»
      // Y el id es lo único que se puede buscar en la consola.
      final f = filasDeInscritos(_torneo(['abc123']), const []);
      expect(f.single.nombre, contains('abc123'));
      expect(f.single.nombre, contains('Sin ficha'));
    });

    test('CLAVE: los tres motivos son distintos en la pantalla', () {
      // El aviso decía lo mismo para dos casos que piden cosas distintas: uno
      // se añade al directorio y el otro no existe.
      final codigo = File(
              'lib/screens/organizador/inscritos_tabla.dart')
          .readAsStringSync();
      expect(codigo, contains('no está en tu directorio'),
          reason: 'existe y no la tienes: se puede añadir');
      expect(codigo, contains('la creó otra cuenta'),
          reason: 'existe, es ajena: se ve y no se edita');
      expect(codigo, contains('nunca se le creó ficha'),
          reason: 'jugó y no tiene ficha: el mayoritario, 28 de 47');
      expect(codigo, contains('Créale una ficha'),
          reason: 'y qué hacer, no solo qué pasa');
      expect(codigo, contains('no aparece en ningún sitio'),
          reason: 'huérfana de verdad: quitar y volver a inscribir');
      // Y el viejo, que valía para los tres, se fue del CÓDIGO. Sigue escrito
      // en el comentario que explica por qué, y buscarlo en el fichero entero
      // cazaba la explicación en vez del texto en pantalla.
      final enPantalla = codigo
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(enPantalla.contains('ya no está en tu directorio'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · el handicap ajeno se VE y no se toca', () {
    test('CLAVE: una ficha de otra cuenta no es editable', () {
      // La regla de `players` deja modificar al CREADOR. Ofrecer el campo
      // sería ofrecer algo que falla al guardar.
      final f = filasDeInscritos(
        _torneo(['p9']),
        const [],
        globales: {'p9': _global('p9', 'Diego Estrada', 9.0)},
      );
      expect(f.single.handicap, 9.0, reason: 'se VE');
      expect(f.single.editable, isFalse, reason: 'y no se toca');
    });

    test('CLAVE: pero una ficha global MÍA sí', () {
      final f = filasDeInscritos(
        _torneo(['p9']),
        const [],
        globales: {'p9': _global('p9', 'Mi jugador', 9.0, mia: true)},
      );
      expect(f.single.editable, isTrue);
    });

    test('CLAVE: y el lápiz solo sale cuando se puede', () {
      final codigo = File(
              'lib/screens/organizador/inscritos_tabla.dart')
          .readAsStringSync();
      expect(codigo, contains('if (fila.editable) ...['),
          reason: 'un campo que va a fallar es peor que no ofrecerlo');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · la resolución pide por ID, y no vincula nada', () {
    test('CLAVE: nunca lista el catálogo', () {
      // La regla es `allow get` sin `list`: un `.where(...)` aquí fallaría en
      // producción y no en la revisión. Es la misma guarda que ya se puso en
      // courseCorrections.
      final codigo =
          File('lib/services/player_service.dart').readAsStringSync();
      final i = codigo.indexOf('static Future<Map<String, ({Player ficha, bool mia})>> fichasGlobales');
      expect(i, greaterThan(-1));
      final cuerpo = codigo.substring(i, codigo.indexOf('\n  }', i));
      expect(cuerpo, contains('_players.doc(id).get()'));
      expect(cuerpo.contains('.where('), isFalse);
    });

    test('CLAVE: y NO mete a nadie en el directorio', () {
      // Leer para enseñar un nombre no puede vincular 47 personas. Vincular es
      // una decisión.
      final codigo =
          File('lib/services/player_service.dart').readAsStringSync();
      final i = codigo.indexOf('static Future<Map<String, ({Player ficha, bool mia})>> fichasGlobales');
      final cuerpo = codigo.substring(i, codigo.indexOf('\n  }', i));
      expect(cuerpo.contains('playerLinks'), isFalse);
      expect(cuerpo.contains('.set('), isFalse);
    });

    test('CONTRAPESO: un fallo devuelve VACÍO, no a medias', () {
      // Media resolución dejaría unas filas con nombre y otras sin él, y eso se
      // lee como que a esas les pasa algo distinto.
      final codigo =
          File('lib/services/player_service.dart').readAsStringSync();
      final i = codigo.indexOf('static Future<Map<String, ({Player ficha, bool mia})>> fichasGlobales');
      final cuerpo = codigo.substring(i, codigo.indexOf('\n  }', i));
      expect(cuerpo, contains('return const {};'));
    });
  });
}
