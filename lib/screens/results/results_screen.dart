// ─────────────────────────────────────────────────────────────────────────────
// RESULTS SCREEN — Liquidación financiera centrada en jugadores (no en apuestas)
// Nivel 1: balance por jugador  (podio PGA premium — respeta modo claro/oscuro/clásico)
// Nivel 2: cara a cara          (pagos cinematográficos)
// Nivel 3: detalle expandible   (breakdown por tipo de apuesta)
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../engines/ledger_engine.dart';
import '../../engines/bet_engine.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/sliding_adjustment_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: paleta de gradientes adaptada a cada GolfTheme
// ─────────────────────────────────────────────────────────────────────────────
class _ThemeGrad {
  final GolfTheme t;
  const _ThemeGrad(this.t);

  bool get isLight => t.brightness == Brightness.light;

  // Color base de fondo del scaffold
  Color get scaffoldBg => t.bg;

  // Gradiente del header (dos colores)
  List<Color> get header => isLight
      ? [t.primary.withValues(alpha: 0.10), t.bg]
      : [t.primary.withValues(alpha: 0.22), t.bg];

  Color get headerBorder => t.divider;

  // Gradiente tarjeta hero ganador — positivo
  List<Color> get winnerHeroPos => isLight
      ? [t.profit.withValues(alpha: 0.08), t.card]
      : [t.profit.withValues(alpha: 0.18), t.surface];

  // Gradiente tarjeta hero ganador — negativo
  List<Color> get winnerHeroNeg => isLight
      ? [t.loss.withValues(alpha: 0.06), t.card]
      : [t.loss.withValues(alpha: 0.16), t.surface];

  // Color borde ganador pos/neg
  Color winnerBorderPos(bool pos) => pos
      ? t.profit.withValues(alpha: isLight ? 0.30 : 0.35)
      : t.loss.withValues(alpha: isLight ? 0.25 : 0.30);

  // Color sombra ganador
  Color winnerShadowPos(bool pos) => pos
      ? t.profit.withValues(alpha: isLight ? 0.08 : 0.14)
      : t.loss.withValues(alpha: isLight ? 0.06 : 0.12);

  // Fondo filas de ranking
  Color get rankingRowBg => t.card;
  Color get rankingRowBorder => t.divider;

  // Gradiente tarjeta de pago
  List<Color> get paymentCard => isLight
      ? [t.loss.withValues(alpha: 0.05), t.card]
      : [t.loss.withValues(alpha: 0.12), t.surface];

  Color get paymentBorder => t.loss.withValues(alpha: isLight ? 0.20 : 0.25);

  // Fondo monto del pago
  List<Color> get paymentAmount => isLight
      ? [t.loss.withValues(alpha: 0.10), t.card]
      : [t.loss.withValues(alpha: 0.20), t.surface];

  // Fondo sección de detalle por jugador
  Color get detailCardBg => t.card;
  Color detailCardBorder(bool expanded) => expanded
      ? t.accent.withValues(alpha: isLight ? 0.40 : 0.35)
      : t.divider;

  // Fondo tarjeta duelo cara a cara
  Color get duelCardBg => t.surface;

  // Etiqueta dorada de sección (dorado en dark/classic, verde primario en light)
  Color get sectionLabelColor => isLight ? t.primary : t.accent;

  // Icono trofeo header
  List<Color> get trophyGrad => isLight
      ? [t.primary, t.primary.withValues(alpha: 0.70)]
      : [t.accent, t.primary];

  // Botón cerrar ronda
  List<Color> get closeRoundGrad => isLight
      ? [t.primary, t.primary.withValues(alpha: 0.80)]
      : [t.profit.withValues(alpha: 0.90), t.profit.withValues(alpha: 0.60)];

  Color get closeRoundBorder => t.profit.withValues(alpha: 0.40);
  Color get closeRoundText   => isLight ? t.onPrimary : t.bg;

  // Medalla #1 (dorado siempre, pero más suave en light)
  List<Color> get medal1 => isLight
      ? [const Color(0xFFF9A825), const Color(0xFFE65100)]
      : [const Color(0xFFF9A825), const Color(0xFFFF8F00)];

  Color get medal1Shadow => const Color(0xFFF9A825).withValues(alpha: isLight ? 0.25 : 0.40);

  // Texto del monto grande
  Color amountColor(bool isPos) => isPos ? t.profit : t.loss;

  // Colores semáforo para chips de balance en duelo
  Color chipBg(double bal) {
    if (bal == 0) return t.scoreUnder.withValues(alpha: 0.12);
    return (bal > 0 ? t.profit : t.loss).withValues(alpha: 0.12);
  }

  Color chipBorder(double bal) {
    if (bal == 0) return t.scoreUnder.withValues(alpha: 0.40);
    return (bal > 0 ? t.profit : t.loss).withValues(alpha: 0.40);
  }

  Color chipText(double bal) {
    if (bal == 0) return t.scoreUnder;
    return bal > 0 ? t.profit : t.loss;
  }

  // Fondo diagnóstico
  Color get diagBg  => Colors.orange.withValues(alpha: isLight ? 0.06 : 0.09);
  Color get diagBorder => Colors.orange.withValues(alpha: isLight ? 0.20 : 0.28);

  // Chip de unidades
  Color get unitChipBg     => t.accent.withValues(alpha: 0.10);
  Color get unitChipBorder => t.accent.withValues(alpha: 0.28);
  Color get unitAccent     => t.accent;
}

// ─────────────────────────────────────────────────────────────────────────────
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});
  @override State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  String? _expandedPlayerId;

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final t    = prov.theme;
    GolfThemeExt.setCurrent(t);

    if (!prov.hasRound) {
      return Scaffold(backgroundColor: t.bg, body: Center(
        child: Text('No hay ronda activa', style: TextStyle(color: t.sub)),
      ));
    }

    final round    = prov.round!;
    final balances = prov.balances;
    final netDebts = prov.netDebts;

    final sortedPlayers = round.players.toList()
      ..sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));

    final g = _ThemeGrad(t);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          _PGAHeader(round: round, t: t, g: g, prov: prov, onFinish: _confirmFinish),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // NIVEL 1: Podio PGA
                  _PGAPodium(players: sortedPlayers, balances: balances, t: t, g: g),
                  const SizedBox(height: 24),

                  // NIVEL 2: Pagos directos
                  if (netDebts.isNotEmpty) ...[
                    _PGASectionLabel(label: 'TRANSFERENCIAS', icon: Icons.currency_exchange_rounded, g: g),
                    const SizedBox(height: 10),
                    ...netDebts.map((d) => _PGAPaymentCard(debt: d, round: round, t: t, g: g)),
                    const SizedBox(height: 24),
                  ],

                  // NIVEL 3: Detalle cara a cara
                  _PGASectionLabel(label: 'DETALLE POR JUGADOR', icon: Icons.analytics_outlined, g: g),
                  const SizedBox(height: 10),
                  ...sortedPlayers.map((p) => _PlayerDetailSection(
                    player: p, round: round, t: t, g: g,
                    isExpanded: _expandedPlayerId == p.id,
                    onToggle: () => setState(() =>
                      _expandedPlayerId = _expandedPlayerId == p.id ? null : p.id),
                  )),

                  // Diagnóstico Medal
                  if (round.betGroups.any((gr) => gr.modules.any((m) => m.type == BetModuleType.medal))) ...[
                    const SizedBox(height: 20),
                    _MedalDiagPanel(round: round, t: t, g: g),
                  ],

                  // Diagnóstico scores
                  const SizedBox(height: 16),
                  _ScoresDiagPanel(round: round, balances: balances, t: t, g: g),

                  // Sliding
                  if (round.sliding.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _PGASectionLabel(label: 'SLIDING', icon: Icons.swap_horiz_rounded, g: g),
                    const SizedBox(height: 10),
                    SlidingSummaryCard(round: round, t: t),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _confirmFinish(BuildContext context, Round round, RoundProvider prov, GolfTheme t) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Finalizar ronda', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
      content: Text(
        'Los resultados se guardarán en el historial y la ronda quedará cerrada.',
        style: TextStyle(color: t.sub),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('Cancelar', style: TextStyle(color: t.sub))),
        TextButton(onPressed: () async {
          Navigator.pop(ctx);
          final roundSnapshot = prov.round;
          final ok = await prov.finishRound();
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('⚠️ Sin conexión. La ronda se guardó localmente y se sincronizará pronto.'),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 5),
            ));
          }
          if (roundSnapshot != null && context.mounted) {
            await showSlidingAdjustmentDialog(context, roundSnapshot);
          }
        }, child: Text('Finalizar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700))),
      ],
    ));
  }
}

// ── Header PGA adaptado al tema ───────────────────────────────────────────────
class _PGAHeader extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  final RoundProvider prov;
  final void Function(BuildContext, Round, RoundProvider, GolfTheme) onFinish;
  const _PGAHeader({required this.round, required this.t, required this.g,
      required this.prov, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: g.header,
        ),
        border: Border(bottom: BorderSide(color: g.headerBorder, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(children: [
        // Ícono trofeo
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: g.trophyGrad,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(
              color: g.trophyGrad.first.withValues(alpha: 0.30),
              blurRadius: 8, offset: const Offset(0, 2),
            )],
          ),
          child: Icon(Icons.emoji_events_rounded, color: t.onPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('RESULTADOS FINALES',
            style: TextStyle(
              color: t.text, fontWeight: FontWeight.w900,
              fontSize: 13, letterSpacing: 1.5,
            )),
          Text(round.name,
            style: TextStyle(color: t.sub, fontSize: 11),
            overflow: TextOverflow.ellipsis),
        ])),
        // Botón cerrar ronda
        GestureDetector(
          onTap: () => onFinish(context, round, prov, t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: g.closeRoundGrad),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: g.closeRoundBorder),
              boxShadow: [BoxShadow(
                color: t.profit.withValues(alpha: 0.18),
                blurRadius: 8,
              )],
            ),
            child: Text('Cerrar ronda',
              style: TextStyle(color: g.closeRoundText, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ),
      ]),
    );
  }
}

// ── Label de sección estilo PGA adaptado al tema ──────────────────────────────
class _PGASectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final _ThemeGrad g;
  const _PGASectionLabel({required this.label, required this.icon, required this.g});

  @override
  Widget build(BuildContext context) {
    final color = g.sectionLabelColor;
    return Row(children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.0,
      )),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.22))),
    ]);
  }
}

// ── Podio PGA adaptado al tema ────────────────────────────────────────────────
class _PGAPodium extends StatelessWidget {
  final List<Player> players;
  final Map<String, double> balances;
  final GolfTheme t;
  final _ThemeGrad g;
  const _PGAPodium({required this.players, required this.balances, required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (players.isNotEmpty)
        _WinnerHeroCard(player: players[0], balance: balances[players[0].id] ?? 0, t: t, g: g),
      if (players.length > 1) const SizedBox(height: 8),
      ...players.skip(1).toList().asMap().entries.map((e) {
        final rank = e.key + 2;
        final p    = e.value;
        final bal  = balances[p.id] ?? 0.0;
        return _RankingRow(rank: rank, player: p, balance: bal, t: t, g: g);
      }),
    ]);
  }
}

// Tarjeta hero ganador (#1)
class _WinnerHeroCard extends StatelessWidget {
  final Player player;
  final double balance;
  final GolfTheme t;
  final _ThemeGrad g;
  const _WinnerHeroCard({required this.player, required this.balance, required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final isPos = balance >= 0;
    final heroGrad = isPos ? g.winnerHeroPos : g.winnerHeroNeg;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: heroGrad,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: g.winnerBorderPos(isPos), width: 1.5),
        boxShadow: [BoxShadow(
          color: g.winnerShadowPos(isPos),
          blurRadius: 20,
          spreadRadius: 2,
        )],
      ),
      child: Row(children: [
        // Medalla #1
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: g.medal1,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: g.medal1Shadow, blurRadius: 10)],
          ),
          child: Center(
            child: Text('1', style: TextStyle(
              color: t.brightness == Brightness.light ? Colors.white : Colors.white,
              fontWeight: FontWeight.w900, fontSize: 18,
            )),
          ),
        ),
        const SizedBox(width: 14),
        GAvatar(name: player.name, colorIndex: player.colorIndex, size: 52),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(player.name,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 2),
          Text('HCP ${player.handicapBase.toStringAsFixed(0)}',
            style: TextStyle(color: t.sub, fontSize: 11)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: g.chipBg(isPos ? 1 : -1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: g.chipBorder(isPos ? 1 : -1)),
            ),
            child: Text(
              isPos ? 'LÍDER  ·  COBRA' : 'PAGA',
              style: TextStyle(
                color: isPos ? t.profit : t.loss,
                fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.0,
              ),
            ),
          ),
        ])),
        // Balance grande
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '\$${balance.abs().toStringAsFixed(0)}',
            style: TextStyle(
              color: g.amountColor(isPos),
              fontWeight: FontWeight.w900,
              fontSize: 28,
            ),
          ),
          Text('MXN', style: TextStyle(color: t.sub, fontSize: 10, letterSpacing: 0.5)),
        ]),
      ]),
    );
  }
}

// Fila de ranking compacta (#2 en adelante)
class _RankingRow extends StatelessWidget {
  final int rank;
  final Player player;
  final double balance;
  final GolfTheme t;
  final _ThemeGrad g;
  const _RankingRow({required this.rank, required this.player, required this.balance,
      required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final isPos = balance >= 0;
    // Gradientes de medalla: plata y bronce siempre igual de saturados según tema
    final isLight = t.brightness == Brightness.light;
    final medal2 = isLight
        ? [const Color(0xFF78909C), const Color(0xFF546E7A)]
        : [const Color(0xFFB0BEC5), const Color(0xFF78909C)];
    final medal3 = isLight
        ? [const Color(0xFF8D6E63), const Color(0xFF6D4C41)]
        : [const Color(0xFFBF9660), const Color(0xFF8D6E3A)];
    final medalN = [const Color(0xFF757575), const Color(0xFF616161)];

    final medGrad = rank == 2 ? medal2 : rank == 3 ? medal3 : medalN;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: g.rankingRowBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: g.rankingRowBorder, width: 1),
        ),
        child: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: medGrad),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text('$rank',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
          ),
          const SizedBox(width: 10),
          GAvatar(name: player.name, colorIndex: player.colorIndex, size: 36),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(player.name,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
            Text('HCP ${player.handicapBase.toStringAsFixed(0)}',
              style: TextStyle(color: t.sub, fontSize: 10)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '\$${balance.abs().toStringAsFixed(0)}',
              style: TextStyle(
                color: g.amountColor(isPos),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            Text(
              isPos ? 'COBRA' : 'PAGA',
              style: TextStyle(
                color: g.amountColor(isPos).withValues(alpha: 0.70),
                fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Tarjeta de pago adaptada al tema ─────────────────────────────────────────
class _PGAPaymentCard extends StatelessWidget {
  final NetDebt debt;
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  const _PGAPaymentCard({required this.debt, required this.round, required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final payer    = round.players.firstWhere((p) => p.id == debt.fromPlayerId);
    final receiver = round.players.firstWhere((p) => p.id == debt.toPlayerId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: g.paymentCard,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: g.paymentBorder),
        ),
        child: Row(children: [
          // Pagador
          Column(children: [
            GAvatar(name: payer.name, colorIndex: payer.colorIndex, size: 38),
            const SizedBox(height: 4),
            Text(payer.name.split(' ').first,
              style: TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w600)),
            Text('PAGA', style: TextStyle(
              color: t.loss, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ]),
          // Flecha + monto
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.arrow_forward_rounded, color: t.loss, size: 18),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: g.paymentAmount),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.loss.withValues(alpha: 0.40)),
              ),
              child: Text('\$${debt.amount.toStringAsFixed(0)}',
                style: TextStyle(
                  color: t.loss,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                )),
            ),
          ])),
          // Cobrador
          Column(children: [
            GAvatar(name: receiver.name, colorIndex: receiver.colorIndex, size: 38),
            const SizedBox(height: 4),
            Text(receiver.name.split(' ').first,
              style: TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w600)),
            Text('COBRA', style: TextStyle(
              color: t.profit, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ]),
        ]),
      ),
    );
  }
}

// ── Nivel 3: Detalle por jugador expandible ───────────────────────────────────
class _PlayerDetailSection extends StatelessWidget {
  final Player player;
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  final bool isExpanded;
  final VoidCallback onToggle;
  const _PlayerDetailSection({
    required this.player, required this.round, required this.t, required this.g,
    required this.isExpanded, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: g.detailCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: g.detailCardBorder(isExpanded)),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  GAvatar(name: player.name, colorIndex: player.colorIndex, size: 34),
                  const SizedBox(width: 12),
                  Expanded(child: Text(player.name,
                    style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14))),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.keyboard_arrow_down, color: t.sub, size: 20),
                  ),
                ]),
              ),
            ),
            if (isExpanded) ...[
              Divider(height: 1, color: t.divider),
              _PlayerFaceToFace(player: player, round: round, t: t, g: g),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Cara a cara ───────────────────────────────────────────────────────────────
class _PlayerFaceToFace extends StatelessWidget {
  final Player player;
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  const _PlayerFaceToFace({required this.player, required this.round, required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final Set<String> bettingOpponentIds = {};
    bool playerHasUnitsModule = false;
    for (final group in round.betGroups) {
      for (final mod in group.modules) {
        final pids = mod.participantIds.isNotEmpty ? mod.participantIds : group.playerIds;
        if (!pids.contains(player.id)) continue;
        for (final pid in pids) {
          if (pid != player.id) bettingOpponentIds.add(pid);
        }
        if (mod.type == BetModuleType.units) playerHasUnitsModule = true;
      }
    }
    final opponents = round.players.where((p) => bettingOpponentIds.contains(p.id)).toList();

    final Map<UnitEventType, List<int>> unitsByType = {};
    if (playerHasUnitsModule) {
      for (int h = 1; h <= 18; h++) {
        for (final evt in round.getEvents(player.id, h)) {
          unitsByType.putIfAbsent(evt.type, () => []).add(h);
        }
      }
    }
    final hasUnits = unitsByType.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...opponents.map((opp) {
            final breakdown = LedgerEngine.breakdownBetween(round, player.id, opp.id);

            for (final gr in round.betGroups) {
              if (!gr.playerIds.contains(player.id) || !gr.playerIds.contains(opp.id)) continue;
              for (final mod in gr.modules) {
                if (mod.type != BetModuleType.matchAutoPress) continue;
                double mpLiveBal = 0.0;
                final presses = BetEngine.matchAutoPressLive(round, player.id, opp.id, mod);
                for (final pr in presses) {
                  if (pr.played == 0) continue;
                  if (pr.leadingPlayerId == player.id) mpLiveBal += pr.value;
                  if (pr.leadingPlayerId == opp.id) mpLiveBal -= pr.value;
                }
                breakdown[BetModuleType.matchAutoPress] = mpLiveBal;
              }
            }

            final balance = breakdown.values.fold<double>(0.0, (s, v) => s + v);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: g.duelCardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: g.chipBorder(balance).withValues(alpha: 0.25)),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    GAvatar(name: opp.name, colorIndex: opp.colorIndex, size: 28),
                    const SizedBox(width: 8),
                    Expanded(child: Text(opp.name,
                      style: TextStyle(color: t.text, fontWeight: FontWeight.w600, fontSize: 13))),
                    // Balance chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: g.chipBg(balance),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: g.chipBorder(balance)),
                      ),
                      child: Text(
                        balance.abs() < 0.005
                            ? 'AS'
                            : '${balance > 0 ? '+' : ''}\$${balance.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: g.chipText(balance),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ]),
                  // Desglose por módulo
                  Builder(builder: (_) {
                    final order = [
                      BetModuleType.skins,
                      BetModuleType.nassau,
                      BetModuleType.matchAutoPress,
                      BetModuleType.medal,
                      BetModuleType.putts,
                      BetModuleType.oyeses,
                      BetModuleType.units,
                    ];
                    final allTypes = order.where((type) {
                      for (final gr in round.betGroups) {
                        final pids = gr.playerIds;
                        if (!pids.contains(player.id) || !pids.contains(opp.id)) continue;
                        if (gr.modules.any((m) => m.type == type)) return true;
                      }
                      return false;
                    }).toList();

                    if (allTypes.isEmpty) return const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.only(left: 36, top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: allTypes.map((betType) {
                          final amount = breakdown[betType] ?? 0.0;
                          final amtColor = amount > 0
                              ? t.profit
                              : amount < 0 ? t.loss : t.sub;
                          final amtText = amount.abs() < 0.005
                              ? 'AS'
                              : '${amount >= 0 ? '+' : ''}\$${amount.toStringAsFixed(0)}';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              Text('${betType.icon}  ${betType.label}',
                                style: TextStyle(color: t.sub, fontSize: 11)),
                              const Spacer(),
                              Text(amtText,
                                style: TextStyle(color: amtColor, fontSize: 11, fontWeight: FontWeight.w700)),
                            ]),
                          );
                        }).toList(),
                      ),
                    );
                  }),
                  Divider(color: t.divider.withValues(alpha: 0.5), height: 16),
                ]),
              ),
            );
          }),

          if (hasUnits) _UnitsDetailSection(
            player: player, round: round, unitsByType: unitsByType, t: t, g: g,
          ),
        ],
      ),
    );
  }
}

// ── Unidades ganadas ───────────────────────────────────────────────────────────
class _UnitsDetailSection extends StatelessWidget {
  final Player player;
  final Round round;
  final Map<UnitEventType, List<int>> unitsByType;
  final GolfTheme t;
  final _ThemeGrad g;
  const _UnitsDetailSection({
    required this.player, required this.round,
    required this.unitsByType, required this.t, required this.g,
  });

  String _icon(UnitEventType type) => const {
    UnitEventType.birdie:       '🐦',
    UnitEventType.eagle:        '🦅',
    UnitEventType.sandyPar:     '🏖️',
    UnitEventType.parUnico:     '⭐',
    UnitEventType.birdieUnico:  '💫',
    UnitEventType.holeOut:      '🕳️',
  }[type]!;

  double _earnedFor(UnitEventType type) {
    double total = 0;
    for (final group in round.betGroups) {
      for (final mod in group.modules) {
        if (mod.type != BetModuleType.units) continue;
        final pids = mod.participantIds.isNotEmpty ? mod.participantIds : group.playerIds;
        if (!pids.contains(player.id)) continue;
        final holes = unitsByType[type] ?? [];
        final value = mod.units.valueFor(type);
        for (final _ in holes) {
          total += value * (pids.length - 1);
        }
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final totalUnits  = unitsByType.values.fold<int>(0, (sum, holes) => sum + holes.length);
    final totalEarned = unitsByType.keys.fold<double>(0, (sum, type) => sum + _earnedFor(type));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: g.unitChipBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: g.unitChipBorder),
        ),
        child: Row(children: [
          const Text('💫', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(child: Text('UNIDADES GANADAS',
            style: TextStyle(color: g.unitAccent, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: g.unitAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$totalUnits unit${totalUnits != 1 ? 's' : ''}  ·  \$${totalEarned.toStringAsFixed(0)}',
              style: TextStyle(color: g.unitAccent, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),

      ...unitsByType.entries.map((entry) {
        final type   = entry.key;
        final holes  = List<int>.from(entry.value)..sort();
        final count  = holes.length;
        final earned = _earnedFor(type);

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.divider),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_icon(type), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(type.label,
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('×$count',
                    style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 11)),
                ),
                const SizedBox(width: 8),
                Text(
                  earned > 0 ? '+\$${earned.toStringAsFixed(0)}' : '\$0',
                  style: TextStyle(
                    color: earned > 0 ? t.profit : t.sub,
                    fontWeight: FontWeight.w800, fontSize: 13,
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 5, runSpacing: 4, children: holes.map((h) {
                final par = round.course.holes
                    .firstWhere((ch) => ch.hole == h, orElse: () => round.course.holes.first).par;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: g.unitChipBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: g.unitChipBorder),
                  ),
                  child: Text('H$h · P$par',
                    style: TextStyle(color: g.unitAccent, fontSize: 10, fontWeight: FontWeight.w700)),
                );
              }).toList()),
            ]),
          ),
        );
      }),
    ]);
  }
}

// ── ResultsBody reutilizable (historial) ─────────────────────────────────────
class ResultsBody extends StatefulWidget {
  final Round round;
  const ResultsBody({required this.round, super.key});
  @override State<ResultsBody> createState() => _ResultsBodyState();
}

class _ResultsBodyState extends State<ResultsBody> {
  String? _expandedPlayerId;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<RoundProvider>().theme;
    final g = _ThemeGrad(t);
    final round = widget.round;
    final balances = LedgerEngine.playerBalances(round);
    final netDebts = LedgerEngine.compute(round);
    final sortedPlayers = round.players.toList()
      ..sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PGASectionLabel(label: 'BALANCE FINAL', icon: Icons.emoji_events_rounded, g: g),
        const SizedBox(height: 10),
        _PGAPodium(players: sortedPlayers, balances: balances, t: t, g: g),
        const SizedBox(height: 20),
        if (netDebts.isNotEmpty) ...[
          _PGASectionLabel(label: 'TRANSFERENCIAS', icon: Icons.currency_exchange_rounded, g: g),
          const SizedBox(height: 10),
          ...netDebts.map((d) => _PGAPaymentCard(debt: d, round: round, t: t, g: g)),
          const SizedBox(height: 20),
        ],
        _PGASectionLabel(label: 'DETALLE POR JUGADOR', icon: Icons.analytics_outlined, g: g),
        const SizedBox(height: 10),
        ...sortedPlayers.map((p) => _PlayerDetailSection(
          player: p, round: round, t: t, g: g,
          isExpanded: _expandedPlayerId == p.id,
          onToggle: () => setState(() =>
            _expandedPlayerId = _expandedPlayerId == p.id ? null : p.id),
        )),

        if (round.sliding.isNotEmpty) ...[
          const SizedBox(height: 20),
          _PGASectionLabel(label: 'SLIDING', icon: Icons.swap_horiz_rounded, g: g),
          const SizedBox(height: 10),
          SlidingSummaryCard(round: round, t: t),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }
}

// ── Panel diagnóstico Medal ────────────────────────────────────────────────────
class _MedalDiagPanel extends StatefulWidget {
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  const _MedalDiagPanel({required this.round, required this.t, required this.g});
  @override State<_MedalDiagPanel> createState() => _MedalDiagPanelState();
}

class _MedalDiagPanelState extends State<_MedalDiagPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final round = widget.round;
    final diag = BetEngine.diagnoseMedal(round);
    final hasZero = diag.any((d) => d['entries'] == 0);
    final nameOf = {for (final p in round.players) p.id: p.name};

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasZero ? t.loss.withValues(alpha: 0.4) : t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(hasZero ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: hasZero ? t.loss : t.profit, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                hasZero
                    ? 'Medal: hay duelo(s) sin resultado — toca para ver detalle'
                    : 'Medal: todos los duelos calculados correctamente',
                style: TextStyle(
                  color: hasZero ? t.loss : t.profit,
                  fontWeight: FontWeight.w700, fontSize: 12,
                ),
              )),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: t.sub, size: 16),
            ]),
          ),
        ),

        if (_expanded) ...[
          Divider(height: 1, color: t.divider),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: diag.map((d) {
                final entries   = d['entries'] as int;
                final rawReason = d['reason'] as String;
                final reason    = nameOf.entries.fold(rawReason, (s, e) => s.replaceAll(e.key, e.value));
                final pids      = d['pids'] as List;
                final nets      = d['nets'] as Map;
                final grosses   = d['grosses'] as Map;
                final strokesD  = d['strokes'] as Map? ?? {};
                final mode      = d['mode'] as String;
                final groupN    = d['groupName'] as String;
                final isAvA     = d['isAllVsAll'] as bool? ?? false;
                final pairDets  = (d['pairDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                final ok        = entries > 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ok
                        ? t.profit.withValues(alpha: 0.07)
                        : t.loss.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ok
                          ? t.profit.withValues(alpha: 0.25)
                          : t.loss.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(ok ? Icons.check : Icons.close_rounded,
                          size: 14, color: ok ? t.profit : t.loss),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        '$groupN · ${mode.toUpperCase()} · \$${d['value']} · ${isAvA ? "Todos vs Todos" : "1 Pot"}',
                        style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 12),
                      )),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: ok
                              ? t.profit.withValues(alpha: 0.20)
                              : t.loss.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          ok ? '$entries pago(s)' : 'EMPATE / SIN DATOS',
                          style: TextStyle(
                            color: ok ? t.profit : t.loss,
                            fontSize: 10, fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),

                    if (isAvA && pairDets.isNotEmpty) ...[
                      Text('Net = Gross − strokes recibidos',
                          style: TextStyle(color: t.sub, fontSize: 9, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 4),
                      Table(
                        columnWidths: const {
                          0: FlexColumnWidth(2.5),
                          1: FlexColumnWidth(3.5),
                          2: FlexColumnWidth(3.5),
                          3: FlexColumnWidth(2),
                        },
                        children: [
                          TableRow(children: [
                            _cell('PAR', t, header: true),
                            _cell('JUGADOR A', t, header: true),
                            _cell('JUGADOR B', t, header: true),
                            _cell('GANA', t, header: true),
                          ]),
                          ...pairDets.map((pair) {
                            final p1     = pair['p1'] as String;
                            final p2     = pair['p2'] as String;
                            final g1     = pair['gross1'] as int;
                            final s1     = pair['strokes1'] as int;
                            final net1   = pair['net1'] as int;
                            final g2     = pair['gross2'] as int;
                            final s2     = pair['strokes2'] as int;
                            final net2   = pair['net2'] as int;
                            final winner = pair['winner'] as String;
                            final winName = winner == 'EMPATE' ? 'EMPATE' : (nameOf[winner] ?? winner);
                            final isW1   = winner == p1;
                            final isW2   = winner == p2;
                            return TableRow(children: [
                              _cell('${nameOf[p1] ?? p1}\nvs', t),
                              _cell(s1 > 0 ? '$g1-$s1=$net1' : '$g1', t,
                                  highlight: isW1 ? t.profit : null, bold: isW1),
                              _cell(s2 > 0 ? '$g2-$s2=$net2' : '$g2', t,
                                  highlight: isW2 ? t.profit : null, bold: isW2),
                              _cell(winName, t,
                                  highlight: winner == 'EMPATE' ? null : t.profit,
                                  bold: winner != 'EMPATE'),
                            ]);
                          }),
                        ],
                      ),
                    ] else ...[
                      Table(
                        columnWidths: const {
                          0: FlexColumnWidth(3),
                          1: FlexColumnWidth(2),
                          2: FlexColumnWidth(2),
                          3: FlexColumnWidth(2),
                        },
                        children: [
                          TableRow(children: [
                            _cell('JUGADOR', t, header: true),
                            _cell('GROSS', t, header: true),
                            _cell('−STR', t, header: true),
                            _cell('NET', t, header: true),
                          ]),
                          ...pids.map((pid) {
                            final gv = grosses[pid] as int? ?? 0;
                            final nv = nets[pid]    as int? ?? 0;
                            final sv = strokesD[pid] as int? ?? 0;
                            final name = nameOf[pid.toString()] ?? pid.toString();
                            return TableRow(children: [
                              _cell(name, t),
                              _cell(gv > 0 ? gv.toString() : '–', t),
                              _cell(sv > 0 ? sv.toString() : '–', t),
                              _cell(nv > 0 ? nv.toString() : '–', t),
                            ]);
                          }),
                        ],
                      ),
                    ],

                    const SizedBox(height: 6),
                    Text(reason, style: TextStyle(color: t.sub, fontSize: 10)),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _cell(String text, GolfTheme t,
      {bool header = false, Color? highlight, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(text,
          style: TextStyle(
            color: header ? t.sub : (highlight ?? t.text),
            fontSize: header ? 9 : 11,
            fontWeight: header ? FontWeight.w800 : (bold ? FontWeight.w700 : FontWeight.w500),
            letterSpacing: header ? 0.6 : 0,
          ),
        ),
      );
}

// ── Panel diagnóstico scores ──────────────────────────────────────────────────
class _ScoresDiagPanel extends StatelessWidget {
  final Round round;
  final Map<String, double> balances;
  final GolfTheme t;
  final _ThemeGrad g;
  const _ScoresDiagPanel({required this.round, required this.balances, required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final scoreInfo = round.players.map((p) {
      final holes  = round.scores[p.id] ?? {};
      final scored = holes.values.where((h) => h.hasScore).length;
      final total  = holes.values.fold(0, (s, h) => s + (h.grossScore ?? 0));
      return '${p.name}: $scored hoyos, total=$total, bal=${balances[p.id]?.toStringAsFixed(0) ?? "0"}';
    }).join('\n');

    final betInfo = round.betGroups.expand((gr) => gr.modules).map((m) =>
        '${m.type.name}: participants=${m.participantIds.length}, useHcp=${m.useHandicap}')
        .join('\n');

    String engineInfo;
    try {
      final entries = BetEngine.computeAll(round);
      final lines = entries.map((e) =>
          '  ${e.betType.name} H${e.hole ?? "-"}: ${e.fromPlayerId.substring(0,6)}→${e.toPlayerId.substring(0,6)} \$${e.amount.toStringAsFixed(0)}')
          .join('\n');
      engineInfo = 'Entradas del motor: ${entries.length}\n$lines';
    } catch (e) {
      engineInfo = 'ERROR en motor: $e';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: g.diagBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: g.diagBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🔍 DIAGNÓSTICO (temporal)',
          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w800, fontSize: 11)),
        const SizedBox(height: 6),
        Text('Scores:\n$scoreInfo',
          style: TextStyle(color: t.text.withValues(alpha: 0.70), fontSize: 10, fontFamily: 'monospace')),
        const SizedBox(height: 6),
        Text('Módulos:\n$betInfo',
          style: TextStyle(color: t.text.withValues(alpha: 0.70), fontSize: 10, fontFamily: 'monospace')),
        const SizedBox(height: 6),
        Text(engineInfo, style: TextStyle(color: _entriesColor(engineInfo), fontSize: 10, fontFamily: 'monospace')),
      ]),
    );
  }

  Color _entriesColor(String info) {
    if (info.startsWith('ERROR')) return Colors.red;
    if (info.contains('Entradas del motor: 0')) return Colors.orange;
    return Colors.greenAccent;
  }
}
