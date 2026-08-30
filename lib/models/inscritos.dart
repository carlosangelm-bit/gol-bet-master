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
