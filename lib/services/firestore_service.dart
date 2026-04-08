// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE — Golf Bet Master
// Gestiona rondas activas, historial y plantillas de apuestas
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../providers/round_provider.dart' show roundToJson, roundFromJson;
import 'auth_service.dart';
import 'handicap_service.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;
  static const _uuid = Uuid();

  /// UID del usuario autenticado actualmente (null si no está autenticado)
  static String? get currentUid => AuthService.uid;

  // ── Paths ───────────────────────────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> _rounds() =>
      _db.collection('users').doc(AuthService.uid).collection('rounds');

  static CollectionReference<Map<String, dynamic>> _templates() =>
      _db.collection('users').doc(AuthService.uid).collection('templates');

  // ══════════════════════════════════════════════════════════════════════════════
  // RONDAS
  // ══════════════════════════════════════════════════════════════════════════════

  // ── Paths para diferenciales de handicap ──────────────────────────────────
  static CollectionReference<Map<String, dynamic>> _scoreDiffs() =>
      _db.collection('users').doc(AuthService.uid).collection('scoreDifferentials');

  /// Guarda o actualiza una ronda en Firestore.
  /// Al finalizar, calcula y persiste el Score Differential del jugador propietario.
  static Future<void> saveRound(Round round) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    final data = roundToJson(round);
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['isFinished'] = round.isFinished;
    // Si se está finalizando, agregar el timestamp de finalización
    if (round.isFinished) {
      data['finishedAt'] = FieldValue.serverTimestamp();
      // Calcular y guardar Score Differential para el jugador vinculado al uid
      await _saveScoreDifferentialsForRound(round);
    }
    await _rounds().doc(round.id).set(data, SetOptions(merge: true));
  }

  /// Calcula y guarda el Score Differential del jugador del usuario al finalizar una ronda.
  /// Prioridad: jugador con linkedUserId == uid → primer jugador con scores válidos.
  static Future<void> _saveScoreDifferentialsForRound(Round round) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    if (round.players.isEmpty) return;
    try {
      // Prioridad 1: jugador con linkedUserId == uid
      Player? target = round.players.where((p) => p.linkedUserId == uid).firstOrNull;
      // Prioridad 2: primer jugador con scores registrados
      if (target == null) {
        for (final p in round.players) {
          final hasScores = (round.scores[p.id] ?? {})
              .values.any((s) => (s.grossScore ?? 0) > 0);
          if (hasScores) { target = p; break; }
        }
      }
      // Prioridad 3: primer jugador de la lista
      target ??= round.players.first;

      final diff = HandicapService.calculateFromRound(
        round: round,
        playerId: target.id,
      );
      if (diff == null) return;

      // Guardar en users/{uid}/scoreDifferentials/{roundId}
      await _scoreDiffs().doc(round.id).set(diff.toJson(), SetOptions(merge: false));
      if (kDebugMode) {
        debugPrint('[Handicap] Diferencial ${diff.differential} guardado '
            'para ${target.name} en "${round.name}"');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Handicap] Error al guardar diferencial: $e');
    }
  }

  /// Recalcula y guarda el Score Differential de una ronda ya finalizada.
  /// Útil para migrar el historial existente.
  static Future<bool> recalculateDifferentialForRound(Round round) async {
    if (!round.isFinished) return false;
    try {
      await _saveScoreDifferentialsForRound(round);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stream de todos los Score Differentials del usuario (tiempo real)
  static Stream<List<ScoreDifferential>> scoreDifferentialsStream() {
    if (AuthService.uid == null) return Stream.value([]);
    return _scoreDiffs()
        .snapshots()
        .map((snap) => snap.docs
            .map((d) {
              try {
                return ScoreDifferential.fromJson(
                    Map<String, dynamic>.from(d.data()));
              } catch (_) {
                return null;
              }
            })
            .whereType<ScoreDifferential>()
            .toList());
  }

  /// Carga todos los Score Differentials una vez
  static Future<List<ScoreDifferential>> getScoreDifferentials() async {
    if (AuthService.uid == null) return [];
    try {
      final snap = await _scoreDiffs().get();
      return snap.docs
          .map((d) {
            try {
              return ScoreDifferential.fromJson(
                  Map<String, dynamic>.from(d.data()));
            } catch (_) {
              return null;
            }
          })
          .whereType<ScoreDifferential>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Carga la ronda activa (la más reciente no finalizada)
  static Future<Round?> loadActiveRound() async {
    if (AuthService.uid == null) return null;
    try {
      // Sin orderBy para evitar índice compuesto — filtramos y ordenamos en memoria
      final snap = await _rounds()
          .where('isFinished', isEqualTo: false)
          .limit(10)
          .get();
      if (snap.docs.isEmpty) return null;
      // Ordenar por updatedAt en memoria
      final sorted = snap.docs.toList()
        ..sort((a, b) {
          final aT = (a.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime(0);
          final bT = (b.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime(0);
          return bT.compareTo(aT);
        });
      return roundFromJson(sorted.first.data());
    } catch (_) {
      return null;
    }
  }

  /// Stream de la ronda activa (tiempo real)
  static Stream<Round?> activeRoundStream(String roundId) {
    if (AuthService.uid == null) return Stream.value(null);
    return _rounds().doc(roundId).snapshots().map((snap) {
      if (!snap.exists) return null;
      try { 
        final d = snap.data();
        if (d == null) return null;
        return roundFromJson(d); 
      } catch (_) { return null; }
    });
  }

  /// Finaliza una ronda (marca como terminada en Firestore)
  static Future<void> finishRound(String roundId) async {
    if (AuthService.uid == null) return;
    await _rounds().doc(roundId).update({
      'isFinished': true,
      'finishedAt': FieldValue.serverTimestamp(),
      'updatedAt':  FieldValue.serverTimestamp(),
    });
  }

  /// Recupera rondas huérfanas: documentos con isFinished:false que tienen
  /// scores registrados (probablemente se concluyeron pero no quedaron en historial).
  /// Las marca como finalizadas para que aparezcan en el historial.
  /// Retorna el número de rondas recuperadas.
  static Future<int> recoverOrphanRounds() async {
    if (AuthService.uid == null) return 0;
    try {
      final snap = await _rounds()
          .where('isFinished', isEqualTo: false)
          .limit(20)
          .get();
      int recovered = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        // Solo recuperar si tiene jugadores y scores (ronda que tuvo actividad real)
        final players = data['players'] as List? ?? [];
        final scores  = data['scores'] as Map? ?? {};
        if (players.isNotEmpty && scores.isNotEmpty) {
          await doc.reference.update({
            'isFinished': true,
            'finishedAt': FieldValue.serverTimestamp(),
            'updatedAt':  FieldValue.serverTimestamp(),
          });
          recovered++;
        }
      }
      return recovered;
    } catch (_) {
      return 0;
    }
  }

  /// Elimina una ronda activa
  static Future<void> deleteRound(String roundId) async {
    if (AuthService.uid == null) return;
    await _rounds().doc(roundId).delete();
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // HISTORIAL
  // ══════════════════════════════════════════════════════════════════════════════

  /// Obtiene el historial de rondas finalizadas (paginado)
  static Future<List<RoundSummary>> getHistory({
    int limit = 100,
    DocumentSnapshot? startAfter,
  }) async {
    if (AuthService.uid == null) return [];
    try {
      // Traer suficientes docs para ordenar en memoria sin perder la más reciente
      final snap = await _rounds()
          .where('isFinished', isEqualTo: true)
          .limit(limit)
          .get();
      final list = snap.docs.map((d) => RoundSummary.fromFirestore(d)).toList();
      list.sort((a, b) {
        final aT = a.finishedAt ?? DateTime(0);
        final bT = b.finishedAt ?? DateTime(0);
        return bT.compareTo(aT);
      });
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Stream del historial en tiempo real
  static Stream<List<RoundSummary>> historyStream() {
    if (AuthService.uid == null) return Stream.value([]);
    return _rounds()
        .where('isFinished', isEqualTo: true)
        .limit(100)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => RoundSummary.fromFirestore(d)).toList();
          list.sort((a, b) {
            final aT = a.finishedAt ?? DateTime(0);
            final bT = b.finishedAt ?? DateTime(0);
            return bT.compareTo(aT);
          });
          return list;
        });
  }

  /// Carga una ronda completa del historial
  static Future<Round?> loadRoundById(String roundId) async {
    if (AuthService.uid == null) return null;
    try {
      final snap = await _rounds().doc(roundId).get();
      if (!snap.exists) return null;
      final d = snap.data();
      if (d == null) return null;
      return roundFromJson(d);
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // PLANTILLAS DE APUESTAS FAVORITAS
  // ══════════════════════════════════════════════════════════════════════════════

  /// Guarda una plantilla nueva
  static Future<RoundTemplate> saveTemplate(RoundTemplate template) async {
    if (AuthService.uid == null) throw Exception('No autenticado');
    final id = template.id.isEmpty ? _uuid.v4() : template.id;
    final t = template.copyWith(id: id);
    await _templates().doc(id).set(t.toFirestore());
    return t;
  }

  /// Actualiza una plantilla existente
  static Future<void> updateTemplate(RoundTemplate template) async {
    if (AuthService.uid == null) return;
    await _templates().doc(template.id).set(template.toFirestore(), SetOptions(merge: true));
  }

  /// Elimina una plantilla
  static Future<void> deleteTemplate(String templateId) async {
    if (AuthService.uid == null) return;
    await _templates().doc(templateId).delete();
  }

  /// Stream de plantillas en tiempo real (sin orderBy para evitar índice)
  static Stream<List<RoundTemplate>> templatesStream() {
    if (AuthService.uid == null) return Stream.value([]);
    return _templates()
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => RoundTemplate.fromFirestore(d)).toList();
          list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return list;
        });
  }

  /// Carga todas las plantillas una vez
  static Future<List<RoundTemplate>> getTemplates() async {
    if (AuthService.uid == null) return [];
    try {
      final snap = await _templates()
          .orderBy('updatedAt', descending: true)
          .get();
      return snap.docs.map((d) => RoundTemplate.fromFirestore(d)).toList();
    } catch (_) {
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // CONFIGURACIONES DE PARTIDA (GAME PRESETS)
  // ══════════════════════════════════════════════════════════════════════════════

  static CollectionReference<Map<String, dynamic>> _gamePresets() =>
      _db.collection('users').doc(AuthService.uid).collection('gamePresets');

  /// Guarda un nuevo preset (o sobreescribe si ya existe)
  static Future<GamePreset> saveGamePreset(GamePreset preset) async {
    if (AuthService.uid == null) throw Exception('No autenticado');
    final id = preset.id.isEmpty ? _uuid.v4() : preset.id;
    final p = preset.copyWith(id: id, updatedAt: DateTime.now());
    await _gamePresets().doc(id).set(p.toFirestore());
    return p;
  }

  /// Elimina un preset
  static Future<void> deleteGamePreset(String presetId) async {
    if (AuthService.uid == null) return;
    await _gamePresets().doc(presetId).delete();
  }

  /// Stream de presets en tiempo real (sin orderBy para evitar índice compuesto)
  static Stream<List<GamePreset>> gamePresetsStream() {
    if (AuthService.uid == null) return Stream.value([]);
    return _gamePresets()
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => GamePreset.fromFirestore(d)).toList();
          // Ordenar en memoria por updatedAt descendente
          list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return list;
        });
  }

  /// Carga todos los presets una vez
  static Future<List<GamePreset>> getGamePresets() async {
    if (AuthService.uid == null) return [];
    // No usar orderBy para evitar necesidad de índice compuesto
    final snap = await _gamePresets().get();
    final list = snap.docs.map((d) => GamePreset.fromFirestore(d)).toList();
    // Ordenar en memoria
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }
}

// ── Resumen de ronda para historial (ligero, sin scores completos) ─────────────
class RoundSummary {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final List<String> playerNames;
  final bool isFinished;
  final String docId;

  const RoundSummary({
    required this.id,
    required this.name,
    required this.createdAt,
    this.finishedAt,
    required this.playerNames,
    required this.isFinished,
    required this.docId,
  });

  factory RoundSummary.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final players = (d['players'] as List? ?? []);
    // createdAt puede llegar como Timestamp (escritura nueva) o String ISO (escritura antigua)
    final rawCreatedAt = d['createdAt'];
    final DateTime parsedCreatedAt;
    if (rawCreatedAt is Timestamp) {
      parsedCreatedAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is String) {
      parsedCreatedAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    } else {
      parsedCreatedAt = DateTime.now();
    }
    return RoundSummary(
      id:          d['id'] as String? ?? doc.id,
      name:        d['name'] as String? ?? 'Ronda',
      createdAt:   parsedCreatedAt,
      finishedAt:  (d['finishedAt'] as Timestamp?)?.toDate(),
      playerNames: players.map((p) => (p as Map)['name'] as String? ?? '').toList(),
      isFinished:  d['isFinished'] as bool? ?? false,
      docId:       doc.id,
    );
  }
}

// ── Plantilla de apuesta favorita ─────────────────────────────────────────────
class RoundTemplate {
  final String id;
  final String name;           // "Nassau con los amigos"
  final String emoji;          // "⛳️"
  final String description;    // Descripción breve
  final List<String> playerNames;  // Nombres de los jugadores
  final List<Map<String, dynamic>> betGroupsJson; // BetGroups serializados
  final DateTime updatedAt;
  final int useCount;          // Veces usado

  const RoundTemplate({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.playerNames,
    required this.betGroupsJson,
    required this.updatedAt,
    this.useCount = 0,
  });

  RoundTemplate copyWith({
    String? id, String? name, String? emoji, String? description,
    List<String>? playerNames, List<Map<String, dynamic>>? betGroupsJson,
    DateTime? updatedAt, int? useCount,
  }) => RoundTemplate(
    id:            id ?? this.id,
    name:          name ?? this.name,
    emoji:         emoji ?? this.emoji,
    description:   description ?? this.description,
    playerNames:   playerNames ?? this.playerNames,
    betGroupsJson: betGroupsJson ?? this.betGroupsJson,
    updatedAt:     updatedAt ?? this.updatedAt,
    useCount:      useCount ?? this.useCount,
  );

  /// Reconstruir BetGroups desde la plantilla
  List<BetGroup> toBetGroups() =>
      betGroupsJson.map((j) => BetGroup.fromJson(j)).toList();

  Map<String, dynamic> toFirestore() => {
    'id':            id,
    'name':          name,
    'emoji':         emoji,
    'description':   description,
    'playerNames':   playerNames,
    'betGroupsJson': betGroupsJson,
    'updatedAt':     FieldValue.serverTimestamp(),
    'useCount':      useCount,
  };

  factory RoundTemplate.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return RoundTemplate(
      id:          doc.id,
      name:        d['name'] as String? ?? '',
      emoji:       d['emoji'] as String? ?? '⛳️',
      description: d['description'] as String? ?? '',
      playerNames: List<String>.from(d['playerNames'] as List? ?? []),
      betGroupsJson: (d['betGroupsJson'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      updatedAt:  (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      useCount:    (d['useCount'] as int?) ?? 0,
    );
  }
}

// ── GamePreset — configuración de partida guardada ────────────────────────────
// Una configuración de partida guarda los módulos de apuesta SIN jugadores.
// Al usarla en una nueva ronda, se asignan los jugadores en ese momento.
class GamePreset {
  final String id;
  final String name;           // "Nassau con los amigos"
  final String emoji;          // "⛳️"
  final String description;    // Descripción breve opcional
  final List<Map<String, dynamic>> modulesJson; // BetModuleInstances serializados (sin participantIds)
  final DateTime updatedAt;
  final int useCount;

  const GamePreset({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.modulesJson,
    required this.updatedAt,
    this.useCount = 0,
  });

  GamePreset copyWith({
    String? id, String? name, String? emoji, String? description,
    List<Map<String, dynamic>>? modulesJson,
    DateTime? updatedAt, int? useCount,
  }) => GamePreset(
    id:          id ?? this.id,
    name:        name ?? this.name,
    emoji:       emoji ?? this.emoji,
    description: description ?? this.description,
    modulesJson: modulesJson ?? this.modulesJson,
    updatedAt:   updatedAt ?? this.updatedAt,
    useCount:    useCount ?? this.useCount,
  );

  /// Reconstruir instancias de módulo desde el preset
  /// Se pasan los playerIds para asignarlos como participantes
  List<BetModuleInstance> toModules(List<String> playerIds) {
    return modulesJson.map((j) {
      final mod = BetModuleInstance.fromJson(j);
      return mod.copyWith(participantIds: playerIds);
    }).toList();
  }

  Map<String, dynamic> toFirestore() => {
    'id':          id,
    'name':        name,
    'emoji':       emoji,
    'description': description,
    'modulesJson': modulesJson,
    'updatedAt':   FieldValue.serverTimestamp(),
    'useCount':    useCount,
  };

  factory GamePreset.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return GamePreset(
      id:          doc.id,
      name:        d['name'] as String? ?? '',
      emoji:       d['emoji'] as String? ?? '⛳️',
      description: d['description'] as String? ?? '',
      modulesJson: (d['modulesJson'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      updatedAt:   (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      useCount:    (d['useCount'] as int?) ?? 0,
    );
  }
}
