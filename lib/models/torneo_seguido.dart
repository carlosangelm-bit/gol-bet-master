// ─────────────────────────────────────────────────────────────────────────────
// SEGUIR UN TORNEO AJENO — lo que hace que una liga funcione
//
// ══════════════════════════════════════════════════════════════════════════════
// POR QUÉ ESTE FALLO SOBREVIVIÓ: DOS SILENCIOS ENCADENADOS
// ══════════════════════════════════════════════════════════════════════════════
//
// En una liga de temporada cada jugador marca sus propias rondas. Había DOS cosas
// roas, y ninguna se veía:
//
//   1 · La lista de torneos marcables salía de users/{miUid}/torneos, o sea SOLO
//       los míos. Copa de Primavera —del organizador— no aparecía en el asistente
//       de nadie más. Ni se podía intentar.
//   2 · Y si se hubiera podido, el resultado habría caído en users/{quienCierra}
//       y la tabla del organizador lo habría ignorado.
//
// EL PRIMERO IMPEDÍA LLEGAR AL SEGUNDO, y ahí está la razón de que durara: nadie
// podía producir el caso que habría destapado el otro fallo. Un torneo probado por
// su organizador funcionaba perfectamente, porque él sí veía sus torneos y él sí
// cerraba las rondas.
//
// Es el patrón que conviene reconocer: cuando una función está roa en dos puntos
// de la misma cadena, el primero ESCONDE al segundo, y arreglar solo uno deja el
// fallo intacto con otra cara. Aquí se arreglaron los dos a la vez a propósito
// —seguir el torneo Y publicar el resultado— porque cualquiera de los dos solo no
// habría cambiado nada observable.
//
// Un torneo seguido es una REFERENCIA, no una copia: nombre y emoji para poderlo
// enseñar, y el token y el dueño para poder publicarle resultados. Nada de la
// configuración —cómo puntúa, cómo acumula, el bote— porque eso lo decide el
// organizador y una copia envejecería.
//
// Vive en users/{miUid}/torneosSeguidos/{torneoId}, o sea bajo mi propia cuenta:
// no hace falta ninguna regla nueva para esto.
// ─────────────────────────────────────────────────────────────────────────────

class TorneoSeguido {
  /// El id del torneo del organizador. Es la clave del documento.
  final String torneoId;

  /// El token del enlace. Es lo que permite a la regla verificar quién es el
  /// dueño sin leer datos privados de nadie.
  final String token;

  /// El organizador. Se guarda porque hay que declararlo al publicar un
  /// resultado, y la regla lo compara contra el enlace.
  final String ownerUid;

  final String nombre;
  final String emoji;

  /// Cuándo se empezó a seguir. Para poder decir "sigues este torneo desde…".
  final DateTime desde;

  /// Qué nombre de la lista de participantes reclama esta persona.
  ///
  /// Es EL PUENTE entre las dos partes. El organizador inscribe jugadores de su
  /// directorio y quien sigue el torneo tiene su propia cuenta: no hay id común,
  /// y lo único que comparten es el nombre. Por eso seguir un torneo exige haber
  /// dicho cuál eres —y por eso la lista del enlace, que solo trae inscritos, es
  /// además la comprobación de que estás inscrito—.
  final String jugadorNombre;

  const TorneoSeguido({
    required this.torneoId,
    required this.token,
    required this.ownerUid,
    required this.nombre,
    this.emoji = '🏆',
    required this.desde,
    this.jugadorNombre = '',
  });

  Map<String, dynamic> toJson() => {
        'torneoId': torneoId,
        'token': token,
        'ownerUid': ownerUid,
        'nombre': nombre,
        'emoji': emoji,
        'desde': desde.toIso8601String(),
        if (jugadorNombre.isNotEmpty) 'jugadorNombre': jugadorNombre,
      };

  factory TorneoSeguido.fromJson(Map<String, dynamic> j) => TorneoSeguido(
        torneoId: (j['torneoId'] as String?) ?? '',
        token: (j['token'] as String?) ?? '',
        ownerUid: (j['ownerUid'] as String?) ?? '',
        nombre: (j['nombre'] as String?) ?? 'Torneo',
        emoji: (j['emoji'] as String?) ?? '🏆',
        desde: DateTime.tryParse((j['desde'] as String?) ?? '') ??
            DateTime(2000),
        jugadorNombre: (j['jugadorNombre'] as String?) ?? '',
      );

  /// Si la referencia sirve para publicar.
  ///
  /// Sin nombre reclamado tampoco: el resultado se descartaría en la lectura por
  /// no poder emparejarlo con ningún inscrito, y publicarlo sería escribir algo
  /// que nadie va a contar.
  bool get utilizable =>
      torneoId.isNotEmpty &&
      token.isNotEmpty &&
      ownerUid.isNotEmpty &&
      jugadorNombre.isNotEmpty;
}

/// Un resultado publicado a un torneo ajeno.
///
/// Lleva el resultado de la ronda Y su procedencia: quién lo escribió y a qué
/// torneo. La procedencia no es metadato: es lo que permite descartar en la
/// lectura lo que la regla no puede comprobar en la escritura —ver el comentario
/// del bloque torneoResultados en firestore.rules—.
class ResultadoDeTorneo {
  final String torneoId;
  final String roundId;
  final String token;
  final String torneoOwnerUid;

  /// Quién lo publicó, por uid. Para poder auditar quién escribió qué.
  ///
  /// NO sirve para comprobar la inscripción: un uid de cuenta y un id de jugador
  /// son espacios distintos y no pueden coincidir. Compararlos era el fallo que
  /// hacía que la tabla descartara todo en silencio.
  final String escritoPor;

  /// Qué nombre de la lista de participantes reclama el autor.
  ///
  /// Esto SÍ es lo que decide si cuenta: ver resultadosQueCuentan.
  final String jugadorNombre;

  /// El resultado, en el mismo JSON que RoundResult.
  final Map<String, dynamic> resultado;

  const ResultadoDeTorneo({
    required this.torneoId,
    required this.roundId,
    required this.token,
    required this.torneoOwnerUid,
    required this.escritoPor,
    this.jugadorNombre = '',
    required this.resultado,
  });

  /// El id del documento. Determinista a propósito: volver a cerrar la misma
  /// ronda ACTUALIZA en vez de añadir otra fila, y la regla lo exige.
  String get docId => '${torneoId}_$roundId';

  Map<String, dynamic> toJson() => {
        'torneoId': torneoId,
        'roundId': roundId,
        'token': token,
        'torneoOwnerUid': torneoOwnerUid,
        'escritoPor': escritoPor,
        if (jugadorNombre.isNotEmpty) 'jugadorNombre': jugadorNombre,
        'resultado': resultado,
      };

  factory ResultadoDeTorneo.fromJson(Map<String, dynamic> j) =>
      ResultadoDeTorneo(
        torneoId: (j['torneoId'] as String?) ?? '',
        roundId: (j['roundId'] as String?) ?? '',
        token: (j['token'] as String?) ?? '',
        torneoOwnerUid: (j['torneoOwnerUid'] as String?) ?? '',
        escritoPor: (j['escritoPor'] as String?) ?? '',
        jugadorNombre: (j['jugadorNombre'] as String?) ?? '',
        resultado: j['resultado'] is Map
            ? Map<String, dynamic>.from(j['resultado'] as Map)
            : const {},
      );
}
