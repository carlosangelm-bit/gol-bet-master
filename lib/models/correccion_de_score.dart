// ─────────────────────────────────────────────────────────────────────────────
import 'models.dart';
// CORREGIR UN SCORE, CON CONSTANCIA
//
// «Sobrescribir en silencio un score de otro es lo que hace desconfiar de la
// app entera.»
//
// El día del torneo alguien anota un 5 donde había un 4, o se le olvida un
// hoyo. El organizador tiene que poder arreglarlo — y esa es justo la
// capacidad que, sin rastro, convierte la app en algo de lo que no te fías:
// si el organizador puede cambiar cualquier número y nadie se entera, ningún
// número significa nada.
//
// La constancia es lo que hace que corregir sea aceptable. No es un registro
// de auditoría para nadie externo: es para que el jugador al que le cambiaron
// un golpe pueda ver QUÉ se cambió, DE QUÉ A QUÉ y QUIÉN lo hizo.
//
// ── El nombre horneado que AQUÍ sí es correcto ──────────────────────────────
//
// Cinco veces en este proyecto un dato metido dentro de un nombre acabó
// mintiendo, y la conclusión fue "el nombre es para leerlo, no para llevar
// datos dentro". Esto parece lo contrario y no lo es.
//
// Una corrección es un HECHO PASADO. "Lo corrigió Carlos el sábado a las 11"
// es cierto para siempre, aunque Carlos cambie de nombre en el directorio
// mañana. Guardar solo el uid y resolverlo al pintar daría el nombre de HOY
// para un hecho de ayer — y en un registro de quién hizo qué, eso es peor.
//
// Se guardan los dos: el uid, que es lo que identifica, y el nombre, que es lo
// que estaba escrito cuando pasó.
// ─────────────────────────────────────────────────────────────────────────────

/// Un score que alguien cambió, y el rastro de quién.
class CorreccionDeScore {
  final String jugadorId;

  /// El nombre del jugador cuando se corrigió. Ver la cabecera.
  final String jugadorNombre;

  final int hoyo;

  /// Lo que había. Null cuando el hoyo estaba VACÍO: rellenar un hueco y
  /// cambiar un número son dos cosas distintas y la frase lo dice.
  final int? antes;

  /// Lo que quedó. Null cuando se BORRA un score, que también es corregir.
  final int? despues;

  final String porUid;
  final String porNombre;
  final DateTime cuando;

  const CorreccionDeScore({
    required this.jugadorId,
    required this.jugadorNombre,
    required this.hoyo,
    required this.antes,
    required this.despues,
    required this.porUid,
    required this.porNombre,
    required this.cuando,
  });

  /// La frase, ya escrita. Vive aquí y no en la pantalla porque hay tres
  /// formas distintas —rellenar, cambiar y borrar— y repartirlas por la
  /// interfaz es como acaban diciendo cosas distintas en dos sitios.
  String get frase {
    final quien = '$jugadorNombre · hoyo $hoyo';
    if (antes == null && despues != null) return '$quien: se anotó $despues';
    if (antes != null && despues == null) return '$quien: se borró el $antes';
    return '$quien: $antes → $despues';
  }

  Map<String, dynamic> toJson() => {
        'jugadorId': jugadorId,
        'jugadorNombre': jugadorNombre,
        'hoyo': hoyo,
        if (antes != null) 'antes': antes,
        if (despues != null) 'despues': despues,
        'porUid': porUid,
        'porNombre': porNombre,
        'cuando': cuando.toIso8601String(),
      };

  factory CorreccionDeScore.fromJson(Map<String, dynamic> j) =>
      CorreccionDeScore(
        jugadorId: (j['jugadorId'] as String?) ?? '',
        jugadorNombre: (j['jugadorNombre'] as String?) ?? '—',
        hoyo: (j['hoyo'] as num?)?.toInt() ?? 0,
        antes: (j['antes'] as num?)?.toInt(),
        despues: (j['despues'] as num?)?.toInt(),
        porUid: (j['porUid'] as String?) ?? '',
        porNombre: (j['porNombre'] as String?) ?? '—',
        cuando:
            DateTime.tryParse((j['cuando'] as String?) ?? '') ?? DateTime(2000),
      );
}

/// Aplica una corrección a [round] y deja el rastro.
///
/// ── Función pura, y por qué eso importa aquí ────────────────────────────────
///
/// Corregir es dos cosas a la vez: cambiar el número y anotar que se cambió. Si
/// vivieran en sitios distintos —el número en la pantalla, el rastro en el
/// servicio— llegaría el día en que una se hace y la otra no. Y la que se
/// saltaría es el rastro, porque es la que no se ve.
///
/// Aquí van juntas o no van. Quien llama guarda lo que salga; si no guarda, no
/// pasó ninguna de las dos.
///
/// [nuevo] en null BORRA el score del hoyo. Borrar también es corregir y
/// también deja rastro: un hoyo que se vacía sin decirlo es un score que
/// desaparece.
///
/// Devuelve la ronda sin tocar cuando no hay nada que cambiar —el score ya era
/// ese—: anotar una corrección que no cambió nada llenaría el registro de ruido
/// y haría dudar del que sí importa.
Round conCorreccion(
  Round round, {
  required String jugadorId,
  required int hoyo,
  required int? nuevo,
  required String porUid,
  required String porNombre,
  required DateTime cuando,
}) {
  final actual = round.scores[jugadorId]?[hoyo]?.grossScore;
  if (actual == nuevo) return round;

  final delJugador = Map<int, HoleScore>.from(round.scores[jugadorId] ?? {});
  if (nuevo == null) {
    // El hoyo se vacía conservando lo demás del score —los putts, los eventos—
    // que no es lo que se está corrigiendo.
    // `copyWith(grossScore: null)` NO borra —cae en el valor de antes—, así que
    // se construye entero conservando los putts, que no es lo que se corrige.
    final previo = delJugador[hoyo];
    delJugador[hoyo] = HoleScore(
        playerId: jugadorId, hole: hoyo, putts: previo?.putts ?? 0);
  } else {
    final previo = delJugador[hoyo];
    delJugador[hoyo] = previo == null
        ? HoleScore(playerId: jugadorId, hole: hoyo, grossScore: nuevo)
        : previo.copyWith(grossScore: nuevo);
  }

  return round.copyWith(
    scores: {...round.scores, jugadorId: delJugador},
    correcciones: [
      ...round.correcciones,
      CorreccionDeScore(
        jugadorId: jugadorId,
        jugadorNombre: round.players
                .where((p) => p.id == jugadorId)
                .map((p) => p.name)
                .firstOrNull ??
            '—',
        hoyo: hoyo,
        antes: actual,
        despues: nuevo,
        porUid: porUid,
        porNombre: porNombre,
        cuando: cuando,
      ),
    ],
  );
}
