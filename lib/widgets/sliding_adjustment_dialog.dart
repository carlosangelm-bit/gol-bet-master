// ─────────────────────────────────────────────────────────────────────────────
// SLIDING ADJUSTMENT DIALOG
// Diálogo modal que aparece al finalizar una ronda y sugiere ajustes de sliding
// basados en el resultado de la apuesta principal (Match / Nassau / Skins).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/app_theme.dart';
import '../engines/sliding_adjustment_engine.dart';
import '../models/models.dart';
import '../services/player_service.dart';
import '../services/auth_service.dart';

class SlidingAdjustmentDialog extends StatefulWidget {
  final Round round;

  const SlidingAdjustmentDialog({super.key, required this.round});

  @override
  State<SlidingAdjustmentDialog> createState() => _SlidingAdjustmentDialogState();
}

class _SlidingAdjustmentDialogState extends State<SlidingAdjustmentDialog> {
  List<SlidingAdjustmentSuggestion>? _suggestions;
  bool _loading = true;
  bool _saving  = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final uid = AuthService.uid;  // puede ser null — el engine usa fallback al primer jugador

    try {
      // Obtener playerLinks del usuario actual (vacío si no está autenticado)
      final linksSnap = uid != null
          ? await PlayerService.getLinksForUser(uid)
          : <String, PlayerLink>{};

      final suggestions = SlidingAdjustmentEngine.computeSuggestions(
        round:       widget.round,
        currentUid:  uid,
        playerLinks: linksSnap,
      );
      setState(() {
        _suggestions = suggestions;
        _loading     = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[SlidingAdjustmentDialog] Error: $e');
      setState(() {
        _error   = 'No se pudo calcular el ajuste de sliding.';
        _loading = false;
      });
    }
  }

  Future<void> _applyAccepted() async {
    final suggestions = _suggestions;
    if (suggestions == null) return;

    setState(() => _saving = true);

    try {
      for (final s in suggestions) {
        if (!s.accepted || s.delta == 0) continue;

        // ── Ajuste unilateral: actualizar mi playerLink con el oponente ──────
        final link = await PlayerService.getLinkOrDefault(s.opponentId);
        final updated = link.copyWith(
          defaultSlidingAdjustment: s.suggestedAdjustment,
        );
        await PlayerService.updateLink(updated);

        // ── Ajuste bilateral: si el oponente está vinculado, actualizar
        //    también su playerLink hacia mí con el delta invertido ───────────
        if (s.opponentIsLinked) {
          await _applyBilateral(
            opponentUid:  _getOpponentUid(s.opponentId),
            myPlayerId:   s.playerId,
            inverseDelta: -s.delta,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SlidingAdjustmentDialog] Save error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  /// Actualiza el playerLink del oponente hacia mi jugador con el delta inverso.
  /// Usa el UID del oponente (linkedUserId) para escribir en su colección.
  Future<void> _applyBilateral({
    required String? opponentUid,
    required String myPlayerId,
    required int inverseDelta,
  }) async {
    if (opponentUid == null || opponentUid.isEmpty) return;
    try {
      // Leer el playerLink que tiene el oponente hacia mí
      final snap = await PlayerService.getLinkForUserAndPlayer(
        uid: opponentUid, playerId: myPlayerId);
      if (snap == null) return;
      final updatedLink = snap.copyWith(
        defaultSlidingAdjustment: snap.defaultSlidingAdjustment + inverseDelta,
      );
      await PlayerService.updateLinkForUser(
        uid: opponentUid, link: updatedLink);
    } catch (e) {
      if (kDebugMode) debugPrint('[SlidingAdjustmentDialog] Bilateral error: $e');
    }
  }

  /// Obtiene el linkedUserId del jugador oponente desde la ronda.
  String? _getOpponentUid(String opponentId) {
    final player = widget.round.players
        .where((p) => p.id == opponentId)
        .firstOrNull;
    return player?.linkedUserId;
  }

  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;

    return Dialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? _buildLoading(t)
            : _error != null
                ? _buildError(t)
                : _buildContent(t),
      ),
    );
  }

  Widget _buildLoading(GolfTheme t) {
    return SizedBox(
      height: 120,
      child: Center(child: CircularProgressIndicator(color: t.primary)),
    );
  }

  Widget _buildError(GolfTheme t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: t.sub, fontSize: 14),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        _closeButton(t),
      ],
    );
  }

  Widget _buildContent(GolfTheme t) {
    final suggestions = _suggestions ?? [];
    final hasSuggestions = suggestions.any((s) => s.delta != 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.swap_vert_rounded, color: t.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ajuste de Sliding',
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
              Text('Basado en la apuesta principal',
                  style: TextStyle(color: t.sub, fontSize: 11)),
            ],
          )),
        ]),

        const SizedBox(height: 16),
        Divider(color: t.divider, height: 1),
        const SizedBox(height: 16),

        if (!hasSuggestions && suggestions.isEmpty)
          _buildNoSuggestions(t)
        else if (!hasSuggestions && suggestions.isNotEmpty)
          _buildAllTies(t, suggestions)
        else
          ...suggestions.map((s) => _SuggestionTile(
            suggestion: s,
            t: t,
            onChanged: (val) => setState(() => s.accepted = val),
          )),

        const SizedBox(height: 20),

        // Botones
        if (hasSuggestions) ...[
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.divider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Cancelar', style: TextStyle(color: t.sub)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: _saving ? null : _applyAccepted,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: t.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _saving
                  ? SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(color: t.onPrimary, strokeWidth: 2))
                  : Text('Aceptar cambios',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
        ] else
          _closeButton(t),
      ],
    );
  }

  Widget _buildNoSuggestions(GolfTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: Text(
        'No hay apuestas registradas en esta ronda\npara calcular el ajuste.',
        style: TextStyle(color: t.sub, fontSize: 13),
        textAlign: TextAlign.center,
      )),
    );
  }

  Widget _buildAllTies(GolfTheme t, List<SlidingAdjustmentSuggestion> suggestions) {
    return Column(
      children: [
        ...suggestions.map((s) => _SuggestionTile(
          suggestion: s,
          t: t,
          onChanged: (_) {},
        )),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(Icons.handshake_rounded, color: t.sub, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Todos los duelos terminaron en empate. No se sugieren cambios.',
              style: TextStyle(color: t.sub, fontSize: 12),
            )),
          ]),
        ),
      ],
    );
  }

  Widget _closeButton(GolfTheme t) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).pop(false),
        style: ElevatedButton.styleFrom(
          backgroundColor: t.surface,
          foregroundColor: t.text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: const Text('Cerrar'),
      ),
    );
  }
}

// ── Tile individual para cada sugerencia ─────────────────────────────────────
class _SuggestionTile extends StatelessWidget {
  final SlidingAdjustmentSuggestion suggestion;
  final GolfTheme t;
  final ValueChanged<bool> onChanged;

  const _SuggestionTile({
    required this.suggestion,
    required this.t,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final isTie = s.delta == 0;

    Color accentColor;
    String resultIcon;
    String resultLabel;
    String adjustmentText;

    if (isTie) {
      accentColor    = t.sub;
      resultIcon     = '🤝';
      resultLabel    = 'Empate';
      adjustmentText = 'Sin cambio';
    } else if (s.delta < 0) {
      // Yo gané → recibo menos strokes
      accentColor    = const Color(0xFF2E7D32); // verde oscuro
      resultIcon     = '🏆';
      resultLabel    = 'Ganaste vs ${s.opponentName}';
      final curr = s.currentAdjustment.toStringAsFixed(1);
      final sug  = s.suggestedAdjustment.toStringAsFixed(1);
      adjustmentText = 'Sliding: $curr → $sug';
    } else {
      // Yo perdí → recibo más strokes
      accentColor    = const Color(0xFFC62828); // rojo oscuro
      resultIcon     = '📉';
      resultLabel    = 'Perdiste vs ${s.opponentName}';
      final curr = s.currentAdjustment.toStringAsFixed(1);
      final sug  = s.suggestedAdjustment.toStringAsFixed(1);
      adjustmentText = 'Sliding: $curr → $sug';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isTie
                ? t.divider
                : (s.accepted ? accentColor.withValues(alpha: 0.4) : t.divider),
            width: 1.2,
          ),
        ),
        child: Row(children: [
          // Ícono resultado
          Text(resultIcon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),

          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(resultLabel,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  )),
              const SizedBox(height: 2),
              Text(s.duelResult.sourceBet,
                  style: TextStyle(color: t.sub, fontSize: 11)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.compare_arrows_rounded, color: t.sub, size: 13),
                const SizedBox(width: 4),
                Text(adjustmentText,
                    style: TextStyle(
                      color: isTie ? t.sub : t.text,
                      fontSize: 12,
                      fontWeight: isTie ? FontWeight.normal : FontWeight.w600,
                    )),
              ]),
              // Badge bilateral/unilateral
              if (!isTie) ...[
                const SizedBox(height: 5),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: s.opponentIsLinked
                          ? const Color(0xFF1565C0).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: s.opponentIsLinked
                            ? const Color(0xFF1565C0).withValues(alpha: 0.40)
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        s.opponentIsLinked ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                        size: 10,
                        color: s.opponentIsLinked
                            ? const Color(0xFF42A5F5)
                            : t.sub,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        s.opponentIsLinked ? 'Ajuste bilateral' : 'Solo local',
                        style: TextStyle(
                          fontSize: 10,
                          color: s.opponentIsLinked
                              ? const Color(0xFF42A5F5)
                              : t.sub,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ),
                ]),
              ],
            ],
          )),

          // Toggle para aceptar/rechazar (solo si hay cambio)
          if (!isTie)
            Switch(
              value:    s.accepted,
              onChanged: onChanged,
              activeThumbColor: t.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SLIDING SUMMARY CARD — Para mostrar al fondo de la pantalla de resultados
// ─────────────────────────────────────────────────────────────────────────────

class SlidingSummaryCard extends StatelessWidget {
  final Round round;
  final GolfTheme t;

  const SlidingSummaryCard({super.key, required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    // Mostrar las relaciones de sliding de la ronda actual
    final slidingList = round.sliding;
    if (slidingList.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.swap_vert_rounded, color: t.sub, size: 14),
          const SizedBox(width: 6),
          Text('SLIDING DE RONDA', style: TextStyle(
            color: t.sub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 8),
        ...slidingList.map((rel) {
          final pA = round.players.where((p) => p.id == rel.playerAId).firstOrNull;
          final pB = round.players.where((p) => p.id == rel.playerBId).firstOrNull;
          if (pA == null || pB == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Expanded(child: Text(pA.name,
                    style: TextStyle(color: t.text, fontSize: 12, fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: rel.adjustment > 0
                        ? Colors.green.shade700.withValues(alpha: 0.15)
                        : rel.adjustment < 0
                            ? Colors.red.shade700.withValues(alpha: 0.15)
                            : t.divider.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    rel.adjustment == 0
                        ? 'par'
                        : rel.adjustment > 0
                            ? '+${rel.adjustment.toStringAsFixed(0)}'
                            : rel.adjustment.toStringAsFixed(0),
                    style: TextStyle(
                      color: rel.adjustment > 0
                          ? Colors.green.shade400
                          : rel.adjustment < 0
                              ? Colors.red.shade400
                              : t.sub,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(child: Text(pB.name,
                    style: TextStyle(color: t.text, fontSize: 12, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.end)),
              ]),
            ),
          );
        }),
      ],
    );
  }
}


/// Muestra el diálogo de ajuste de sliding y retorna true si se aplicaron cambios.
Future<bool> showSlidingAdjustmentDialog(BuildContext context, Round round) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SlidingAdjustmentDialog(round: round),
  );
  return result == true;
}
