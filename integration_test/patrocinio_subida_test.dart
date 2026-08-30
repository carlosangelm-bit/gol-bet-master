// ─────────────────────────────────────────────────────────────────────────────
// ⚠ ESTA PRUEBA NO SE HA EJECUTADO NUNCA
//
// El arnés está aquí y es correcto; lo que no hay es una ejecución. Se intentó
// de dos formas y ninguna terminó en el entorno donde se escribió:
//
//   · `flutter test --platform chrome` no carga los plugins de Firebase. El
//     setUpAll se quedó colgado doce minutos hasta que saltó el temporizador.
//   · `flutter drive -d web-server` con chromedriver 151 arrancó y estuvo
//     veinte minutos sin emitir una sola línea. Se abandonó.
//
// Así que quien la ejecute por primera vez está haciendo la verificación de
// verdad, y conviene que lo sepa: si falla, puede ser el código O puede ser el
// arnés. No dar por bueno ninguno de los dos hasta verlo pasar.
//
// EL CAMINO QUE SOLO COMPILABA
//
//   firebase emulators:exec --only storage,auth \
//     "flutter drive -d chrome --driver=test_driver/integration_test.dart \
//      --target=integration_test/patrocinio_subida_test.dart"
//
// Es una prueba de INTEGRACIÓN y no una de las normales por un motivo concreto:
// `flutter test --platform chrome` no carga los plugins de Firebase, y se queda
// colgado en la inicialización hasta que salta el temporizador. Se intentó; el
// setUpAll tardó doce minutos en rendirse.
//
// Todo lo demás de patrocinio se prueba sin Firebase: la ruta, el tope, lo que
// la pantalla pide. Y las reglas se prueban contra el emulador… con el SDK de
// JavaScript.
//
// Queda un tramo que ninguna de las dos cosas toca, y es justo el que en este
// proyecto suele guardar la sorpresa:
//
//     bytes → putData → getDownloadURL → <img>
//
// O sea, el plugin `firebase_storage` de Flutter hablando con la regla de
// verdad. Que la regla acepte una subida del SDK de JS no dice que acepte la de
// Flutter: el contentType, la ruta y el tamaño los construye ESTE código.
//
// Por eso esta prueba corre en un navegador y no en la VM: los plugins de
// Firebase no existen en `flutter test` a secas.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:golf_bet_master/core/firebase_options.dart';
import 'package:golf_bet_master/services/auth_service.dart';
import 'package:golf_bet_master/services/patrocinio_storage.dart';

/// Un PNG de 1×1 de verdad, no bytes al azar.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

void main() {
  setUpAll(() async {
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseStorage.instance.useStorageEmulator('127.0.0.1', 9199);
    // Anónimo: lo único que hace falta es un uid, y la regla compara ese uid
    // con el de la ruta. Es exactamente lo que pasa con una cuenta de verdad.
    await FirebaseAuth.instance.signInAnonymously();
  });

  test('CLAVE: subir de verdad, desde Flutter, contra la regla', () async {
    expect(AuthService.uid, isNotNull, reason: 'sin uid no hay ruta que valga');

    final r = await PatrocinioStorage.subir(
      torneoId: 'tor_prueba',
      espacio: 'cabecera',
      nombreOriginal: 'logo.png',
      datos: _png,
    );

    expect(r.resultado, ResultadoDeSubida.ok, reason: r.frase);
    expect(r.url, isNotNull);
    expect(r.url!, contains('patrocinio'));
  });

  test('y la URL que devuelve sirve para pintar la imagen', () async {
    final r = await PatrocinioStorage.subir(
      torneoId: 'tor_prueba',
      espacio: 'lateral',
      nombreOriginal: 'columna.png',
      datos: _png,
    );
    expect(r.ok, isTrue, reason: r.frase);

    // Se trae de vuelta por la referencia, que es lo que hace un <img>: si el
    // contentType o la ruta estuvieran mal, aquí se vería.
    final vuelta = await FirebaseStorage.instance
        .refFromURL(r.url!)
        .getData();
    expect(vuelta, isNotNull);
    expect(vuelta!.length, _png.length);

    final meta =
        await FirebaseStorage.instance.refFromURL(r.url!).getMetadata();
    expect(meta.contentType, 'image/png',
        reason: 'la regla exige image/*; sin declararlo llegaría octet-stream');
  });

  test('CRITERIO 4: y borrar de verdad lo quita', () async {
    final r = await PatrocinioStorage.subir(
      torneoId: 'tor_prueba',
      espacio: 'pie',
      nombreOriginal: 'socio.png',
      datos: _png,
    );
    expect(r.ok, isTrue, reason: r.frase);

    expect(await PatrocinioStorage.borrar(r.url!), isTrue);

    // Y ya no está. Sin esto, un borrar() que devolviera true sin hacer nada
    // pasaría la línea de arriba.
    var sigue = true;
    try {
      await FirebaseStorage.instance.refFromURL(r.url!).getMetadata();
    } on FirebaseException catch (e) {
      sigue = e.code != 'object-not-found';
    }
    expect(sigue, isFalse, reason: 'el archivo tenía que haber desaparecido');
  });

  test('CONTRAPESO: lo que la regla rechaza, se rechaza de verdad', () async {
    // Un PDF con el contentType correcto para un PDF. La regla pide image/*.
    // Si esto pasara, el espacio de lectura pública serviría para alojar
    // cualquier cosa a nombre del proyecto.
    final ruta = PatrocinioStorage.rutaDe(
        ownerUid: AuthService.uid!, torneoId: 'tor_prueba', archivo: 'x.pdf');
    var rechazado = false;
    try {
      await FirebaseStorage.instance.ref(ruta).putData(
          _png, SettableMetadata(contentType: 'application/pdf'));
    } catch (_) {
      rechazado = true;
    }
    expect(rechazado, isTrue);
  });

  test('CONTRAPESO: y no se puede escribir en el espacio de otro', () async {
    final ruta = PatrocinioStorage.rutaDe(
        ownerUid: 'uid_de_otro', torneoId: 'tor_prueba', archivo: 'colada.png');
    var rechazado = false;
    try {
      await FirebaseStorage.instance
          .ref(ruta)
          .putData(_png, SettableMetadata(contentType: 'image/png'));
    } catch (_) {
      rechazado = true;
    }
    expect(rechazado, isTrue);
  });
}
