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
import 'ledger_engine.dart';
import 'rabbit_engine.dart';
import 'wolf_engine.dart';
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
        case BetModuleType.rabbit:
          notas.addAll(_rabbit(round, grupo, mod));
        case BetModuleType.wolf:
          notas.addAll(_wolf(round, grupo, mod));
        default:
          break;
      }
    }
  }

  // El residuo de redondeo, que no es de ningún formato en concreto: sale de
  // repartir un importe entre cruces que no lo dividen exacto.
  final residuo = _residuoDeRedondeo(round);
  if (residuo != null) notas.add(residuo);

  return notas;
}

/// Cuando el importe no divide exacto entre los cruces, y por tanto lo que se
/// enseña no cuadra al céntimo.
///
/// Lo encontró la prueba de que el ledger cierra en cero sobre toda la matriz:
/// un Nassau 2 contra 3 a \$200 reparte \$33.33 por cruce, así que los dos que
/// ganan cobran \$100 justos y los tres que pagan ponen \$66.67 cada uno. Suma
/// \$200.01. Los ASIENTOS cierran exacto —el reparto es correcto— y lo que se
/// descuadra es lo que se ENSEÑA, porque a cada persona se le redondea su total.
///
/// No se "arregla" moviendo el céntimo a alguien: elegir a quién sería inventarse
/// una regla que el grupo no pactó, y el redondeo es aritmética, no un fallo. Lo
/// que se hace es DECIRLO, que es para lo que existe este canal.
NotaDeLiquidacion? _residuoDeRedondeo(Round round) {
  final entradas = LedgerEngine.entriesOf(round);
  if (entradas.isEmpty) return null;

  // Los balances tal cual salen del ledger, sin redondear a céntimos, contra los
  // que la app enseña. La diferencia es el residuo.
  final crudo = <String, double>{};
  for (final e in entradas) {
    if (e.amount <= 0) continue;
    crudo[e.fromPlayerId] = (crudo[e.fromPlayerId] ?? 0) - e.amount;
    crudo[e.toPlayerId] = (crudo[e.toPlayerId] ?? 0) + e.amount;
  }
  // Al peso, que es como se enseña en las tarjetas y los chips.
  final alPeso = crudo.values.fold(0.0, (s, v) => s + v.roundToDouble());
  if (alPeso.abs() < 0.5) return null;

  final falta = alPeso.abs().round();
  return NotaDeLiquidacion(
    // Sin módulo: el residuo es de la ronda, no de una apuesta.
    moduleId: '',
    tipo: entradas.first.betType,
    texto: 'Las cifras están redondeadas al peso y no cuadran por \$$falta: '
        'el importe no se divide exacto entre los cruces. El reparto es '
        'correcto —los asientos suman cero— así que al pagar, cuadradlo entre '
        'vosotros.',
    tono: TonoNota.informativa,
  );
}

List<NotaDeLiquidacion> _snake(
    Round round, BetGroup grupo, BetModuleInstance mod) {
  final pids = round.participantesDe(mod, grupo.playerIds);
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

// ── RABBIT ───────────────────────────────────────────────────────────────────
//
// Una línea por segmento. El caso que el encargo pide explicar es el conejo
// SUELTO al cerrar: nadie cobra ese tramo, y sin la frase es indistinguible de
// un segmento que no se calculó.
List<NotaDeLiquidacion> _rabbit(
    Round round, BetGroup grupo, BetModuleInstance mod) {
  final pids = round.participantesDe(mod, grupo.playerIds);
  final cfg = mod.rabbit;
  final rec = RabbitEngine.recorrido(round, pids, cfg);
  final notas = <NotaDeLiquidacion>[];

  for (final seg in rec.segmentos) {
    // Un segmento del que no se ha capturado NADA no tiene nada que contar
    // todavía. Decir "el conejo quedó suelto en los segundos nueve" antes de
    // jugarlos sería afirmar el resultado de algo que no ha pasado.
    if (seg.pasos.every((p) => p.evento == RabbitEvento.sinScore)) continue;

    final String texto;
    final TonoNota tono;

    if (seg.dueno == null) {
      final arrastra = cfg.acumula && seg.primero;
      if (seg.completo) {
        texto = 'El conejo quedó suelto al cerrar los ${seg.etiqueta}: '
            '${arrastra ? 'el importe pasa al siguiente tramo' : 'nadie cobra ese tramo'}.';
        tono = TonoNota.informativa;
      } else {
        // En curso "quedó suelto" sería un veredicto. Está suelto, que es otra
        // cosa: cualquiera lo agarra ganando un hoyo.
        texto = 'El conejo está suelto: lo agarra quien gane un hoyo solo. '
            'Quedan ${seg.hoyosSinCapturar} hoyos de los ${seg.etiqueta}.';
        tono = TonoNota.provisional;
      }
    } else {
      final quien = _nombre(round, seg.dueno!);
      // Se cuenta CÓMO llegó ahí, no solo quién: el conejo se mueve varias veces
      // y el dueño sin la historia parece arbitrario.
      final capturas = seg.pasos
          .where((p) =>
              p.evento == RabbitEvento.capturado ||
              p.evento == RabbitEvento.robado)
          .length;
      final sueltas =
          seg.pasos.where((p) => p.evento == RabbitEvento.soltado).length;
      final historia = sueltas > 0
          ? ' Cambió de manos $capturas ${capturas == 1 ? 'vez' : 'veces'} y se '
              'soltó $sueltas.'
          : '';

      if (seg.completo) {
        // Cerrado: el resultado ya es un hecho y se puede afirmar.
        texto = '$quien tiene el conejo al cerrar los ${seg.etiqueta}.$historia';
        tono = TonoNota.informativa;
      } else {
        // EN CURSO. La frase cambia de tiempo verbal a propósito: decir que
        // alguien "lo tiene al cerrar" con hoyos por jugar afirma un resultado
        // que aún puede cambiar —basta con que otro gane un hoyo para que se
        // suelte—. Y el estado del conejo DURANTE la vuelta es justo la tensión
        // del juego, así que callarse hasta el cierre esconde lo que importa.
        final desde =
            seg.desdeHoyo != null ? ' desde el hoyo ${seg.desdeHoyo}' : '';
        texto = 'Lo tiene $quien$desde. Se cobra al cerrar los '
            '${seg.etiqueta}, y quedan ${seg.hoyosSinCapturar} hoyos.$historia';
        tono = TonoNota.provisional;
      }
    }

    notas.add(NotaDeLiquidacion(
        moduleId: mod.id,
        tipo: BetModuleType.rabbit,
        texto: texto,
        tono: tono));
  }

  // Squirrel encendido y nadie capturó nunca: conviene decir por qué, porque
  // desde fuera parece que el formato no funciona.
  if (cfg.squirrel &&
      rec.segmentos.every((s) => s.dueno == null) &&
      rec.segmentos
          .any((s) => s.pasos.any((p) => p.evento == RabbitEvento.sinBirdie))) {
    notas.add(NotaDeLiquidacion(
        moduleId: mod.id,
        tipo: BetModuleType.rabbit,
        texto: 'Con Squirrel encendido hace falta birdie neto para capturar, '
            'y los hoyos ganados se ganaron sin birdie.',
        tono: TonoNota.informativa));
  }

  return notas;
}

// ── WOLF ─────────────────────────────────────────────────────────────────────
//
// Un hoyo sin WolfCall no liquida, y hay que DECIRLO. Es el criterio del
// encargo, y la razón es la misma que en los otros dos: sin la frase, un hoyo
// que no paga es indistinguible de uno que se calculó y salió empatado.
//
// Se agrupan en UNA línea con los hoyos nombrados, no una por hoyo. Dieciocho
// avisos del mismo problema entierran el resto de la pantalla — es el mismo
// colapso que ya se aplicó a los avisos de score incompleto.
List<NotaDeLiquidacion> _wolf(
    Round round, BetGroup grupo, BetModuleInstance mod) {
  final pids = round.participantesDe(mod, grupo.playerIds);
  final notas = <NotaDeLiquidacion>[];

  NotaDeLiquidacion nota(String texto, TonoNota tono) => NotaDeLiquidacion(
      moduleId: mod.id, tipo: BetModuleType.wolf, texto: texto, tono: tono);

  final motivoTamano = BetModuleType.wolf.motivoNoDisponible(pids.length);
  if (motivoTamano != null) {
    // No debería poder crearse —el selector lo atenúa— pero una ronda guardada
    // a la que se le saca un jugador acaba aquí, y quedarse mudo sería lo peor.
    // El motivo sale de la tabla para que diga lo mismo que el selector.
    return [nota('$motivoTamano No liquida.', TonoNota.faltaDato)];
  }

  final hoyos = WolfEngine.recorrido(round, pids, mod.wolf);

  final sinEleccion = hoyos
      .where((h) => h.sinLiquidar == WolfSinLiquidar.sinEleccion)
      .map((h) => h.hoyo)
      .toList();
  final sinScore = hoyos
      .where((h) => h.sinLiquidar == WolfSinLiquidar.sinScore)
      .map((h) => h.hoyo)
      .toList();

  if (sinEleccion.isNotEmpty) {
    // Se distingue de "falta el score": aquí falta una DECISIÓN del usuario,
    // así que el tono pide acción. No se inventa un compañero.
    final lista = sinEleccion.length <= 6
        ? 'H${sinEleccion.join(', H')}'
        : '${sinEleccion.length} hoyos';
    notas.add(nota(
        'Sin compañero elegido en $lista: '
        '${sinEleccion.length == 1 ? 'ese hoyo' : 'esos hoyos'} no liquida'
        '${sinEleccion.length == 1 ? '' : 'n'}. '
        'Se elige al anotar el score.',
        TonoNota.faltaDato));
  }

  if (sinScore.isNotEmpty) {
    notas.add(nota(
        'Faltan scores en ${sinScore.length} '
        '${sinScore.length == 1 ? 'hoyo' : 'hoyos'}.',
        TonoNota.provisional));
  }

  // Los Lone Wolf son la sal del formato: merecen su línea cuando ocurren.
  final solos = hoyos.where((h) => h.liquido && h.loneWolf).toList();
  if (solos.isNotEmpty) {
    final ganados = solos.where((h) => h.ganadores.length == 1).length;
    notas.add(nota(
        '${solos.length} ${solos.length == 1 ? 'hoyo' : 'hoyos'} en solitario: '
        '$ganados ganado${ganados == 1 ? '' : 's'}.',
        TonoNota.informativa));
  }

  return notas;
}
