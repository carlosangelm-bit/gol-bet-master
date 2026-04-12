// ─────────────────────────────────────────────────────────────────────────────
// CAPTURE SCREEN — Layout Opción C
// Estructura:
//   1. Header + selector de hoyos + info del hoyo (fijos arriba)
//   2. Tabla compacta: todos los jugadores — tocar fila = jugador activo
//      Cada fila: Avatar · Apodo · Progreso vs par · −score+ · −putts+
//   3. Zona del jugador activo:
//      - Botones rápidos 2×3 (Eagle/Birdie/Par / Bogey/Doble/+3)
//      - Botón Units (abre sheet igual que antes)
//   4. Oyeses (solo par 3)
//   5. Navegación prev/next hoyo
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/sliding_adjustment_dialog.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  int _currentHole = 1; // Se corrige en initState via postFrameCallback
  String? _activePlayerId; // jugador seleccionado en la tabla
  final ScrollController _holeScroll = ScrollController();

  List<int> _firstSegment(StartingNine sn) =>
      sn == StartingNine.back ? List.generate(9, (i) => i + 10) : List.generate(9, (i) => i + 1);
  List<int> _secondSegment(StartingNine sn) =>
      sn == StartingNine.back ? List.generate(9, (i) => i + 1) : List.generate(9, (i) => i + 10);
  int _lastOfFirst(StartingNine sn)   => sn == StartingNine.back ? 18 : 9;
  int _firstOfSecond(StartingNine sn) => sn == StartingNine.back ? 1 : 10;
  bool _isInSecondSegment(Round round) {
    final sn = round.startingNine;
    if (sn == StartingNine.front) return _currentHole >= 10;
    return _currentHole <= 9;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov  = context.read<RoundProvider>();
      if (!prov.hasRound) return;
      final round = prov.round!;
      final sn    = round.startingNine;
      final order = [..._firstSegment(sn), ..._secondSegment(sn)];
      for (final h in order) {
        final activePlayers = round.players.where((p) => round.scores.containsKey(p.id)).toList();
        if (!activePlayers.every((p) => round.getScore(p.id, h).hasScore)) {
          _jumpToHole(h);
          break;
        }
      }
      // Activar el primer jugador por defecto
      final activePlayers = round.players.where((p) => round.scores.containsKey(p.id)).toList();
      if (activePlayers.isNotEmpty) {
        setState(() => _activePlayerId = activePlayers.first.id);
      }
    });
  }

  @override
  void dispose() {
    _holeScroll.dispose();
    super.dispose();
  }

  void _jumpToHole(int h) {
    setState(() => _currentHole = h);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_holeScroll.hasClients) return;
      // Calcular posición correcta según el orden real de juego
      final prov  = context.read<RoundProvider>();
      final round = prov.hasRound ? prov.round! : null;
      if (round == null) return;
      final sn    = round.startingNine;
      final order = [..._firstSegment(sn), ..._secondSegment(sn)];
      final idx   = order.indexOf(h);
      if (idx < 0) return;
      _holeScroll.animateTo(
        idx * 46.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final t    = prov.theme;
    GolfThemeExt.setCurrent(t);

    if (!prov.hasRound) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.sports_golf, color: t.sub, size: 48),
            const SizedBox(height: 12),
            Text('No hay ronda activa', style: TextStyle(color: t.sub, fontSize: 16)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: GPrimaryButton(
                label: 'Iniciar Ronda',
                onTap: () => context.read<RoundProvider>().setTab(0),
              ),
            ),
          ]),
        ),
      );
    }

    final round = prov.round!;
    // Validar que _currentHole pertenece al orden de juego real
    final sn0       = round.startingNine;
    final firstSeg0 = sn0 == StartingNine.back
        ? List.generate(9, (i) => i + 10)
        : List.generate(9, (i) => i + 1);
    final secondSeg0 = sn0 == StartingNine.back
        ? List.generate(9, (i) => i + 1)
        : List.generate(9, (i) => i + 10);
    final playOrder0 = round.totalHoles == 9
        ? firstSeg0
        : [...firstSeg0, ...secondSeg0];
    if (!playOrder0.contains(_currentHole)) {
      // Hoyo inválido para esta ronda → corregir de inmediato
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToHole(playOrder0.first));
      _currentHole = playOrder0.first;
    }
    final ch    = round.course.holes.firstWhere((h) => h.hole == _currentHole,
        orElse: () => round.course.holes.first);

    // Asegurar que siempre hay un jugador activo válido
    final activePlayers = round.players.where((p) => round.scores.containsKey(p.id)).toList();
    final activeId = (_activePlayerId != null &&
            activePlayers.any((p) => p.id == _activePlayerId))
        ? _activePlayerId!
        : activePlayers.first.id;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ─────────────────────────────────────────────────────
          _CaptureHeader(round: round, t: t),

          // ── Selector de hoyos ──────────────────────────────────────────
          _HoleSelector(
            round: round,
            currentHole: _currentHole,
            scrollCtrl: _holeScroll,
            t: t,
            onSelect: _jumpToHole,
            showAll: _isInSecondSegment(round),
          ),

          // ── Info del hoyo ──────────────────────────────────────────────
          _HoleInfoBar(ch: ch, t: t),

          // ── Cuerpo principal scrollable ────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Tabla de jugadores ─────────────────────────────────
                _PlayerTable(
                  round: round,
                  currentHole: _currentHole,
                  activePlayerId: activeId,
                  t: t,
                  onSelectPlayer: (pid) => setState(() => _activePlayerId = pid),
                ),

                const SizedBox(height: 10),

                // ── Zona del jugador activo ────────────────────────────
                _ActivePlayerZone(
                  round: round,
                  activePlayerId: activeId,
                  hole: _currentHole,
                  ch: ch,
                  t: t,
                ),

                // ── Ranking Oyes (solo par 3) ──────────────────────────
                if (ch.isPar3) ...[
                  const SizedBox(height: 10),
                  _OyesRankingSection(hole: _currentHole, t: t),
                ],

                const SizedBox(height: 10),

                // ── Navegación prev/next ───────────────────────────────
                Builder(builder: (_) {
                  final sn          = round.startingNine;
                  final is9Holes    = round.totalHoles == 9;
                  final firstSeg    = _firstSegment(sn);
                  final secondSeg   = _secondSegment(sn);
                  final firstSecond = _firstOfSecond(sn);
                  // Orden real de juego según startingNine
                  final playOrder   = is9Holes
                      ? firstSeg
                      : [...firstSeg, ...secondSeg];
                  int curIdx = playOrder.indexOf(_currentHole);
                  // Si el hoyo actual no está en el playOrder (ej. _currentHole=1
                  // pero la ronda empieza por Back 9), saltar al primer hoyo válido.
                  if (curIdx == -1) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _jumpToHole(playOrder.first);
                    });
                    curIdx = 0;
                  }
                  final hasPrev     = curIdx > 0;
                  final hasNext     = curIdx >= 0 && curIdx < playOrder.length - 1;
                  final inSecond    = secondSeg.contains(_currentHole);
                  final isLastOfFirst = curIdx == firstSeg.length - 1 && !is9Holes;
                  final isVeryLast    = curIdx == playOrder.length - 1;
                  final isLast9       = is9Holes && curIdx == playOrder.length - 1;

                  return _HoleNavButtons(
                    current:    _currentHole,
                    startingNine: sn,
                    is9HoleRound: is9Holes,
                    inSecondSegment: inSecond,
                    prevHole: hasPrev ? playOrder[curIdx - 1] : null,
                    nextHole: hasNext ? playOrder[curIdx + 1] : null,
                    isLastOfFirstSegment: isLastOfFirst,
                    firstOfSecond: firstSecond,
                    isVeryLast: isVeryLast,
                    isLast9: isLast9,
                    t: t,
                    onPrev: hasPrev ? () => _jumpToHole(playOrder[curIdx - 1]) : null,
                    onNext: hasNext ? () => _jumpToHole(playOrder[curIdx + 1]) : null,
                    onContinueTo18: isLast9
                        ? () => _jumpToHole(firstSecond)
                        : null,
                  );
                }),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────
class _CaptureHeader extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  const _CaptureHeader({required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    final completed      = _countCompleted(round);
    final effectiveTotal = _effectiveTotal(round);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(color: t.bg, border: Border(bottom: BorderSide(color: t.divider))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Score', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3)),
          Text(round.name, style: TextStyle(color: t.sub, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: t.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.primary.withValues(alpha: 0.25)),
          ),
          child: Text('$completed/$effectiveTotal hoyos',
              style: TextStyle(color: t.primary, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  int _effectiveTotal(Round round) {
    if (round.totalHoles == 18) return 18;
    final secondStart = round.startingNine == StartingNine.back ? 1 : 10;
    final secondEnd   = round.startingNine == StartingNine.back ? 9 : 18;
    final hasSecond   = round.scores.values.any((hmap) =>
        hmap.keys.any((h) => h >= secondStart && h <= secondEnd));
    return hasSecond ? 18 : round.totalHoles;
  }

  int _countCompleted(Round round) {
    final total = _effectiveTotal(round);
    final activePlayers = round.players.where((p) => round.scores.containsKey(p.id)).toList();
    int c = 0;
    for (int h = 1; h <= total; h++) {
      if (activePlayers.every((p) => round.getScore(p.id, h).hasScore)) c++;
    }
    return c;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELECTOR DE HOYOS
// ─────────────────────────────────────────────────────────────────────────────
class _HoleSelector extends StatelessWidget {
  final Round round;
  final int currentHole;
  final ScrollController scrollCtrl;
  final GolfTheme t;
  final void Function(int) onSelect;
  final bool showAll;
  const _HoleSelector({
    required this.round, required this.currentHole,
    required this.scrollCtrl, required this.t, required this.onSelect,
    this.showAll = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: t.surface,
      child: ListView.builder(
        controller: scrollCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        itemCount: (round.totalHoles == 9 && !showAll) ? 9 : 18,
        itemBuilder: (_, i) {
          // Respetar siempre el orden real de juego (startingNine)
          final List<int> order;
          if (round.totalHoles == 9 && !showAll) {
            order = round.startingNine == StartingNine.back
                ? List.generate(9, (j) => j + 10)
                : List.generate(9, (j) => j + 1);
          } else {
            final first  = round.startingNine == StartingNine.back
                ? List.generate(9, (j) => j + 10)
                : List.generate(9, (j) => j + 1);
            final second = round.startingNine == StartingNine.back
                ? List.generate(9, (j) => j + 1)
                : List.generate(9, (j) => j + 10);
            order = [...first, ...second];
          }
          final h = order[i];
          final isSel   = h == currentHole;
          final activePlayers = round.players.where((p) => round.scores.containsKey(p.id)).toList();
          final allDone = activePlayers.isNotEmpty &&
              activePlayers.every((p) => round.getScore(p.id, h).hasScore);
          final isPar3  = round.course.holes.firstWhere((c) => c.hole == h).isPar3;

          return GestureDetector(
            onTap: () => onSelect(h),
            child: Container(
              width: 42,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: isSel
                    ? t.primary
                    : allDone
                        ? t.primary.withValues(alpha: 0.18)
                        : t.card,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSel ? t.primary : allDone ? t.primary.withValues(alpha: 0.4) : t.divider,
                ),
              ),
              alignment: Alignment.center,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  '$h',
                  style: TextStyle(
                    color: isSel ? t.onPrimary : allDone ? t.primary : t.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (isPar3)
                  Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      color: isSel ? t.onPrimary.withValues(alpha: 0.7) : t.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INFO DEL HOYO
// ─────────────────────────────────────────────────────────────────────────────
class _HoleInfoBar extends StatelessWidget {
  final CourseHole ch;
  final GolfTheme t;
  const _HoleInfoBar({required this.ch, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: t.bg,
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Text(
            '${ch.hole}',
            style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w900, fontSize: 22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Row(children: [
          _chip('Par ${ch.par}', t.primary, t),
          const SizedBox(width: 6),
          _chip('SI ${ch.strokeIndex}', t.sub, t),
          const SizedBox(width: 6),
          _chip(ch.hole <= 9 ? 'Front 9' : 'Back 9',
              ch.hole <= 9 ? t.primary : t.accent, t),
          if (ch.isPar3) ...[
            const SizedBox(width: 6),
            _chip('⛳ Oyes', t.accent, t, accent: true),
          ],
        ])),
      ]),
    );
  }

  Widget _chip(String label, Color color, GolfTheme t, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: accent ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABLA DE JUGADORES — todas las filas compactas
// ─────────────────────────────────────────────────────────────────────────────
class _PlayerTable extends StatelessWidget {
  final Round round;
  final int currentHole;
  final String activePlayerId;
  final GolfTheme t;
  final void Function(String) onSelectPlayer;

  const _PlayerTable({
    required this.round,
    required this.currentHole,
    required this.activePlayerId,
    required this.t,
    required this.onSelectPlayer,
  });

  // Nombre corto: player.name ya contiene el displayName/apodo asignado al crear la ronda
  String _shortName(Player p) => p.isVirtual ? p.name : p.name.split(' ').first;

  // Progreso bruto acumulado vs par (solo hoyos completados hasta el actual)
  String _grossProgress(Round round, String playerId) {
    int totalGross = 0;
    int totalPar   = 0;
    for (final hole in round.course.holes) {
      final s = round.getScore(playerId, hole.hole);
      if (!s.hasScore) continue;
      totalGross += s.grossScore!;
      totalPar   += hole.par;
    }
    if (totalPar == 0) return '';
    final diff = totalGross - totalPar;
    if (diff == 0) return 'E';
    return diff > 0 ? '+$diff' : '$diff';
  }

  Color _progressColor(String progress, GolfTheme t) {
    if (progress.isEmpty || progress == 'E') return t.sub;
    if (progress.startsWith('+')) return t.scoreOver;
    return t.scoreUnder;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.divider),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: round.players.where((p) => round.scores.containsKey(p.id)).toList().asMap().entries.map((entry) {
          final idx    = entry.key;
          final player = entry.value;
          final isActive = player.id == activePlayerId;
          final score    = prov.round!.getScore(player.id, currentHole);
          final gross    = score.grossScore ?? 0;
          final putts    = score.putts;
          final par      = round.course.holes
              .firstWhere((h) => h.hole == currentHole).par;
          final progress = _grossProgress(round, player.id);
          final progColor = _progressColor(progress, t);
          final shortName = _shortName(player);

          // Color del score del hoyo actual
          Color scoreColor = t.sub;
          if (score.hasScore) {
            final rel = gross - par;
            if (rel < 0) {
              scoreColor = t.scoreUnder;
            } else if (rel > 0) {
              scoreColor = t.scoreOver;
            } else {
              scoreColor = t.sub;
            }
          }

          return GestureDetector(
            onTap: () => onSelectPlayer(player.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: isActive
                    ? t.primary.withValues(alpha: 0.06)
                    : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    color: isActive ? t.primary : Colors.transparent,
                    width: 3,
                  ),
                  bottom: idx < round.players.length - 1
                      ? BorderSide(color: t.divider.withValues(alpha: 0.6))
                      : BorderSide.none,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                // Avatar
                GAvatar(name: player.name, colorIndex: player.colorIndex, size: 36),
                const SizedBox(width: 8),

                // Nombre + HCP
                SizedBox(
                  width: 64,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      shortName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive ? t.primary : t.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'HCP ${player.handicapBase.toStringAsFixed(0)}',
                      style: TextStyle(color: t.sub, fontSize: 10),
                    ),
                  ]),
                ),

                const SizedBox(width: 4),

                // Progreso vs par (bruto acumulado)
                if (progress.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: progColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: progColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      progress,
                      style: TextStyle(
                        color: progColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 32),

                const Spacer(),

                // Score del hoyo: − valor +
                // Cuando no hay score, el par se muestra como placeholder.
                // − desde par → guarda par-1 (birdie); + desde par → par+1 (bogey)
                _ScoreStepper(
                  score: gross,
                  hasScore: score.hasScore,
                  scoreColor: scoreColor,
                  par: par,
                  t: t,
                  onDec: () {
                    // Base: score actual si ya registrado, o par si es placeholder
                    final base = score.hasScore ? gross : par;
                    final newScore = base > 1 ? base - 1 : 1;
                    prov.updateScore(player.id, currentHole, newScore,
                        putts == 0 ? 2 : putts);
                  },
                  onInc: () {
                    final base = score.hasScore ? gross : par;
                    prov.updateScore(player.id, currentHole, base + 1,
                        putts == 0 ? 2 : putts);
                  },
                  onTapPar: () {
                    // Toque en el círculo sin score → registra exactamente el par
                    prov.updateScore(player.id, currentHole, par,
                        putts == 0 ? 2 : putts);
                  },
                ),

                // Divisor vertical
                Container(
                  width: 1, height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: t.divider,
                ),

                // Putts: − valor +
                _PuttsStepper(
                  putts: putts,
                  t: t,
                  onDec: () => prov.updateScore(
                      player.id, currentHole, score.grossScore,
                      putts > 0 ? putts - 1 : 0),
                  onInc: () => prov.updateScore(
                      player.id, currentHole, score.grossScore, putts + 1),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEPPER DE SCORE (inline en la tabla)
// ─────────────────────────────────────────────────────────────────────────────
class _ScoreStepper extends StatelessWidget {
  final int score;
  final bool hasScore;
  final Color scoreColor;
  final int par;
  final GolfTheme t;
  final VoidCallback onDec;
  final VoidCallback onInc;
  /// Registra exactamente el par (toque al círculo cuando no hay score).
  final VoidCallback onTapPar;

  const _ScoreStepper({
    required this.score, required this.hasScore, required this.scoreColor,
    required this.par, required this.t,
    required this.onDec, required this.onInc, required this.onTapPar,
  });

  @override
  Widget build(BuildContext context) {
    // Cuando no hay score aún, mostramos el par como placeholder visual.
    // El círculo tiene estilo atenuado para distinguirlo de un score real.
    final displayScore = hasScore ? score : par;
    final displayColor = hasScore ? scoreColor : t.sub;
    final bgColor      = hasScore
        ? scoreColor.withValues(alpha: 0.15)
        : t.surface;
    final borderColor  = hasScore
        ? scoreColor.withValues(alpha: 0.5)
        : t.divider;
    final borderWidth  = hasScore ? 1.5 : 1.0;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      _stepBtn(Icons.remove, t.loss, onDec, t),
      const SizedBox(width: 4),
      GestureDetector(
        // Toque en el círculo cuando no hay score → registra el par
        onTap: hasScore ? null : onTapPar,
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          alignment: Alignment.center,
          child: Text(
            '$displayScore',
            style: TextStyle(
              color: displayColor,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      _stepBtn(Icons.add, t.profit, onInc, t),
    ]);
  }

  Widget _stepBtn(IconData ic, Color color, VoidCallback fn, GolfTheme t) {
    return GestureDetector(
      onTap: fn,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        alignment: Alignment.center,
        child: Icon(ic, size: 16, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEPPER DE PUTTS (inline en la tabla)
// ─────────────────────────────────────────────────────────────────────────────
class _PuttsStepper extends StatelessWidget {
  final int putts;
  final GolfTheme t;
  final VoidCallback onDec;
  final VoidCallback onInc;

  const _PuttsStepper({
    required this.putts, required this.t,
    required this.onDec, required this.onInc,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('PUTTS', style: TextStyle(color: t.sub, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      const SizedBox(height: 3),
      Row(mainAxisSize: MainAxisSize.min, children: [
        _btn(Icons.remove, onDec, t),
        SizedBox(
          width: 24,
          child: Text(
            '$putts',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        _btn(Icons.add, onInc, t),
      ]),
    ]);
  }

  Widget _btn(IconData ic, VoidCallback fn, GolfTheme t) => GestureDetector(
    onTap: fn,
    child: Container(
      width: 28, height: 28,
      alignment: Alignment.center,
      child: Icon(ic, size: 14, color: t.sub),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ZONA DEL JUGADOR ACTIVO — botones rápidos 2×3 + Units
// ─────────────────────────────────────────────────────────────────────────────
class _ActivePlayerZone extends StatefulWidget {
  final Round round;
  final String activePlayerId;
  final int hole;
  final CourseHole ch;
  final GolfTheme t;

  const _ActivePlayerZone({
    required this.round, required this.activePlayerId,
    required this.hole, required this.ch, required this.t,
  });

  @override
  State<_ActivePlayerZone> createState() => _ActivePlayerZoneState();
}

class _ActivePlayerZoneState extends State<_ActivePlayerZone> {
  static const _quickValues = [10.0, 25.0, 50.0, 100.0];
  final Map<UnitEventType, double> _values = {
    for (final e in UnitEventType.values) e: 25.0,
  };

  @override
  Widget build(BuildContext context) {
    final prov   = context.watch<RoundProvider>();
    final t      = widget.t;
    final par    = widget.ch.par;
    final score  = prov.round!.getScore(widget.activePlayerId, widget.hole);
    final gross  = score.grossScore ?? 0;
    final putts  = score.putts;
    final player = widget.round.players.firstWhere(
        (p) => p.id == widget.activePlayerId);

    // Nombre corto: player.name ya contiene el apodo/displayName asignado al crear la ronda
    // Para equipos virtuales, usar nombre completo
    final shortName = player.isVirtual ? player.name : player.name.split(' ').first;

    // Conteo de units activos
    final activeUnits = UnitEventType.values
        .where((e) => prov.hasEvent(widget.activePlayerId, widget.hole, e))
        .length;

    // Opciones rápidas de score: 3 por fila
    final options = [
      (par - 2, 'Eagle',  t.scoreUnder),
      (par - 1, 'Birdie', t.scoreUnder),
      (par,     'Par',    t.sub),
      (par + 1, 'Bogey',  t.scoreOver),
      (par + 2, 'Doble',  t.scoreOver),
      (par + 3, '+3',     t.scoreOver),
    ].where((o) => o.$1 >= 1).toList();

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Cabecera: jugador activo ────────────────────────────────────
        Row(children: [
          GAvatar(name: player.name, colorIndex: player.colorIndex, size: 22),
          const SizedBox(width: 6),
          Text(
            shortName,
            style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text('Score rápido', style: TextStyle(color: t.primary, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          // Borrar score
          if (score.hasScore)
            GestureDetector(
              onTap: () => prov.updateScore(widget.activePlayerId, widget.hole, null, 0),
              child: Text('Borrar', style: TextStyle(color: t.loss.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ]),
        const SizedBox(height: 10),

        // ── Botones rápidos 2×3 ─────────────────────────────────────────
        ...[ [0, 1, 2], [3, 4, 5] ].map((row) {
          final rowOptions = row
              .where((i) => i < options.length)
              .map((i) => options[i])
              .toList();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: rowOptions.map((o) {
              final scoreVal = o.$1;
              final label    = o.$2;
              final color    = o.$3;
              final isSel    = score.hasScore && gross == scoreVal;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => prov.updateScore(
                      widget.activePlayerId, widget.hole, scoreVal,
                      putts == 0 ? 2 : putts,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 130),
                      height: 58,
                      decoration: BoxDecoration(
                        color: isSel ? color : t.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSel ? color : t.divider,
                          width: isSel ? 2 : 1,
                        ),
                        boxShadow: isSel
                            ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          '$scoreVal',
                          style: TextStyle(
                            color: isSel ? Colors.white : t.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                        ),
                        Text(
                          label,
                          style: TextStyle(
                            color: isSel ? Colors.white.withValues(alpha: 0.85) : color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            }).toList()),
          );
        }),

        const SizedBox(height: 4),

        // ── Fila Units ──────────────────────────────────────────────────
        Row(children: [
          Text('UNITS', style: TextStyle(color: t.sub, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(width: 8),
          Expanded(child: _UnitsButton(
            player: player,
            hole: widget.hole,
            t: t,
            values: _values,
            quickValues: _quickValues,
            activeCount: activeUnits,
          )),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTÓN UNITS (igual que antes: abre sheet)
// ─────────────────────────────────────────────────────────────────────────────
class _UnitsButton extends StatefulWidget {
  final Player player;
  final int hole;
  final GolfTheme t;
  final Map<UnitEventType, double> values;
  final List<double> quickValues;
  final int activeCount;

  const _UnitsButton({
    required this.player, required this.hole, required this.t,
    required this.values, required this.quickValues, required this.activeCount,
  });

  @override
  State<_UnitsButton> createState() => _UnitsButtonState();
}

class _UnitsButtonState extends State<_UnitsButton> {
  late final Map<UnitEventType, double> _values;

  @override
  void initState() {
    super.initState();
    _values = Map<UnitEventType, double>.from(widget.values);
  }

  @override
  Widget build(BuildContext context) {
    final prov   = context.watch<RoundProvider>();
    final t      = widget.t;
    final active = UnitEventType.values
        .where((e) => prov.hasEvent(widget.player.id, widget.hole, e))
        .toList();

    return Row(children: [
      // Chips de units activos
      Expanded(
        child: active.isEmpty
            ? Text('Sin units', style: TextStyle(color: t.sub, fontSize: 12))
            : Wrap(spacing: 4, runSpacing: 4, children: active.map((e) {
                final v = _values[e]!;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.accent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${e.label}  \$${v.toStringAsFixed(0)}',
                    style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                );
              }).toList()),
      ),
      const SizedBox(width: 8),
      // Botón abrir sheet
      GestureDetector(
        onTap: () => _openUnitsSheet(context, prov),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active.isNotEmpty ? t.accent.withValues(alpha: 0.12) : t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active.isNotEmpty ? t.accent.withValues(alpha: 0.5) : t.divider,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_circle_outline,
                size: 15, color: active.isNotEmpty ? t.accent : t.sub),
            const SizedBox(width: 5),
            Text(
              active.isEmpty ? 'Units' : '${active.length} unit${active.length > 1 ? "s" : ""}',
              style: TextStyle(
                color: active.isNotEmpty ? t.accent : t.sub,
                fontSize: 12, fontWeight: FontWeight.w700,
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  void _openUnitsSheet(BuildContext outerCtx, RoundProvider outerProv) {
    final t = widget.t;
    showModalBottomSheet(
      context: outerCtx,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => ChangeNotifierProvider<RoundProvider>.value(
        value: outerProv,
        child: _UnitsSheetContent(
          playerId:    widget.player.id,
          playerName:  widget.player.name,
          hole:        widget.hole,
          t:           t,
          values:      _values,
          quickValues: widget.quickValues,
          onValueChange: (evt, v) => setState(() => _values[evt] = v),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RANKING OYES (par 3)
// ─────────────────────────────────────────────────────────────────────────────
class _OyesRankingSection extends StatelessWidget {
  final int hole;
  final GolfTheme t;
  const _OyesRankingSection({required this.hole, required this.t});

  @override
  Widget build(BuildContext context) {
    final prov     = context.watch<RoundProvider>();
    final round    = prov.round!;
    final ranking  = round.getOyese(hole);
    final ranked   = ranking?.ranking ?? [];
    final unranked = round.players.map((p) => p.id)
        .where((id) => !ranked.contains(id)).toList();

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.accent.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events, color: t.accent, size: 13),
              const SizedBox(width: 4),
              Text('RANKING OYES — Hoyo $hole',
                  style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
            ]),
          ),
          const Spacer(),
          if (ranked.isNotEmpty)
            GestureDetector(
              onTap: () => prov.setOyeseRanking(hole, []),
              child: Text('Limpiar', style: TextStyle(color: t.sub, fontSize: 10)),
            ),
        ]),
        const SizedBox(height: 10),

        if (ranked.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Toca un jugador para asignar 1°, 2°, 3°...',
              style: TextStyle(color: t.sub, fontSize: 12),
            ),
          ),

        if (ranked.isNotEmpty) ...[
          ...ranked.asMap().entries.map((e) {
            final p = round.players.firstWhere((pl) => pl.id == e.value);
            return _RankedPlayerTile(
              position: e.key + 1,
              player: p,
              t: t,
              onRemove: () {
                final newRanking = List<String>.from(ranked)..removeAt(e.key);
                prov.setOyeseRanking(hole, newRanking);
              },
            );
          }),
          const SizedBox(height: 6),
        ],

        if (unranked.isNotEmpty) ...[
          Text(
            ranked.isEmpty ? 'Selecciona el orden (1° = más cerca del hoyo):' : 'Sin posición:',
            style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: unranked.map((pid) {
            final p = round.players.firstWhere((pl) => pl.id == pid);
            return GestureDetector(
              onTap: () => prov.setOyeseRanking(hole, [...ranked, pid]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: t.primary.withValues(alpha: 0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  GAvatar(name: p.name, colorIndex: p.colorIndex, size: 22),
                  const SizedBox(width: 6),
                  Text(
                    '${p.name.split(' ').first}  +${ranked.length + 1}°',
                    style: TextStyle(color: t.primary, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ]),
              ),
            );
          }).toList()),
        ],
      ]),
    );
  }
}

class _RankedPlayerTile extends StatelessWidget {
  final int position;
  final Player player;
  final GolfTheme t;
  final VoidCallback onRemove;
  const _RankedPlayerTile({required this.position, required this.player, required this.t, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final posColors = [t.primary, t.sub, t.sub.withValues(alpha: 0.6)];
    final posColor  = posColors[position.clamp(1, 3) - 1];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: position == 1 ? t.primary.withValues(alpha: 0.4) : t.divider),
      ),
      child: Row(children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: posColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: posColor.withValues(alpha: 0.5)),
          ),
          alignment: Alignment.center,
          child: Text('$position°',
              style: TextStyle(color: posColor, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        GAvatar(name: player.name, colorIndex: player.colorIndex, size: 26),
        const SizedBox(width: 8),
        Expanded(child: Text(player.name,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13))),
        GestureDetector(
          onTap: onRemove,
          child: Icon(Icons.close, color: t.sub, size: 16),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UNITS SHEET CONTENT (igual que antes)
// ─────────────────────────────────────────────────────────────────────────────
class _UnitsSheetContent extends StatefulWidget {
  final String playerId;
  final String playerName;
  final int hole;
  final GolfTheme t;
  final Map<UnitEventType, double> values;
  final List<double> quickValues;
  final void Function(UnitEventType, double) onValueChange;

  const _UnitsSheetContent({
    required this.playerId, required this.playerName, required this.hole,
    required this.t, required this.values, required this.quickValues,
    required this.onValueChange,
  });

  @override
  State<_UnitsSheetContent> createState() => _UnitsSheetContentState();
}

class _UnitsSheetContentState extends State<_UnitsSheetContent> {
  late final Map<UnitEventType, double> _localValues;

  @override
  void initState() {
    super.initState();
    _localValues = Map<UnitEventType, double>.from(widget.values);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final t    = widget.t;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40, height: 4,
              decoration: BoxDecoration(color: t.divider, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                Icon(Icons.star_rounded, color: t.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Units — ${widget.playerName.split(' ').first}  •  Hoyo ${widget.hole}',
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Icon(Icons.close, color: t.sub, size: 20),
                ),
              ]),
            ),
            Divider(color: t.divider, height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: UnitEventType.values.length,
                itemBuilder: (_, i) {
                  final evt     = UnitEventType.values[i];
                  final isActive = prov.hasEvent(widget.playerId, widget.hole, evt);
                  final selVal  = _localValues[evt] ?? 25.0;
                  final isCustom = !widget.quickValues.contains(selVal);

                  return _UnitRow(
                    evt: evt, isActive: isActive, selVal: selVal,
                    isCustom: isCustom, quickValues: widget.quickValues, t: t,
                    onToggle: () {
                      context.read<RoundProvider>().toggleEvent(
                          widget.playerId, widget.hole, evt);
                      setState(() {});
                    },
                    onValueChange: (v) {
                      setState(() => _localValues[evt] = v);
                      widget.onValueChange(evt, v);
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: GPrimaryButton(label: 'Listo', onTap: () => Navigator.pop(ctx)),
            ),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UNIT ROW (igual que antes)
// ─────────────────────────────────────────────────────────────────────────────
class _UnitRow extends StatelessWidget {
  final UnitEventType evt;
  final bool isActive;
  final double selVal;
  final bool isCustom;
  final List<double> quickValues;
  final GolfTheme t;
  final VoidCallback onToggle;
  final void Function(double) onValueChange;

  const _UnitRow({
    required this.evt, required this.isActive, required this.selVal,
    required this.isCustom, required this.quickValues, required this.t,
    required this.onToggle, required this.onValueChange,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? t.accent.withValues(alpha: 0.07) : t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? t.accent.withValues(alpha: 0.4) : t.divider),
      ),
      child: Column(children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isActive ? t.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isActive ? t.accent : t.sub.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: isActive ? Icon(Icons.check, color: Colors.white, size: 14) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(evt.label, style: TextStyle(
                  color: isActive ? t.text : t.sub,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  fontSize: 14,
                )),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('\$${selVal.toStringAsFixed(0)}',
                      style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
            ]),
          ),
        ),
        if (isActive) ...[
          Divider(color: t.divider.withValues(alpha: 0.6), height: 1, indent: 12, endIndent: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(children: [
              Text('Valor:', style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(child: Row(children: [
                ...quickValues.map((v) {
                  final isSel = selVal == v;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => onValueChange(v),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSel ? t.primary : t.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSel ? t.primary : t.divider, width: isSel ? 2 : 1),
                        ),
                        child: Text('\$${v.toStringAsFixed(0)}', style: TextStyle(
                          color: isSel ? t.onPrimary : t.text,
                          fontSize: 12, fontWeight: isSel ? FontWeight.w800 : FontWeight.w400,
                        )),
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: () => _showCustomDialog(context),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: isCustom ? t.primary : t.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isCustom ? t.primary : t.divider, width: isCustom ? 2 : 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit_outlined, size: 11, color: isCustom ? t.onPrimary : t.sub),
                      const SizedBox(width: 3),
                      Text(
                        isCustom ? '\$${selVal.toStringAsFixed(0)}' : 'Otro',
                        style: TextStyle(
                          color: isCustom ? t.onPrimary : t.sub,
                          fontSize: 12, fontWeight: isCustom ? FontWeight.w800 : FontWeight.w400,
                        ),
                      ),
                    ]),
                  ),
                ),
              ])),
            ]),
          ),
        ],
      ]),
    );
  }

  void _showCustomDialog(BuildContext context) {
    final ctrl = TextEditingController(text: isCustom ? selVal.toStringAsFixed(0) : '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Text('Valor personalizado',
            style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 18),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'Ej: 200', prefixText: '\$ ',
            fillColor: t.surface, filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.primary, width: 2)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: t.sub))),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null && v > 0) { onValueChange(v); Navigator.pop(ctx); }
            },
            child: Text('OK', style: TextStyle(color: t.primary, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTONES DE NAVEGACIÓN PREV/NEXT HOYO
// ─────────────────────────────────────────────────────────────────────────────
class _HoleNavButtons extends StatelessWidget {
  final int current;
  final GolfTheme t;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onContinueTo18;
  final int? prevHole;
  final int? nextHole;
  final bool isLastOfFirstSegment;
  final bool isVeryLast;
  final bool isLast9;
  final bool is9HoleRound;
  final bool inSecondSegment;
  final int firstOfSecond;
  final StartingNine startingNine;

  const _HoleNavButtons({
    required this.current, required this.t, required this.startingNine,
    required this.firstOfSecond,
    this.onPrev, this.onNext, this.onContinueTo18,
    this.prevHole, this.nextHole,
    this.isLastOfFirstSegment = false, this.isVeryLast = false,
    this.isLast9 = false, this.is9HoleRound = false, this.inSecondSegment = false,
  });

  @override
  Widget build(BuildContext context) {
    final prevLabel = prevHole != null ? '← Hoyo $prevHole' : '←';

    if (isLast9) {
      return Column(children: [
        Row(children: [
          Expanded(child: _NavBtn(label: prevLabel, enabled: onPrev != null, t: t, onTap: onPrev)),
          const SizedBox(width: 8),
          Expanded(child: _NavBtn(label: '✓ Terminar', enabled: true, t: t, primary: true,
              onTap: () => _finishRound(context))),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: _NavBtn(
            label: '⛳ Continuar ${startingNine == StartingNine.back ? "Front 9" : "Back 9"} →',
            enabled: true, t: t, primary: false, onTap: onContinueTo18,
          ),
        ),
      ]);
    }

    final String nextLabel;
    if (isVeryLast) {
      nextLabel = '✓ Terminar';
    } else if (isLastOfFirstSegment) {
      nextLabel = '⛳ ${startingNine == StartingNine.back ? "Front 9 →" : "Back 9 →"}';
    } else {
      nextLabel = nextHole != null ? 'Hoyo $nextHole →' : '→';
    }

    return Row(children: [
      Expanded(child: _NavBtn(label: prevLabel, enabled: onPrev != null, t: t, onTap: onPrev)),
      const SizedBox(width: 8),
      Expanded(child: _NavBtn(
        label: nextLabel,
        enabled: onNext != null || isVeryLast,
        t: t, primary: true,
        onTap: onNext ?? (isVeryLast ? () => _finishRound(context) : null),
      )),
    ]);
  }

  Future<void> _finishRound(BuildContext context) async {
    final prov = context.read<RoundProvider>();
    final t    = prov.theme;

    // Solo el owner/admin puede finalizar una ronda en vivo
    if (prov.isLiveRound && !prov.isLiveOwner) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Solo el organizador puede finalizar la ronda.'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Text('Finalizar ronda', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        content: Text('Los resultados se guardarán en el historial y la ronda quedará cerrada.',
            style: TextStyle(color: t.sub)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: TextStyle(color: t.sub))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Finalizar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    // Capturar la ronda ANTES de que finishRound limpie el estado
    final round = prov.round;

    final ok = await prov.finishRound();
    if (!context.mounted) return;
    prov.setTab(0);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('⚠️ Sin conexión. La ronda se guardó localmente y se sincronizará cuando haya conexión.'),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 5),
      ));
    }

    // Mostrar diálogo de ajuste de sliding
    if (round != null && context.mounted) {
      await showSlidingAdjustmentDialog(context, round);
    }
  }
}

class _NavBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool primary;
  final GolfTheme t;
  final VoidCallback? onTap;
  const _NavBtn({required this.label, required this.enabled, required this.t,
      this.primary = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: !enabled
              ? t.surface.withValues(alpha: 0.5)
              : primary ? t.primary : t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: !enabled ? t.divider.withValues(alpha: 0.4) : primary ? t.primary : t.divider,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: !enabled ? t.sub.withValues(alpha: 0.4) : primary ? t.onPrimary : t.text,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
