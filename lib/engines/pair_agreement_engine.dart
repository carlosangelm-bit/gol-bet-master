// ─────────────────────────────────────────────────────────────────────────────
// PAIR AGREEMENT ENGINE
//
// Traduce entre dos mundos:
//   • Acuerdos recordados  — qué apuesta habitualmente cada pareja ([PairAgreement])
//   • Módulos de una ronda — los duelos concretos que liquida el BetEngine
//
// Existe porque configurar una ronda era reconstruir desde cero lo mismo de
// siempre. Con esto, meter a los jugadores instancia sus acuerdos y la
// configuración se reduce a revisar y ajustar las desviaciones.
//
// Es lógica pura: no toca Firestore ni UI, así que se puede testear sin red.
//
// La persistencia vive dentro de [GamePreset]: un acuerdo pertenece a un juego
// concreto ("el de los martes"), porque los mismos jugadores pueden apostar
// distinto según el día. Un acuerdo sin juego que lo enmarque es ambiguo.
// ─────────────────────────────────────────────────────────────────────────────
import '../models/models.dart';

/// Estado de una pareja presente en la ronda respecto de su acuerdo guardado.
enum PairStatus {
  /// Los módulos de la ronda coinciden con el acuerdo. Nada que decidir.
  asAlways,

  /// Hay acuerdo guardado pero lo de la ronda difiere: distinto importe,
  /// distinto tipo, o apuestas añadidas o quitadas.
  changed,

  /// La pareja juega algo pero no hay acuerdo guardado. Candidato a recordar.
  unsaved,

  /// Hay acuerdo guardado y la pareja no está apostando nada en esta ronda.
  notPlaying,
}

/// Diagnóstico de una pareja: qué dice el acuerdo y qué dice la ronda.
class PairDiff {
  final String pairKey;
  final String p1Id;
  final String p2Id;
  final PairStatus status;

  /// Módulos que la pareja juega en la ronda actual.
  final List<BetModuleInstance> inRound;

  /// Plantillas guardadas para la pareja (vacío si no hay acuerdo).
  final List<BetModuleInstance> saved;

  const PairDiff({
    required this.pairKey,
    required this.p1Id,
    required this.p2Id,
    required this.status,
    required this.inRound,
    required this.saved,
  });

  /// true si conviene ofrecer al usuario guardar/actualizar el acuerdo.
  bool get worthSaving =>
      status == PairStatus.unsaved || status == PairStatus.changed;
}

class PairAgreementEngine {
  // ══════════════════════════════════════════════════════════════════════════
  // LECTURA — de acuerdos a módulos
  // ══════════════════════════════════════════════════════════════════════════

  /// Todas las parejas posibles entre [playerIds], como claves canónicas.
  /// Excluye jugadores virtuales de equipo, que no tienen acuerdos propios.
  static List<String> pairKeysAmong(List<String> playerIds) {
    final ids = playerIds.where((id) => id.isNotEmpty).toSet().toList()..sort();
    final keys = <String>[];
    for (var i = 0; i < ids.length; i++) {
      for (var k = i + 1; k < ids.length; k++) {
        keys.add(BetModuleInstance.pairKey(ids[i], ids[k]));
      }
    }
    return keys;
  }

  /// Instancia los acuerdos de todas las parejas presentes en [playerIds].
  ///
  /// Solo genera módulos para parejas que tienen acuerdo guardado; las demás
  /// quedan sin apuesta y la UI las marca como pendientes de configurar.
  ///
  /// [newId] debe devolver un id distinto en cada llamada (Uuid().v4).
  static List<BetModuleInstance> instantiate({
    required List<String> playerIds,
    required Map<String, PairAgreement> agreements,
    required String Function() newId,
  }) {
    final result = <BetModuleInstance>[];
    for (final key in pairKeysAmong(playerIds)) {
      final agreement = agreements[key];
      if (agreement == null || agreement.isEmpty) continue;
      result.addAll(agreement.instantiate(newId));
    }
    return result;
  }

  /// Parejas presentes que no tienen acuerdo guardado. Son las únicas que
  /// obligan a configurar algo a mano.
  static List<String> pairsWithoutAgreement({
    required List<String> playerIds,
    required Map<String, PairAgreement> agreements,
  }) =>
      pairKeysAmong(playerIds)
          .where((k) => agreements[k]?.isEmpty ?? true)
          .toList();

  // ══════════════════════════════════════════════════════════════════════════
  // ESCRITURA — de módulos a acuerdos
  // ══════════════════════════════════════════════════════════════════════════

  /// Agrupa por pareja los módulos de duelo de [modules].
  ///
  /// Solo considera módulos que cubren exactamente a dos jugadores: un skins de
  /// grupo o una apuesta por equipos no es el acuerdo de ninguna pareja
  /// concreta y guardarlo como tal duplicaría la apuesta al reinstanciarla.
  static Map<String, List<BetModuleInstance>> groupByPair(
      List<BetModuleInstance> modules) {
    final byPair = <String, List<BetModuleInstance>>{};
    for (final m in modules) {
      if (m.hasTeamSides) continue;
      final pids = m.participantIds;
      if (pids.length != 2) continue;
      if (pids[0] == pids[1]) continue;
      byPair.putIfAbsent(BetModuleInstance.pairKey(pids[0], pids[1]), () => [])
          .add(m);
    }
    return byPair;
  }

  /// Compara lo que juega cada pareja en la ronda contra su acuerdo guardado.
  ///
  /// Devuelve una entrada por pareja relevante: las que están jugando y las que
  /// tienen acuerdo pero hoy no juegan ([PairStatus.notPlaying]). Las parejas
  /// sin acuerdo y sin apuesta no aparecen — no hay nada que decir de ellas.
  static List<PairDiff> diff({
    required List<String> playerIds,
    required List<BetModuleInstance> modules,
    required Map<String, PairAgreement> agreements,
  }) {
    final inRoundByPair = groupByPair(modules);
    final present = pairKeysAmong(playerIds).toSet();

    // Parejas a examinar: las que juegan hoy (dentro de la ronda) más las que
    // tienen acuerdo y están presentes aunque no jueguen.
    final keys = <String>{
      ...inRoundByPair.keys.where(present.contains),
      ...agreements.keys.where((k) => present.contains(k)),
    };

    // ids por clave, tomados de la fuente que los tenga explícitos: el acuerdo
    // guardado o los participantes del módulo. Nunca de parsear la clave.
    final idsByKey = <String, (String, String)>{};
    for (final a in agreements.values) {
      idsByKey[a.pairKey] = (a.p1Id, a.p2Id);
    }
    for (final entry in inRoundByPair.entries) {
      final pids = entry.value.first.participantIds;
      if (pids.length == 2) idsByKey[entry.key] ??= (pids[0], pids[1]);
    }

    final diffs = <PairDiff>[];
    for (final key in keys.toList()..sort()) {
      final ids = idsByKey[key];
      if (ids == null) continue;
      final inRound = inRoundByPair[key] ?? const <BetModuleInstance>[];
      final saved = agreements[key]?.templates ?? const <BetModuleInstance>[];

      final PairStatus status;
      if (inRound.isEmpty) {
        status = PairStatus.notPlaying;
      } else if (saved.isEmpty) {
        status = PairStatus.unsaved;
      } else {
        status = _sameBets(inRound, saved)
            ? PairStatus.asAlways
            : PairStatus.changed;
      }

      diffs.add(PairDiff(
        pairKey: key,
        p1Id: ids.$1,
        p2Id: ids.$2,
        status: status,
        inRound: inRound,
        saved: saved,
      ));
    }
    return diffs;
  }

  /// true si ambos conjuntos representan las mismas apuestas con la misma
  /// configuración, sin importar el orden.
  ///
  /// Se apoya en [BetModuleInstance.configSignature], que ya resume tipo +
  /// config tipada e ignora ids y participantes — exactamente lo que distingue
  /// "el mismo trato" de "un trato distinto".
  static bool _sameBets(
      List<BetModuleInstance> a, List<BetModuleInstance> b) {
    if (a.length != b.length) return false;
    final sa = a.map((m) => m.configSignature).toList()..sort();
    final sb = b.map((m) => m.configSignature).toList()..sort();
    for (var i = 0; i < sa.length; i++) {
      if (sa[i] != sb[i]) return false;
    }
    return true;
  }
}
