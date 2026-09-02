// ─────────────────────────────────────────────────────────────────────────────
// LA LÍNEA ENTRE EL GOLFISTA Y EL ORGANIZADOR
//
// «El módulo de organizador es exclusivo para ese segmento de negocio y no
// tiene que ver con la capacidad del usuario recreativo de crear torneos desde
// su perfil.»
//
// Son dos clientes, no dos roles. Y el criterio que manda sobre todos:
//
//   «Si al separar se rompe la liga de los sábados de alguien, la separación
//    está mal hecha — y esa es la única parte donde no vale "es de prueba".»
//
// Por eso el grupo 1 no prueba el módulo: prueba que el golfista no perdió
// nada. Es el que decide si la separación vale.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/organizador_provider.dart';
import 'package:golf_bet_master/services/organizador_service.dart';

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · CRITERIO 4: el golfista no pierde nada', () {
    test('CLAVE: crear un torneo no pide nada nuevo', () {
      // La liga de los sábados. Si esto necesitara una marca, la separación
      // estaría cobrando lo que se queda gratis.
      final t = Torneo(id: 't1', nombre: 'Liga de los sábados');
      expect(t.nombre, 'Liga de los sábados');
      // Y nace con la duración que menos supone.
      expect(t.duracion, DuracionDeTorneo.unDia);
      // Sin ninguna marca de producto: el torneo no sabe de cobros, y no puede
      // saberlo —ver la doc de DuracionDeTorneo—.
      final j = t.toJson();
      expect(j.keys.any((k) => k.toLowerCase().contains('organiz')), isFalse);
      expect(j.keys.any((k) => k.toLowerCase().contains('pag')), isFalse);
    });

    test('CLAVE: un torneo guardado ANTES de esto sigue leyéndose', () {
      // No hay migración —los datos son de prueba— pero un torneo sin el campo
      // nuevo tiene que caer en algo, no reventar.
      final viejo = Torneo.fromJson({
        'id': 't1',
        'nombre': 'Liga de los sábados',
        'participantes': ['ana', 'beto'],
      });
      expect(viejo.duracion, DuracionDeTorneo.unDia);
      expect(viejo.participantes.length, 2);
    });

    test('CLAVE: y el enlace de WhatsApp sigue siendo del jugador', () {
      // Es lo que un golfista usa para compartir la tabla de su liga. Si
      // hubiera pasado al lado de pago, se cobraría a quien no lo esperaba.
      final codigo =
          File('lib/screens/torneos/torneos_screen.dart').readAsStringSync();
      expect(codigo, contains('Copiar para WhatsApp'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · CRITERIO 3: nada del portal se alcanza desde el jugador', () {
    /// Los ficheros de la app del jugador que importan código del portal.
    List<String> quienEntraAlPortal() {
      final out = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.contains('/organizador/')) continue;
        for (final l in f.readAsLinesSync()) {
          if (!l.startsWith('import ')) continue;
          if (l.contains('organizador/')) out.add('${f.path}: ${l.trim()}');
        }
      }
      return out;
    }

    test('CLAVE: solo la ruta y la puerta del logo', () {
      // La dirección es lo que hace posible cobrar por separado: el portal
      // puede apoyarse en lo del jugador, y lo del jugador NO en el portal.
      //
      // Tres excepciones, y las tres nombradas:
      //   · main.dart          → la ruta /organizador/{id}, que es la entrada
      //   · home_screen.dart   → la puerta del logo
      //   · torneos_screen     → apagarTele: cortar la pared nunca se cobra
      final entradas = quienEntraAlPortal();
      const permitidos = [
        'lib/main.dart',
        'lib/screens/home/home_screen.dart',
        'lib/screens/torneos/torneos_screen.dart',
      ];
      for (final e in entradas) {
        expect(permitidos.any(e.startsWith), isTrue,
            reason: 'entrada al portal sin justificar: $e');
      }
      expect(entradas.length, lessThanOrEqualTo(3));
    });

    test('CLAVE: encender la pantalla del club NO está en la app del jugador',
        () {
      // Es lo que se cobra. Estaba montado en la hoja de compartir.
      final codigo =
          File('lib/screens/torneos/torneos_screen.dart').readAsStringSync();
      expect(codigo.contains('BloqueTele('), isFalse);
    });

    test('CONTRAPESO: pero APAGARLA sí, y tiene que seguir', () {
      // «Dejar de compartir» apaga también la pared, o la frase del botón es
      // mentira. Cortar nunca se cobra.
      final codigo =
          File('lib/screens/torneos/torneos_screen.dart').readAsStringSync();
      expect(codigo, contains('apagarTele('));
    });

    test('CLAVE: y las dos piezas del organizador viven en su carpeta', () {
      expect(File('lib/screens/organizador/tele_sheet.dart').existsSync(),
          isTrue);
      expect(
          File('lib/screens/organizador/republicar_pantalla.dart').existsSync(),
          isTrue);
      expect(File('lib/screens/torneos/tele_sheet.dart').existsSync(), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · CRITERIO 2: la marca no la puede escribir el usuario', () {
    String reglaDe(String coleccion) {
      final texto = File('firestore.rules').readAsStringSync();
      final i = texto.indexOf('match /$coleccion/');
      expect(i, greaterThan(-1), reason: 'no existe la regla de $coleccion');
      final resto = texto.substring(i + 10);
      final j = resto.indexOf('\n    match /');
      return (j == -1 ? resto : resto.substring(0, j))
          .split('\n')
          .map((l) {
            final c = l.indexOf('//');
            return c == -1 ? l : l.substring(0, c);
          })
          .join('\n');
    }

    test('CLAVE: organizadores tiene su regla, y NADIE escribe', () {
      // Es lo que salva el modelo: en `users/{uid}` la marca la escribiría el
      // propio usuario con su token, sin tocar la app.
      final r = reglaDe('organizadores');
      expect(r, contains('allow write: if false'));
      expect(r, contains('allow get:'));
      expect(r, contains('allow list: if false'),
          reason: 'quién ha contratado no es un directorio');
      expect(r.contains('allow read'), isFalse,
          reason: 'read concede list de paso — cuarta vez en este fichero');
    });

    test('CLAVE: y la marca NO está en el documento del usuario', () {
      // La comprobación del otro lado: si alguien la moviera ahí «para
      // simplificar», se volvería autoservicio.
      final perfil =
          File('lib/services/user_profile_service.dart').readAsStringSync();
      expect(perfil.toLowerCase().contains('esorganizador'), isFalse);
      final servicio =
          File('lib/services/organizador_service.dart').readAsStringSync();
      expect(servicio, contains("collection('organizadores')"));
    });

    test('CLAVE: un fallo de red NO abre el módulo', () {
      // Sin sesión, sin red o con la regla denegando, la respuesta correcta es
      // la misma: no se enseña. Un error de red no puede abrir un producto de
      // pago.
      final servicio =
          File('lib/services/organizador_service.dart').readAsStringSync();
      final i = servicio.indexOf('} catch (e) {');
      expect(i, greaterThan(-1), reason: 'hay que atrapar el fallo');
      // Lo que sigue al catch, sin pasarse del final del fichero.
      expect(servicio.substring(i), contains('return false'),
          reason: 'y la respuesta ante un fallo es NO');
      // Y sin sesión, también.
      expect(servicio, contains('if (uid == null) return false;'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · CRITERIO 1: solo lo ve quien está marcado', () {
    test('CLAVE: tres estados, y «no sé» no es «no»', () {
      // Sin la distinción, tocar el logo en el primer segundo de sesión
      // enseñaría la hoja de venta a un organizador que lleva pagando. Es el
      // mismo fallo que costó dos entregas en el portal.
      final p = OrganizadorProvider();
      expect(p.marcado, isNull);
      expect(p.resuelto, isFalse);
      p.sembrar(false);
      expect(p.resuelto, isTrue);
      expect(p.marcado, isFalse);
    });

    test('CLAVE: al cerrar sesión se olvida — la marca es de la cuenta', () {
      final p = OrganizadorProvider()..sembrar(true);
      p.olvidar();
      expect(p.marcado, isNull, reason: 'no es del aparato');
    });

    testWidgets('CLAVE: sin marca, el logo no enseña el punto',
        (tester) async {
      // Una insignia que no lleva a ningún sitio es lo que este proyecto ya
      // quitó una vez —los tres chips del hero—.
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<OrganizadorProvider>(
              create: (_) => OrganizadorProvider()..sembrar(false)),
        ],
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ));
      // La comprobación de que la condición existe, sin montar media app: el
      // punto se pinta solo con `marcado == true`.
      final codigo =
          File('lib/screens/home/home_screen.dart').readAsStringSync();
      expect(codigo, contains('if (org.marcado == true)'));
    });

    test('CLAVE: la hoja de venta dice que crear torneos ES GRATIS', () {
      // La línea que impide que esto haga daño. Sin ella, la hoja parece decir
      // que lo que ya tienes está detrás de un pago.
      final codigo =
          File('lib/screens/organizador/puerta_del_modulo.dart')
              .readAsStringSync();
      expect(codigo, contains('seguirá siendo gratis'));
      // Y no hay botón de comprar: no es autoservicio.
      expect(codigo.contains('Comprar'), isFalse);
      expect(codigo, contains('Escríbenos'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('5 · la duración, que el precio necesita y hoy no existía', () {
    test('CLAVE: tres duraciones, y viajan', () {
      expect(DuracionDeTorneo.values.length, 3);
      final t = Torneo(id: 't1', nombre: 'Liga')
          .copyWith(duracion: DuracionDeTorneo.temporada);
      expect(Torneo.fromJson(t.toJson()).duracion, DuracionDeTorneo.temporada);
    });

    test('CLAVE: y no engorda el documento por defecto', () {
      expect(Torneo(id: 't1', nombre: 'X').toJson().containsKey('duracion'),
          isFalse);
    });

    test('CLAVE: es distinta de formato y de fuente de rondas', () {
      // Los tres se confundían: formato es cómo se compite, fuente es qué
      // rondas cuentan, y desde/hasta solo se usa con el rango. Una liga de
      // temporada puede no tener fechas.
      final liga = Torneo(id: 't1', nombre: 'Liga')
          .copyWith(duracion: DuracionDeTorneo.temporada);
      expect(liga.formato, FormatoDeTorneo.liga);
      expect(liga.fuente, FuenteDeRondas.marcadas);
      expect(liga.desde, isNull, reason: 'y aun así es de temporada');
    });

    test('cada una dice para qué es', () {
      for (final d in DuracionDeTorneo.values) {
        expect(d.label, isNotEmpty);
        expect(d.descripcion.length, greaterThan(20), reason: d.name);
      }
    });
  });
}
