// ─────────────────────────────────────────────────────────────────────────────
// EL AVISO DE SCORE INCOMPLETO — cuarta vez, y ahora fuera del `build`
//
// Ha vuelto tres veces desde una ronda real:
//
//   1ª · contaba los DIECIOCHO del campo en una ronda de nueve
//   2ª · lo mismo, en el sitio de al lado que se quedó sin tocar
//   3ª · nombraba JUGADORES cuando lo que faltaban eran HOYOS, y lo repetía
//        seis veces, una por apuesta, con una sola causa
//
// Y un barrido por estructura —el que enumera quién cuenta hoyos por su
// cuenta— no lo cazó ninguna de las veces. El motivo es el mismo que dejó vivir
// la cuenta paralela de la ventaja en Inicio:
//
//     **esta cuenta vivía dentro de un `build()`**, así que ninguna prueba
//     llegaba y ningún barrido la reconocía como una cuenta.
//
// Por eso lo que se arregla aquí no es el aviso: es DÓNDE vive. Una función
// pura que se puede contradecir con una ronda de nueve y un test.
// ─────────────────────────────────────────────────────────────────────────────
import '../engines/bet_engine.dart';
import 'models.dart';

/// Una línea del aviso, ya redactada.
typedef LineaDeAviso = String;

/// Por qué una ronda no tiene el score completo, dicho una vez por causa.
///
/// Vacío cuando no falta nada — que es lo que tiene que devolver una ronda de
/// nueve con sus nueve hoyos anotados.
///
/// [nombreCorto] traduce un id de jugador a lo que se enseña.
List<LineaDeAviso> avisosDeScoreIncompleto(
  Round round, {
  required String Function(String pid) nombreCorto,
}) {
  final mods = [
    for (final grp in round.betGroups)
      for (final m in grp.modules) (grp, m),
  ];

  // ── LOS HOYOS QUE LA RONDA JUEGA, no los que tiene el campo ───────────────
  //
  // Es lo que falló las dos primeras veces: `round.course.holes` son los
  // dieciocho del campo, y en una ronda de nueve nueve hoyos llenos nunca
  // llegaban a dieciocho.
  final enJuego = BetEngine.segmentsOf(round).hoyosEnJuego;

  final porTipo = <BetModuleType, Set<String>>{};

  // ── LOS HOYOS QUE NO ANOTÓ NADIE ──────────────────────────────────────────
  //
  // Son la causa común de toda la ronda, y es lo que se decía seis veces: un
  // hoyo vacío deja a TODOS los jugadores sin score en él, así que cada apuesta
  // nombraba a todos sus participantes. De ahí «falta CAM, RICH, Dylan» cuando
  // lo que faltaban eran los hoyos 10 al 18.
  //
  // Y en una ronda CERRADA no faltan ni siquiera eso: la ronda se declaró de
  // dieciocho, se jugaron nueve y se cerró. No hay nada pendiente — terminó.
  // Abierta sí se dice, porque ahí es justo el aviso que se quiere ver.
  //
  // (`singleNine` pide `totalHoles <= 9`, y ese campo se fija al crear la
  // ronda. Cerrarla en el nueve no lo cambia, y no se toca: los motores
  // liquidan por él y esa liquidación salió bien. Lo que se corrige es el
  // aviso, no el dinero.)
  //
  // Se calcula en su propia pasada, ANTES del recorrido de las apuestas. Se
  // llenaba dentro de ese recorrido y se leía en la misma vuelta: la primera
  // apuesta aún no lo había visto entero, así que el resultado dependía del
  // orden de los módulos.
  final hoyosVacios = {
    for (final h in enJuego)
      if (!round.scores.keys.any((pid) => round.getScore(pid, h).hasScore)) h,
  };

  // ── UNA RONDA CERRADA NO ESTÁ CAPTURANDO ──────────────────────────────────
  //
  // Este aviso existe para decir «el balance de abajo está incompleto, ve a
  // terminar de anotar». Una ronda cerrada y liquidada no tiene nada que
  // terminar: el balance ya es final. Por eso ahí se dice como mucho UNA cosa,
  // y sobre HOYOS, nunca sobre personas ni una vez por apuesta.
  //
  // Es la cuarta vuelta de este aviso, y el caso real fue este: un score suelto
  // en un hoyo del segundo nueve. `singleNine` pide que NADIE haya anotado en
  // el segundo segmento, así que un solo número en el 10 convierte una ronda de
  // nueve en una de dieciocho. Los hoyos 11 al 18 quedaban vacíos —causa común,
  // callada— pero el 10 no, y los tres que no lo anotaron salían como que
  // «faltan», seis veces, una por apuesta.
  //
  // (La raíz está en `segmentsOf`, y ahí no se toca: ese mismo `singleNine`
  // decide si Nassau liquida el B9 y el total. Cambiarlo mueve dinero en rondas
  // ya liquidadas, y nadie lo ha pedido. Queda dicho.)
  if (round.isFinished) {
    final aMedias = <int>{};
    final sinScore = <String>{};
    for (final h in enJuego) {
      if (hoyosVacios.contains(h)) continue;
      for (final pid in round.scores.keys) {
        if (round.getScore(pid, h).hasScore) continue;
        aMedias.add(h);
        sinScore.add(nombreCorto(pid));
      }
    }
    if (aMedias.isEmpty) return const [];
    // El hoyo primero, porque el hoyo es la causa: con «(10)» delante se ve de
    // un vistazo que alguien tocó el segundo nueve. El nombre detrás, porque
    // sigue siendo el dato accionable si de verdad quedó un jugador sin anotar.
    return [
      'Se cerró con ${aMedias.length} hoyo${aMedias.length == 1 ? '' : 's'} '
          'a medias (${rangoDeHoyos(aMedias)}) · sin score: '
          '${sinScore.join(', ')}',
    ];
  }

  for (final (grp, m) in mods) {
    final pids = round.scoreCarriersOfModule(m, grp.playerIds);
    final faltan = <String>{};
    // Los hoyos que esta apuesta tiene que mirar: los de la ronda menos los que
    // no anotó nadie. Si lo único que le falta son ésos, su motivo es el de la
    // ronda entera y se dice una vez más abajo, no una por apuesta.
    for (final h in enJuego) {
      if (hoyosVacios.contains(h)) continue;
      for (final pid in pids) {
        if (!round.getScore(pid, h).hasScore) faltan.add(nombreCorto(pid));
      }
    }
    if (faltan.isEmpty) continue;
    porTipo[m.type] = {...?porTipo[m.type], ...faltan};
  }

  return [
    // La causa común, UNA vez, con el número que la convierte en diagnóstico:
    // «18 en juego y 9 sin anotar» explica de golpe una ronda que se creó de
    // dieciocho y se dejó en nueve.
    if (hoyosVacios.isNotEmpty)
      'La ronda tiene ${enJuego.length} hoyos en juego y '
          '${hoyosVacios.length} sin anotar (${rangoDeHoyos(hoyosVacios)})',
    // Una línea por TIPO, y siempre con la misma forma.
    //
    // Había una segunda forma —«sin score en N duelos»— para cuando varios
    // módulos del mismo tipo fallaban a la vez. Escondía justo el dato que se
    // necesita: con dos Nassau a los que les falta el mismo jugador decía «sin
    // score en 2 duelos» y no lo nombraba. Los nombres ya vienen unidos de los
    // duelos del tipo, así que decirlos es a la vez más corto y más útil.
    for (final e in porTipo.entries)
      '${e.key.label} · falta ${e.value.join(', ')}',
  ];
}

/// «10–18» en vez de «10, 11, 12, 13, 14, 15, 16, 17, 18».
///
/// Nueve números seguidos no se leen; un rango sí. Con hoyos sueltos se
/// enumeran, que es cuando el detalle importa.
String rangoDeHoyos(Set<int> hoyos) {
  if (hoyos.isEmpty) return '';
  final orden = hoyos.toList()..sort();
  final tramos = <String>[];
  var ini = orden.first, prev = orden.first;
  for (final h in orden.skip(1)) {
    if (h == prev + 1) {
      prev = h;
      continue;
    }
    tramos.add(ini == prev ? '$ini' : '$ini–$prev');
    ini = prev = h;
  }
  tramos.add(ini == prev ? '$ini' : '$ini–$prev');
  return tramos.join(', ');
}
