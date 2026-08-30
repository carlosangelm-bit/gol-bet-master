// ─────────────────────────────────────────────────────────────────────────────
// LOS ARCHIVOS DE PATROCINIO — subirlos, reemplazarlos y borrarlos
//
// ── Por qué Storage y no una URL pegada ─────────────────────────────────────
//
// La alternativa era que el organizador pegara la dirección del logotipo en el
// servidor del patrocinador. Es gratis y es peor: el día que la marca cambie su
// web o se le caiga el servidor, el banner que alguien pagó desaparece de la
// pantalla del club. Con el archivo aquí, la imagen es nuestra y no depende de
// nadie.
//
// ── La ruta lleva el dueño ──────────────────────────────────────────────────
//
//     patrocinio/{ownerUid}/{torneoId}/{archivo}
//
// El uid va en la ruta para que la regla de Storage compruebe de quién es sin
// preguntarle a Firestore. Ver storage.rules, que explica el intercambio.
//
// ── Y por qué NO se guarda la ruta en el modelo ─────────────────────────────
//
// Haría falta para borrar… si no existiera `refFromURL`, que hace exactamente
// eso: de la URL de descarga saca la referencia. Guardar la ruta además de la
// URL habría metido un campo nuevo en la instantánea PÚBLICA del leaderboard, y
// la regla de ese documento es que si dudas de si un campo entra, no entra.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Lo que puede salir de subir un archivo.
enum ResultadoDeSubida {
  ok,
  sinSesion,
  demasiadoGrande,
  noEsImagen,

  /// El proyecto no tiene Storage activado todavía.
  ///
  /// No es un fallo del código ni de la red: es un botón que hay que pulsar una
  /// vez en la consola de Firebase. Tiene su propio caso porque el error que
  /// devuelve Firebase no lo dice —habla de un bucket que no existe—, y sin
  /// traducirlo la pantalla enseñaría un mensaje técnico que no indica a nadie
  /// qué hacer.
  sinBucket,

  /// Falló la subida. El motivo va en [SubidaDePatrocinio.motivo].
  fallo,
}

class SubidaDePatrocinio {
  final ResultadoDeSubida resultado;

  /// La URL de descarga, si salió bien.
  final String? url;
  final String? motivo;

  const SubidaDePatrocinio(this.resultado, {this.url, this.motivo});

  bool get ok => resultado == ResultadoDeSubida.ok;

  /// La frase para la pantalla. Nunca "algo falló".
  String get frase => switch (resultado) {
        ResultadoDeSubida.ok => '',
        ResultadoDeSubida.sinSesion => 'Hay que entrar con tu cuenta para subir '
            'archivos.',
        ResultadoDeSubida.demasiadoGrande =>
          'El archivo pasa de ${PatrocinioStorage.maxMB} MB. Un logotipo no '
              'necesita tanto: exporta a PNG o SVG antes de subirlo.',
        ResultadoDeSubida.noEsImagen =>
          'Solo se aceptan imágenes: PNG, JPG, SVG o WEBP.',
        ResultadoDeSubida.sinBucket =>
          'Falta activar Firebase Storage en este proyecto. Se hace una sola '
              'vez, desde la consola de Firebase → Storage → Comenzar. Hasta '
              'entonces se pueden preparar los textos, pero no subir archivos.',
        ResultadoDeSubida.fallo => 'No se pudo subir: ${motivo ?? "sin motivo"}',
      };
}

class PatrocinioStorage {
  /// El mismo tope que la regla de Storage.
  ///
  /// Está en dos sitios a propósito y conviene saber por qué: la regla es la que
  /// MANDA —protege aunque alguien llame al servicio de otra forma— y esto es
  /// para poder decirlo antes de gastar la subida. Si cambia uno, cambia el
  /// otro; hay una prueba que compara las dos cifras.
  static const maxMB = 5;
  static const maxBytes = maxMB * 1024 * 1024;

  /// Las extensiones que la regla acepta como imagen.
  static const extensiones = ['png', 'jpg', 'jpeg', 'svg', 'webp'];

  /// El `contentType` que le corresponde a una extensión.
  ///
  /// Se declara a mano y no se deja adivinar: la regla de Storage mira el
  /// contentType, así que un `application/octet-stream` por defecto haría que
  /// una subida legítima la rechazara la regla, y el error saldría lejos de
  /// aquí.
  static String? tipoDe(String nombre) {
    final ext = nombre.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'svg' => 'image/svg+xml',
      'webp' => 'image/webp',
      _ => null,
    };
  }

  /// La ruta de un archivo. Pública para que las pruebas la fijen: es la misma
  /// forma que da por buena storage.rules.
  static String rutaDe({
    required String ownerUid,
    required String torneoId,
    required String archivo,
  }) =>
      'patrocinio/$ownerUid/$torneoId/$archivo';

  /// Un nombre único para el archivo.
  ///
  /// Único y no fijo por espacio —"cabecera.png"— porque reemplazar un logotipo
  /// conservando el nombre deja la URL igual, y la imagen vieja sigue saliendo
  /// hasta que a alguien se le ocurra vaciar la caché del navegador. En una
  /// pantalla que nadie toca en ocho horas, eso es la imagen equivocada todo el
  /// día.
  static String nombreDe(String espacio, String original, int cuando) {
    final ext = original.contains('.')
        ? original.split('.').last.toLowerCase()
        : 'png';
    return '$espacio-$cuando.$ext';
  }

  /// Sube [datos] y devuelve la URL de descarga.
  static Future<SubidaDePatrocinio> subir({
    required String torneoId,
    required String espacio,
    required String nombreOriginal,
    required Uint8List datos,
    DateTime? cuando,
  }) async {
    final uid = AuthService.uid;
    if (uid == null) {
      return const SubidaDePatrocinio(ResultadoDeSubida.sinSesion);
    }
    // Las dos comprobaciones ANTES de gastar la subida. La regla las repite;
    // esto es para poder explicarlo en vez de enseñar un error de red.
    if (datos.lengthInBytes >= maxBytes) {
      return const SubidaDePatrocinio(ResultadoDeSubida.demasiadoGrande);
    }
    final tipo = tipoDe(nombreOriginal);
    if (tipo == null) {
      return const SubidaDePatrocinio(ResultadoDeSubida.noEsImagen);
    }
    final ruta = rutaDe(
      ownerUid: uid,
      torneoId: torneoId,
      archivo: nombreDe(
          espacio, nombreOriginal, (cuando ?? DateTime.now()).millisecondsSinceEpoch),
    );
    try {
      final ref = FirebaseStorage.instance.ref(ruta);
      await ref.putData(datos, SettableMetadata(contentType: tipo));
      return SubidaDePatrocinio(ResultadoDeSubida.ok,
          url: await ref.getDownloadURL());
    } catch (e) {
      debugPrint('[Patrocinio] no se pudo subir $ruta: $e');
      if (esFaltaDeBucket('$e')) {
        return const SubidaDePatrocinio(ResultadoDeSubida.sinBucket);
      }
      return SubidaDePatrocinio(ResultadoDeSubida.fallo, motivo: '$e');
    }
  }

  /// Borra el archivo que hay detrás de [url]. **Explícito, nunca automático.**
  ///
  /// Decisión de Carlos: los torneos usan sus activos y los borran después, pero
  /// el borrado lo pide el organizador. Un torneo puede querer conservar su
  /// resumen con los patrocinadores dentro mucho después de cerrarse; borrar al
  /// cerrar habría destruido eso sin preguntar.
  ///
  /// Devuelve true si se borró. Un archivo que ya no está cuenta como borrado:
  /// el objetivo era que no estuviera.
  static Future<bool> borrar(String url) async {
    if (url.isEmpty) return true;
    // Solo lo nuestro. Una URL pegada a mano apunta a otro sitio, y llamar a
    // delete sobre ella es pedirle a Firebase que borre algo ajeno.
    if (!esNuestra(url)) return false;
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return true;
      debugPrint('[Patrocinio] no se pudo borrar: $e');
      return false;
    } catch (e) {
      debugPrint('[Patrocinio] no se pudo borrar: $e');
      return false;
    }
  }

  /// Si el error viene de que el proyecto no tiene Storage activado.
  ///
  /// Se mira por texto porque Firebase no da un código propio para esto: el
  /// bucket sencillamente no existe, y lo que llega es un 404 sobre él. Es feo,
  /// y aun así es mejor que enseñarle al organizador un error de red cuando lo
  /// que falta es pulsar un botón en la consola.
  static bool esFaltaDeBucket(String error) {
    final e = error.toLowerCase();
    return e.contains('bucket') &&
        (e.contains('does not exist') ||
            e.contains('not found') ||
            e.contains('no existe'));
  }

  /// Si la URL apunta a un archivo subido por esta app.
  ///
  /// Se comprueba antes de borrar. También sirve para que la pantalla sepa si
  /// puede ofrecer "quitar el archivo" o solo "quitar el enlace": borrar algo
  /// que no es nuestro no es una opción que tenga sentido enseñar.
  static bool esNuestra(String url) =>
      url.contains('firebasestorage.googleapis.com') &&
      url.contains('patrocinio');
}
