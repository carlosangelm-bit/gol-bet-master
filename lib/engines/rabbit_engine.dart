// ─────────────────────────────────────────────────────────────────────────────
// RABBIT — el conejo empieza suelto, lo captura quien gana un hoyo en solitario
//
// Motor aislado. Sale entero de los scores netos que ya existen: no pide nada
// nuevo en el campo.
//
// Y no reinventa el "ganador del hoyo": GameEngine.holeWinner ya devuelve el
// ganador ÚNICO por neto y null en empate, que es literalmente la pregunta que
// Rabbit hace hoyo a hoyo. Reescribirla habría creado una segunda definición de
// "ganar un hoyo" que puede discrepar de la que usa Skins.
//
// Dos decisiones que no se podían deducir de la especificación resumida y se
// preguntaron:
//
//   · "En solitario" = neto más bajo, ESTRICTAMENTE único. Un empate en el
//     mejor score no captura.
//   · Un empate NO suelta el conejo: quien lo tenía sigue teniéndolo. El empate
//     solo impide capturarlo. Es lo que hace que el conejo sea difícil de
//     arrancar, que es de donde sale la tensión del juego.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';
import 'bet_engine.dart';
import 'game_engine.dart';

/// Qué pasó con el conejo en un hoyo.
///
/// Se guarda por hoyo aunque el estado sea solo "de quién es", porque es lo que
/// permite contar la historia en pantalla: "lo agarró A en el 4, lo soltó B en
/// el 7, se quedó suelto". Con solo el dueño final no hay narración posible.
enum RabbitEvento {
  /// Hoyo empatado: nadie captura y el dueño —si había— lo conserva.
  bloqueado,

  /// Estaba suelto y alguien ganó el hoyo en solitario.
  capturado,

  /// El dueño ganó otra vez: sigue siendo suyo.
  retenido,

  /// Ganó otro y el conejo se SUELTA —no se transfiere—. Es la regla estándar:
  /// hay que ganar otro hoyo para volver a agarrarlo. Con [RabbitConfig.robable]
  /// esto no ocurre: se transfiere directo.
  soltado,

  /// Ganó otro y el conejo cambia de manos en el acto. Solo con `robable`.
  robado,

  /// Falta el score de alguien: este hoyo todavía no dice nada.
  sinScore,

  /// Ganó el hoyo pero sin birdie neto, y `squirrel` lo exige.
  sinBirdie,
}

/// Lo que pasó en un hoyo.
class RabbitPaso {
  final int hoyo;
  final RabbitEvento evento;

  /// Quién ganó el hoyo en solitario, si alguien.
  final String? ganador;

  /// De quién es el conejo DESPUÉS de este hoyo. Null = suelto.
  final String? dueno;

  const RabbitPaso({
    required this.hoyo,
    required this.evento,
    required this.ganador,
    required this.dueno,
  });
}

/// El resultado de un segmento —la primera vuelta de nueve o la segunda—.
class RabbitSegmento {
  /// Etiqueta del segmento tal como se cobra. Sale del orden REAL de juego, así
  /// que en una ronda que sale por el 10 el "primer nueve" son los hoyos 10-18.
  final String etiqueta;

  /// true si es el primero que se juega.
  final bool primero;

  final List<RabbitPaso> pasos;

  /// Quién tiene el conejo al final de lo capturado. Null = suelto.
  final String? dueno;

  /// Desde qué hoyo lo tiene.
  ///
  /// Existe para poder contarlo EN CURSO: "lo tiene CAV desde el hoyo 2" dice
  /// algo cierto a mitad de vuelta, mientras "lo tiene al cerrar los nueve"
  /// afirma un resultado que aún puede cambiar. Con siete hoyos por jugar, el
  /// conejo se suelta con que otro gane uno.
  final int? desdeHoyo;

  /// Hoyos del segmento sin capturar del todo.
  final int hoyosSinCapturar;

  const RabbitSegmento({
    required this.etiqueta,
    required this.primero,
    required this.pasos,
    required this.dueno,
    required this.desdeHoyo,
    required this.hoyosSinCapturar,
  });

  bool get quedoSuelto => dueno == null;
  bool get completo => hoyosSinCapturar == 0;
}

class RabbitRecorrido {
  final List<RabbitSegmento> segmentos;
  const RabbitRecorrido(this.segmentos);
}

class RabbitEngine {
  /// Recorre los hoyos y devuelve qué pasó en cada segmento.
  ///
  /// El conejo se REINICIA en el primer hoyo de cada segmento: el Back es una
  /// caza nueva. Por eso el recorrido se hace por segmento y no de corrido.
  static RabbitRecorrido recorrido(
      Round round, List<String> pids, RabbitConfig cfg) {
    final segs = BetEngine.segmentsOf(round);

    // Los segmentos en ORDEN DE JUEGO. singleNine deja fuera el segundo: en una
    // ronda de nueve hoyos no hay un "cierre del 18" que cobrar, y ofrecerlo
    // dejaría un apunte de \$0 en el resultado.
    final aJugar = <({String etiqueta, bool primero, List<int> holes})>[
      (etiqueta: 'primeros 9', primero: true, holes: segs.firstNine),
      if (!segs.singleNine)
        (etiqueta: 'segundos 9', primero: false, holes: segs.secondNine),
    ];

    final salida = <RabbitSegmento>[];

    for (final seg in aJugar) {
      String? dueno; // null = suelto. Arranca suelto en cada segmento.
      final pasos = <RabbitPaso>[];
      var sinCapturar = 0;

      for (final h in seg.holes) {
        final completo =
            pids.every((pid) => round.getScore(pid, h).hasScore);
        if (!completo) {
          sinCapturar++;
          pasos.add(RabbitPaso(
              hoyo: h, evento: RabbitEvento.sinScore, ganador: null,
              dueno: dueno));
          continue;
        }

        // La misma definición de "ganar un hoyo" que usa Skins: neto más bajo
        // y estrictamente único.
        final ganador = GameEngine.holeWinner(round, pids, h, true);

        if (ganador == null) {
          // Empate. No cambia nada: el dueño lo conserva.
          pasos.add(RabbitPaso(
              hoyo: h, evento: RabbitEvento.bloqueado, ganador: null,
              dueno: dueno));
          continue;
        }

        // Squirrel: ganar el hoyo no basta, hace falta birdie neto.
        if (cfg.squirrel && !_esBirdieNeto(round, ganador, h)) {
          pasos.add(RabbitPaso(
              hoyo: h, evento: RabbitEvento.sinBirdie, ganador: ganador,
              dueno: dueno));
          continue;
        }

        if (dueno == null) {
          dueno = ganador;
          pasos.add(RabbitPaso(
              hoyo: h, evento: RabbitEvento.capturado, ganador: ganador,
              dueno: dueno));
        } else if (dueno == ganador) {
          pasos.add(RabbitPaso(
              hoyo: h, evento: RabbitEvento.retenido, ganador: ganador,
              dueno: dueno));
        } else if (cfg.robable) {
          dueno = ganador;
          pasos.add(RabbitPaso(
              hoyo: h, evento: RabbitEvento.robado, ganador: ganador,
              dueno: dueno));
        } else {
          // La regla estándar: ganarle al dueño SUELTA el conejo, no lo
          // transfiere. Hay que ganar otro hoyo para agarrarlo.
          dueno = null;
          pasos.add(RabbitPaso(
              hoyo: h, evento: RabbitEvento.soltado, ganador: ganador,
              dueno: null));
        }
      }

      // Desde cuándo lo tiene: el último hoyo en que cambió de manos.
      int? desde;
      for (final p in pasos) {
        if (p.evento == RabbitEvento.capturado ||
            p.evento == RabbitEvento.robado) {
          desde = p.hoyo;
        } else if (p.evento == RabbitEvento.soltado) {
          desde = null;
        }
      }

      salida.add(RabbitSegmento(
          etiqueta: seg.etiqueta, primero: seg.primero, pasos: pasos,
          dueno: dueno, desdeHoyo: desde, hoyosSinCapturar: sinCapturar));
    }

    return RabbitRecorrido(salida);
  }

  static bool _esBirdieNeto(Round round, String pid, int hoyo) {
    final ctx = GameEngine.contextForHole(round, pid, hoyo, true);
    return ctx != null && ctx.relativeToPar < 0;
  }

  /// Los asientos del conejo.
  ///
  /// Quien lo tiene al cerrar el segmento COBRA a cada uno de los demás. El
  /// conejo es una presa, no un castigo: se caza. Cuando queda suelto nadie
  /// cobra ese segmento —y eso es lo que la nota tiene que explicar, porque un
  /// segmento sin asientos es indistinguible de uno que no se calculó—.
  static List<LedgerEntry> liquidar(
      Round round, List<String> pids, BetModuleInstance mod) {
    final cfg = mod.rabbit;
    final rec = recorrido(round, pids, cfg);
    final entries = <LedgerEntry>[];

    // El bote que nadie cobró, si se acumula.
    var arrastre = 0.0;

    for (final seg in rec.segmentos) {
      final enJuego = cfg.value + arrastre;
      arrastre = 0.0;

      if (seg.dueno == null) {
        // Nadie cobra. Con `acumula` el importe pasa al siguiente segmento; sin
        // ella se pierde, que es el estándar.
        if (cfg.acumula) arrastre = enJuego;
        continue;
      }

      final resto = pids.where((p) => p != seg.dueno).toList();
      if (resto.isEmpty || enJuego <= 0) continue;

      final etiqueta = seg.etiqueta;
      for (final otro in resto) {
        entries.add(LedgerEntry(
          fromPlayerId: otro,
          toPlayerId: seg.dueno!,
          amount: enJuego,
          betType: BetModuleType.rabbit,
          reason: 'Conejo $etiqueta',
        ));
      }
    }

    return entries;
  }
}
