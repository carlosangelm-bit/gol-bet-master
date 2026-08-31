// ─────────────────────────────────────────────────────────────────────────────
// LIVE ROUND SERVICE — Rondas en vivo compartidas en tiempo real
//
// Estructura Firestore:
//   liveRounds/{roundId}                   → documento de la ronda compartida
//   liveRounds/{roundId}/invitations/{uid} → invitación por usuario
//   users/{uid}/liveRoundRefs/{roundId}    → referencia rápida para buscar inv.
//
// Convención:
//   • El organizador escribe la ronda completa en liveRounds/{id}
//   • Cada jugador invitado tiene un doc en liveRounds/{id}/invitations/{uid}
//   • Cuando un jugador acepta, su app escucha liveRounds/{id} en tiempo real
//   • Cualquier escritura de score va a liveRounds/{id} (merge)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../providers/round_provider.dart' show roundToJson, roundFromJson;
import 'auth_service.dart';
import 'firestore_service.dart';

// ── Modelo de invitación ──────────────────────────────────────────────────────
class LiveRoundInvitation {
  final String roundId;
  final String roundName;
  final String liveCode;
  final String ownerUid;
  final String ownerName;
  final List<String> playerNames;
  final String courseName;
  final DateTime createdAt;
  final InvitationStatus status;
  // ID del Player dentro de la ronda que corresponde a este usuario
  final String? myPlayerId;

  const LiveRoundInvitation({
    required this.roundId,
    required this.roundName,
    required this.liveCode,
    required this.ownerUid,
    required this.ownerName,
    required this.playerNames,
    required this.courseName,
    required this.createdAt,
    required this.status,
    this.myPlayerId,
  });

  bool get isPending  => status == InvitationStatus.pending;
  bool get isAccepted => status == InvitationStatus.accepted;

  factory LiveRoundInvitation.fromFirestore(Map<String, dynamic> d, String roundId) {
    return LiveRoundInvitation(
      roundId:     roundId,
      roundName:   d['roundName']   as String? ?? 'Ronda',
      liveCode:    d['liveCode']    as String? ?? '',
      ownerUid:    d['ownerUid']    as String? ?? '',
      ownerName:   d['ownerName']   as String? ?? 'Organizador',
      playerNames: List<String>.from(d['playerNames'] as List? ?? []),
      courseName:  d['courseName']  as String? ?? '',
      createdAt:   (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status:      InvitationStatus.values.firstWhere(
        (s) => s.name == (d['status'] as String? ?? 'pending'),
        orElse: () => InvitationStatus.pending,
      ),
      myPlayerId: d['myPlayerId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'roundName':   roundName,
    'liveCode':    liveCode,
    'ownerUid':    ownerUid,
    'ownerName':   ownerName,
    'playerNames': playerNames,
    'courseName':  courseName,
    'createdAt':   FieldValue.serverTimestamp(),
    'status':      status.name,
    'role':        'invited',   // siempre incluir role para que los queries funcionen
    if (myPlayerId != null) 'myPlayerId': myPlayerId,
  };
}

enum InvitationStatus { pending, accepted, declined }

// ── Servicio principal ────────────────────────────────────────────────────────
class LiveRoundService {
  static final _db = FirebaseFirestore.instance;

  // ── Paths ──────────────────────────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> get _liveRounds =>
      _db.collection('liveRounds');

  static CollectionReference<Map<String, dynamic>> _invitations(String roundId) =>
      _liveRounds.doc(roundId).collection('invitations');

  static CollectionReference<Map<String, dynamic>> _myRefs() =>
      _db.collection('users').doc(AuthService.uid).collection('liveRoundRefs');

  // ── Generar código de 6 chars (letras+números, legible) ───────────────────
  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin 0,O,1,I
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CREAR / PUBLICAR RONDA EN VIVO
  // ══════════════════════════════════════════════════════════════════════════

  /// Publica una ronda en liveRounds y envía invitaciones a los jugadores
  /// que tienen linkedUserId. Retorna la ronda actualizada con isLive=true.
  static Future<Round> publishRound(Round round) async {
    final uid = AuthService.uid;
    if (uid == null) throw Exception('No autenticado');

    final code = _generateCode();
    final liveRound = round.copyWith(
      isLive: true,
      ownerUid: uid,
      liveCode: code,
    );

    // 1. Guardar ronda en colección compartida
    final data = roundToJson(liveRound);
    data['publishedAt'] = FieldValue.serverTimestamp();
    data['updatedAt']   = FieldValue.serverTimestamp();
    await _liveRounds.doc(round.id).set(data);

    // 2. Guardar referencia en el directorio del organizador
    await _myRefs().doc(round.id).set({
      'roundId':  round.id,
      'liveCode': code,
      'role':     'owner',
      'joinedAt': FieldValue.serverTimestamp(),
    });

    // 3. Enviar invitaciones a los jugadores con linkedUserId
    final ownerName = AuthService.currentUser?.displayName ?? 'Organizador';
    final playerNames = round.players.map((p) => p.name).toList();
    final batch = _db.batch();

    for (final player in round.players) {
      if (player.hasLinkedAccount && player.linkedUserId != uid) {
        final invitedUid = player.linkedUserId!;

        // Doc en liveRounds/{id}/invitations/{uid}
        final invRef = _invitations(round.id).doc(invitedUid);
        batch.set(invRef, LiveRoundInvitation(
          roundId:     round.id,
          roundName:   round.name,
          liveCode:    code,
          ownerUid:    uid,
          ownerName:   ownerName,
          playerNames: playerNames,
          courseName:  round.course.name,
          createdAt:   DateTime.now(),
          status:      InvitationStatus.pending,
          myPlayerId:  player.id,
        ).toFirestore());

        // Ref rápida en users/{uid}/liveRoundRefs/{roundId}
        final refDoc = _db.collection('users').doc(invitedUid)
            .collection('liveRoundRefs').doc(round.id);
        batch.set(refDoc, {
          'roundId':     round.id,
          'liveCode':    code,
          'role':        'invited',
          'status':      'pending',
          'myPlayerId':  player.id,
          'invitedAt':   FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
    if (kDebugMode) debugPrint('[LiveRound] Ronda publicada: ${round.id} ($code)');
    return liveRound;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LAS RONDAS DE UN TORNEO — la agregación, y por qué no hace falta más
  // ══════════════════════════════════════════════════════════════════════════
  //
  // El problema medido: la tabla de un torneo sale de tablaDe(t, resultados), y
  // esos resultados son users/{miUid}/roundResults. Si cada grupo cerrara SU
  // ronda, el resultado caería en la colección de cada uno y el organizador no
  // vería nada.
  //
  // ── La colección nueva que NO se construyó, y por qué ─────────────────────
  //
  // Lo primero que se diseñó fue una colección de nivel superior
  // —torneoResultados— donde cada grupo publicara su resultado, con reglas que
  // verificaran la procedencia leyendo la ronda en vivo. Se descartó al medir
  // que NO HACE FALTA:
  //
  //   · Cerrar una ronda en vivo ya está reservado al DUEÑO —lo comprueba la
  //     pantalla de captura y lo cierran las reglas—.
  //   · El resultado se escribe en users/{quienCierra}/roundResults.
  //   · Y quien cierra es necesariamente el dueño.
  //
  // Así que si el organizador es dueño de las rondas de su torneo —que es como
  // funciona un shotgun: él arma los grupos— los resultados caen SOLOS en su
  // colección y la tabla ya agrega. Sin colección nueva, sin reglas nuevas, y
  // sin que nadie escriba bajo users/** de otro.
  //
  // Lo que faltaba no era arquitectura: era que el organizador PUDIERA VER Y
  // CERRAR las rondas de su torneo sin cargarlas como "la ronda actual".
  // loadOwnerActiveLiveRound devuelve la primera sin terminar y con límite 5, así
  // que con veinticinco grupos no servía.

  /// Un grupo del torneo, tal como lo ve el organizador.
  ///
  /// Lo mínimo para decidir: quién juega, si ya acabaron de anotar y si está
  /// cerrada. La ronda completa se carga solo al cerrarla.
  static Future<List<({
    String roundId,
    String nombre,
    List<String> jugadores,
    int hoyosCapturados,
    int totalHoles,
    bool cerrada,
  })>> gruposDelTorneo(String torneoId) async {
    final uid = AuthService.uid;
    if (uid == null) return [];

    // Las refs de las rondas que YO organizo. Sin límite: veinticinco grupos son
    // veinticinco refs, y quedarse en cinco era el fallo.
    final refs = await _myRefs().where('role', isEqualTo: 'owner').get();
    final out = <({
      String roundId,
      String nombre,
      List<String> jugadores,
      int hoyosCapturados,
      int totalHoles,
      bool cerrada,
    })>[];

    for (final ref in refs.docs) {
      final roundId = ref.data()['roundId'] as String? ?? ref.id;
      final snap = await _liveRounds.doc(roundId).get();
      final data = snap.data();
      if (data == null) continue;
      // Solo las de ESTE torneo. La marca viaja en la ronda desde la fase A.
      final marcas =
          ((data['torneoIds'] as List?) ?? const []).map((e) => '$e').toList();
      if (!marcas.contains(torneoId)) continue;

      Round? r;
      try {
        r = roundFromJson(data);
      } catch (e) {
        debugPrint('[Torneo] ronda $roundId ilegible: $e');
        continue;
      }
      // Cuántos hoyos tienen ya score de alguien: es lo que dice si el grupo va
      // por el 7 o ya acabó, que es la pregunta del organizador.
      var capturados = 0;
      for (var h = 1; h <= r.totalHoles; h++) {
        if (r.players.any((p) => r!.getScore(p.id, h).hasScore)) capturados++;
      }
      out.add((
        roundId: roundId,
        nombre: r.name,
        jugadores: r.realPlayers.map((p) => p.name).toList(),
        hoyosCapturados: capturados,
        totalHoles: r.totalHoles,
        cerrada: r.isFinished,
      ));
    }
    out.sort((a, b) => a.nombre.compareTo(b.nombre));
    return out;
  }

  /// Cierra una ronda del torneo SIN hacerla la ronda actual.
  ///
  /// Es lo que permite cerrar veinticinco: el estado de la app sostiene una sola
  /// ronda, pero cerrar no necesita cargarla ahí —es leer, marcar y guardar—.
  ///
  /// El resultado se escribe en la colección de QUIEN CIERRA, y quien cierra es
  /// el dueño. De ahí sale la agregación.
  static Future<bool> cerrarRondaDelTorneo(String roundId) async {
    final uid = AuthService.uid;
    if (uid == null) return false;
    try {
      final snap = await _liveRounds.doc(roundId).get();
      final data = snap.data();
      if (data == null) return false;
      // Solo el dueño. La regla también lo impide, pero fallar aquí da un
      // mensaje y no un PERMISSION_DENIED.
      if ((data['ownerUid'] as String?) != uid) {
        debugPrint('[Torneo] $roundId no es tuya: no se cierra');
        return false;
      }
      final round = roundFromJson(data).copyWith(isFinished: true);
      // El historial y el RESULTADO, que es lo que la tabla del torneo lee.
      await FirestoreService.saveRound(round);
      await finishLiveRound(roundId);
      return true;
    } catch (e) {
      debugPrint('[Torneo] no se pudo cerrar $roundId: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INVITACIONES — Lectura y acciones
  // ══════════════════════════════════════════════════════════════════════════

  /// Stream de invitaciones pendientes para el usuario actual.
  /// Filtra automáticamente las rondas ya finalizadas (isFinished=true).
  static Stream<List<LiveRoundInvitation>> pendingInvitationsStream() {
    final uid = AuthService.uid;
    if (uid == null) return Stream.value([]);

    return _db.collection('users').doc(uid)
        .collection('liveRoundRefs')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return <LiveRoundInvitation>[];

      final invitations = <LiveRoundInvitation>[];
      for (final ref in snap.docs) {
        try {
          final roundId = ref.data()['roundId'] as String? ?? ref.id;

          // Verificar que la ronda no esté finalizada antes de mostrar la invitación
          final roundSnap = await _liveRounds.doc(roundId).get();
          if (!roundSnap.exists || roundSnap.data() == null) continue;
          final isFinished = roundSnap.data()!['isFinished'] as bool? ?? false;
          if (isFinished) {
            // Limpiar silenciosamente la ref pendiente de una ronda ya terminada
            _myRefs().doc(roundId).update({'status': 'declined'}).catchError((_) {});
            continue;
          }

          final invDoc = await _invitations(roundId).doc(uid).get();
          if (invDoc.exists && invDoc.data() != null) {
            invitations.add(LiveRoundInvitation.fromFirestore(
              invDoc.data()!, roundId,
            ));
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[LiveRound] Error leyendo inv: $e');
        }
      }
      return invitations;
    });
  }

  /// Carga la ronda en vivo activa donde el usuario es el organizador.
  /// Revisa users/{uid}/liveRoundRefs con role='owner' y carga desde liveRounds.
  static Future<Round?> loadOwnerActiveLiveRound() async {
    final uid = AuthService.uid;
    if (uid == null) return null;
    try {
      final refs = await _myRefs()
          .where('role', isEqualTo: 'owner')
          .limit(5)
          .get();
      if (refs.docs.isEmpty) return null;

      // Buscar la primera ronda no finalizada
      for (final ref in refs.docs) {
        final roundId = ref.data()['roundId'] as String? ?? ref.id;
        final snap = await _liveRounds.doc(roundId).get();
        if (!snap.exists || snap.data() == null) continue;
        final data = snap.data()!;
        final isFinished = data['isFinished'] as bool? ?? false;
        if (!isFinished) {
          try {
            return roundFromJson(data);
          } catch (e) {
            if (kDebugMode) debugPrint('[LiveRound] Error parseando ronda del dueño: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] Error buscando ronda del dueño: $e');
    }
    return null;
  }

  /// Carga la ronda en vivo activa donde el usuario es invitado con status='accepted'.
  /// Ordena por acceptedAt descendente para cargar siempre la más reciente.
  static Future<Round?> loadAcceptedLiveRound() async {
    final uid = AuthService.uid;
    if (uid == null) return null;
    try {
      // Obtener todas las refs de invitado aceptadas
      QuerySnapshot<Map<String, dynamic>> refs;
      try {
        refs = await _myRefs()
            .where('role', isEqualTo: 'invited')
            .where('status', isEqualTo: 'accepted')
            .limit(10)
            .get();
      } catch (_) {
        // Fallback sin índice compuesto: filtrar en memoria
        final all = await _myRefs()
            .where('role', isEqualTo: 'invited')
            .limit(15)
            .get();
        refs = all; // usamos el mismo tipo; filtramos abajo
      }

      if (refs.docs.isEmpty) return null;

      // Ordenar en memoria por acceptedAt descendente → la más reciente primero
      final sorted = refs.docs
          .where((d) => (d.data()['status'] as String?) == 'accepted')
          .toList()
        ..sort((a, b) {
          final aTs = a.data()['acceptedAt'];
          final bTs = b.data()['acceptedAt'];
          final aDate = aTs is Timestamp ? aTs.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = bTs is Timestamp ? bTs.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate); // descendente
        });

      // Ventana de gracia: consideramos rondas finalizadas hace menos de 24 horas
      // para que el invitado pueda ver resultados y dar sliding incluso si reabre la app.
      final graceCutoff = DateTime.now().subtract(const Duration(hours: 24));

      // Buscar primero una ronda NO finalizada; luego buscar la más reciente finalizada
      // dentro de la ventana de gracia (para el caso en que el admin ya cerró).
      Round? activeRound;
      Round? recentlyFinishedRound;

      for (final ref in sorted) {
        final roundId = ref.data()['roundId'] as String? ?? ref.id;
        final snap = await _liveRounds.doc(roundId).get();
        if (!snap.exists || snap.data() == null) continue;
        final data = snap.data()!;
        final isFinished = data['isFinished'] as bool? ?? false;

        if (!isFinished) {
          // Ronda activa → máxima prioridad
          try {
            activeRound = roundFromJson(data);
            break;
          } catch (e, st) {
            debugPrint('[LiveRound] Error parseando ronda activa del invitado: $e');
            debugPrint('[LiveRound] StackTrace: $st');
          }
        } else if (recentlyFinishedRound == null) {
          // Ronda finalizada → verificar ventana de gracia (finishedAt o updatedAt)
          final finishedTs = data['finishedAt'] ?? data['updatedAt'];
          DateTime? finishedAt;
          if (finishedTs is Timestamp) {
            finishedAt = finishedTs.toDate();
          }
          if (finishedAt != null && finishedAt.isAfter(graceCutoff)) {
            try {
              recentlyFinishedRound = roundFromJson(data);
            } catch (e) {
              debugPrint('[LiveRound] Error parseando ronda finalizada del invitado: $e');
            }
          }
        }
      }

      // Retornar: activa > recién finalizada (ventana de gracia) > null
      return activeRound ?? recentlyFinishedRound;
    } catch (e, st) {
      debugPrint('[LiveRound] Error buscando ronda aceptada del invitado: $e');
      debugPrint('[LiveRound] StackTrace: $st');
    }
    return null;
  }

  /// Acepta una invitación: actualiza status, declina el resto de pendientes
  /// automáticamente, y retorna la ronda cargada.
  static Future<Round?> acceptInvitation(LiveRoundInvitation inv) async {
    final uid = AuthService.uid;
    if (uid == null) return null;

    // 1. Marcar esta invitación como aceptada
    try {
      await _invitations(inv.roundId).doc(uid).update({'status': 'accepted'});
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] Error actualizando invitation status: $e');
    }
    try {
      await _myRefs().doc(inv.roundId).update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] Error actualizando liveRoundRef status: $e');
    }

    // 2. Declinar automáticamente todas las demás invitaciones pendientes
    //    para evitar que el usuario pueda unirse a dos rondas simultáneamente.
    try {
      final others = await _myRefs()
          .where('status', isEqualTo: 'pending')
          .get();
      if (others.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in others.docs) {
          final otherId = doc.data()['roundId'] as String? ?? doc.id;
          if (otherId == inv.roundId) continue; // no tocar la que acaba de aceptar
          // Declinar en liveRoundRef
          batch.update(_myRefs().doc(otherId), {'status': 'declined'});
          // Declinar en el sub-documento de invitación
          batch.update(_invitations(otherId).doc(uid), {'status': 'declined'});
        }
        await batch.commit();
        if (kDebugMode) {
          debugPrint('[LiveRound] ${others.docs.length - 1} invitación(es) pendiente(s) declinada(s) automáticamente.');
        }
      }
    } catch (e) {
      // No bloqueamos el flujo principal si falla el auto-declinar
      if (kDebugMode) debugPrint('[LiveRound] Error auto-declinando otras invitaciones: $e');
    }

    // 3. Cargar la ronda desde liveRounds
    try {
      final snap = await _liveRounds.doc(inv.roundId).get();
      if (!snap.exists || snap.data() == null) {
        if (kDebugMode) debugPrint('[LiveRound] Documento de ronda no encontrado: ${inv.roundId}');
        return null;
      }
      return roundFromJson(snap.data()!);
    } catch (e, st) {
      debugPrint('[LiveRound] Error cargando/parseando ronda en acceptInvitation: $e');
      debugPrint('[LiveRound] StackTrace: $st');
      return null;
    }
  }

  /// Rechaza una invitación
  static Future<void> declineInvitation(LiveRoundInvitation inv) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    await Future.wait([
      _invitations(inv.roundId).doc(uid).update({'status': 'declined'}),
      _myRefs().doc(inv.roundId).update({'status': 'declined'}),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STREAM EN TIEMPO REAL — Escuchar cambios de la ronda
  // ══════════════════════════════════════════════════════════════════════════

  /// Stream de la ronda en vivo (actualización en tiempo real para todos)
  static Stream<Round?> liveRoundStream(String roundId) {
    return _liveRounds.doc(roundId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      try {
        return roundFromJson(snap.data()!);
      } catch (e) {
        if (kDebugMode) debugPrint('[LiveRound] Error parseando stream: $e');
        return null;
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ESCRITURA — Actualizar score en ronda en vivo
  // ══════════════════════════════════════════════════════════════════════════

  /// Trae la ronda en vivo [roundId] entera, para verla o corregirla.
  ///
  /// Solo funciona con las rondas que el organizador POSEE: la regla de
  /// liveRounds deja leer a quien está en `participantUids` o es `ownerUid`, y
  /// el organizador de un torneo no es ninguna de las dos cosas en la ronda que
  /// montó otra cuenta. Ver la cabecera de la sección de scores del portal.
  ///
  /// Devuelve null si no está o si no se puede leer, sin lanzar: el día del
  /// torneo una excepción aquí deja al organizador sin la pantalla entera.
  static Future<Round?> cargarRondaEnVivo(String roundId) async {
    try {
      final snap = await _liveRounds.doc(roundId).get();
      final data = snap.data();
      if (data == null) return null;
      return roundFromJson(data);
    } catch (e) {
      debugPrint('[Torneo] no se pudo leer $roundId: $e');
      return null;
    }
  }

  /// Guarda una ronda corregida. Devuelve si se pudo.
  ///
  /// No usa [saveRound] a ciegas: esa se rinde en silencio si la ronda no es
  /// `isLive`, y aquí "no pasó nada" y "se guardó" tienen que distinguirse —el
  /// organizador acaba de cambiar un score de otra persona—.
  static Future<bool> guardarCorregida(Round round) async {
    if (!round.isLive) return false;
    try {
      final data = roundToJson(round);
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _liveRounds.doc(round.id).set(data, SetOptions(merge: false));
      return true;
    } catch (e) {
      debugPrint('[Torneo] no se pudo corregir ${round.id}: $e');
      return false;
    }
  }

  /// Persiste la ronda completa en liveRounds (merge para no pisar otros campos)
  static Future<void> saveRound(Round round) async {
    if (!round.isLive) return;
    final data = roundToJson(round);
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _liveRounds.doc(round.id).set(data, SetOptions(merge: false));
  }

  /// Finaliza la ronda en vivo: marca isFinished y limpia refs
  static Future<void> finishLiveRound(String roundId) async {
    await _liveRounds.doc(roundId).update({
      'isFinished':  true,
      'finishedAt':  FieldValue.serverTimestamp(),
      'updatedAt':   FieldValue.serverTimestamp(),
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UNIÓN POR CÓDIGO — Entrar a ronda sin invitación previa
  // ══════════════════════════════════════════════════════════════════════════

  /// Resultado de intentar unirse a una ronda por código.
  /// - [round]        : ronda encontrada (siempre presente si no es error)
  /// - [myPlayer]     : jugador ya ligado a este uid (puede ser null)
  /// - [unlinkedPlayers]: jugadores de la ronda sin linkedUserId (para elegir)
  /// - [error]        : mensaje de error si algo falló
  static Future<({
    Round? round,
    Player? myPlayer,
    List<Player> unlinkedPlayers,
    String? error,
  })> findRoundByCode(String code) async {
    final uid = AuthService.uid;
    if (uid == null) {
      return (round: null, myPlayer: null, unlinkedPlayers: <Player>[], error: 'No autenticado');
    }

    final trimmed = code.trim().toUpperCase();
    if (trimmed.length != 6) {
      return (round: null, myPlayer: null, unlinkedPlayers: <Player>[], error: 'El código debe tener 6 caracteres');
    }

    try {
      // Buscar en liveRounds por liveCode
      final snap = await _liveRounds
          .where('liveCode', isEqualTo: trimmed)
          .where('isFinished', isEqualTo: false)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        return (round: null, myPlayer: null, unlinkedPlayers: <Player>[], error: 'Código incorrecto o la ronda ya terminó');
      }

      final round = roundFromJson(snap.docs.first.data());

      // ¿Ya hay un jugador ligado a este uid?
      final myPlayer = round.players
          .where((p) => p.linkedUserId == uid && !p.isVirtual)
          .firstOrNull;

      // Jugadores reales sin ligar (candidatos para que el usuario elija)
      final unlinkedPlayers = round.players
          .where((p) => !p.isVirtual &&
              (p.linkedUserId == null || p.linkedUserId!.isEmpty))
          .toList();

      return (round: round, myPlayer: myPlayer, unlinkedPlayers: unlinkedPlayers, error: null);
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] findRoundByCode error: $e');
      return (round: null, myPlayer: null, unlinkedPlayers: <Player>[], error: 'Error al buscar la ronda');
    }
  }

  /// Confirma la unión a la ronda: liga al jugador elegido con el uid actual
  /// y escribe los documentos necesarios para que la ronda aparezca en home.
  static Future<Round?> joinRoundByCode({
    required Round round,
    required Player chosenPlayer,
  }) async {
    final uid = AuthService.uid;
    if (uid == null) return null;

    try {
      final batch = _db.batch();

      // 1. Actualizar linkedUserId en el jugador global (players/{id})
      batch.update(_db.collection('players').doc(chosenPlayer.id), {
        'linkedUserId': uid,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // 2. Actualizar players[] dentro del documento liveRounds/{roundId}
      final updatedPlayers = round.players.map((p) {
        if (p.id == chosenPlayer.id) {
          return {...p.toJson(), 'linkedUserId': uid};
        }
        return p.toJson();
      }).toList();
      batch.update(_liveRounds.doc(round.id), {
        'players': updatedPlayers,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 3. Crear/actualizar invitación en liveRounds/{id}/invitations/{uid}
      final invRef = _invitations(round.id).doc(uid);
      batch.set(invRef, {
        'roundId':    round.id,
        'roundName':  round.name,
        'liveCode':   round.liveCode ?? '',
        'ownerUid':   round.ownerUid ?? '',
        'ownerName':  '',
        'playerNames': round.players.map((p) => p.name).toList(),
        'courseName': round.course.name,
        'myPlayerId': chosenPlayer.id,
        'role':       'invited',
        'status':     'accepted',
        'createdAt':  FieldValue.serverTimestamp(),
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      // 4. Crear liveRoundRef en users/{uid}/liveRoundRefs/{roundId}
      batch.set(_myRefs().doc(round.id), {
        'roundId':    round.id,
        'liveCode':   round.liveCode ?? '',
        'role':       'invited',
        'status':     'accepted',
        'myPlayerId': chosenPlayer.id,
        'invitedAt':  FieldValue.serverTimestamp(),
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // 5. Releer la ronda actualizada para devolverla con linkedUserId correcto
      final updated = await _liveRounds.doc(round.id).get();
      if (updated.exists && updated.data() != null) {
        return roundFromJson(updated.data()!);
      }
      return round;
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] joinRoundByCode error: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BÚSQUEDA DE USUARIO — Para vincular jugador a cuenta
  // ══════════════════════════════════════════════════════════════════════════

  /// Busca usuarios por email para vincular jugador a cuenta
  static Future<List<Map<String, dynamic>>> searchUsersByEmail(String email) async {
    if (email.length < 3) return [];
    try {
      final snap = await _db.collection('users')
          .where('email', isEqualTo: email.toLowerCase().trim())
          .limit(5)
          .get();
      return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] searchUsers error: $e');
      return [];
    }
  }

  /// Busca usuarios por displayName (búsqueda parcial, hasta 10 resultados)
  static Future<List<Map<String, dynamic>>> searchUsersByName(String query) async {
    if (query.length < 2) return [];
    try {
      // Firestore no tiene full-text search; usamos prefix match
      final q = query.trim();
      final snap = await _db.collection('users')
          .where('displayName', isGreaterThanOrEqualTo: q)
          .where('displayName', isLessThan: '${q}z')
          .limit(10)
          .get();
      return snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[LiveRound] searchByName error: $e');
      return [];
    }
  }

  /// Vincula un Player del directorio a un UID de usuario
  /// Actualiza players/{playerId} y users/{uid}/playerLinks/{playerId}
  static Future<void> linkPlayerToUser({
    required String playerId,
    required String targetUid,
  }) async {
    final uid = AuthService.uid;
    if (uid == null) return;
    await Future.wait([
      // Actualizar el Player global
      _db.collection('players').doc(playerId).update({
        'linkedUserId': targetUid,
        'updatedAt': DateTime.now().toIso8601String(),
      }),
      // Actualizar el link del usuario actual
      _db.collection('users').doc(uid)
          .collection('playerLinks').doc(playerId)
          .update({'linkedUserId': targetUid}),
    ]);
  }
}
