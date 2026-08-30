// ─────────────────────────────────────────────────────────────────────────────
// EL INVENTARIO DE PATROCINIO — punto 2 del portal
//
// Lo que se prueba aquí es lo que NO necesita Firebase: el contrato entre el
// servicio y la regla, lo que la pantalla pide, y lo que bloquea el guardado.
//
// Lo que Firebase sí necesita —subir de verdad, leer sin sesión, borrar— vive
// en test_rules/storage.mjs, contra el emulador. Están separados a propósito:
// una prueba que finge una subida no dice nada sobre si la regla la deja pasar.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/ancho.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/patrocinio.dart';
import 'package:golf_bet_master/models/torneo.dart';
import 'package:golf_bet_master/providers/torneo_provider.dart';
import 'package:golf_bet_master/screens/organizador/patrocinio_seccion.dart';
import 'package:golf_bet_master/services/patrocinio_storage.dart';
import 'package:provider/provider.dart';

Torneo _torneo({InventarioProyectado inv = const InventarioProyectado()}) =>
    Torneo(
      id: 'tor_1',
      nombre: 'Copa de Primavera',
      fuente: FuenteDeRondas.marcadas,
      metodo: MetodoDePuntuacion.posicion,
      participantes: const ['p1'],
      inventario: inv,
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · el servicio y la regla dicen lo mismo', () {
    test('CLAVE: la ruta es la que la regla da por buena', () {
      // storage.rules acota `patrocinio/{ownerUid}/{torneoId}/{archivo}`, con
      // esa profundidad exacta. Si el servicio construyera otra —una subcarpeta
      // más, por ejemplo— la subida la rechazaría la regla y el error saldría
      // lejos de aquí.
      final r = PatrocinioStorage.rutaDe(
          ownerUid: 'uid_org', torneoId: 'tor_1', archivo: 'cabecera-1.png');
      expect(r, 'patrocinio/uid_org/tor_1/cabecera-1.png');
      expect(r.split('/'), hasLength(4),
          reason: 'la regla acota la profundidad: ni un nivel de más');
    });

    test('CLAVE: el tope del servicio y el de la regla son el mismo número', () {
      // Están en dos sitios porque hacen dos cosas —la regla protege, el
      // servicio explica antes de gastar la subida—. Que se separen es el fallo
      // que esto impide: uno diría "hasta 5 MB" y el otro rechazaría a los 2.
      final regla = File('storage.rules').readAsStringSync();
      expect(regla, contains('${PatrocinioStorage.maxMB} * 1024 * 1024'));
    });

    test('y los tipos que declara son los que la regla acepta', () {
      // La regla pide `image/*`. Todos los que el servicio declara lo son.
      for (final ext in PatrocinioStorage.extensiones) {
        final tipo = PatrocinioStorage.tipoDe('logo.$ext');
        expect(tipo, isNotNull, reason: ext);
        expect(tipo!.startsWith('image/'), isTrue, reason: '$ext → $tipo');
      }
    });

    test('CONTRAPESO: lo que no es imagen no tiene tipo', () {
      // Sin esto, un `tipoDe` que devolviera image/png para todo pasaría lo de
      // arriba y subiría un ejecutable con nombre de logo.
      for (final malo in ['virus.exe', 'folleto.pdf', 'hoja.xlsx', 'sinpunto']) {
        expect(PatrocinioStorage.tipoDe(malo), isNull, reason: malo);
      }
    });

    test('el nombre del archivo cambia al reemplazar', () {
      // Con un nombre fijo por espacio, la URL no cambia y el navegador sigue
      // enseñando el logo viejo. En una pantalla que nadie toca en ocho horas,
      // eso es la imagen equivocada todo el día.
      final a = PatrocinioStorage.nombreDe('cabecera', 'logo.png', 1000);
      final b = PatrocinioStorage.nombreDe('cabecera', 'logo.png', 2000);
      expect(a, isNot(b));
      expect(a.endsWith('.png'), isTrue);
    });

    test('y conserva la extensión que traía', () {
      expect(PatrocinioStorage.nombreDe('lateral', 'MARCA.SVG', 1).endsWith('.svg'),
          isTrue);
      expect(PatrocinioStorage.nombreDe('pie', 'sinextension', 1).endsWith('.png'),
          isTrue, reason: 'sin extensión se asume png, no se rompe');
    });

    test('borrar solo toca lo nuestro', () {
      // Llamar a delete sobre una URL ajena es pedirle a Firebase que borre
      // algo de otro. Se comprueba antes.
      expect(
          PatrocinioStorage.esNuestra(
              'https://firebasestorage.googleapis.com/v0/b/x/o/patrocinio%2Fa%2Fb%2Fc.png'),
          isTrue);
      expect(PatrocinioStorage.esNuestra('https://marca.com/logo.png'), isFalse);
      expect(
          PatrocinioStorage.esNuestra(
              'https://firebasestorage.googleapis.com/v0/b/x/o/otracosa%2Fc.png'),
          isFalse,
          reason: 'ni otra carpeta del mismo bucket');
    });

    test('una URL vacía no es un error, es que no había nada', () async {
      expect(await PatrocinioStorage.borrar(''), isTrue);
    });

    test('CLAVE: "falta activar Storage" se distingue de un fallo de red', () {
      // El proyecto no tenía el bucket creado al construir esto, y el error de
      // Firebase habla de un bucket inexistente. Sin traducirlo, la pantalla
      // enseñaría eso mismo, que no le dice a nadie qué hacer: lo que falta es
      // pulsar un botón en la consola, una sola vez.
      expect(
          PatrocinioStorage.esFaltaDeBucket(
              '[firebase_storage/object-not-found] The bucket does not exist.'),
          isTrue);
      expect(
          PatrocinioStorage.esFaltaDeBucket('Bucket not found for project'),
          isTrue);
      // CONTRAPESO: un fallo normal NO se disfraza de esto. Decirle a alguien
      // que active Storage cuando lo que hay es un corte de red le manda a
      // buscar el problema al sitio equivocado.
      expect(PatrocinioStorage.esFaltaDeBucket('network request failed'),
          isFalse);
      expect(
          PatrocinioStorage.esFaltaDeBucket(
              '[firebase_storage/unauthorized] User is not authorized'),
          isFalse);
      expect(PatrocinioStorage.esFaltaDeBucket('object-not-found'), isFalse,
          reason: 'un archivo que falta no es un bucket que falta');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · los espacios y lo que hay que pedir', () {
    test('los tres espacios traen su medida del §5', () {
      expect(EspacioDePatrocinio.cabecera.medida, '728 × 90');
      expect(EspacioDePatrocinio.lateral.medida, '300 × 600');
      expect(EspacioDePatrocinio.pie.medida, contains('240'));
    });

    test('y los dos que faltan siguen fuera, a propósito', () {
      // Ranking de oyes y longest drive dependen de que alguien del staff los
      // mida en el campo. Que no estén es una decisión, no un olvido.
      expect(EspacioDePatrocinio.values, hasLength(3));
    });

    test('CRITERIO 5: la lista del §11 tiene los seis activos', () {
      expect(activosDelPatrocinador, hasLength(6));
      final nombres = activosDelPatrocinador.map((a) => a.etiqueta).join(' · ');
      for (final esperado in [
        'Etiqueta de patrocinio',
        'Logotipo',
        'Titular',
        'Texto alternativo',
        'Llamada a la acción',
        'Enlace de destino',
      ]) {
        expect(nombres, contains(esperado));
      }
    });

    test('y solo la etiqueta es obligatoria', () {
      // §6: la naturaleza comercial tiene que ser clara. Lo demás lo entrega el
      // patrocinador cuando lo tiene.
      final obligatorios =
          activosDelPatrocinador.where((a) => a.obligatorio).toList();
      expect(obligatorios, hasLength(1));
      expect(obligatorios.first.etiqueta, 'Etiqueta de patrocinio');
    });

    test('las siete palabras del titular se cuentan bien', () {
      expect(maxPalabrasTitular, 7);
      expect(palabrasDelTitular('Eleva cada gran ronda'), 4);
      expect(palabrasDelTitular('  uno   dos  '), 2, reason: 'sin contar huecos');
      expect(palabrasDelTitular(''), 0);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · la pantalla', () {
    Future<Torneo> montar(WidgetTester tester,
        {InventarioProyectado inv = const InventarioProyectado(),
        Size tamano = const Size(1440, 950)}) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      GolfThemeExt.setCurrent(GolfTheme.classic);
      final t = _torneo(inv: inv);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TorneoProvider()..sembrar([t])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (_, c) => PatrocinioSeccion(
                  torneo: t, ancho: anchoDe(c.maxWidth), t: GolfTheme.classic),
            ),
          ),
        ),
      ));
      await tester.pump();
      return t;
    }

    testWidgets('CRITERIO 5: enseña los tres espacios con sus medidas',
        (tester) async {
      await montar(tester);
      for (final e in EspacioDePatrocinio.values) {
        expect(find.text(e.titulo), findsOneWidget, reason: e.name);
        expect(find.text(e.medida), findsOneWidget, reason: e.medida);
      }
    });

    testWidgets('y lo que hay que pedirle al patrocinador', (tester) async {
      await montar(tester);
      expect(find.textContaining('LO QUE PEDIRLE'), findsOneWidget);
      for (final a in activosDelPatrocinador) {
        // findRichText: la lista va en RichText para poder poner el nombre en
        // negrita y el motivo detrás. Sin esta bandera, find no la ve.
        expect(find.textContaining(a.etiqueta, findRichText: true), findsWidgets,
            reason: a.etiqueta);
      }
    });

    testWidgets('dice que los archivos NO se borran solos', (tester) async {
      // Decisión de Carlos: el borrado es explícito. Si la pantalla no lo dice,
      // el organizador supone lo contrario y no limpia nunca.
      await montar(tester);
      expect(find.textContaining('no se limpian solos'), findsOneWidget);
    });

    testWidgets('sin patrocinio, ofrece añadir y no enseña huecos',
        (tester) async {
      await montar(tester);
      expect(find.text('Añadir patrocinador'), findsNWidgets(3));
      expect(find.textContaining('Sin logotipo'), findsNothing);
    });

    testWidgets('con una cabecera puesta, la enseña', (tester) async {
      await montar(tester,
          inv: const InventarioProyectado(
              cabecera: PiezaDePatrocinio(
                  etiqueta: 'Patrocinador oficial',
                  titular: 'Eleva cada gran ronda')));
      expect(find.text('PATROCINADOR OFICIAL'), findsOneWidget);
      expect(find.text('Eleva cada gran ronda'), findsOneWidget);
      expect(find.text('Sin logotipo'), findsOneWidget,
          reason: 'y dice que le falta el archivo');
    });

    testWidgets('el intervalo de rotación solo con más de un socio',
        (tester) async {
      await montar(tester,
          inv: const InventarioProyectado(pie: [
            PiezaDePatrocinio(etiqueta: 'Socio', titular: 'A'),
          ]));
      expect(find.textContaining('cambian cada'), findsNothing);

      await montar(tester,
          inv: const InventarioProyectado(pie: [
            PiezaDePatrocinio(etiqueta: 'Socio', titular: 'A'),
            PiezaDePatrocinio(etiqueta: 'Socio', titular: 'B'),
          ]));
      expect(find.textContaining('cambian cada 12 segundos'), findsOneWidget);
    });

    testWidgets('en móvil también se puede, aunque no sea su sitio',
        (tester) async {
      // Y sin desbordarse: con un Row, la fila del título más la medida se
      // salía 116 px en 390. La medida no se recorta —es lo que hay que pedirle
      // a la marca—, así que baja de línea.
      final errores = <String>[];
      final anterior = FlutterError.onError;
      FlutterError.onError = (d) => errores.add(d.exceptionAsString());
      await montar(tester, tamano: const Size(390, 844));
      FlutterError.onError = anterior;
      expect(errores.where((e) => e.contains('overflow')), isEmpty,
          reason: errores.join(' | '));
      expect(find.text('Cabecera'), findsOneWidget);
      expect(find.text('240 × 60 por logotipo'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · el formulario de una pieza', () {
    Future<void> abrir(WidgetTester tester,
        {PiezaDePatrocinio? pieza,
        Future<PlatformFile?> Function()? elegir}) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      GolfThemeExt.setCurrent(GolfTheme.classic);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditorDePieza(
            espacio: EspacioDePatrocinio.cabecera,
            torneoId: 'tor_1',
            pieza: pieza,
            t: GolfTheme.classic,
            elegirArchivo: elegir,
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('CRITERIO 5: pide los seis activos del §11', (tester) async {
      await abrir(tester);
      expect(find.text('Etiqueta de patrocinio *'), findsOneWidget);
      expect(find.text('Titular'), findsOneWidget);
      expect(find.text('Texto alternativo del logotipo'), findsOneWidget);
      expect(find.text('Llamada a la acción'), findsOneWidget);
      expect(find.text('Enlace de destino'), findsOneWidget);
      expect(find.text('Subir logotipo'), findsOneWidget);
    });

    testWidgets('y dice la medida y el peso máximo antes de subir nada',
        (tester) async {
      await abrir(tester);
      expect(find.textContaining('728 × 90'), findsWidgets);
      expect(find.textContaining('hasta 5 MB'), findsOneWidget);
    });

    testWidgets('CLAVE: sin etiqueta no se puede guardar, y se explica',
        (tester) async {
      // §6. Es lo único que bloquea.
      //
      // Con el titular RELLENO y la etiqueta vacía: es el caso que aísla la
      // etiqueta. Dejando los dos vacíos, la prueba pasaba igual aunque nadie
      // comprobara la etiqueta —lo bloqueaba el titular—, y eso no probaba nada.
      await abrir(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Titular'), 'Eleva cada gran ronda');
      await tester.pump();
      expect(find.textContaining('Hace falta la etiqueta'), findsOneWidget);
      final boton =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
      expect(boton.onPressed, isNull,
          reason: 'con titular pero sin etiqueta, sigue bloqueado');
    });

    testWidgets('CONTRAPESO: y sin titular pero con logotipo, tampoco basta',
        (tester) async {
      // El otro lado del mismo aislamiento.
      await abrir(tester,
          pieza: const PiezaDePatrocinio(
              etiqueta: '', logoUrl: 'https://x/l.png'));
      final boton =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
      expect(boton.onPressed, isNull);
    });

    testWidgets('con etiqueta y titular, sí', (tester) async {
      await abrir(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Etiqueta de patrocinio *'),
          'Patrocinador oficial');
      await tester.enterText(
          find.widgetWithText(TextField, 'Titular'), 'Eleva cada gran ronda');
      await tester.pump();
      final boton =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
      expect(boton.onPressed, isNotNull);
    });

    testWidgets('CLAVE: el titular largo se AVISA y se guarda igual',
        (tester) async {
      // Recortarlo en silencio convierte un incumplimiento del manual en media
      // frase en la pared del club.
      await abrir(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Etiqueta de patrocinio *'), 'Socio');
      await tester.enterText(find.widgetWithText(TextField, 'Titular'),
          'una dos tres cuatro cinco seis siete ocho');
      await tester.pump();
      expect(find.textContaining('van 8'), findsOneWidget);
      final boton =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
      expect(boton.onPressed, isNotNull, reason: 'se avisa, no se bloquea');
    });

    testWidgets('CONTRAPESO: con siete no avisa', (tester) async {
      await abrir(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Etiqueta de patrocinio *'), 'Socio');
      await tester.enterText(find.widgetWithText(TextField, 'Titular'),
          'una dos tres cuatro cinco seis siete');
      await tester.pump();
      expect(find.textContaining('palabras como máximo'), findsNothing);
    });

    testWidgets('cancelar el selector de archivos no deja nada colgado',
        (tester) async {
      await abrir(tester, elegir: () async => null);
      await tester.tap(find.text('Subir logotipo'));
      await tester.pumpAndSettle();
      expect(find.text('Subir logotipo'), findsOneWidget,
          reason: 'vuelve a su estado, no se queda en "Subiendo…"');
    });

    testWidgets('CRITERIO 4: con un logo puesto, se ofrece borrarlo',
        (tester) async {
      await abrir(tester,
          pieza: const PiezaDePatrocinio(
              etiqueta: 'Socio', logoUrl: 'https://x/l.png'));
      expect(find.text('Reemplazar'), findsOneWidget);
      expect(find.byTooltip('Borrar el archivo'), findsOneWidget);
      expect(find.textContaining('no se limpia solo al cerrar'), findsOneWidget);
    });

    testWidgets('y sin logo no se ofrece borrar nada', (tester) async {
      await abrir(tester);
      expect(find.byTooltip('Borrar el archivo'), findsNothing);
    });
  });
}
