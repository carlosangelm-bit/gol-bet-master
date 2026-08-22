// ─────────────────────────────────────────────────────────────────────────────
// NOTAS DE LIQUIDACIÓN — lo que una apuesta tiene que DECIR, no cobrar
//
// Hasta ahora una apuesta podía comunicar dos cosas: asientos en el ledger, o
// un StateError que sale en el banner de integridad. Faltaba un tercer canal, y
// se ve claro con Snake:
//
//   Nadie hizo 3-putt en toda la ronda. El cálculo es CORRECTO y el resultado
//   es cero asientos. Pero un cero sin explicación se lee como un fallo, y el
//   banner de integridad no sirve porque no ha pasado nada malo.
//
// Eso es una NOTA: la apuesta liquidó bien y tiene algo que contar. Mismo caso
// el conejo que queda suelto al cerrar el 9, o el hoyo de Wolf donde nadie
// eligió compañero.
//
// La regla que hace que esto no se convierta en un segundo motor: cada nota se
// calcula con la MISMA función que liquida. SnakeEngine.buscar() la llaman las
// dos capas. Si las notas recorrieran los hoyos por su cuenta, la pantalla
// podría decir que la serpiente la tiene RAFA mientras el ledger le cobra a CAM.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';
import 'snake_engine.dart';

/// Qué tono le toca a la nota.
enum TonoNota {
  /// Así funciona la apuesta. No hay nada que hacer.
  informativa,

  /// El resultado puede cambiar todavía. Falta capturar.
  provisional,

  /// Falta un dato que el usuario tiene que dar. Esto sí pide acción.
  faltaDato,
}

class NotaDeLiquidacion {
  final String moduleId;
  final BetModuleType tipo;

  /// La frase, ya escrita para pantalla.
  final String texto;

  final TonoNota tono;

  const NotaDeLiquidacion({
    required this.moduleId,
    required this.tipo,
    required this.texto,
    required this.tono,
  });
}

/// Lo que las apuestas de [round] tienen que decir.
///
/// Vacío es la respuesta normal: la mayoría de los formatos no tienen nada que
/// explicar. Solo aparecen líneas cuando hay algo que un número no dice.
List<NotaDeLiquidacion> notasDeLiquidacion(Round round) {
  final notas = <NotaDeLiquidacion>[];

  for (final grupo in round.betGroups) {
    for (final mod in grupo.modules) {
      switch (mod.type) {
        case BetModuleType.snake:
          notas.addAll(_snake(round, grupo, mod));
        default:
          break;
      }
    }
  }
  return notas;
}

List<NotaDeLiquidacion> _snake(
    Round round, BetGroup grupo, BetModuleInstance mod) {
  final pids = mod.effectivePids(grupo.playerIds);
  final cfg = mod.snake;
  final r = SnakeEngine.buscar(round, pids, cfg);

  NotaDeLiquidacion nota(String texto, TonoNota tono) => NotaDeLiquidacion(
      moduleId: mod.id, tipo: BetModuleType.snake, texto: texto, tono: tono);

  if (!r.hayDueno) {
    // El caso del encargo. Con hoyos sin capturar la frase cambia: "todavía" no
    // es lo mismo que "en toda la ronda", y decir lo segundo a mitad de vuelta
    // sería afirmar algo que aún no se sabe.
    return [
      r.provisional
          ? nota(
              'Nadie ha llegado a ${cfg.umbral} putts todavía. '
              'Quedan ${r.hoyosSinCapturar} hoyos por capturar.',
              TonoNota.provisional)
          : nota(
              'Nadie hizo ${cfg.umbral} putts en toda la ronda: '
              'la serpiente no se cobra.',
              TonoNota.informativa),
    ];
  }

  final nombres = r.duenos.map((pid) => _nombre(round, pid)).join(' y ');
  final quien = r.empatada
      ? '$nombres empataron con ${r.putts} putts en el hoyo ${r.hoyo}'
      : '$nombres la agarró en el hoyo ${r.hoyo} con ${r.putts} putts';

  final comoPaga = r.empatada
      ? (cfg.empate == SnakeEmpate.ambosPagan
          ? ' · pagan los dos completo'
          : ' · se reparten el monto')
      : '';

  if (r.provisional) {
    return [
      nota(
          '$quien$comoPaga. Provisional: quedan ${r.hoyosSinCapturar} hoyos '
          'por capturar y un 3-putt posterior se la lleva.',
          TonoNota.provisional),
    ];
  }
  return [nota('$quien$comoPaga.', TonoNota.informativa)];
}

String _nombre(Round round, String pid) {
  for (final p in round.players) {
    if (p.id == pid) return p.name.split(' ').first;
  }
  return pid;
}
