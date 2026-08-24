// ─────────────────────────────────────────────────────────────────────────────
// FIRESTORE SERVICE — Golf Bet Master
// Gestiona rondas activas, historial y plantillas de apuestas
// ─────────────────────────────────────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../engines/pair_agreement_engine.dart';
import '../models/models.dart';
import '../providers/round_provider.dart' show roundToJson, roundFromJson;
import 'auth_service.dart';
import 'handicap_service.dart';
import 'user_profile_service.dart';
import '../models/round_result.dart';
import '../models/torneo.dart';
import '../models/torneo_seguido.dart';
import '../models/torneo_publicado.dart';

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

  /// El dinero de cada ronda cerrada, en documentos de ~1KB.
  ///
  /// Hermana de scoreDifferentials y por el mismo motivo: el tablero del perfil
  /// necesita tu histórico, y calcularlo de las rondas significaba descargarlas
  /// enteras —Firestore no proyecta campos—. El id del documento es el de la
  /// ronda, así que volver a cerrarla reescribe en vez de sumar dos veces.
  static CollectionReference<Map<String, dynamic>> _roundResults() =>
      _db.collection('users').doc(AuthService.uid).collection('roundResults');

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
      // Y el dinero, que es lo que lee el tablero del perfil.
      await _saveRoundResultFor(round);
    }
    await _rounds().doc(round.id).set(data, SetOptions(merge: true));
  }

  // ── Quién de la ronda eres TÚ ─────────────────────────────────────────────
  //
  // Dos cosas se escriben a tu nombre al cerrar una ronda: el diferencial que
  // mueve tu handicap y el resultado en dinero que alimenta tu perfil. Las dos
  // necesitan la misma respuesta, y antes cada sitio la resolvía a su manera.
  //
  // El orden importa, y el cambio está en la última rama:
  //
  //   1. profile.myPlayerId — la respuesta DURABLE. Se crea al registrarse y el
  //      usuario la puede corregir en Ajustes. Es la única que él controla.
  //   2. linkedUserId == uid — el vínculo de esta ronda. Cubre unirse a una
  //      ronda ajena, que sí escribe el vínculo al entrar.
  //   3. El único que anotó, si es que hay uno solo.
  //
  // Lo que ya NO se hace: caer a `players.first`. Era una adivinanza, y una
  // adivinanza aquí no deja un hueco, escribe el handicap de OTRA PERSONA en el
  // tuyo. Devolver null y no guardar nada es peor a corto plazo y correcto: un
  // dato que falta se nota y se arregla; uno inventado se queda.
  static Player? _yoEnLaRonda(Round round, String uid) {
    if (round.players.isEmpty) return null;

    final mio = UserProfileService.miJugadorId;
    if (mio != null && mio.isNotEmpty) {
      final p = round.players.where((p) => p.id == mio).firstOrNull;
      if (p != null) return p;
      // El perfil dice quién eres y no estás en esta ronda: la organizaste sin
      // jugarla. No hay diferencial tuyo que guardar.
      return null;
    }

    final vinculado =
        round.players.where((p) => p.linkedUserId == uid && !p.isVirtual).firstOrNull;
    if (vinculado != null) return vinculado;

    // Sin identidad y sin vínculo: solo si hay UN anotador es deducible.
    final anotaron = round.players
        .where((p) =>
            !p.isVirtual &&
            (round.scores[p.id] ?? const {})
                .values
                .any((s) => (s.grossScore ?? 0) > 0))
        .toList();
    return anotaron.length == 1 ? anotaron.first : null;
  }

  // ── El dinero de una ronda cerrada ────────────────────────────────────────
  //
  // Se escribe con el id de la ronda como id del documento: cerrar dos veces
  // reescribe, nunca duplica. Y es derivado, así que se puede reconstruir
  // entero desde las rondas —igual que los diferenciales—.
  static Future<void> _saveRoundResultFor(Round round) async {
    if (AuthService.uid == null) return;
    try {
      final result = RoundResult.fromRound(round, playedAt: round.createdAt);
      await _roundResults()
          .doc(round.id)
          .set(result.toJson(), SetOptions(merge: false));
    } catch (e) {
      if (kDebugMode) debugPrint('[RoundResult] Error al guardar: $e');
    }
  }

  /// Los resultados en dinero del usuario, en tiempo real.
  static Stream<List<RoundResult>> roundResultsStream() {
    if (AuthService.uid == null) return Stream.value(const []);
    return _roundResults().snapshots().map((snap) => snap.docs
        .map((d) {
          try {
            return RoundResult.fromJson(Map<String, dynamic>.from(d.data()));
          } catch (_) {
            return null;
          }
        })
        .whereType<RoundResult>()
        .toList());
  }

  /// Reconstruye el resultado de una ronda ya cerrada. Para el backfill.
  static Future<bool> rebuildRoundResult(Round round) async {
    if (!round.isFinished) return false;
    try {
      await _saveRoundResultFor(round);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Calcula y guarda el Score Differential del jugador del usuario al finalizar una ronda.
  static Future<void> _saveScoreDifferentialsForRound(Round round) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    if (round.players.isEmpty) return;
    try {
      final target = _yoEnLaRonda(round, uid);
      if (target == null) return;

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

  // ══════════════════════════════════════════════════════════════════════════════
  // BETTING GROUPS — Grupos habituales con apuestas por duelo
  // ══════════════════════════════════════════════════════════════════════════════

  static CollectionReference<Map<String, dynamic>> _bettingGroups() =>
      _db.collection('users').doc(AuthService.uid).collection('bettingGroups');

  /// Guarda o actualiza un BettingGroup en Firestore.
  static Future<BettingGroup> saveBettingGroup(BettingGroup group) async {
    if (AuthService.uid == null) throw Exception('No autenticado');
    final id   = group.id.isEmpty ? _uuid.v4() : group.id;
    final data = group.copyWith(id: id, updatedAt: DateTime.now()).toFirestore();
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _bettingGroups().doc(id).set(data, SetOptions(merge: true));
    return group.copyWith(id: id, updatedAt: DateTime.now());
  }

  /// Elimina un BettingGroup.
  static Future<void> deleteBettingGroup(String groupId) async {
    if (AuthService.uid == null) return;
    await _bettingGroups().doc(groupId).delete();
  }

  /// Stream reactivo de BettingGroups del usuario.
  static Stream<List<BettingGroup>> bettingGroupsStream() {
    if (AuthService.uid == null) return Stream.value([]);
    return _bettingGroups().snapshots().map((snap) {
      final list = snap.docs
          .map((d) => BettingGroup.fromFirestore(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TORNEOS COMPARTIDOS — la copia publicada
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Colección de NIVEL SUPERIOR, no bajo users/: es lo que la hace legible por
  // alguien que no es el dueño. Y el documento es autocontenido —solo lo del
  // torneo— así que la regla es `read` sobre algo que no tiene nada más.
  //
  // Las reglas están probadas contra el emulador en test_rules/run.mjs. Fue ahí
  // donde salió que users/{uid} tenía `allow read` para cualquier autenticado,
  // exponiendo el correo de todos.

  static CollectionReference<Map<String, dynamic>> _sharedTorneos() =>
      _db.collection('sharedTorneos');

  /// Publica o actualiza la copia de un torneo. Devuelve el token.
  static Future<String> publicarTorneo(TorneoPublicado copia) async {
    if (AuthService.uid == null) throw Exception('No autenticado');
    await _sharedTorneos().doc(copia.token).set(copia.toJson());
    return copia.token;
  }

  /// Apaga el enlace SIN romperlo.
  ///
  /// El documento se sobrescribe con lo mínimo —dueño y bandera— así que deja de
  /// servir nombres y cifras de verdad, pero el TOKEN sobrevive. Encender vuelve
  /// a publicar la instantánea completa en el mismo enlace.
  ///
  /// Es lo que hace posible un enlace estable: borrarlo obligaba a generar otro
  /// token al volver a publicar, o sea a reenviarlo a doce personas.
  static Future<void> apagarEnlace(String token) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    // set y no update: deja el documento con SOLO estos dos campos, así que lo
    // que había dentro deja de estar. Apagar tiene que apagar.
    await _sharedTorneos().doc(token).set({'ownerUid': uid, 'activo': false});
  }

  /// Borra el documento del todo. Solo para cuando se borra el torneo.
  ///
  /// Para dejar de compartir está [apagarEnlace]: borrar rompe el enlace que ya
  /// se repartió.
  static Future<void> revocarTorneo(String token) async {
    if (AuthService.uid == null) return;
    await _sharedTorneos().doc(token).delete();
  }

  /// Lee una copia publicada. Devuelve null si el enlace ya no vale.
  static Future<TorneoPublicado?> leerTorneoPublicado(String token) async {
    try {
      final d = await _sharedTorneos().doc(token).get();
      if (!d.exists || d.data() == null) return null;
      return TorneoPublicado.fromJson(token, Map<String, dynamic>.from(d.data()!));
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TORNEOS SEGUIDOS Y RESULTADOS PUBLICADOS — la liga de temporada
  // ══════════════════════════════════════════════════════════════════════════
  //
  // El shotgun no necesita esto: allí el organizador es dueño de las rondas y sus
  // resultados caen solos en su colección. La liga sí, porque cada jugador cierra
  // la suya.
  //
  // Dos piezas: los torneos que sigo —bajo mi cuenta, sin reglas nuevas— y los
  // resultados que publico a un torneo ajeno, que sí tienen su regla y sus
  // pruebas de emulador.

  static CollectionReference<Map<String, dynamic>> _seguidos() => _db
      .collection('users')
      .doc(AuthService.uid)
      .collection('torneosSeguidos');

  static CollectionReference<Map<String, dynamic>> _torneoResultados() =>
      _db.collection('torneoResultados');

  /// Los torneos ajenos que sigo. Para poder marcarles rondas.
  static Stream<List<TorneoSeguido>> torneosSeguidosStream() {
    if (AuthService.uid == null) return Stream.value(const []);
    return _seguidos().snapshots().map((snap) => snap.docs
        .map((d) {
          try {
            return TorneoSeguido.fromJson({...d.data(), 'torneoId': d.id});
          } catch (_) {
            return null;
          }
        })
        .whereType<TorneoSeguido>()
        .where((x) => x.utilizable)
        .toList());
  }

  /// Empieza a seguir un torneo desde su enlace.
  static Future<void> seguirTorneo(TorneoSeguido s) async {
    if (AuthService.uid == null) throw Exception('No autenticado');
    await _seguidos().doc(s.torneoId).set(s.toJson());
  }

  static Future<void> dejarDeSeguir(String torneoId) async {
    if (AuthService.uid == null) return;
    await _seguidos().doc(torneoId).delete();
  }

  /// Publica el resultado de una ronda a un torneo AJENO.
  ///
  /// El id del documento es determinista —{torneoId}_{roundId}— así que volver a
  /// cerrar la misma ronda actualiza en vez de añadir otra fila. La regla lo
  /// exige, y por eso corregir una ronda no duplica nada.
  static Future<void> publicarResultadoDeTorneo(ResultadoDeTorneo r) async {
    if (AuthService.uid == null) return;
    await _torneoResultados().doc(r.docId).set(r.toJson());
  }

  /// Los resultados publicados a un torneo MÍO, con quién los escribió.
  ///
  /// La procedencia viaja porque la tabla la necesita: solo cuentan los de gente
  /// inscrita, y eso es lo que la regla no puede comprobar al escribir.
  static Future<List<ResultadoPublicado>> resultadosPublicados(
      String torneoId) async {
    final uid = AuthService.uid;
    if (uid == null) return const [];
    try {
      final snap = await _torneoResultados()
          .where('torneoOwnerUid', isEqualTo: uid)
          .where('torneoId', isEqualTo: torneoId)
          .get();
      final out = <ResultadoPublicado>[];
      for (final d in snap.docs) {
        try {
          final r = ResultadoDeTorneo.fromJson(d.data());
          if (r.resultado.isEmpty) continue;
          out.add(ResultadoPublicado(
            // El NOMBRE reclamado, no el uid: es lo único que se puede emparejar
            // con la lista de inscritos. Ver resultadosQueCuentan.
            jugadorNombre: r.jugadorNombre,
            // Y el id, que dice CUÁL de los que jugaron es. Vacío en lo
            // publicado antes de que el campo existiera; se pasa como null para
            // que el emparejamiento caiga al nombre, que es lo que se podía.
            jugadorId: r.jugadorId.isEmpty ? null : r.jugadorId,
            resultado: RoundResult.fromJson(r.resultado),
          ));
        } catch (e) {
          debugPrint('[Torneo] resultado publicado ilegible ${d.id}: $e');
        }
      }
      return out;
    } catch (e) {
      // Sin conexión o sin permiso: la tabla sale con lo propio y no revienta.
      debugPrint('[Torneo] no se pudieron leer los publicados: $e');
      return const [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TORNEOS
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Mismo patrón que bettingGroups. Lo que se guarda es la DEFINICIÓN del
  // torneo —qué rondas cuentan, cómo puntúa, cómo acumula— nunca la tabla: la
  // tabla se deriva de los RoundResult cada vez que se abre.
  //
  // Es la lección del RoundResult desfasado. Si la tabla se guardara, corregir
  // una ronda dejaría la clasificación vieja sin avisar a nadie.

  static CollectionReference<Map<String, dynamic>> _torneos() =>
      _db.collection('users').doc(AuthService.uid).collection('torneos');

  static Future<Torneo> saveTorneo(Torneo t) async {
    if (AuthService.uid == null) throw Exception('No autenticado');
    final id = t.id.isEmpty ? _uuid.v4() : t.id;
    final conId = Torneo.fromJson({...t.toJson(), 'id': id});
    await _torneos().doc(id).set(conId.toJson(), SetOptions(merge: true));
    return conId;
  }

  static Future<void> deleteTorneo(String id) async {
    if (AuthService.uid == null) return;
    await _torneos().doc(id).delete();
  }

  static Stream<List<Torneo>> torneosStream() {
    if (AuthService.uid == null) return Stream.value(const []);
    return _torneos().snapshots().map((snap) => snap.docs
        .map((d) {
          try {
            return Torneo.fromJson({...d.data(), 'id': d.id});
          } catch (_) {
            return null;
          }
        })
        .whereType<Torneo>()
        .toList());
  }

  /// Carga todos los BettingGroups una sola vez.
  static Future<List<BettingGroup>> getBettingGroups() async {
    if (AuthService.uid == null) return [];
    try {
      final snap = await _bettingGroups().get();
      final list = snap.docs
          .map((d) => BettingGroup.fromFirestore(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return [];
    }
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

  /// Nombre del campo, si se decidió incluirlo al guardar.
  ///
  /// OPCIONAL a propósito. Hasta ahora ningún punto de partida guardado —ni
  /// plantilla ni grupo de apuesta— guardaba campo, así que "incluir el campo"
  /// no tenía nada que incluir.
  ///
  /// Quien juega siempre en el mismo campo lo marca; quien rota entre Malanquín
  /// y México, no. Y null significa exactamente eso: no se pidió, no que se
  /// haya perdido. Las plantillas guardadas antes de que existiera el campo lo
  /// tienen null y se comportan igual que siempre.
  final String? courseName;

  const RoundTemplate({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.playerNames,
    required this.betGroupsJson,
    required this.updatedAt,
    this.useCount = 0,
    this.courseName,
  });

  RoundTemplate copyWith({
    String? id, String? name, String? emoji, String? description,
    List<String>? playerNames, List<Map<String, dynamic>>? betGroupsJson,
    DateTime? updatedAt, int? useCount, String? courseName,
  }) => RoundTemplate(
    id:            id ?? this.id,
    name:          name ?? this.name,
    emoji:         emoji ?? this.emoji,
    description:   description ?? this.description,
    playerNames:   playerNames ?? this.playerNames,
    betGroupsJson: betGroupsJson ?? this.betGroupsJson,
    updatedAt:     updatedAt ?? this.updatedAt,
    useCount:      useCount ?? this.useCount,
    courseName:    courseName ?? this.courseName,
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
    // Solo se escribe si se pidió: el default no ensucia lo guardado, y una
    // plantilla vieja releída sigue teniendo null.
    if (courseName != null) 'courseName': courseName,
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
      // Ausente en todo lo guardado antes de que el campo existiera: null, que
      // significa "no se pidió", y se comporta igual que siempre.
      courseName:  d['courseName'] as String?,
    );
  }
}

// ── GamePreset — configuración de partida guardada ────────────────────────────
// Una configuración de partida guarda los módulos de apuesta SIN jugadores.
// Al usarla en una nueva ronda, se asignan los jugadores en ese momento.
/// Un juego recurrente: "el de los martes", "el de los viernes".
///
/// Es el CONTEXTO de las apuestas, y por eso los acuerdos por pareja viven
/// aquí dentro y no en una colección global del usuario: los mismos jugadores
/// pueden apostar distinto el martes que el viernes, así que un acuerdo
/// "Yo↔Oscar" sin juego que lo enmarque es ambiguo.
///
/// Reproduce la estructura de reglas + excepciones que ya usa la pantalla de
/// Apuestas para mostrar la configuración:
///   • [modulesJson]        → REGLAS: lo que juega todo el grupo
///   • [pairAgreementsJson] → EXCEPCIONES: lo que una pareja juega distinto
class GamePreset {
  final String id;
  final String name;           // "Nassau con los amigos"
  final String emoji;          // "⛳️"
  final String description;    // Descripción breve opcional
  final List<Map<String, dynamic>> modulesJson; // BetModuleInstances serializados (sin participantIds)

  /// Acuerdos por pareja de ESTE juego, cada uno con sus dos playerIds
  /// explícitos ([PairAgreement.toFirestore]).
  ///
  /// Se guarda como lista y no como mapa indexado por pairKey a propósito: el
  /// modelo tiene tres convenciones de clave de par con separadores distintos,
  /// y con los ids dentro de cada entrada no hay ninguna clave que parsear.
  final List<Map<String, dynamic>> pairAgreementsJson;

  /// Nómina habitual del juego: quién suele jugar "el de los martes".
  ///
  /// Es una SUGERENCIA, no una restricción — el juego se puede jugar con un
  /// suplente. Se guarda porque los acuerdos por pareja ya referencian
  /// playerIds, así que el juego conoce a sus jugadores de todos modos; tenerlos
  /// listados convierte cargar el juego en un solo toque en vez de re-elegir a
  /// las mismas cuatro personas cada semana.
  final List<String> playerIds;

  final DateTime updatedAt;
  final int useCount;

  const GamePreset({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.modulesJson,
    this.pairAgreementsJson = const [],
    this.playerIds = const [],
    required this.updatedAt,
    this.useCount = 0,
  });

  /// Construye un juego a partir de una configuración ya hecha.
  /// El inverso de [apply]; ver [PairAgreementEngine.capture].
  factory GamePreset.fromCapture({
    required String id,
    required String name,
    required String emoji,
    String description = '',
    required PresetCapture capture,
    required List<String> playerIds,
    int useCount = 0,
  }) =>
      GamePreset(
        id: id,
        name: name,
        emoji: emoji,
        description: description,
        modulesJson: capture.groupRulesJson,
        pairAgreementsJson: capture.pairAgreementsJson,
        playerIds: playerIds,
        updatedAt: DateTime.now(),
        useCount: useCount,
      );

  GamePreset copyWith({
    String? id, String? name, String? emoji, String? description,
    List<Map<String, dynamic>>? modulesJson,
    List<Map<String, dynamic>>? pairAgreementsJson,
    List<String>? playerIds,
    DateTime? updatedAt, int? useCount,
  }) => GamePreset(
    id:          id ?? this.id,
    name:        name ?? this.name,
    emoji:       emoji ?? this.emoji,
    description: description ?? this.description,
    modulesJson: modulesJson ?? this.modulesJson,
    pairAgreementsJson: pairAgreementsJson ?? this.pairAgreementsJson,
    playerIds:   playerIds ?? this.playerIds,
    updatedAt:   updatedAt ?? this.updatedAt,
    useCount:    useCount ?? this.useCount,
  );

  /// Acuerdos por pareja de este juego, indexados por su clave canónica.
  /// Las entradas ilegibles se descartan: un juego con la mitad de sus
  /// acuerdos sigue sirviendo, perderlo entero no.
  Map<String, PairAgreement> get pairAgreements {
    final result = <String, PairAgreement>{};
    for (final j in pairAgreementsJson) {
      final a = PairAgreement.fromFirestore(j, '');
      if (a != null && !a.isEmpty) result[a.pairKey] = a;
    }
    return result;
  }

  /// Solo las REGLAS de grupo, sin las excepciones por pareja.
  ///
  /// Se conserva para el camino que ya existía. Si el juego tiene acuerdos por
  /// pareja, prefiere [apply]: esto los ignora en silencio.
  List<BetModuleInstance> toModules(List<String> playerIds) {
    return modulesJson.map((j) {
      final mod = BetModuleInstance.fromJson(j);
      return mod.copyWith(participantIds: playerIds);
    }).toList();
  }

  /// El juego completo aplicado a [playerIds]: reglas más excepciones, ya
  /// reconciliadas entre sí.
  ///
  /// Es la forma correcta de instanciar un juego. Deliberadamente NO existe un
  /// método que devuelva solo las excepciones: sumarlo a [toModules] crearía dos
  /// apuestas del mismo tipo sobre la misma pareja y se le cobraría dos veces.
  /// Toda la reconciliación vive en [PairAgreementEngine.resolve].
  ///
  /// [newId] debe devolver un id distinto en cada llamada (Uuid().v4).
  ///
  /// Revisa [PresetApplication.conflicts] antes de usar el resultado: lo que
  /// aparezca ahí quedó SIN aplicar y necesita decisión del usuario.
  PresetApplication apply(
    List<String> playerIds,
    String Function() newId,
  ) =>
      PairAgreementEngine.resolve(
        groupRules:
            modulesJson.map((j) => BetModuleInstance.fromJson(j)).toList(),
        agreements: pairAgreements,
        playerIds: playerIds,
        newId: newId,
      );

  Map<String, dynamic> toFirestore() => {
    'id':          id,
    'name':        name,
    'emoji':       emoji,
    'description': description,
    'modulesJson': modulesJson,
    'pairAgreementsJson': pairAgreementsJson,
    'playerIds':   playerIds,
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
      // Ausente en presets guardados antes de esta versión → lista vacía, que
      // se comporta igual que antes: solo reglas de grupo.
      pairAgreementsJson: (d['pairAgreementsJson'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      playerIds: (d['playerIds'] as List? ?? [])
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList(),
      updatedAt:   (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      useCount:    (d['useCount'] as int?) ?? 0,
    );
  }
}
