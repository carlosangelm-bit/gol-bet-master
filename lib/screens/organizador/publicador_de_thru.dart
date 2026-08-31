// ─────────────────────────────────────────────────────────────────────────────
// EL «THRU» EN VIVO — quién lo escribe, cada cuánto, y por qué así
//
// «Va a mostrarse en vivo en todas las pantallas donde se publique el enlace, y
// el jugador podrá acceder a la versión móvil del leaderboard.»
//
// ── MI OBJECIÓN ANTERIOR ESTABA MAL PLANTEADA ───────────────────────────────
//
// Descarté el Thru diciendo que la pared no tiene sesión. Eso no era el
// problema: `leaderboards/{token}` ya se lee sin sesión y lleva la tabla
// entera. Lo único que había que resolver es CUÁNDO se reescribe — hoy al
// cerrar una ronda, y hace falta que sea mientras se juega.
//
// ── QUIÉN ESCRIBE: el portal, y no los veintidós teléfonos ──────────────────
//
// La regla de `leaderboards` deja escribir SOLO al dueño del documento. Para
// que cada equipo publicara su propio Thru habría que aflojarla, y el token es
// el string menos secreto del sistema: se proyecta en una pared ocho horas.
// Cualquiera que lo lea podría escribir en el documento público.
//
// Así que escribe el portal del organizador, que es el dueño de las rondas del
// shotgun. Y eso trae un beneficio que no se ve de entrada: UN SOLO ESCRITOR.
// Con veintidós teléfonos publicando no habría carrera —el mapa se escribe por
// rutas de campo— pero sí veintidós lecturas de las rondas y veintidós
// escrituras donde basta una.
//
// El precio, y hay que decirlo: el Thru es tan vivo como el portal esté
// abierto. El día del torneo lo está —es la pantalla que el organizador usa—
// pero es una dependencia, y callarla sería el mismo error de antes.
//
// ── CADA CUÁNTO: sesenta segundos, con el número delante ────────────────────
//
// Las dos opciones que se midieron:
//
//   POR HOYO, desde cada equipo: 22 equipos × 18 hoyos = 396 escrituras por
//   ronda, veintidós escritores, y una regla más floja en el documento público.
//
//   POR TIEMPO, desde el portal: una escritura con los veintidós equipos
//   dentro. A 60 s, cinco horas de torneo son 300 escrituras, un escritor, y
//   ninguna regla nueva.
//
// Cuestan lo mismo. Lo que decide es el escritor y la regla.
//
// Y sesenta segundos no es un compromiso: un grupo tarda doce o quince minutos
// en un hoyo, así que un Thru con un minuto de retraso no puede equivocarse en
// más del hoyo en el que están. Agrupar más —cinco minutos— tampoco ahorraría
// nada medible y empezaría a notarse.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/torneo.dart';
import '../../services/firestore_service.dart';
import '../../services/live_round_service.dart';

/// Cada cuánto se reescribe el Thru. Ver la cabecera.
const cadenciaDelThru = Duration(seconds: 60);

/// El mapa de Thru de [grupos], emparejado con los equipos de [torneo].
///
/// ── El emparejamiento, que es donde esto se puede torcer ────────────────────
///
/// Los grupos vienen del servicio y los equipos del torneo, así que hay que
/// cruzarlos. Se cruzan por la SALIDA —«Hoyo 7B»—, que es lo que las rondas
/// llevan en el nombre y lo que el equipo guarda. Cruzar por posición en la
/// lista habría funcionado el primer día y se habría torcido en cuanto un grupo
/// se cerrara antes que otro y el orden cambiara.
///
/// Un grupo sin equipo que le corresponda se salta: en un torneo individual no
/// hay equipos y esto devuelve el mapa vacío, que es lo correcto.
Map<String, ThruDeEquipo> thruDeLosGrupos(
  Torneo torneo,
  List<GrupoDelTorneo> grupos,
  DateTime ahora,
) {
  if (!torneo.porEquipos || torneo.equipos.isEmpty) return const {};
  final porSalida = {for (final e in torneo.equipos) e.salida: e};
  final out = <String, ThruDeEquipo>{};
  for (final g in grupos) {
    // El nombre de la ronda es «Equipo 07 · Hoyo 7B»: la salida es lo que va
    // después del separador. Se busca por contenido y no por posición porque el
    // nombre puede llevar el nombre del equipo en medio.
    final equipo = porSalida.entries
        .where((e) => g.nombre.contains(e.key))
        .map((e) => e.value)
        .firstOrNull;
    if (equipo == null) continue;
    out[equipo.id] = g.thru(ahora);
  }
  return out;
}

/// Mantiene el Thru al día mientras esta pieza está montada.
///
/// Es un widget y no un servicio porque su vida es la de la pantalla: el
/// temporizador arranca al abrir el portal y muere al cerrarlo, sin nada que
/// acordarse de apagar. Un servicio con un timer suelto sobrevive a la pantalla
/// y sigue escribiendo desde ninguna parte.
class PublicadorDeThru extends StatefulWidget {
  final Torneo torneo;
  final Widget child;

  /// Para tests: sin esto el temporizador pide red cada minuto.
  final bool modoDePrueba;

  const PublicadorDeThru({
    super.key,
    required this.torneo,
    required this.child,
    this.modoDePrueba = false,
  });

  @override
  State<PublicadorDeThru> createState() => _PublicadorDeThruState();
}

class _PublicadorDeThruState extends State<PublicadorDeThru> {
  Timer? _timer;

  /// Si una publicación está en marcha. Sin esto, una red lenta acumularía
  /// publicaciones cada minuto hasta que una llegue.
  bool _publicando = false;

  @override
  void initState() {
    super.initState();
    if (widget.modoDePrueba) return;
    // La primera, ya: esperar un minuto para el primer dato haría que el
    // organizador abriera el portal y viera la pared sin Thru.
    _publicar();
    _timer = Timer.periodic(cadenciaDelThru, (_) => _publicar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _publicar() async {
    final t = widget.torneo;
    // Tres condiciones, y las tres son "no hay nada que publicar", no fallos:
    // sin equipos no hay Thru, sin pantalla encendida no hay dónde, y un torneo
    // cerrado ya no se mueve.
    if (!t.porEquipos || t.tokenTele == null || t.cerrado) return;
    if (_publicando) return;
    _publicando = true;
    try {
      final grupos = await LiveRoundService.gruposDelTorneo(t.id);
      final mapa = thruDeLosGrupos(t, grupos, DateTime.now());
      if (mapa.isEmpty) return;
      await FirestoreService.publicarThru(t.tokenTele!, mapa);
    } finally {
      _publicando = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
