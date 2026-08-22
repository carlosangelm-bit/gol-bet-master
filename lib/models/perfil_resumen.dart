// ─────────────────────────────────────────────────────────────────────────────
// PERFIL RESUMEN — tu histórico, calculado de los resultados guardados
//
// Lógica pura sobre [RoundResult]. Sin Flutter y sin Firestore: el tablero la
// consume y los tests también.
//
// La distinción que ordena todo el archivo: NO SABER quién eres no es lo mismo
// que ir en cero. Un tablero que enseña "+$0 · 0 rondas" a quien no tiene
// identidad asignada está afirmando algo falso con la misma cara con la que
// afirmaría algo cierto. Por eso [PerfilResumen.identificado] existe y por eso
// no hay un constructor que devuelva ceros por defecto.
//
// Misma regla una capa más abajo: una ronda que jugaron otros no cuenta como
// tablas para ti, se queda fuera.
// ─────────────────────────────────────────────────────────────────────────────
import 'round_result.dart';

/// Tolerancia de comparación, la misma que usa el ledger para netear.
const double _epsilon = 0.005;

/// Una ronda pasada, como la enseña el tablero.
class RondaEnResumen {
  final String roundId;
  final String nombre;
  final String campo;
  final DateTime fecha;

  /// Score bruto total, o null si no anotaste esa ronda.
  final int? gross;
  final int holes;

  /// Lo que te dejó. Positivo ganaste.
  final double neto;

  const RondaEnResumen({
    required this.roundId,
    required this.nombre,
    required this.campo,
    required this.fecha,
    required this.gross,
    required this.holes,
    required this.neto,
  });
}

/// Contra quién juegas más, y cómo te va.
class RivalHabitual {
  final String playerId;
  final String nombre;

  /// Rondas que jugaron juntos.
  final int rondasJuntos;

  /// Tu balance contra él. Positivo: le ganas.
  final double balance;

  const RivalHabitual({
    required this.playerId,
    required this.nombre,
    required this.rondasJuntos,
    required this.balance,
  });
}

/// Tu histórico.
class PerfilResumen {
  /// Si hay un jugador asignado a tu cuenta.
  ///
  /// En false, TODO lo demás está vacío y el tablero debe decir que falta
  /// asignar quién eres —no enseñar ceros—.
  final bool identificado;

  final double balanceTotal;

  /// Rondas cerradas en las que JUGASTE. Las de otros no cuentan.
  final int rondas;

  final int ganadas;
  final int perdidas;
  final int tablas;

  /// Positiva: rondas ganadas seguidas. Negativa: perdidas seguidas. Cero si la
  /// última fue tablas o no hay rondas.
  final int racha;

  /// Las más recientes primero.
  final List<RondaEnResumen> ultimas;

  final RivalHabitual? rival;

  const PerfilResumen({
    required this.identificado,
    required this.balanceTotal,
    required this.rondas,
    required this.ganadas,
    required this.perdidas,
    required this.tablas,
    required this.racha,
    required this.ultimas,
    required this.rival,
  });

  /// Lo que se enseña cuando no se sabe quién eres.
  static const PerfilResumen sinIdentidad = PerfilResumen(
    identificado: false,
    balanceTotal: 0,
    rondas: 0,
    ganadas: 0,
    perdidas: 0,
    tablas: 0,
    racha: 0,
    ultimas: [],
    rival: null,
  );

  bool get hayHistorial => rondas > 0;
}

/// Calcula tu histórico de [resultados].
///
/// [miId] nulo o vacío devuelve [PerfilResumen.sinIdentidad]: sin sujeto no hay
/// nada que sumar, y sumar de todas formas daría ceros indistinguibles de un
/// jugador que va en tablas.
///
/// [cuantasUltimas] limita solo la LISTA de rondas recientes. Los totales usan
/// todo lo que se le pase: un tope silencioso en el balance haría que el número
/// grande de la pantalla dependiera de un detalle de presentación.
PerfilResumen resumenDe(
  List<RoundResult> resultados, {
  required String? miId,
  int cuantasUltimas = 4,
}) {
  if (miId == null || miId.isEmpty) return PerfilResumen.sinIdentidad;

  // Solo las rondas que jugué, más recientes primero.
  final mias = resultados.where((r) => r.jugo(miId)).toList()
    ..sort((a, b) => b.playedAt.compareTo(a.playedAt));

  if (mias.isEmpty) {
    return const PerfilResumen(
      identificado: true,
      balanceTotal: 0,
      rondas: 0,
      ganadas: 0,
      perdidas: 0,
      tablas: 0,
      racha: 0,
      ultimas: [],
      rival: null,
    );
  }

  var total = 0.0, ganadas = 0, perdidas = 0, tablas = 0;
  for (final r in mias) {
    final n = r.netoDe(miId);
    total += n;
    if (n > _epsilon) {
      ganadas++;
    } else if (n < -_epsilon) {
      perdidas++;
    } else {
      tablas++;
    }
  }

  // La racha se lee desde la ronda más reciente hacia atrás y se corta en el
  // primer resultado distinto. Unas tablas la cortan: no continúan una racha ni
  // empiezan una.
  var racha = 0;
  final signoUltima = _signo(mias.first.netoDe(miId));
  if (signoUltima != 0) {
    for (final r in mias) {
      if (_signo(r.netoDe(miId)) != signoUltima) break;
      racha += signoUltima;
    }
  }

  // El rival habitual: con quién coincidí más veces. Se mide por RONDAS
  // JUNTOS, no por dinero —"contra quién juegas" es una pregunta distinta de
  // "a quién le ganas más"—.
  final juntos = <String, int>{};
  final contra = <String, double>{};
  final nombres = <String, String>{};
  for (final r in mias) {
    for (final otro in r.playerIds) {
      if (otro == miId) continue;
      juntos[otro] = (juntos[otro] ?? 0) + 1;
      contra[otro] = (contra[otro] ?? 0) + r.netoEntre(miId, otro);
      nombres[otro] = r.playerNames[otro] ?? nombres[otro] ?? 'Jugador';
    }
  }

  RivalHabitual? rival;
  if (juntos.isNotEmpty) {
    // Empate en rondas: gana el id menor. Arbitrario pero ESTABLE — sin
    // desempate la tarjeta cambiaría de rival entre dos aperturas sin que nada
    // hubiera pasado.
    final orden = juntos.keys.toList()
      ..sort((a, b) {
        final c = juntos[b]!.compareTo(juntos[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    final id = orden.first;
    rival = RivalHabitual(
      playerId: id,
      nombre: nombres[id] ?? 'Jugador',
      rondasJuntos: juntos[id]!,
      balance: _redondea(contra[id] ?? 0),
    );
  }

  return PerfilResumen(
    identificado: true,
    balanceTotal: _redondea(total),
    rondas: mias.length,
    ganadas: ganadas,
    perdidas: perdidas,
    tablas: tablas,
    racha: racha,
    ultimas: mias
        .take(cuantasUltimas)
        .map((r) => RondaEnResumen(
              roundId: r.roundId,
              nombre: r.roundName,
              campo: r.courseName,
              fecha: r.playedAt,
              gross: r.grossByPlayer[miId],
              holes: r.holesPlayed,
              neto: r.netoDe(miId),
            ))
        .toList(),
    rival: rival,
  );
}

int _signo(double v) => v > _epsilon ? 1 : (v < -_epsilon ? -1 : 0);

double _redondea(double v) => (v * 100).round() / 100;

// ─────────────────────────────────────────────────────────────────────────────
// QUÉ ENSEÑA EL TABLERO
//
// El estado vacío es el que se equivoca. "+$0 · 0 rondas" es una afirmación, y
// hay tres situaciones distintas que la producirían siendo falsa en dos:
//
//   · No se sabe quién eres         → no hay sujeto que sumar
//   · Hay rondas cerradas pero sin  → el histórico existe, falta calcularlo
//     resultado guardado
//   · De verdad no has jugado       → cero es cierto
//
// La segunda es la que aparece al estrenar esto: las rondas cerradas ANTES de
// que existiera la colección no tienen documento. Enseñar cero ahí sería dar por
// bueno un total corto. Se enseña la acción de calcularlo.
//
// El número de rondas cerradas se saca de los diferenciales de handicap, que ya
// están en memoria: uno por ronda cerrada, escrito en el mismo momento. No
// cuesta una lectura más.
// ─────────────────────────────────────────────────────────────────────────────

/// Lo que el tablero tiene que enseñar en el bloque del dinero.
enum EstadoTablero {
  /// Falta asignar qué jugador del directorio eres.
  sinIdentidad,

  /// Hay rondas cerradas cuyo resultado no se ha calculado todavía.
  historialPendiente,

  /// Identificado y sin rondas cerradas. El cero es cierto.
  sinRondas,

  /// Hay histórico que enseñar.
  listo,
}

/// Qué enseñar, dado lo que se sabe.
///
/// [rondasCerradas] es el total conocido por otra vía —los diferenciales de
/// handicap—, y [conResultado] cuántas tienen ya su dinero guardado. Que la
/// segunda sea menor que la primera es exactamente "falta backfill".
EstadoTablero estadoDelTablero({
  required bool identificado,
  required int conResultado,
  required int rondasCerradas,
}) {
  if (!identificado) return EstadoTablero.sinIdentidad;
  if (conResultado > 0) return EstadoTablero.listo;
  // Sin resultados: la pregunta es si hay algo que calcular.
  return rondasCerradas > 0
      ? EstadoTablero.historialPendiente
      : EstadoTablero.sinRondas;
}
