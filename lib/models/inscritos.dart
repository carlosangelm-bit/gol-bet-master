// ─────────────────────────────────────────────────────────────────────────────
// LA TABLA DE INSCRITOS — el cálculo, aparte de la pantalla
//
// Buscar, ordenar y contar 150 filas es lógica, no pintura. Vive aquí y no
// dentro del portal por dos motivos, y el segundo es el que importa:
//
//   · se puede probar sin montar una pantalla ni una sesión, y
//   · el portal de escritorio y la lista del móvil pueden consumir LO MISMO. Dos
//     implementaciones de "buscar inscritos" habrían dado dos resultados para la
//     misma letra, y el que se equivocara sería el que nadie mira.
//
// ── El hueco que hay que nombrar: el handicap es GLOBAL ─────────────────────
//
// El torneo no guarda handicaps. Guarda una VENTAJA —handicap, sliding o
// ninguna— y, cuando toca handicap, se usa el `handicapBase` de la ficha del
// jugador, que es la misma ficha que usan todas las demás rondas.
//
// O sea que editar el handicap de Ana desde el portal de este torneo le cambia
// el handicap en TODAS partes. No es un defecto de esta pantalla: es que un
// handicap por torneo no existe en el modelo. Se dice en la interfaz en vez de
// dejar que se descubra, y el día que haga falta uno por torneo será un campo
// nuevo, no un parche aquí.
// ─────────────────────────────────────────────────────────────────────────────
import '../services/player_service.dart';
import 'torneo.dart';

/// Cómo se ordena la tabla.
enum OrdenDeInscritos {
  /// Como los inscribió el organizador. Es el orden que él reconoce.
  inscripcion,
  nombre,
  handicap,
}

extension OrdenDeInscritosTexto on OrdenDeInscritos {
  String get label => switch (this) {
        OrdenDeInscritos.inscripcion => 'Orden de inscripción',
        OrdenDeInscritos.nombre => 'Nombre',
        OrdenDeInscritos.handicap => 'Handicap',
      };

  /// Para el móvil, donde los tres tienen que caber en una fila.
  ///
  /// Con la etiqueta larga, "Handicap" se salía de la pantalla en 390 px y solo
  /// aparecía al arrastrar. Un control que hay que descubrir arrastrando es un
  /// control que no está: lo cazó la prueba de la punta estrecha.
  String get labelCorto => switch (this) {
        OrdenDeInscritos.inscripcion => 'Inscripción',
        OrdenDeInscritos.nombre => 'Nombre',
        OrdenDeInscritos.handicap => 'Handicap',
      };
}

/// Una fila de la tabla.
class FilaDeInscrito {
  final String playerId;
  final String nombre;
  final double handicap;

  /// La posición en la que lo inscribió el organizador, empezando en 1.
  final int inscrito;

  /// Está en la lista del torneo pero no en el directorio de quien mira.
  ///
  /// Pasa de verdad: el organizador borra una ficha del directorio y el id se
  /// queda inscrito. Sin esto la fila desaparecía y el recuento no cuadraba con
  /// la lista guardada, que es la clase de diferencia que nadie explica.
  final bool huerfano;

  const FilaDeInscrito({
    required this.playerId,
    required this.nombre,
    required this.handicap,
    required this.inscrito,
    this.huerfano = false,
  });
}

/// Las filas del torneo, buscadas y ordenadas.
///
/// [busca] compara con [nombreComparable], la misma normalización que usan la
/// importación por pegado y el reparto de resultados: dos normalizaciones
/// distintas darían un fallo silencioso —el nombre coincide para el ojo y no
/// para el código—.
List<FilaDeInscrito> filasDeInscritos(
  Torneo torneo,
  List<PlayerWithLink> directorio, {
  String busca = '',
  OrdenDeInscritos orden = OrdenDeInscritos.inscripcion,
  bool descendente = false,
}) {
  final porId = {for (final pw in directorio) pw.player.id: pw};

  var filas = <FilaDeInscrito>[];
  for (var i = 0; i < torneo.participantes.length; i++) {
    final pid = torneo.participantes[i];
    final pw = porId[pid];
    filas.add(FilaDeInscrito(
      playerId: pid,
      // Sin ficha no hay nombre. Se enseña que falta en vez de esconder la fila.
      nombre: pw?.displayName ?? 'Ficha no encontrada',
      handicap: pw?.player.handicapBase ?? 0,
      inscrito: i + 1,
      huerfano: pw == null,
    ));
  }

  final q = nombreComparable(busca);
  if (q.isNotEmpty) {
    filas = filas.where((f) => nombreComparable(f.nombre).contains(q)).toList();
  }

  int cmp(FilaDeInscrito a, FilaDeInscrito b) => switch (orden) {
        OrdenDeInscritos.inscripcion => a.inscrito.compareTo(b.inscrito),
        OrdenDeInscritos.nombre =>
          nombreComparable(a.nombre).compareTo(nombreComparable(b.nombre)),
        // A igual handicap, por nombre: sin desempate, reordenar la tabla
        // barajaba a los quince que van a 12 y parecía que cambiaban de sitio
        // solos.
        OrdenDeInscritos.handicap => a.handicap == b.handicap
            ? nombreComparable(a.nombre).compareTo(nombreComparable(b.nombre))
            : a.handicap.compareTo(b.handicap),
      };

  filas.sort(descendente ? (a, b) => cmp(b, a) : cmp);
  return filas;
}

/// Quita a [playerId] de la lista de inscritos.
///
/// Devuelve el torneo tal cual si no estaba: así quien llama no tiene que
/// comprobarlo y no se guarda una escritura idéntica.
Torneo sinInscrito(Torneo t, String playerId) {
  if (!t.participantes.contains(playerId)) return t;
  return t.copyWith(
    participantes: t.participantes.where((p) => p != playerId).toList(),
    // Y de la siembra del cuadro: dejarlo ahí cruzaba a alguien que ya no juega.
    siembra: t.siembra.where((p) => p != playerId).toList(),
  );
}

/// Quita VARIOS de una vez.
///
/// ── Por qué en bloque y no en bucle ────────────────────────────────────────
///
/// «Copa de Primavera tiene 153 inscritos y las salidas son 22. Para probar hay
/// que bajar a 88: 65 personas fuera, y solo se puede de una en una.»
///
/// Quitar uno a uno no era solo lento: cada quitado guardaba el torneo, la lista
/// se recomponía, y seis clics seguidos en la misma posición contaban UNO —los
/// otros cinco caían mientras la fila se recolocaba—. Encadenar la misma acción
/// sesenta y cinco veces sobre una lista que se mueve no es una molestia, es
/// imposible.
///
/// Esto lo convierte en una escritura y en un solo cambio de lista. Es la misma
/// decisión que ya se tomó en la importación: pegar 150 nombres es UNA acción,
/// así que quitar 65 también.
Torneo sinInscritos(Torneo t, Set<String> playerIds) {
  if (playerIds.isEmpty) return t;
  final fuera = t.participantes.where(playerIds.contains).toSet();
  if (fuera.isEmpty) return t;
  return t.copyWith(
    participantes: t.participantes.where((p) => !fuera.contains(p)).toList(),
    // Y de la siembra del cuadro, por lo mismo que en singular: dejarlos ahí
    // cruzaría a gente que ya no juega.
    siembra: t.siembra.where((p) => !fuera.contains(p)).toList(),
  );
}

/// Añade ids al final, sin duplicar y conservando el orden de inscripción.
Torneo conInscritos(Torneo t, List<String> ids) {
  final ya = t.participantes.toSet();
  final nuevos = <String>[];
  for (final id in ids) {
    if (ya.add(id)) nuevos.add(id);
  }
  if (nuevos.isEmpty) return t;
  return t.copyWith(participantes: [...t.participantes, ...nuevos]);
}

// ─────────────────────────────────────────────────────────────────────────────
// POR QUÉ NO SE ENCUENTRA UN TORNEO — el diagnóstico, no el síntoma
//
// "Este torneo no está en tu cuenta" es lo que se dice cuando la búsqueda
// falla, y es cierto casi siempre. El problema es que también es lo que se dice
// cuando el fallo es OTRO, y entonces manda a buscar el problema al sitio
// equivocado. Ya pasó dos veces con esta misma pantalla.
//
// Así que la pantalla no adivina: compara y CUENTA lo que ve. Un id que difiere
// solo en espacios o mayúsculas, o que es el prefijo de uno de los que llegaron,
// no es "de otra cuenta": es un id mal leído, y eso se sabe mirando.
// ─────────────────────────────────────────────────────────────────────────────

/// Qué pasó al buscar un torneo por id.
enum Hallazgo {
  encontrado,

  /// La lista llegó vacía. Probablemente el problema no es el enlace.
  listaVacia,

  /// Hay torneos, y ninguno se parece a este id. Es de otra cuenta.
  ajeno,

  /// Hay uno que coincide salvo espacios o mayúsculas: el id llegó sucio.
  casiIgual,

  /// Hay uno que se LEE igual pero no lo es: sobra algún carácter que no se ve
  /// —un espacio de ancho cero, un salto de línea, un carácter de control—.
  ///
  /// Es el único caso que no se puede diagnosticar mirando la pantalla, porque
  /// en la pantalla los dos ids se ven idénticos. Por eso se nombra: sin esto,
  /// el reporte diría "son iguales y no los encuentra" y no habría por dónde
  /// seguir.
  invisible,

  /// El id buscado es un trozo de uno de los que hay —o al revés—: la URL se
  /// leyó a medias, con la barra final o con la query pegada.
  recortado,
}

class DiagnosticoDeTorneo {
  final Hallazgo hallazgo;

  /// El id que se buscaba, tal como llegó.
  final String buscado;

  /// Los ids que sí llegaron.
  final List<String> disponibles;

  /// Sus nombres, en el mismo orden. Es lo que un humano reconoce.
  final List<String> nombres;

  /// El que casi coincide, si lo hay.
  final String? parecido;

  const DiagnosticoDeTorneo({
    required this.hallazgo,
    required this.buscado,
    required this.disponibles,
    required this.nombres,
    this.parecido,
  });

  /// La frase que explica qué pasó. Sin culpar a nadie de más.
  String get explicacion => switch (hallazgo) {
        Hallazgo.encontrado => '',
        Hallazgo.listaVacia =>
          'No llegó ningún torneo de esta cuenta, así que puede que el '
              'problema no sea el enlace. Prueba a recargar.',
        Hallazgo.ajeno =>
          'El portal solo abre los torneos que organizas tú. Si lo creaste con '
              'otra cuenta, entra con esa.',
        Hallazgo.casiIgual =>
          'Hay un torneo casi con este id: se diferencian en espacios o '
              'mayúsculas. El enlace llegó con algo de más.',
        Hallazgo.invisible =>
          'Hay un torneo con este mismo id, pero el del enlace lleva algún '
              'carácter que no se ve. Por eso los dos se leen igual y no '
              'coinciden.',
        Hallazgo.recortado =>
          'El id del enlace y uno de los tuyos empiezan igual y no terminan '
              'igual. Suele ser una barra final o una interrogación pegada a la '
              'dirección.',
      };
}

String _limpio(String s) => s.trim().toLowerCase();

/// El texto sin los caracteres que NO SE VEN.
///
/// Quita controles, espacios de ancho cero y la marca de orden de bytes; deja
/// intacta la puntuación visible. Esa distinción es la que importa: una barra
/// final se ve y se puede señalar en pantalla; un `\u200b` pegado al copiar, no.
/// Son dos diagnósticos distintos y solo uno necesita que la app lo cuente.
String _sinInvisibles(String s) => s
    .toLowerCase()
    .replaceAll(
        RegExp(r'[\u0000-\u0020\u007f\u00a0\u200b-\u200f\u2028\u2029\ufeff]'),
        '');

/// Busca [id] entre [torneos] y explica el resultado.
DiagnosticoDeTorneo buscarTorneo(String id, List<Torneo> torneos) {
  final ids = torneos.map((t) => t.id).toList();
  final nombres = torneos.map((t) => t.nombre).toList();
  DiagnosticoDeTorneo con(Hallazgo h, [String? parecido]) =>
      DiagnosticoDeTorneo(
          hallazgo: h,
          buscado: id,
          disponibles: ids,
          nombres: nombres,
          parecido: parecido);

  if (ids.contains(id)) return con(Hallazgo.encontrado);
  if (torneos.isEmpty) return con(Hallazgo.listaVacia);

  final q = _limpio(id);
  for (final otro in ids) {
    if (_limpio(otro) == q) return con(Hallazgo.casiIgual, otro);
  }
  // Primero lo que NO se ve, porque es lo único que la pantalla no puede
  // enseñar por su cuenta. Si lo que sobra es puntuación visible —una barra,
  // una interrogación— esto no salta y cae en el recorte, que sí se señala.
  final sinInv = _sinInvisibles(id);
  if (sinInv.isNotEmpty) {
    for (final otro in ids) {
      if (_sinInvisibles(otro) == sinInv) {
        return con(Hallazgo.invisible, otro);
      }
    }
  }
  // Un trozo, en cualquiera de los dos sentidos, y con algo de largo: dos ids
  // cortos que comparten tres letras no son una pista, son ruido.
  if (q.length >= 8) {
    for (final otro in ids) {
      final o = _limpio(otro);
      if (o.startsWith(q) || q.startsWith(o)) {
        return con(Hallazgo.recortado, otro);
      }
    }
  }
  return con(Hallazgo.ajeno);
}
