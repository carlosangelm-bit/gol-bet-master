// ─────────────────────────────────────────────────────────────────────────────
// CAPTURE SCREEN — Pantalla principal de registro de scores
// Estructura:
//   1. Selector de hoyos (horizontal scroll, top)
//   2. Info del hoyo actual (par, SI, badge par3/oyes)
//   3. Lista de jugadores con:
//      - Botones rápidos: Birdie / Par / Bogey / Doble / +3 / -
//      - Entrada manual (+/-)
//      - Putts (contador lateral)
//      - Chips de Units con valor configurable
//   4. Ranking de Oyes (solo en par 3) — al fondo
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../widgets/common_widgets.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  int _currentHole = 1;
  final ScrollController _holeScroll = ScrollController();

  // ── Helpers de segmento según startingNine ─────────────────────────────────
  // Devuelve los hoyos del primer segmento (el que se juega primero)
  List<int> _firstSegment(StartingNine sn) =>
      sn == StartingNine.back ? List.generate(9, (i) => i + 10) : List.generate(9, (i) => i + 1);

  // Devuelve los hoyos del segundo segmento
  List<int> _secondSegment(StartingNine sn) =>
      sn == StartingNine.back ? List.generate(9, (i) => i + 1) : List.generate(9, (i) => i + 10);

  // Último hoyo del primer segmento
  int _lastOfFirst(StartingNine sn)  => sn == StartingNine.back ? 18 : 9;
  // Primer hoyo del segundo segmento
  int _firstOfSecond(StartingNine sn) => sn == StartingNine.back ? 1 : 10;

  /// Devuelve true si el hoyo actual pertenece al segundo segmento.
  /// Usado para mostrar los 18 hoyos en el selector cuando la ronda
  /// de 9 se extendió voluntariamente al segundo nine.
  bool _isInSecondSegment(Round round) {
    final sn = round.startingNine;
    if (sn == StartingNine.front) return _currentHole >= 10;
    return _currentHole <= 9;
  }

  @override
  void initState() {
    super.initState();
    // Auto-ir al primer hoyo sin completar, respetando startingNine
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov  = context.read<RoundProvider>();
      if (!prov.hasRound) return;
      final round = prov.round!;
      final sn    = round.startingNine;
      // Recorrer primero el primer segmento, luego el segundo
      final order = [..._firstSegment(sn), ..._secondSegment(sn)];
      for (final h in order) {
        if (!round.players.every((p) => round.getScore(p.id, h).hasScore)) {
          _jumpToHole(h);
          break;
        }
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
    // Scroll al hoyo seleccionado (cada item ~44px)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_holeScroll.hasClients) {
        _holeScroll.animateTo(
          (h - 1) * 44.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
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
    final ch    = round.course.holes.firstWhere((h) => h.hole == _currentHole);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ────────────────────────────────────────────────────
          _CaptureHeader(round: round, t: t),

          // ── Selector de hoyos ─────────────────────────────────────────
          _HoleSelector(
            round: round,
            currentHole: _currentHole,
            scrollCtrl: _holeScroll,
            t: t,
            onSelect: _jumpToHole,
            showAll: _isInSecondSegment(round),
          ),

          // ── Info del hoyo ─────────────────────────────────────────────
          _HoleInfoBar(ch: ch, t: t),

          // ── Contenido principal ───────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(children: [
                // Jugadores
                ...round.players.map((p) => _PlayerScoreCard(
                  key: ValueKey('${p.id}_$_currentHole'),
                  player: p,
                  hole: _currentHole,
                  ch: ch,
                  t: t,
                )),

                // Ranking Oyes (solo par 3)
                if (ch.isPar3) ...[
                  const SizedBox(height: 8),
                  _OyesRankingSection(hole: _currentHole, t: t),
                ],

                const SizedBox(height: 8),
                // Navegación prev/next — respeta startingNine y segmentos
                Builder(builder: (_) {
                  final sn          = round.startingNine;
                  final is9Holes    = round.totalHoles == 9;
                  final firstSeg    = _firstSegment(sn);
                  final secondSeg   = _secondSegment(sn);
                  final lastFirst   = _lastOfFirst(sn);
                  final firstSecond = _firstOfSecond(sn);
                  // En ronda de 9: el orden activo es solo el primer segmento
                  // En ronda de 18: orden completo
                  final activeOrder = is9Holes ? firstSeg : [...firstSeg, ...secondSeg];
                  final allOrder    = [...firstSeg, ...secondSeg]; // siempre 18 para continuar
                  final curIdx      = activeOrder.indexOf(_currentHole);
                  // Si estamos en el segundo segmento (ronda extendida), usar allOrder
                  final curIdxFull  = allOrder.indexOf(_currentHole);
                  final inSecond    = secondSeg.contains(_currentHole);
                  final hasPrev     = inSecond
                      ? curIdxFull > 0
                      : curIdx > 0;
                  final hasNext     = inSecond
                      ? curIdxFull < allOrder.length - 1
                      : (!is9Holes && curIdx < activeOrder.length - 1);
                  // ¿Estamos en el último hoyo del primer segmento?
                  final isLastOfFirst = _currentHole == lastFirst && !inSecond;
                  // ¿Estamos en el último hoyo de toda la ronda (18)?
                  final isVeryLast = _currentHole == allOrder.last && inSecond;
                  // ¿Ronda de 9 y estamos en el último hoyo del segmento activo?
                  final isLast9 = is9Holes && _currentHole == firstSeg.last && !inSecond;
                  return _HoleNavButtons(
                    current:    _currentHole,
                    startingNine: sn,
                    is9HoleRound: is9Holes,
                    inSecondSegment: inSecond,
                    prevHole:   hasPrev
                        ? (inSecond ? allOrder[curIdxFull - 1] : activeOrder[curIdx - 1])
                        : null,
                    nextHole:   hasNext
                        ? (inSecond ? allOrder[curIdxFull + 1] : activeOrder[curIdx + 1])
                        : null,
                    isLastOfFirstSegment: isLastOfFirst && !is9Holes,
                    firstOfSecond: firstSecond,
                    isVeryLast: isVeryLast,
                    isLast9: isLast9,
                    t: t,
                    onPrev: hasPrev
                        ? () => _jumpToHole(inSecond
                            ? allOrder[curIdxFull - 1]
                            : activeOrder[curIdx - 1])
                        : null,
                    onNext: hasNext
                        ? () => _jumpToHole(inSecond
                            ? allOrder[curIdxFull + 1]
                            : activeOrder[curIdx + 1])
                        : null,
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

// ── Header de captura ─────────────────────────────────────────────────────────
class _CaptureHeader extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  const _CaptureHeader({required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    final completed = _countCompleted(round);
    // Calcular el total real de hoyos jugados o programados
    // Si la ronda es de 9 pero ya hay scores en hoyos del segundo nine,
    // mostrar el total real jugado (hasta 18).
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
          child: Text('$completed/$effectiveTotal hoyos', style: TextStyle(color: t.primary, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  /// Total efectivo: normalmente totalHoles, pero si el usuario de una ronda
  /// de 9 ya registró scores en el segundo nine, mostrar 18.
  int _effectiveTotal(Round round) {
    if (round.totalHoles == 18) return 18;
    // Ver si hay scores en el segundo segmento
    final secondStart = round.startingNine == StartingNine.back ? 1 : 10;
    final secondEnd   = round.startingNine == StartingNine.back ? 9 : 18;
    final hasSecond   = round.scores.values.any((hmap) =>
        hmap.keys.any((h) => h >= secondStart && h <= secondEnd));
    return hasSecond ? 18 : round.totalHoles;
  }

  int _countCompleted(Round round) {
    final total = _effectiveTotal(round);
    int c = 0;
    for (int h = 1; h <= total; h++) {
      if (round.players.every((p) => round.getScore(p.id, h).hasScore)) c++;
    }
    return c;
  }
}

// ── Selector de hoyos ─────────────────────────────────────────────────────────
class _HoleSelector extends StatelessWidget {
  final Round round;
  final int currentHole;
  final ScrollController scrollCtrl;
  final GolfTheme t;
  final void Function(int) onSelect;
  /// Si true, muestra los 18 hoyos aunque totalHoles sea 9
  /// (el usuario extendió la ronda al segundo nine)
  final bool showAll;
  const _HoleSelector({
    required this.round, required this.currentHole,
    required this.scrollCtrl, required this.t, required this.onSelect,
    this.showAll = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: t.surface,
      child: ListView.builder(
        controller: scrollCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        itemCount: (round.totalHoles == 9 && !showAll)
            ? 9   // solo mostrar los hoyos del primer segmento
            : 18, // mostrar todos los 18 hoyos
        itemBuilder: (_, i) {
          // En ronda de 9 (sin extender), mapear índice al hoyo real del primer segmento
          final h = (round.totalHoles == 9 && !showAll)
              ? (round.startingNine == StartingNine.back ? i + 10 : i + 1)
              : i + 1;
          final isSel   = h == currentHole;
          final allDone = round.players.isNotEmpty &&
              round.players.every((p) => round.getScore(p.id, h).hasScore);
          final isPar3  = round.course.holes.firstWhere((c) => c.hole == h).isPar3;

          return GestureDetector(
            onTap: () => onSelect(h),
            child: Container(
              width: 38,
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
                    fontSize: 12,
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

// ── Info bar del hoyo ─────────────────────────────────────────────────────────
class _HoleInfoBar extends StatelessWidget {
  final CourseHole ch;
  final GolfTheme t;
  const _HoleInfoBar({required this.ch, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: t.bg,
      child: Row(children: [
        // Número de hoyo grande
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Text(
            '${ch.hole}',
            style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w900, fontSize: 20),
          ),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hoyo ${ch.hole}', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 15)),
          Row(children: [
            _chip('Par ${ch.par}', t.primary, t),
            const SizedBox(width: 6),
            _chip('SI ${ch.strokeIndex}', t.sub, t),
            if (ch.isPar3) ...[
              const SizedBox(width: 6),
              _chip('⛳ Oyes', t.accent, t, accent: true),
            ],
          ]),
        ]),
        const Spacer(),
        // Segmento badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ch.hole <= 9 ? t.primary.withValues(alpha: 0.1) : t.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            ch.hole <= 9 ? 'Front 9' : 'Back 9',
            style: TextStyle(
              color: ch.hole <= 9 ? t.primary : t.accent,
              fontSize: 11, fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _chip(String label, Color color, GolfTheme t, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: accent ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Tarjeta de jugador con captura completa ───────────────────────────────────
class _PlayerScoreCard extends StatefulWidget {
  final Player player;
  final int hole;
  final CourseHole ch;
  final GolfTheme t;

  const _PlayerScoreCard({
    super.key,
    required this.player,
    required this.hole,
    required this.ch,
    required this.t,
  });

  @override
  State<_PlayerScoreCard> createState() => _PlayerScoreCardState();
}

class _PlayerScoreCardState extends State<_PlayerScoreCard> {
  bool _showManual = false;

  @override
  Widget build(BuildContext context) {
    final prov   = context.watch<RoundProvider>();
    final score  = prov.round!.getScore(widget.player.id, widget.hole);
    final gross  = score.grossScore ?? 0;
    final putts  = score.putts;
    final t      = widget.t;
    final ch     = widget.ch;
    final par    = ch.par;

    // Score relativo al par
    String? relLabel;
    Color? relColor;
    if (score.hasScore) {
      final rel = gross - par;
      if (rel <= -2)     { relLabel = rel == -2 ? 'Eagle' : 'Albatross'; relColor = t.scoreUnder; }
      else if (rel == -1) { relLabel = 'Birdie'; relColor = t.scoreUnder; }
      else if (rel == 0)  { relLabel = 'Par';    relColor = t.sub; }
      else if (rel == 1)  { relLabel = 'Bogey';  relColor = t.scoreOver; }
      else                { relLabel = '+$rel';  relColor = t.scoreOver; }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: score.hasScore ? t.primary.withValues(alpha: 0.25) : t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Fila: avatar + nombre + score actual + putts ─────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            GAvatar(name: widget.player.name, colorIndex: widget.player.colorIndex, size: 34),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.player.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
              Text('HCP ${widget.player.handicapBase.toStringAsFixed(0)}', style: TextStyle(color: t.sub, fontSize: 11)),
            ])),
            // Score display grande
            if (score.hasScore) ...[
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                ScoreCell(score: gross, par: par, size: 38),
                if (relLabel != null)
                  Text(relLabel, style: TextStyle(color: relColor!, fontSize: 10, fontWeight: FontWeight.w700)),
              ]),
            ] else
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.divider),
                ),
                alignment: Alignment.center,
                child: Text('—', style: TextStyle(color: t.sub, fontWeight: FontWeight.w600)),
              ),
            // Putts siempre visible a la derecha
            const SizedBox(width: 10),
            _PuttsCounter(
              putts: putts,
              t: t,
              onDec: () => prov.updateScore(widget.player.id, widget.hole, score.grossScore, putts > 0 ? putts - 1 : 0),
              onInc: () => prov.updateScore(widget.player.id, widget.hole, score.grossScore, putts + 1),
            ),
          ]),
        ),

        Divider(color: t.divider, height: 1),

        // ── Botones rápidos de score ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: _QuickScoreButtons(
            par: par,
            currentScore: gross,
            hasScore: score.hasScore,
            t: t,
            onSelect: (newScore) {
              prov.updateScore(widget.player.id, widget.hole, newScore, putts == 0 ? 2 : putts);
              setState(() => _showManual = false);
            },
            onClear: () => prov.updateScore(widget.player.id, widget.hole, null, 0),
            onManual: () => setState(() => _showManual = !_showManual),
            showManual: _showManual,
          ),
        ),

        // ── Entrada manual (+/-) ──────────────────────────────────────
        if (_showManual)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: _ManualEntry(
              value: gross,
              par: par,
              t: t,
              onChange: (v) => prov.updateScore(widget.player.id, widget.hole, v, putts == 0 ? 2 : putts),
            ),
          ),

        Divider(color: t.divider, height: 1),

        // ── Units — fila compacta con dropdown ───────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
          child: Row(children: [
            Text('UNITS', style: TextStyle(color: t.sub, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(width: 8),
            Expanded(child: _UnitsSection(
              player: widget.player,
              hole: widget.hole,
              t: t,
            )),
          ]),
        ),
      ]),
    );
  }
}

// ── Contador de putts compacto ─────────────────────────────────────────────────
class _PuttsCounter extends StatelessWidget {
  final int putts;
  final GolfTheme t;
  final VoidCallback onDec;
  final VoidCallback onInc;
  const _PuttsCounter({required this.putts, required this.t, required this.onDec, required this.onInc});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text('PUTTS', style: TextStyle(color: t.sub, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      const SizedBox(height: 3),
      Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.divider),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _btn(Icons.remove, onDec, t),
          SizedBox(
            width: 26,
            child: Text(
              '$putts',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          _btn(Icons.add, onInc, t),
        ]),
      ),
    ]);
  }

  Widget _btn(IconData ic, VoidCallback fn, GolfTheme t) => GestureDetector(
    onTap: fn,
    child: Container(
      width: 26, height: 26,
      alignment: Alignment.center,
      child: Icon(ic, size: 13, color: t.sub),
    ),
  );
}

// ── Botones rápidos de score ──────────────────────────────────────────────────
class _QuickScoreButtons extends StatelessWidget {
  final int par;
  final int currentScore;
  final bool hasScore;
  final GolfTheme t;
  final void Function(int) onSelect;
  final VoidCallback onClear;
  final VoidCallback onManual;
  final bool showManual;

  const _QuickScoreButtons({
    required this.par,
    required this.currentScore,
    required this.hasScore,
    required this.t,
    required this.onSelect,
    required this.onClear,
    required this.onManual,
    required this.showManual,
  });

  @override
  Widget build(BuildContext context) {
    // Scores rápidos: Eagle(-2), Birdie(-1), Par(0), Bogey(+1), Doble(+2), Triple(+3)
    final options = [
      (par - 2, 'Eagle', t.scoreUnder),
      (par - 1, 'Birdie', t.scoreUnder),
      (par,     'Par',    t.sub),
      (par + 1, 'Bogey',  t.scoreOver),
      (par + 2, 'Doble',  t.scoreOver),
      (par + 3, '+3',     t.scoreOver),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Etiqueta
      Row(children: [
        Text('SCORE', style: TextStyle(color: t.sub, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const Spacer(),
        if (hasScore)
          GestureDetector(
            onTap: onClear,
            child: Text('Borrar', style: TextStyle(color: t.loss.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w600)),
          ),
      ]),
      const SizedBox(height: 5),
      // Fila de botones
      Row(children: [
        ...options.map((o) {
          final score = o.$1;
          final label = o.$2;
          final color = o.$3;
          final isSel = hasScore && currentScore == score;

          if (score < 1) return const SizedBox.shrink(); // Eagle no disponible si par ≤ 2

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () => onSelect(score),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel ? color : t.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel ? color : t.divider,
                      width: isSel ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      '$score',
                      style: TextStyle(
                        color: isSel ? Colors.white : t.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: isSel ? Colors.white.withValues(alpha: 0.85) : color,
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          );
        }),
        // Botón manual
        GestureDetector(
          onTap: onManual,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: showManual ? t.primary.withValues(alpha: 0.15) : t.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: showManual ? t.primary : t.divider),
            ),
            child: Icon(Icons.edit_outlined, size: 16, color: showManual ? t.primary : t.sub),
          ),
        ),
      ]),
    ]);
  }
}

// ── Entrada manual con teclado ────────────────────────────────────────────────
class _ManualEntry extends StatefulWidget {
  final int value;
  final int par;
  final GolfTheme t;
  final void Function(int) onChange;
  const _ManualEntry({required this.value, required this.par, required this.t, required this.onChange});

  @override
  State<_ManualEntry> createState() => _ManualEntryState();
}

class _ManualEntryState extends State<_ManualEntry> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value > 0 ? '${widget.value}' : '');
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Row(children: [
      Text('Manual:', style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      // +/- counter
      GCounter(
        value: widget.value,
        onDec: () => widget.onChange(widget.value > 1 ? widget.value - 1 : 1),
        onInc: () => widget.onChange(widget.value + 1),
      ),
      const SizedBox(width: 8),
      // O campo de texto directo
      Expanded(
        child: TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'Score',
            hintStyle: TextStyle(color: t.sub, fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true, fillColor: t.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.primary, width: 2)),
            isDense: true,
          ),
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null && n > 0) widget.onChange(n);
          },
        ),
      ),
    ]);
  }
}

// ── Sección de Units — dropdown compacto ─────────────────────────────────────
// Una sola fila por tarjeta: botón "Units" que abre un bottom sheet
// con lista de eventos. Cada evento tiene checkbox + selector de valor.
class _UnitsSection extends StatefulWidget {
  final Player player;
  final int hole;
  final GolfTheme t;
  const _UnitsSection({required this.player, required this.hole, required this.t});
  @override
  State<_UnitsSection> createState() => _UnitsSectionState();
}

class _UnitsSectionState extends State<_UnitsSection> {
  static const _quickValues = [10.0, 25.0, 50.0, 100.0];
  // Valor asociado a cada unit (persiste aunque se desactive)
  final Map<UnitEventType, double> _values = {
    for (final e in UnitEventType.values) e: 25.0,
  };

  @override
  Widget build(BuildContext context) {
    final prov   = context.watch<RoundProvider>();
    final t      = widget.t;
    final active = UnitEventType.values
        .where((e) => prov.hasEvent(widget.player.id, widget.hole, e))
        .toList();

    return Row(children: [
      // Etiqueta + resumen de activos
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
      // Botón para abrir el panel
      GestureDetector(
        onTap: () => _openUnitsSheet(context, prov),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active.isNotEmpty ? t.accent.withValues(alpha: 0.12) : t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active.isNotEmpty ? t.accent.withValues(alpha: 0.5) : t.divider,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_circle_outline,
                size: 14, color: active.isNotEmpty ? t.accent : t.sub),
            const SizedBox(width: 4),
            Text(
              active.isEmpty ? 'Units' : '${active.length} unit${active.length > 1 ? 's' : ''}',
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

  // ── Bottom sheet con la lista completa de units ───────────────────────────
  void _openUnitsSheet(BuildContext outerCtx, RoundProvider outerProv) {
    final t          = widget.t;
    final playerId   = widget.player.id;
    final playerName = widget.player.name;
    final hole       = widget.hole;

    showModalBottomSheet(
      context: outerCtx,
      backgroundColor: t.card,
      isScrollControlled: true,
      // ⚠️ useRootNavigator: false — mantiene el sheet DENTRO del árbol
      // del Provider para que context.watch/read funcionen correctamente
      // ignore: avoid_bool_literals_in_conditional_expressions
      useRootNavigator: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Re-inyectamos el provider en el árbol del sheet con .value
      builder: (sheetCtx) => ChangeNotifierProvider<RoundProvider>.value(
        value: outerProv,
        child: _UnitsSheetContent(
          playerId:    playerId,
          playerName:  playerName,
          hole:        hole,
          t:           t,
          values:      _values,
          quickValues: _quickValues,
          onValueChange: (evt, v) => setState(() => _values[evt] = v),
        ),
      ),
    );
  }
}

// ── Fila individual de unit en el bottom sheet ────────────────────────────────
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
    required this.evt,
    required this.isActive,
    required this.selVal,
    required this.isCustom,
    required this.quickValues,
    required this.t,
    required this.onToggle,
    required this.onValueChange,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? t.accent.withValues(alpha: 0.07) : t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? t.accent.withValues(alpha: 0.4) : t.divider,
        ),
      ),
      child: Column(children: [
        // ── Fila principal: checkbox + nombre + valor seleccionado ────
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              // Checkbox visual
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
                child: isActive
                    ? Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              // Nombre del unit
              Expanded(
                child: Text(
                  evt.label,
                  style: TextStyle(
                    color: isActive ? t.text : t.sub,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 14,
                  ),
                ),
              ),
              // Valor actual (solo cuando activo)
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '\$${selVal.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: t.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
            ]),
          ),
        ),

        // ── Selector de valor (solo cuando activo) ────────────────────
        if (isActive) ...[
          Divider(color: t.divider.withValues(alpha: 0.6), height: 1, indent: 12, endIndent: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(children: [
              Text('Valor:', style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: Row(children: [
                  // Chips de valores rápidos
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
                            border: Border.all(
                              color: isSel ? t.primary : t.divider,
                              width: isSel ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            '\$${v.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: isSel ? t.onPrimary : t.text,
                              fontSize: 12,
                              fontWeight: isSel ? FontWeight.w800 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  // Custom
                  GestureDetector(
                    onTap: () => _showCustomDialog(context),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: isCustom ? t.primary : t.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCustom ? t.primary : t.divider,
                          width: isCustom ? 2 : 1,
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.edit_outlined,
                            size: 11,
                            color: isCustom ? t.onPrimary : t.sub),
                        const SizedBox(width: 3),
                        Text(
                          isCustom ? '\$${selVal.toStringAsFixed(0)}' : 'Otro',
                          style: TextStyle(
                            color: isCustom ? t.onPrimary : t.sub,
                            fontSize: 12,
                            fontWeight: isCustom ? FontWeight.w800 : FontWeight.w400,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  void _showCustomDialog(BuildContext context) {
    final ctrl = TextEditingController(
        text: isCustom ? selVal.toStringAsFixed(0) : '');
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
            hintText: 'Ej: 200',
            prefixText: '\$ ',
            fillColor: t.surface, filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.primary, width: 2)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: TextStyle(color: t.sub))),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null && v > 0) {
                onValueChange(v);
                Navigator.pop(ctx);
              }
            },
            child: Text('OK', style: TextStyle(color: t.primary, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ── Sección ranking de Oyes (par 3) ──────────────────────────────────────────
class _OyesRankingSection extends StatelessWidget {
  final int hole;
  final GolfTheme t;
  const _OyesRankingSection({required this.hole, required this.t});

  @override
  Widget build(BuildContext context) {
    final prov    = context.watch<RoundProvider>();
    final round   = prov.round!;
    final ranking = round.getOyese(hole);
    final ranked  = ranking?.ranking ?? [];
    final unranked = round.players.map((p) => p.id).where((id) => !ranked.contains(id)).toList();

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
            decoration: BoxDecoration(color: t.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events, color: t.accent, size: 13),
              const SizedBox(width: 4),
              Text('RANKING OYES — Hoyo $hole', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
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

        // Jugadores rankeados (ordenados)
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

        // Jugadores sin rankear
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: t.primary.withValues(alpha: 0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  GAvatar(name: p.name, colorIndex: p.colorIndex, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    '${p.name.split(' ').first}  +${ranked.length + 1}°',
                    style: TextStyle(color: t.primary, fontWeight: FontWeight.w700, fontSize: 12),
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
    // Colores por posición
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
        // Medalla de posición
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: posColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: posColor.withValues(alpha: 0.5)),
          ),
          alignment: Alignment.center,
          child: Text(
            '$position°',
            style: TextStyle(color: posColor, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        GAvatar(name: player.name, colorIndex: player.colorIndex, size: 26),
        const SizedBox(width: 8),
        Expanded(child: Text(player.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13))),
        GestureDetector(
          onTap: onRemove,
          child: Icon(Icons.close, color: t.sub, size: 16),
        ),
      ]),
    );
  }
}

// ── Bottom sheet de Units — widget propio con acceso al provider ──────────────
// Tiene su propio State para leer el provider fresco en cada rebuild.
class _UnitsSheetContent extends StatefulWidget {
  final String playerId;
  final String playerName;
  final int hole;
  final GolfTheme t;
  final Map<UnitEventType, double> values;
  final List<double> quickValues;
  final void Function(UnitEventType, double) onValueChange;

  const _UnitsSheetContent({
    required this.playerId,
    required this.playerName,
    required this.hole,
    required this.t,
    required this.values,
    required this.quickValues,
    required this.onValueChange,
  });

  @override
  State<_UnitsSheetContent> createState() => _UnitsSheetContentState();
}

class _UnitsSheetContentState extends State<_UnitsSheetContent> {
  // Copia local de los valores para poder redibujar sin depender del padre
  late final Map<UnitEventType, double> _localValues;

  @override
  void initState() {
    super.initState();
    _localValues = Map<UnitEventType, double>.from(widget.values);
  }

  @override
  Widget build(BuildContext context) {
    // Lee el provider FRESCO desde el contexto del sheet — sin stale reference
    final prov = context.watch<RoundProvider>();
    final t = widget.t;

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
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: t.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Título
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                Icon(Icons.star_rounded, color: t.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Units — ${widget.playerName.split(' ').first}  •  Hoyo ${widget.hole}',
                  style: TextStyle(
                    color: t.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Icon(Icons.close, color: t.sub, size: 20),
                ),
              ]),
            ),
            Divider(color: t.divider, height: 1),
            // Lista de units
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: UnitEventType.values.length,
                itemBuilder: (_, i) {
                  final evt = UnitEventType.values[i];
                  final isActive = prov.hasEvent(widget.playerId, widget.hole, evt);
                  final selVal = _localValues[evt] ?? 25.0;
                  final isCustom = !widget.quickValues.contains(selVal);

                  return _UnitRow(
                    evt: evt,
                    isActive: isActive,
                    selVal: selVal,
                    isCustom: isCustom,
                    quickValues: widget.quickValues,
                    t: t,
                    onToggle: () {
                      // Usa context.read para la acción — no necesita escuchar
                      context.read<RoundProvider>().toggleEvent(
                        widget.playerId,
                        widget.hole,
                        evt,
                      );
                      // Fuerza rebuild del sheet para reflejar el cambio
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
            // Botón cerrar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: GPrimaryButton(
                label: 'Listo',
                onTap: () => Navigator.pop(ctx),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ── Botones de navegación prev/next hoyo ─────────────────────────────────────
class _HoleNavButtons extends StatelessWidget {
  final int current;
  final GolfTheme t;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onContinueTo18; // solo para rondas de 9: ir al seg 2
  final int? prevHole;
  final int? nextHole;
  final bool isLastOfFirstSegment; // fin del seg 1 en ronda de 18
  final bool isVeryLast;           // fin del seg 2 (hoyo 18)
  final bool isLast9;              // fin del seg 1 en ronda de 9 hoyos
  final bool is9HoleRound;
  final bool inSecondSegment;
  final int firstOfSecond;
  final StartingNine startingNine;

  const _HoleNavButtons({
    required this.current,
    required this.t,
    required this.startingNine,
    required this.firstOfSecond,
    this.onPrev,
    this.onNext,
    this.onContinueTo18,
    this.prevHole,
    this.nextHole,
    this.isLastOfFirstSegment = false,
    this.isVeryLast = false,
    this.isLast9 = false,
    this.is9HoleRound = false,
    this.inSecondSegment = false,
  });

  @override
  Widget build(BuildContext context) {
    final prevLabel = prevHole != null ? '← Hoyo $prevHole' : '←';

    // Caso: ronda de 9 hoyos en el último hoyo del segmento activo
    // → Mostrar fila especial: [← Anterior] [✓ Terminar] [→ Continuar 18]
    if (isLast9) {
      return Column(children: [
        Row(children: [
          Expanded(child: _NavBtn(
            label: prevLabel,
            enabled: onPrev != null,
            t: t,
            onTap: onPrev,
          )),
          const SizedBox(width: 8),
          Expanded(child: _NavBtn(
            label: '✓ Terminar',
            enabled: true,
            t: t,
            primary: true,
            onTap: () => _finishRound(context),
          )),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: _NavBtn(
            label: '⛳ Continuar ${startingNine == StartingNine.back ? "Front 9" : "Back 9"} →',
            enabled: true,
            t: t,
            primary: false,
            onTap: onContinueTo18,
          ),
        ),
      ]);
    }

    // Caso normal: siguiente / segmento / terminar 18
    final String nextLabel;
    if (isVeryLast) {
      nextLabel = '✓ Terminar';
    } else if (isLastOfFirstSegment) {
      final segName = startingNine == StartingNine.back ? 'Front 9 →' : 'Back 9 →';
      nextLabel = '⛳ $segName';
    } else {
      nextLabel = nextHole != null ? 'Hoyo $nextHole →' : '→';
    }

    final nextEnabled = onNext != null || isVeryLast;

    return Row(children: [
      Expanded(child: _NavBtn(
        label: prevLabel,
        enabled: onPrev != null,
        t: t,
        onTap: onPrev,
      )),
      const SizedBox(width: 8),
      Expanded(child: _NavBtn(
        label: nextLabel,
        enabled: nextEnabled,
        t: t,
        primary: true,
        onTap: onNext ?? (isVeryLast ? () => _finishRound(context) : null),
      )),
    ]);
  }

  Future<void> _finishRound(BuildContext context) async {
    final prov = context.read<RoundProvider>();
    final t    = prov.theme;
    // Mostrar diálogo de confirmación (igual que en home_screen y results_screen)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Text('Finalizar ronda',
            style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        content: Text(
          'Los resultados se guardarán en el historial y la ronda quedará cerrada.',
          style: TextStyle(color: t.sub),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: TextStyle(color: t.sub))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Finalizar',
                  style: TextStyle(
                      color: t.primary, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final ok = await prov.finishRound();
    if (!context.mounted) return;

    // Siempre navegar a Inicio (tab 0) — la ronda ya terminó.
    // Si ok==false, la ronda quedó encolada localmente y se sincronizará luego.
    prov.setTab(0);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
            '⚠️ Sin conexión a Firestore. La ronda se guardó localmente y se sincronizará automáticamente cuando haya conexión.'),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 5),
      ));
    }
  }
}

class _NavBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool primary;
  final GolfTheme t;
  final VoidCallback? onTap;
  const _NavBtn({required this.label, required this.enabled, required this.t, this.primary = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: !enabled
              ? t.surface.withValues(alpha: 0.5)
              : primary
                  ? t.primary
                  : t.surface,
          borderRadius: BorderRadius.circular(10),
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
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
