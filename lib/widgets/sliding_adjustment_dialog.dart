// ─────────────────────────────────────────────────────────────────────────────
// SLIDING ADJUSTMENT DIALOG — Premium
// Pantalla de ajuste de sliding al finalizar una ronda.
// Características:
//  • Header con gradiente estilo results_screen
//  • Card por jugador con avatar, nombre, HCP, resultado del duelo
//  • Sliding inicial → resultado → sliding sugerido (visual de flecha)
//  • Ajuste manual con slider/stepper para cualquier jugador
//  • Para jugadores NO en directorio: opción "Guardar y registrar sliding"
//  • Badge bilateral/solo-local con indicador premium
//  • Accesible a usuarios con cuenta registrada (premium)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/app_theme.dart';
import '../engines/sliding_adjustment_engine.dart';
import '../models/models.dart';
import '../services/player_service.dart';
import '../services/auth_service.dart';

// ── Paleta interna (mismo estilo _ThemeGrad de results_screen) ────────────────
class _Palette {
  final GolfTheme t;
  const _Palette(this.t);

  bool get isLight => t.brightness == Brightness.light;

  List<Color> get header => isLight
      ? [t.primary, t.primary.withValues(alpha: 0.82)]
      : [const Color(0xFF1A1A2E), const Color(0xFF16213E)];

  Color get headerText => Colors.white;
  Color get headerSub  => Colors.white.withValues(alpha: 0.70);
  Color get headerIcon => Colors.white.withValues(alpha: 0.85);

  Color get card   => isLight ? Colors.white           : const Color(0xFF1C1C1E);
  Color get border => isLight ? const Color(0xFFE8E8EC) : const Color(0xFF2C2C30);
  Color get bg     => isLight ? const Color(0xFFF4F5F9) : const Color(0xFF111114);

  Color get win  => isLight ? const Color(0xFF1B5E20) : const Color(0xFF388E3C);
  Color get lose => isLight ? const Color(0xFF7F0000)  : const Color(0xFFC62828);
  Color get tie  => isLight ? const Color(0xFF455A64)  : const Color(0xFF90A4AE);

  Color get winBg  => win.withValues(alpha: isLight ? 0.08 : 0.14);
  Color get loseBg => lose.withValues(alpha: isLight ? 0.08 : 0.14);
  Color get tieBg  => tie.withValues(alpha: 0.10);

  List<Color> get winGrad  => [const Color(0xFF1B5E20), const Color(0xFF2E7D32)];
  List<Color> get loseGrad => [const Color(0xFF7F0000), const Color(0xFFC62828)];
  List<Color> get tieGrad  => [const Color(0xFF37474F), const Color(0xFF546E7A)];

  Color get slidingArrow  => isLight ? t.primary : t.accent;
  Color get manualPill    => isLight ? t.primary.withValues(alpha: 0.10) : t.accent.withValues(alpha: 0.15);
  Color get manualText    => isLight ? t.primary : t.accent;

  Color get saveBtnBg   => isLight ? t.primary : const Color(0xFF3D5AFE);
  Color get saveBtnText => Colors.white;

  Color get bilateralBg     => const Color(0xFF1565C0).withValues(alpha: 0.14);
  Color get bilateralBorder => const Color(0xFF1565C0).withValues(alpha: 0.35);
  Color get bilateralText   => const Color(0xFF42A5F5);

  Color get localBg     => Colors.white.withValues(alpha: 0.07);
  Color get localBorder => Colors.white.withValues(alpha: 0.14);
  Color get localText   => t.sub;
}

// ─────────────────────────────────────────────────────────────────────────────
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
  // Qué jugador tiene el stepper de ajuste manual expandido
  String? _expandedManualId;
  // Jugadores que el usuario quiere guardar en su directorio
  final Set<String> _pendingSave = {};
  // Nombre custom para jugadores nuevos (si el usuario lo edita)
  final Map<String, String> _customNames = {};

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final uid = AuthService.uid;
    try {
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
        if (!s.accepted) continue;

        // ── Guardar jugador nuevo en directorio si fue seleccionado ──────────
        if (_pendingSave.contains(s.opponentId)) {
          final opponentPlayer = widget.round.players
              .where((p) => p.id == s.opponentId).firstOrNull;
          if (opponentPlayer != null) {
            final customName = _customNames[s.opponentId];
            try {
              // Usar createPlayer para crear el Player global + PlayerLink
              await PlayerService.createPlayer(
                name:                     opponentPlayer.name,
                handicap:                 opponentPlayer.handicapBase,
                colorIndex:               opponentPlayer.colorIndex,
                isFavorite:               false,
                customDisplayName:        customName,
                defaultSlidingAdjustment: s.effectiveAdjustment,
              );
              continue; // el sliding ya quedó guardado en createPlayer
            } catch (_) {
              // Si falla guardar el jugador, intentar solo actualizar el link
            }
          }
        }

        // ── Ajuste sliding para jugador ya en directorio ─────────────────────
        if (s.delta == 0 && s.manualOverride == null) continue;

        final link = await PlayerService.getLinkOrDefault(s.opponentId);
        final updated = link.copyWith(
          defaultSlidingAdjustment: s.effectiveAdjustment,
        );
        await PlayerService.updateLink(updated);

        // ── Ajuste bilateral ─────────────────────────────────────────────────
        if (s.opponentIsLinked) {
          await _applyBilateral(
            opponentUid:          _getOpponentUid(s.opponentId),
            myPlayerId:           s.playerId,
            newOpponentAdj:       s.opponentSuggestedAdjustment,
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

  Future<void> _applyBilateral({
    required String? opponentUid,
    required String myPlayerId,
    required double newOpponentAdj,
  }) async {
    if (opponentUid == null || opponentUid.isEmpty) return;
    try {
      final snap = await PlayerService.getLinkForUserAndPlayer(
          uid: opponentUid, playerId: myPlayerId);
      if (snap == null) return;
      final updatedLink = snap.copyWith(defaultSlidingAdjustment: newOpponentAdj);
      await PlayerService.updateLinkForUser(uid: opponentUid, link: updatedLink);
    } catch (e) {
      if (kDebugMode) debugPrint('[SlidingAdjustmentDialog] Bilateral error: $e');
    }
  }

  String? _getOpponentUid(String opponentId) {
    return widget.round.players
        .where((p) => p.id == opponentId)
        .firstOrNull?.linkedUserId;
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;
    final p = _Palette(t);
    final screenH = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenH * 0.88),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ───────────────────────────────────────────────────
              _buildHeader(p),

              // ── Contenido scrollable ──────────────────────────────────────
              Flexible(
                child: Container(
                  color: p.bg,
                  child: _loading
                      ? _buildLoading(p)
                      : _error != null
                          ? _buildError(p)
                          : _buildContent(p),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_Palette p) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.header,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.swap_vert_rounded, color: p.headerIcon, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AJUSTE DE SLIDING',
              style: TextStyle(
                color: p.headerText,
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 1.4,
              )),
            Text('Basado en el resultado de la apuesta principal',
              style: TextStyle(color: p.headerSub, fontSize: 11)),
          ],
        )),
        // Badge premium
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.shade400.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.shade400.withValues(alpha: 0.55)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.star_rounded, color: Colors.amber.shade300, size: 11),
            const SizedBox(width: 4),
            Text('PREMIUM',
              style: TextStyle(
                color: Colors.amber.shade300,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              )),
          ]),
        ),
      ]),
    );
  }

  Widget _buildLoading(_Palette p) {
    return SizedBox(
      height: 140,
      child: Center(child: CircularProgressIndicator(
        color: GolfThemeExt.current.primary, strokeWidth: 2.5,
      )),
    );
  }

  Widget _buildError(_Palette p) {
    final t = GolfThemeExt.current;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 44),
        const SizedBox(height: 14),
        Text(_error!, style: TextStyle(color: t.sub, fontSize: 14),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.surface,
              foregroundColor: t.text,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: const Text('Cerrar'),
          ),
        ),
      ]),
    );
  }

  Widget _buildContent(_Palette p) {
    final suggestions = _suggestions ?? [];
    final hasSuggestions = suggestions.any((s) => s.delta != 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: suggestions.isEmpty
                ? _buildEmpty(p)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: suggestions.map((s) => _SlidingPlayerCard(
                      suggestion:    s,
                      palette:       p,
                      isExpanded:    _expandedManualId == s.opponentId,
                      pendingSave:   _pendingSave.contains(s.opponentId),
                      customName:    _customNames[s.opponentId],
                      onToggleExpand: () => setState(() {
                        _expandedManualId = _expandedManualId == s.opponentId
                            ? null : s.opponentId;
                      }),
                      onAcceptChanged: (val) => setState(() => s.accepted = val),
                      onManualChanged: (val) => setState(() => s.manualOverride = val),
                      onToggleSave: () => setState(() {
                        if (_pendingSave.contains(s.opponentId)) {
                          _pendingSave.remove(s.opponentId);
                        } else {
                          _pendingSave.add(s.opponentId);
                        }
                      }),
                      onCustomNameChanged: (val) => setState(() {
                        _customNames[s.opponentId] = val;
                      }),
                    )).toList(),
                  ),
          ),
        ),

        // ── Footer con botones ────────────────────────────────────────────
        _buildFooter(p, hasSuggestions, suggestions),
      ],
    );
  }

  Widget _buildEmpty(_Palette p) {
    final t = GolfThemeExt.current;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.sports_golf_rounded, color: t.sub.withValues(alpha: 0.45), size: 44),
        const SizedBox(height: 14),
        Text('Sin apuestas registradas',
          style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 6),
        Text('No hay duelos para calcular el ajuste de sliding.',
          style: TextStyle(color: t.sub, fontSize: 12), textAlign: TextAlign.center),
      ])),
    );
  }

  Widget _buildFooter(_Palette p, bool hasSuggestions,
      List<SlidingAdjustmentSuggestion> suggestions) {
    final t = GolfThemeExt.current;
    final hasChanges = hasSuggestions || _pendingSave.isNotEmpty ||
        suggestions.any((s) => s.manualOverride != null);

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: hasChanges
          ? Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: p.border, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Cancelar', style: TextStyle(color: t.sub, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: ElevatedButton(
                onPressed: _saving ? null : _applyAccepted,
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.saveBtnBg,
                  foregroundColor: p.saveBtnText,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 2,
                ),
                child: _saving
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.2))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 16),
                        const SizedBox(width: 7),
                        const Text('Aplicar cambios',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      ]),
              )),
            ])
          : SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.surface,
                  foregroundColor: t.text,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD DE JUGADOR — toda la info de sliding para ese oponente
// ─────────────────────────────────────────────────────────────────────────────
class _SlidingPlayerCard extends StatelessWidget {
  final SlidingAdjustmentSuggestion suggestion;
  final _Palette palette;
  final bool isExpanded;
  final bool pendingSave;
  final String? customName;
  final VoidCallback onToggleExpand;
  final ValueChanged<bool> onAcceptChanged;
  final ValueChanged<double?> onManualChanged;
  final VoidCallback onToggleSave;
  final ValueChanged<String> onCustomNameChanged;

  const _SlidingPlayerCard({
    required this.suggestion,
    required this.palette,
    required this.isExpanded,
    required this.pendingSave,
    required this.onToggleExpand,
    required this.onAcceptChanged,
    required this.onManualChanged,
    required this.onToggleSave,
    required this.onCustomNameChanged,
    this.customName,
  });

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final p = palette;
    final t = GolfThemeExt.current;
    final isTie   = s.delta == 0 && s.manualOverride == null;
    final iWon    = s.delta < 0;

    final resultColor = isTie ? p.tie : (iWon ? p.win : p.lose);
    final resultBg    = isTie ? p.tieBg : (iWon ? p.winBg : p.loseBg);
    final resultIcon  = isTie ? '🤝' : (iWon ? '🏆' : '📉');
    final resultLabel = isTie
        ? 'Empate'
        : iWon
            ? 'Ganaste'
            : 'Perdiste';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isTie ? p.border : resultColor.withValues(alpha: 0.30),
            width: 1.2,
          ),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: p.isLight ? 0.05 : 0.22),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Banda superior con resultado ────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: resultBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(children: [
              Text(resultIcon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(resultLabel,
                  style: TextStyle(
                    color: resultColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  )),
                Text(s.duelResult.sourceBet,
                  style: TextStyle(color: resultColor.withValues(alpha: 0.72), fontSize: 10)),
              ])),
              // Badge bilateral / local
              _buildBadge(p, s),
            ]),
          ),

          // ── Cuerpo: avatar + nombre + sliding visual ────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Avatar
              Stack(clipBehavior: Clip.none, children: [
                _GAvatar(
                  name: s.opponentName,
                  colorIndex: s.opponentColorIndex,
                  size: 52,
                ),
                if (s.opponentIsLinked)
                  Positioned(
                    right: -2, bottom: -2,
                    child: Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0),
                        shape: BoxShape.circle,
                        border: Border.all(color: p.card, width: 2),
                      ),
                      child: const Icon(Icons.verified_rounded,
                          color: Colors.white, size: 9),
                    ),
                  ),
              ]),
              const SizedBox(width: 13),
              // Nombre y HCP
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.opponentName,
                  style: TextStyle(
                    color: t.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'HCP ${s.opponentHandicap.toStringAsFixed(0)}',
                      style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!s.opponentInDirectory) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                      ),
                      child: Text('No guardado',
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ])),

              // Toggle aceptar
              if (!isTie)
                Switch(
                  value: s.accepted,
                  onChanged: onAcceptChanged,
                  activeThumbColor: resultColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ]),
          ),

          // ── Visualización sliding: inicial → resultado → sugerido ────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: _SlidingFlow(
              current:    s.currentAdjustment,
              suggested:  s.effectiveAdjustment,
              delta:      s.delta,
              hasManual:  s.manualOverride != null,
              palette:    p,
            ),
          ),

          // ── Ajuste manual expandible ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggleExpand,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: p.manualPill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.tune_rounded, size: 13, color: p.manualText),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Ajustar manualmente',
                    style: TextStyle(color: p.manualText, fontSize: 12, fontWeight: FontWeight.w600))),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 16, color: p.manualText,
                  ),
                ]),
              ),
            ),
          ),

          if (isExpanded) _buildManualStepper(p, t, s),

          // ── Opción guardar jugador (no en directorio) ─────────────────────
          if (!s.opponentInDirectory && !s.opponentIsLinked)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: _SavePlayerOption(
                suggestion:    s,
                palette:       p,
                pendingSave:   pendingSave,
                customName:    customName,
                onToggle:      onToggleSave,
                onNameChanged: onCustomNameChanged,
              ),
            ),

          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _buildManualStepper(_Palette p, GolfTheme t, SlidingAdjustmentSuggestion s) {
    final current = s.manualOverride ?? s.suggestedAdjustment;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Ajuste manual',
              style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w600)),
            if (s.manualOverride != null)
              GestureDetector(
                onTap: () => onManualChanged(null),
                child: Text('Restablecer',
                  style: TextStyle(color: p.manualText, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _StepBtn(
              icon: Icons.remove,
              onTap: () => onManualChanged((current - 1).clamp(-20, 20)),
              palette: p,
            ),
            const SizedBox(width: 16),
            Column(children: [
              Text(
                current >= 0 ? '+${current.toStringAsFixed(0)}' : current.toStringAsFixed(0),
                style: TextStyle(
                  color: current > 0 ? p.win : current < 0 ? p.lose : t.sub,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                ),
              ),
              Text('strokes', style: TextStyle(color: t.sub, fontSize: 10)),
            ]),
            const SizedBox(width: 16),
            _StepBtn(
              icon: Icons.add,
              onTap: () => onManualChanged((current + 1).clamp(-20, 20)),
              palette: p,
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            current > 0
                ? 'Tú recibes ${current.abs().toStringAsFixed(0)} stroke${current.abs() != 1 ? "s" : ""} de ${s.opponentName.split(" ").first}'
                : current < 0
                    ? 'Das ${current.abs().toStringAsFixed(0)} stroke${current.abs() != 1 ? "s" : ""} a ${s.opponentName.split(" ").first}'
                    : 'Sin ventaja entre ambos',
            style: TextStyle(color: t.sub, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }

  Widget _buildBadge(_Palette p, SlidingAdjustmentSuggestion s) {
    if (s.opponentIsLinked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: p.bilateralBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.bilateralBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sync_rounded, size: 10, color: p.bilateralText),
          const SizedBox(width: 4),
          Text('Bilateral',
            style: TextStyle(fontSize: 9, color: p.bilateralText, fontWeight: FontWeight.w700)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: p.localBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.localBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.sync_disabled_rounded, size: 10, color: p.localText),
        const SizedBox(width: 4),
        Text('Solo local',
          style: TextStyle(fontSize: 9, color: p.localText, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VISUALIZACIÓN FLUJO SLIDING: Inicio → Δ → Nuevo valor
// ─────────────────────────────────────────────────────────────────────────────
class _SlidingFlow extends StatelessWidget {
  final double current;
  final double suggested;
  final int    delta;
  final bool   hasManual;
  final _Palette palette;

  const _SlidingFlow({
    required this.current,
    required this.suggested,
    required this.delta,
    required this.hasManual,
    required this.palette,
  });

  String _fmt(double v) => v >= 0 ? '+${v.toStringAsFixed(0)}' : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final t   = GolfThemeExt.current;
    final p   = palette;
    final changed = (suggested - current).abs() > 0.01;

    final prevColor = t.sub;
    final newColor  = suggested > 0 ? p.win : suggested < 0 ? p.lose : t.sub;
    final deltaColor = delta < 0
        ? p.win
        : delta > 0
            ? p.lose
            : t.sub;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(children: [
        // Valor inicial
        Expanded(child: Column(children: [
          Text('ANTES', style: TextStyle(
            color: t.sub, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(_fmt(current),
            style: TextStyle(
              color: prevColor,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            )),
          Text('sliding', style: TextStyle(color: t.sub, fontSize: 9)),
        ])),

        // Delta + flecha
        Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              delta < 0 ? '−1' : delta > 0 ? '+1' : '±0',
              style: TextStyle(
                color: deltaColor,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Icon(Icons.arrow_forward_rounded, color: p.slidingArrow, size: 20),
          if (hasManual)
            Text('editado', style: TextStyle(
              color: p.manualText, fontSize: 8, fontWeight: FontWeight.w700)),
        ]),

        // Valor nuevo
        Expanded(child: Column(children: [
          Text(changed ? 'NUEVO' : 'SIN CAMBIO', style: TextStyle(
            color: changed ? newColor : t.sub,
            fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(_fmt(suggested),
            style: TextStyle(
              color: changed ? newColor : t.sub,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            )),
          Text('sliding', style: TextStyle(color: t.sub, fontSize: 9)),
        ])),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OPCIÓN GUARDAR JUGADOR NO REGISTRADO
// ─────────────────────────────────────────────────────────────────────────────
class _SavePlayerOption extends StatefulWidget {
  final SlidingAdjustmentSuggestion suggestion;
  final _Palette palette;
  final bool pendingSave;
  final String? customName;
  final VoidCallback onToggle;
  final ValueChanged<String> onNameChanged;

  const _SavePlayerOption({
    required this.suggestion,
    required this.palette,
    required this.pendingSave,
    required this.onToggle,
    required this.onNameChanged,
    this.customName,
  });

  @override
  State<_SavePlayerOption> createState() => _SavePlayerOptionState();
}

class _SavePlayerOptionState extends State<_SavePlayerOption> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.customName ?? widget.suggestion.opponentName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final t = GolfThemeExt.current;
    final s = widget.suggestion;

    return Container(
      decoration: BoxDecoration(
        color: widget.pendingSave
            ? const Color(0xFF1565C0).withValues(alpha: 0.07)
            : t.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.pendingSave
              ? const Color(0xFF1565C0).withValues(alpha: 0.35)
              : p.border,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Fila principal: checkbox + texto
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onToggle,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: widget.pendingSave
                      ? const Color(0xFF1565C0)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.pendingSave
                        ? const Color(0xFF1565C0)
                        : p.border,
                    width: 1.8,
                  ),
                ),
                child: widget.pendingSave
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Guardar jugador y registrar sliding',
                  style: TextStyle(
                    color: widget.pendingSave ? const Color(0xFF42A5F5) : t.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  )),
                Text(
                  'Se añadirá ${s.opponentName.split(" ").first} a tu directorio con el sliding de esta ronda.',
                  style: TextStyle(color: t.sub, fontSize: 10),
                ),
              ])),
              Icon(Icons.person_add_rounded,
                color: widget.pendingSave ? const Color(0xFF42A5F5) : t.sub,
                size: 20),
            ]),
          ),
        ),

        // Campo de nombre personalizado si está activado
        if (widget.pendingSave)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Divider(color: p.border, height: 1),
              const SizedBox(height: 10),
              Text('Nombre en tu directorio:',
                style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _ctrl,
                onChanged: widget.onNameChanged,
                style: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: s.opponentName,
                  hintStyle: TextStyle(color: t.sub),
                  filled: true,
                  fillColor: t.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: p.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: p.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: const Color(0xFF1565C0), width: 1.8),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS INTERNOS
// ─────────────────────────────────────────────────────────────────────────────

class _GAvatar extends StatelessWidget {
  final String name;
  final int colorIndex;
  final double size;
  const _GAvatar({required this.name, this.colorIndex = 0, this.size = 36});

  static const _colors = [
    Color(0xFF2E7D32), Color(0xFF1565C0), Color(0xFF6A1B9A),
    Color(0xFFC62828), Color(0xFFE65100), Color(0xFF00695C),
    Color(0xFF4A148C), Color(0xFF006064),
  ];

  @override
  Widget build(BuildContext context) {
    final c = _colors[colorIndex % _colors.length];
    final initials = name.trim().isEmpty ? '?'
        : name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials,
        style: TextStyle(color: Colors.white, fontSize: size * 0.36, fontWeight: FontWeight.w800)),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final _Palette palette;
  const _StepBtn({required this.icon, required this.onTap, required this.palette});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: palette.manualPill,
          shape: BoxShape.circle,
          border: Border.all(color: palette.manualText.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: palette.manualText, size: 20),
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
