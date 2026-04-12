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
import '../../services/auth_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/sliding_adjustment_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: paleta de colores sólidos por estado — sin gradientes que desaparezcan
// ─────────────────────────────────────────────────────────────────────────────
class _ThemeGrad {
  final GolfTheme t;
  const _ThemeGrad(this.t);

  bool get isLight => t.brightness == Brightness.light;

  // ── Colores de superficie ──────────────────────────────────────────────────
  Color get scaffoldBg  => t.bg;
  Color get cardSurface => isLight ? Colors.white : const Color(0xFF1C1C1E);
  Color get cardBorder  => isLight ? const Color(0xFFE8E8EC) : const Color(0xFF2C2C30);

  // ── Header ────────────────────────────────────────────────────────────────
  // Gradiente sólido de arriba a abajo, siempre visible
  List<Color> get header => isLight
      ? [t.primary, t.primary.withValues(alpha: 0.82)]
      : [const Color(0xFF1A1A2E), const Color(0xFF16213E)];

  Color get headerText  => Colors.white;
  Color get headerSub   => Colors.white.withValues(alpha: 0.70);

  // ── Ganador hero ──────────────────────────────────────────────────────────
  List<Color> heroGrad(bool isPos) => isPos
      ? (isLight
          ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
          : [const Color(0xFF1B5E20), const Color(0xFF2E7D32)])
      : (isLight
          ? [const Color(0xFF7F0000), const Color(0xFFC62828)]
          : [const Color(0xFF7F0000), const Color(0xFFC62828)]);

  Color get heroText   => Colors.white;
  Color get heroSub    => Colors.white.withValues(alpha: 0.72);

  // ── Fila ranking compacta ─────────────────────────────────────────────────
  Color get rankBg     => cardSurface;
  Color get rankBorder => cardBorder;

  // ── Medallas ──────────────────────────────────────────────────────────────
  List<Color> get medal1 => [const Color(0xFFFFC107), const Color(0xFFFF8F00)];
  List<Color> get medal2 => [const Color(0xFFB0BEC5), const Color(0xFF78909C)];
  List<Color> get medal3 => [const Color(0xFFBF9660), const Color(0xFF8D6E3A)];
  List<Color> get medalN => [const Color(0xFF757575), const Color(0xFF616161)];
  List<Color> medalGrad(int rank) => rank == 1 ? medal1 : rank == 2 ? medal2 : rank == 3 ? medal3 : medalN;

  Color get medal1Shadow => const Color(0xFFFFC107).withValues(alpha: 0.45);

  // ── Monto ─────────────────────────────────────────────────────────────────
  Color amountHero(bool isPos) => Colors.white;
  Color amountRow(bool isPos)  => isPos ? t.profit : t.loss;

  // ── Chip balance duelo ────────────────────────────────────────────────────
  Color chipBg(double bal) {
    if (bal == 0) return t.scoreUnder.withValues(alpha: 0.15);
    return (bal > 0 ? t.profit : t.loss).withValues(alpha: 0.15);
  }
  Color chipBorder(double bal) {
    if (bal == 0) return t.scoreUnder.withValues(alpha: 0.45);
    return (bal > 0 ? t.profit : t.loss).withValues(alpha: 0.45);
  }
  Color chipText(double bal) {
    if (bal == 0) return t.scoreUnder;
    return bal > 0 ? t.profit : t.loss;
  }

  // ── Sección label ─────────────────────────────────────────────────────────
  Color get sectionColor => isLight ? t.primary : t.accent;

  // ── Transferencias ────────────────────────────────────────────────────────
  // Fondo con contraste sólido, no transparente
  List<Color> transferBg(bool isDark) => isDark
      ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
      : [const Color(0xFFF8F9FF), const Color(0xFFEEF0F8)];

  Color get transferBorder => isLight
      ? const Color(0xFFD0D5E8)
      : const Color(0xFF2A2A3E);

  List<Color> get amountPillBg => isLight
      ? [t.primary, t.primary.withValues(alpha: 0.80)]
      : [const Color(0xFF3D5AFE), const Color(0xFF1A237E)];

  Color get amountPillText => Colors.white;

  // ── Duelo card ────────────────────────────────────────────────────────────
  Color get duelBg     => isLight ? const Color(0xFFF4F5F9) : const Color(0xFF1E1E24);
  Color get duelBorder => cardBorder;

  // ── Unidades ─────────────────────────────────────────────────────────────
  Color get unitChipBg     => t.accent.withValues(alpha: 0.12);
  Color get unitChipBorder => t.accent.withValues(alpha: 0.30);
  Color get unitAccent     => t.accent;

  // ── Botón cerrar ronda ───────────────────────────────────────────────────
  List<Color> get closeRoundGrad => isLight
      ? [Colors.white, Colors.white.withValues(alpha: 0.90)]
      : [const Color(0xFF2E7D32), const Color(0xFF1B5E20)];
  Color get closeRoundText => isLight ? t.primary : Colors.white;

  // ── Trofeo ───────────────────────────────────────────────────────────────
  Color get trophyColor => isLight ? Colors.white : t.accent;
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

    final sortedPlayers = getDisplayPlayers(round)
      ..sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));

    final g = _ThemeGrad(t);

    // ── Determinar si este usuario tiene cuenta registrada (linked) ──────────
    final myUid = AuthService.uid;
    final myLinkedPlayer = myUid != null
        ? round.players.where((p) =>
              p.linkedUserId == myUid && !p.isVirtual).firstOrNull
        : null;
    final iAmRegistered = myLinkedPlayer != null;
    final adminFinished = prov.roundFinishedByAdmin;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          // Banner: ronda finalizada por el admin (solo para invitados)
          if (adminFinished && !prov.isLiveOwner)
            _AdminFinishedBanner(
              t: t,
              iAmRegistered: iAmRegistered,
              onClose: () => _handleGuestClose(context, round, prov, iAmRegistered),
            ),
          _PGAHeader(round: round, t: t, g: g, prov: prov, onFinish: _confirmFinish),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // NIVEL 1: Podio PGA
                  _PGAPodium(players: sortedPlayers, round: round, balances: balances, t: t, g: g),
                  const SizedBox(height: 28),

                  // NIVEL 2: Pagos directos
                  if (netDebts.isNotEmpty) ...[
                    _PGASectionLabel(label: 'TRANSFERENCIAS', icon: Icons.currency_exchange_rounded, g: g),
                    const SizedBox(height: 12),
                    ...netDebts.map((d) => _PGAPaymentCard(debt: d, round: round, t: t, g: g)),
                    const SizedBox(height: 28),
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
          // Sliding solo para usuarios con cuenta registrada (premium)
          final myUid = AuthService.uid;
          final myLinkedPlayer = myUid != null
              ? roundSnapshot?.players.where((p) =>
                    p.linkedUserId == myUid && !p.isVirtual).firstOrNull
              : null;
          if (roundSnapshot != null && myLinkedPlayer != null && context.mounted) {
            await showSlidingAdjustmentDialog(context, roundSnapshot);
          }
        }, child: Text('Finalizar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  /// Lógica para que el invitado cierre la ronda desde el banner de "admin finalizó"
  Future<void> _handleGuestClose(
    BuildContext context,
    Round round,
    RoundProvider prov,
    bool iAmRegistered,
  ) async {
    final t = prov.theme;
    // Mostrar diálogo de confirmación
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cerrar ronda', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        content: Text(
          iAmRegistered
              ? 'La ronda se guardará en tu historial y podrás actualizar tus ajustes de sliding.'
              : 'La ronda se cerrará. Puedes revisar los resultados finales antes de salir.',
          style: TextStyle(color: t.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: TextStyle(color: t.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cerrar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final roundSnapshot = round;
    await prov.acknowledgeAdminFinish();

    // Sliding: solo para usuarios con cuenta registrada (funcionalidad premium)
    if (iAmRegistered && context.mounted) {
      await showSlidingAdjustmentDialog(context, roundSnapshot);
    }
  }
}

// ── Banner: el admin finalizó la ronda — aviso para invitados ─────────────────
class _AdminFinishedBanner extends StatelessWidget {
  final GolfTheme t;
  final bool iAmRegistered;
  final VoidCallback onClose;
  const _AdminFinishedBanner({
    required this.t,
    required this.iAmRegistered,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF8C00).withValues(alpha: 0.92),
            const Color(0xFFFF5722).withValues(alpha: 0.92),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        const Text('🏁', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El administrador finalizó la ronda',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Text(
                iAmRegistered
                    ? 'Presiona "Cerrar" para guardar los resultados y actualizar tu sliding.'
                    : 'Revisa los resultados finales y presiona "Cerrar" cuando quieras.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onClose,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child: Text(
              'Cerrar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Header con gradiente sólido siempre visible ───────────────────────────────
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
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(children: [
        // Ícono trofeo
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.emoji_events_rounded, color: g.trophyColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('RESULTADOS FINALES',
            style: TextStyle(
              color: g.headerText, fontWeight: FontWeight.w900,
              fontSize: 13, letterSpacing: 1.4,
            )),
          Text(round.name,
            style: TextStyle(color: g.headerSub, fontSize: 11),
            overflow: TextOverflow.ellipsis),
        ])),
        // Botón cerrar ronda — solo visible para el owner/admin de la ronda
        if (prov.isLiveOwner || !round.isLive)
          GestureDetector(
            onTap: () => onFinish(context, round, prov, t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: g.closeRoundGrad),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 8, offset: const Offset(0, 2),
                )],
              ),
              child: Text('Cerrar ronda',
                style: TextStyle(color: g.closeRoundText, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
      ]),
    );
  }
}

// ── Label de sección ──────────────────────────────────────────────────────────
class _PGASectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final _ThemeGrad g;
  const _PGASectionLabel({required this.label, required this.icon, required this.g});

  @override
  Widget build(BuildContext context) {
    final color = g.sectionColor;
    return Row(children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(
        color: color, fontSize: 10,
        fontWeight: FontWeight.w900, letterSpacing: 2.0,
      )),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.25))),
    ]);
  }
}

// ── Podio PGA ─────────────────────────────────────────────────────────────────
class _PGAPodium extends StatelessWidget {
  final List<Player> players;
  final Round round;
  final Map<String, double> balances;
  final GolfTheme t;
  final _ThemeGrad g;
  const _PGAPodium({required this.players, required this.round, required this.balances, required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (players.isNotEmpty)
        _WinnerHeroCard(player: players[0], round: round, balance: balances[players[0].id] ?? 0, rank: 1, t: t, g: g),
      if (players.length > 1) const SizedBox(height: 8),
      ...players.skip(1).toList().asMap().entries.map((e) {
        final rank = e.key + 2;
        final p    = e.value;
        final bal  = balances[p.id] ?? 0.0;
        return _RankingRow(rank: rank, player: p, round: round, balance: bal, t: t, g: g);
      }),
    ]);
  }
}

// ── Tarjeta hero: fondo de color sólido intenso, texto blanco ────────────────
class _WinnerHeroCard extends StatelessWidget {
  final Player player;
  final Round round;
  final double balance;
  final int rank;
  final GolfTheme t;
  final _ThemeGrad g;
  const _WinnerHeroCard({required this.player, required this.round, required this.balance, required this.rank,
      required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final isPos = balance >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: g.heroGrad(isPos),
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
          color: (isPos ? const Color(0xFF1B5E20) : const Color(0xFF7F0000))
              .withValues(alpha: 0.40),
          blurRadius: 18, offset: const Offset(0, 6),
        )],
      ),
      child: Row(children: [
        // Medalla #1
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: g.medal1,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: g.medal1Shadow, blurRadius: 10)],
          ),
          child: const Center(
            child: Text('1', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20,
            )),
          ),
        ),
        const SizedBox(width: 14),
        GAvatar(name: player.name, colorIndex: player.colorIndex, size: 52),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          playerOrTeamName(
            player,
            round,
            style: TextStyle(color: g.heroText, fontWeight: FontWeight.w800, fontSize: 16),
            showTeamIcon: true,
          ),
          const SizedBox(height: 2),
          if (teamMembersFootnote(player, round, style: TextStyle(color: g.heroSub, fontSize: 10)) != null)
            teamMembersFootnote(player, round, style: TextStyle(color: g.heroSub, fontSize: 10))!
          else
            Text('HCP ${player.handicapBase.toStringAsFixed(0)}',
              style: TextStyle(color: g.heroSub, fontSize: 11)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
            ),
            child: Text(
              isPos ? 'LÍDER  ·  COBRA' : 'PAGA',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2,
              ),
            ),
          ),
        ])),
        // Balance grande en blanco sobre fondo oscuro
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '\$${balance.abs().toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 30,
            ),
          ),
          Text('MXN', style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 10, letterSpacing: 0.5,
          )),
        ]),
      ]),
    );
  }
}

// ── Fila ranking compacta ─────────────────────────────────────────────────────
class _RankingRow extends StatelessWidget {
  final int rank;
  final Player player;
  final Round round;
  final double balance;
  final GolfTheme t;
  final _ThemeGrad g;
  const _RankingRow({required this.rank, required this.player, required this.round, required this.balance,
      required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final isPos = balance >= 0;
    final medGrad = g.medalGrad(rank);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: g.rankBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: g.rankBorder, width: 1),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: g.isLight ? 0.04 : 0.18),
            blurRadius: 8, offset: const Offset(0, 2),
          )],
        ),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: medGrad,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text('$rank',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
          ),
          const SizedBox(width: 10),
          GAvatar(name: player.name, colorIndex: player.colorIndex, size: 38),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            playerOrTeamName(
              player,
              round,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
              showTeamIcon: false,
            ),
            if (teamMembersFootnote(player, round, style: TextStyle(color: t.sub, fontSize: 9)) != null)
              teamMembersFootnote(player, round, style: TextStyle(color: t.sub, fontSize: 9))!
            else
              Text('HCP ${player.handicapBase.toStringAsFixed(0)}',
                style: TextStyle(color: t.sub, fontSize: 10)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '\$${balance.abs().toStringAsFixed(0)}',
              style: TextStyle(
                color: g.amountRow(isPos),
                fontWeight: FontWeight.w800, fontSize: 19,
              ),
            ),
            Text(
              isPos ? 'COBRA' : 'PAGA',
              style: TextStyle(
                color: g.amountRow(isPos).withValues(alpha: 0.70),
                fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Tarjeta de transferencia — diseño impactante ───────────────────────────────
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: g.transferBg(g.isLight ? false : true),
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: g.transferBorder, width: 1),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: g.isLight ? 0.06 : 0.28),
            blurRadius: 12, offset: const Offset(0, 4),
          )],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              // ── Pagador ──────────────────────────────────────────────────
              _TransferPlayer(
                player: payer,
                round: round,
                label: 'PAGA',
                labelColor: t.loss,
                t: t,
                g: g,
              ),

              // ── Centro: flecha + monto ────────────────────────────────────
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Monto en pill con gradiente sólido
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: g.amountPillBg,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(
                          color: g.amountPillBg.first.withValues(alpha: 0.40),
                          blurRadius: 10, offset: const Offset(0, 3),
                        )],
                      ),
                      child: Text(
                        '\$${debt.amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: g.amountPillText,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Flecha animada
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _ArrowDot(color: t.loss.withValues(alpha: 0.50)),
                      const SizedBox(width: 2),
                      _ArrowDot(color: t.loss.withValues(alpha: 0.75)),
                      const SizedBox(width: 2),
                      _ArrowDot(color: t.loss),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_forward_rounded, color: t.loss, size: 16),
                    ]),
                  ],
                ),
              ),

              // ── Cobrador ─────────────────────────────────────────────────
              _TransferPlayer(
                player: receiver,
                round: round,
                label: 'COBRA',
                labelColor: t.profit,
                t: t,
                g: g,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferPlayer extends StatelessWidget {
  final Player player;
  final Round round;
  final String label;
  final Color labelColor;
  final GolfTheme t;
  final _ThemeGrad g;
  const _TransferPlayer({
    required this.player, required this.round, required this.label, required this.labelColor,
    required this.t, required this.g,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: labelColor.withValues(alpha: 0.50), width: 2),
        ),
        child: GAvatar(name: player.name, colorIndex: player.colorIndex, size: 42),
      ),
      const SizedBox(height: 6),
      playerOrTeamName(
        player,
        round,
        style: TextStyle(
          color: t.text, fontSize: 12, fontWeight: FontWeight.w700,
        ),
        showTeamIcon: false,
      ),
      const SizedBox(height: 2),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: labelColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8,
          ),
        ),
      ),
    ]);
  }
}

class _ArrowDot extends StatelessWidget {
  final Color color;
  const _ArrowDot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 4, height: 4,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
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
          color: g.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded
                ? t.accent.withValues(alpha: 0.45)
                : g.cardBorder,
            width: isExpanded ? 1.5 : 1,
          ),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: g.isLight ? 0.04 : 0.20),
            blurRadius: 8, offset: const Offset(0, 2),
          )],
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(children: [
                  GAvatar(name: player.name, colorIndex: player.colorIndex, size: 36),
                  const SizedBox(width: 12),
                  Expanded(child: playerOrTeamName(
                    player,
                    round,
                    style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
                    showTeamIcon: false,
                  )),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.keyboard_arrow_down, color: t.sub, size: 22),
                  ),
                ]),
              ),
            ),
            if (isExpanded) ...[
              Divider(height: 1, color: g.cardBorder),
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
                // ── Match + Press live balance ─────────────────────────────
                if (mod.type == BetModuleType.matchAutoPress) {
                  double mpLiveBal = 0.0;
                  final presses = BetEngine.matchAutoPressLive(round, player.id, opp.id, mod);
                  for (final pr in presses) {
                    if (pr.played == 0) continue;
                    if (pr.leadingPlayerId == player.id) mpLiveBal += pr.value;
                    if (pr.leadingPlayerId == opp.id) mpLiveBal -= pr.value;
                  }
                  breakdown[BetModuleType.matchAutoPress] = mpLiveBal;
                }
                // Nassau: sobreescribir con balance en vivo
                if (mod.type == BetModuleType.nassau) {
                  double npLiveBal = 0.0;
                  if (mod.pressEnabled) {
                    final st = BetEngine.nassauPressLiveStatus(round, player.id, opp.id, mod);
                    final isBack   = round.startingNine == StartingNine.back;
                    final seg1From = isBack ? 10 : 1;
                    final seg1To   = isBack ? 18 : 9;
                    if (st.frontPlayed > 0) {
                      if (st.front > 0) npLiveBal += st.frontVal;
                      if (st.front < 0) npLiveBal -= st.frontVal;
                    }
                    if (st.backPlayed > 0) {
                      if (st.back > 0) npLiveBal += st.backVal;
                      if (st.back < 0) npLiveBal -= st.backVal;
                    }
                    if (st.frontPlayed + st.backPlayed > 0) {
                      if (st.total > 0) npLiveBal += st.totalVal;
                      if (st.total < 0) npLiveBal -= st.totalVal;
                    }
                    for (final p in [...st.frontPresses, ...st.backPresses]) {
                      // Solo liquidar presses CERRADAS; las abiertas son apuestas pendientes
                      if (p.isOpen) continue;
                      final inSeg1   = p.startHole >= seg1From && p.startHole <= seg1To;
                      final pressVal = inSeg1 ? mod.nassau.frontPressValue : mod.nassau.backPressValue;
                      if (p.score > 0) npLiveBal += pressVal;
                      if (p.score < 0) npLiveBal -= pressVal;
                    }
                  } else {
                    final st = BetEngine.nassauLiveStatus(round, player.id, opp.id, mod);
                    if (st.frontPlayed > 0) {
                      if (st.front > 0) npLiveBal += st.frontVal;
                      if (st.front < 0) npLiveBal -= st.frontVal;
                    }
                    if (st.backPlayed > 0) {
                      if (st.back > 0) npLiveBal += st.backVal;
                      if (st.back < 0) npLiveBal -= st.backVal;
                    }
                    if (st.frontPlayed + st.backPlayed > 0) {
                      if (st.total > 0) npLiveBal += st.totalVal;
                      if (st.total < 0) npLiveBal -= st.totalVal;
                    }
                  }
                  breakdown[BetModuleType.nassau] = npLiveBal;
                }
              }
            }

            final balance = breakdown.values.fold<double>(0.0, (s, v) => s + v);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DuelCard(
                opponent: opp, balance: balance, breakdown: breakdown,
                player: player, round: round, t: t, g: g,
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

// ── Tarjeta de duelo cara a cara ──────────────────────────────────────────────
class _DuelCard extends StatelessWidget {
  final Player opponent;
  final double balance;
  final Map<BetModuleType, double> breakdown;
  final Player player;
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  const _DuelCard({
    required this.opponent, required this.balance, required this.breakdown,
    required this.player, required this.round, required this.t, required this.g,
  });

  @override
  Widget build(BuildContext context) {
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
        if (!pids.contains(player.id) || !pids.contains(opponent.id)) continue;
        if (gr.modules.any((m) => m.type == type)) return true;
      }
      return false;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: g.duelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: g.duelBorder),
      ),
      child: Column(
        children: [
          // Cabecera del duelo
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(children: [
              GAvatar(name: opponent.name, colorIndex: opponent.colorIndex, size: 30),
              const SizedBox(width: 8),
              Expanded(child: Text(opponent.name,
                style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13))),
              // Balance chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: g.chipBg(balance),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: g.chipBorder(balance), width: 1),
                ),
                child: Text(
                  balance.abs() < 0.005
                      ? 'AS'
                      : '${balance > 0 ? '+' : ''}\$${balance.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: g.chipText(balance),
                    fontWeight: FontWeight.w900, fontSize: 14,
                  ),
                ),
              ),
            ]),
          ),

          // Desglose por módulo (filas compactas)
          if (allTypes.isNotEmpty) ...[
            Divider(height: 1, color: g.cardBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: allTypes.map((betType) {
                  final amount   = breakdown[betType] ?? 0.0;
                  final amtColor = amount > 0 ? t.profit : amount < 0 ? t.loss : t.sub;
                  final amtText  = amount.abs() < 0.005
                      ? 'AS'
                      : '${amount >= 0 ? '+' : ''}\$${amount.toStringAsFixed(0)}';

                  // Sub-detalle para Oyeses: marcador + zapato
                  String? oyesesDetail;
                  if (betType == BetModuleType.oyeses) {
                    // Buscar módulo de oyeses que incluya a ambos jugadores
                    BetModuleInstance? oyesMod;
                    for (final gr in round.betGroups) {
                      if (!gr.playerIds.contains(player.id) || !gr.playerIds.contains(opponent.id)) continue;
                      final found = gr.modules.where((m) => m.type == BetModuleType.oyeses).toList();
                      if (found.isNotEmpty) { oyesMod = found.first; break; }
                    }
                    if (oyesMod != null) {
                      final o = oyesMod.oyeses;
                      final par3Holes = round.course.holes.where((h) => h.isPar3).toList();
                      final eligible  = o.eligibleHoles.isNotEmpty
                          ? par3Holes.where((h) => o.eligibleHoles.contains(h.hole)).toList()
                          : par3Holes;
                      final totalEligible = eligible.length;
                      int oyes1 = 0, oyes2 = 0, holesPlayed = 0;
                      int winsP1vsP2 = 0, winsP2vsP1 = 0;
                      for (final ch in eligible) {
                        final ranking = round.getOyese(ch.hole);
                        if (ranking == null || ranking.ranking.isEmpty) continue;
                        final ordered = ranking.ranking.where((pid) => [player.id, opponent.id].contains(pid)).toList();
                        if (ordered.length < 2) continue;
                        holesPlayed++;
                        if (ordered[0] == player.id) { oyes1++; winsP1vsP2++; }
                        else { oyes2++; winsP2vsP1++; }
                      }
                      final pName = player.shortName;
                      final oName = opponent.shortName;
                      String scoreLine = '$pName $oyes1 · $oyes2 $oName';
                      if (o.zapatoEnabled && holesPlayed == totalEligible && totalEligible > 0) {
                        final enoughHoles = o.zapatoRequires18 ? (totalEligible >= 3) : true;
                        if (enoughHoles) {
                          final zapatoAmt = o.zapatoValue > 0 ? o.zapatoValue : (totalEligible * o.value);
                          if (winsP1vsP2 == holesPlayed) {
                            scoreLine += '  ·  👟 +\$${zapatoAmt.toStringAsFixed(0)}';
                          } else if (winsP2vsP1 == holesPlayed) {
                            scoreLine += '  ·  👟 -\$${zapatoAmt.toStringAsFixed(0)}';
                          }
                        }
                      }
                      oyesesDetail = scoreLine;
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        // Icono y nombre del tipo de apuesta
                        Text('${betType.icon}', style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(betType.label,
                          style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w500))),
                        // Barra de monto
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: amtColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(amtText,
                            style: TextStyle(
                              color: amtColor,
                              fontWeight: FontWeight.w800, fontSize: 12,
                            )),
                        ),
                      ]),
                      if (oyesesDetail != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 18, top: 2),
                          child: Text(oyesesDetail,
                            style: TextStyle(color: t.sub, fontSize: 10)),
                        ),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ],
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: g.unitChipBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: g.unitChipBorder),
        ),
        child: Row(children: [
          const Text('💫', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text('UNIDADES GANADAS',
            style: TextStyle(color: g.unitAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: g.unitAccent.withValues(alpha: 0.18),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: g.cardBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_icon(type), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(type.label,
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.12),
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
    final sortedPlayers = getDisplayPlayers(round)
      ..sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PGASectionLabel(label: 'BALANCE FINAL', icon: Icons.emoji_events_rounded, g: g),
        const SizedBox(height: 10),
        _PGAPodium(players: sortedPlayers, round: round, balances: balances, t: t, g: g),
        const SizedBox(height: 20),
        if (netDebts.isNotEmpty) ...[
          _PGASectionLabel(label: 'TRANSFERENCIAS', icon: Icons.currency_exchange_rounded, g: g),
          const SizedBox(height: 12),
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
