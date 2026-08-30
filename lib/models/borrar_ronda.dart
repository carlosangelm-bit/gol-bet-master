// ─────────────────────────────────────────────────────────────────────────────
// BORRAR UNA RONDA DEL HISTORIAL — hasta dónde llega, y dónde se para
//
// Una ronda no vive en un sitio. Vive en cinco, y solo los tres primeros se
// pueden borrar desde aquí:
//
//   1 · users/{uid}/rounds/{roundId}              la ronda
//   2 · users/{uid}/roundResults/{roundId}        el balance y MIS torneos
//   3 · users/{uid}/scoreDifferentials/{roundId}  el índice
//   4 · torneoResultados/{torneoId}_{roundId}     lo publicado a torneos AJENOS
//   5 · sharedTorneos/{token} · leaderboards/{token}   las INSTANTÁNEAS
//
// Los tres primeros usan el roundId como id de documento, así que borrar son
// tres borrados y las tablas se arreglan solas: el balance y las tablas de
// torneo se DERIVAN de roundResults, no se guardan.
//
// El cuarto también se puede borrar —la regla deja al autor retirar lo suyo—.
//
// ── El quinto es el que manda ───────────────────────────────────────────────
//
// Una instantánea publicada es una COPIA con fecha. Borrar la ronda no la
// cambia: solo la arregla el organizador volviendo a publicar, y eso no lo
// puede hacer nadie desde esta pantalla.
//
// Así que borrar una ronda de un torneo publicado deja la tabla del organizador
// diciendo algo que ya no existe. Es exactamente el patrón que este proyecto ya
// pagó varias veces —arreglar en un sitio y dejarlo en otro— y por eso aquí se
// para en seco en vez de intentarlo a medias.
//
// Lo que SÍ se puede: una ronda que no cuenta para ningún torneo, y una que solo
// cuenta para torneos MÍOS que nunca se han publicado. En los dos casos no queda
// nada fuera de mi cuenta.
// ─────────────────────────────────────────────────────────────────────────────
import 'torneo.dart';

/// Por qué una ronda no se puede borrar.
enum PorQueNo {
  /// Sí se puede.
  siSePuede,

  /// Cuenta para un torneo de otra persona.
  esDeUnTorneoAjeno,

  /// Cuenta para un torneo mío que ya está publicado.
  torneoPublicado,

  /// La ronda está marcada para un torneo que ya no está en mi cuenta.
  ///
  /// No es lo mismo que "ajeno": puede ser mío y borrado. Se trata como ajeno
  /// —no se borra— porque sin el torneo delante no hay forma de saber si tenía
  /// enlace publicado.
  torneoDesconocido,
}

class SePuedeBorrar {
  final PorQueNo motivo;

  /// Los torneos que lo impiden, por nombre, para poder decirlo.
  final List<String> torneos;

  const SePuedeBorrar(this.motivo, {this.torneos = const []});

  bool get si => motivo == PorQueNo.siSePuede;

  /// La frase que ve el usuario. Con los nombres, nunca "no se puede".
  String get explicacion {
    final lista = torneos.join(', ');
    return switch (motivo) {
      PorQueNo.siSePuede => '',
      PorQueNo.esDeUnTorneoAjeno =>
        'Esta ronda cuenta para un torneo que organiza otra persona '
            '($lista). Borrarla aquí dejaría su tabla diciendo algo que ya no '
            'existe: solo él puede quitarla.',
      PorQueNo.torneoPublicado =>
        'Esta ronda cuenta para $lista, que ya está publicado. La tabla que '
            'compartiste es una copia con fecha y no se arregla sola. Deja de '
            'compartir el torneo y vuelve a intentarlo.',
      PorQueNo.torneoDesconocido =>
        'Esta ronda está marcada para un torneo que ya no está en tu cuenta, '
            'así que no se puede saber qué pasaría con su tabla.',
    };
  }
}

/// Si [torneoIdsDeLaRonda] permite borrar la ronda, dados [misTorneos].
SePuedeBorrar sePuedeBorrar(
  List<String> torneoIdsDeLaRonda,
  List<Torneo> misTorneos,
) {
  // El caso simple, y el más común: no cuenta para nada.
  if (torneoIdsDeLaRonda.isEmpty) {
    return const SePuedeBorrar(PorQueNo.siSePuede);
  }

  final mios = {for (final t in misTorneos) t.id: t};
  final ajenos = torneoIdsDeLaRonda.where((id) => !mios.containsKey(id)).toList();
  if (ajenos.isNotEmpty) {
    // Sin el torneo delante no se distingue "de otro" de "mío y borrado". Los
    // dos se tratan igual: no se borra. Suponer cuál es sería adivinar sobre la
    // tabla de alguien.
    return SePuedeBorrar(PorQueNo.torneoDesconocido, torneos: ajenos);
  }

  // Míos, pero publicados: la instantánea es una copia y no se arregla sola.
  final publicados = torneoIdsDeLaRonda
      .map((id) => mios[id]!)
      .where((t) => t.tokenCompartido != null || t.tokenTele != null)
      .toList();
  if (publicados.isNotEmpty) {
    return SePuedeBorrar(PorQueNo.torneoPublicado,
        torneos: publicados.map((t) => t.nombre).toList());
  }

  // Míos y sin publicar: las tablas se derivan de roundResults, así que
  // borrando la ronda se arreglan solas y no queda nada fuera de mi cuenta.
  return const SePuedeBorrar(PorQueNo.siSePuede);
}
