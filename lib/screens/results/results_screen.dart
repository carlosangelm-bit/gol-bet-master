// ─────────────────────────────────────────────────────────────────────────────
// RESULTS SCREEN — Liquidación financiera centrada en jugadores (no en apuestas)
// Nivel 1: balance por jugador
// Nivel 2: cara a cara (quién le paga a quién)
// Nivel 3: detalle por tipo de apuesta
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../engines/ledger_engine.dart';
import '../../engines/bet_engine.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../widgets/common_widgets.dart';

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

    // Ordenar jugadores por balance (ganadores primero)
    final sortedPlayers = round.players.toList()
      ..sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context, round, t, prov),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // NIVEL 1: Balances
                  GSectionHeader(title: 'BALANCE FINAL'),
                  const SizedBox(height: 8),
                  _BalanceSummaryCards(players: sortedPlayers, balances: balances, t: t),
                  const SizedBox(height: 20),

                  // NIVEL 2: Pagos directos (quién paga a quién)
                  if (netDebts.isNotEmpty) ...[
                    GSectionHeader(title: 'PAGOS A REALIZAR'),
                    const SizedBox(height: 8),
                    ...netDebts.map((d) => _PaymentCard(debt: d, round: round, t: t)),
                    const SizedBox(height: 20),
                  ],

                  // NIVEL 3: Detalle cara a cara expandible por jugador
                  GSectionHeader(title: 'DETALLE POR JUGADOR'),
                  const SizedBox(height: 8),
                  ...sortedPlayers.map((p) => _PlayerDetailSection(
                    player: p,
                    round: round,
                    t: t,
                    isExpanded: _expandedPlayerId == p.id,
                    onToggle: () => setState(() =>
                      _expandedPlayerId = _expandedPlayerId == p.id ? null : p.id),
                  )),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Round round, GolfTheme t, RoundProvider prov) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(color: t.bg, border: Border(bottom: BorderSide(color: t.divider))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Resultados', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 20)),
          Text(round.name, style: TextStyle(color: t.sub, fontSize: 12)),
        ])),
        GestureDetector(
          onTap: () => _confirmFinish(context, round, prov, t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(20)),
            child: Text('Cerrar ronda', style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ),
      ]),
    );
  }

  void _confirmFinish(BuildContext context, Round round, RoundProvider prov, GolfTheme t) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      title: Text('Finalizar ronda', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
      content: Text(
        'Los resultados se guardarán en el historial y la ronda quedará cerrada.',
        style: TextStyle(color: t.sub),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: t.sub))),
        TextButton(onPressed: () {
          Navigator.pop(ctx);
          prov.finishRound();
        }, child: Text('Finalizar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700))),
      ],
    ));
  }
}

// ── Nivel 1: Balance summary ──────────────────────────────────────────────────
class _BalanceSummaryCards extends StatelessWidget {
  final List<Player> players;
  final Map<String, double> balances;
  final GolfTheme t;
  const _BalanceSummaryCards({required this.players, required this.balances, required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: players.asMap().entries.map((e) {
        final p   = e.value;
        final bal = balances[p.id] ?? 0.0;
        final rank = e.key + 1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GCard(child: Row(children: [
            // Rank
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: rank == 1 ? t.primary : t.surface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text('$rank', style: TextStyle(
                color: rank == 1 ? t.onPrimary : t.sub,
                fontWeight: FontWeight.w800, fontSize: 13,
              )),
            ),
            const SizedBox(width: 12),
            GAvatar(name: p.name, colorIndex: p.colorIndex, size: 38),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 15)),
              Text('HCP ${p.handicapBase.toStringAsFixed(0)}', style: TextStyle(color: t.sub, fontSize: 11)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              BalChip(amount: bal),
              const SizedBox(height: 2),
              Text(bal >= 0 ? 'COBRA' : 'PAGA', style: TextStyle(
                color: bal >= 0 ? t.profit : t.loss,
                fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5,
              )),
            ]),
          ])),
        );
      }).toList(),
    );
  }
}

// ── Nivel 2: Pagos directos ───────────────────────────────────────────────────
class _PaymentCard extends StatelessWidget {
  final NetDebt debt;
  final Round round;
  final GolfTheme t;
  const _PaymentCard({required this.debt, required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    final payer    = round.players.firstWhere((p) => p.id == debt.fromPlayerId);
    final receiver = round.players.firstWhere((p) => p.id == debt.toPlayerId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GCard(child: Row(children: [
        Column(children: [
          GAvatar(name: payer.name, colorIndex: payer.colorIndex, size: 34),
          const SizedBox(height: 2),
          Text(payer.name.split(' ').first, style: TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        Expanded(child: Column(children: [
          Icon(Icons.arrow_forward, color: t.loss, size: 20),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: t.loss.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Text('\$${debt.amount.toStringAsFixed(0)}', style: TextStyle(color: t.loss, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          Text('PAGA', style: TextStyle(color: t.loss, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ])),
        Column(children: [
          GAvatar(name: receiver.name, colorIndex: receiver.colorIndex, size: 34),
          const SizedBox(height: 2),
          Text(receiver.name.split(' ').first, style: TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ])),
    );
  }
}

// ── Nivel 3: Detalle por jugador expandible ───────────────────────────────────
class _PlayerDetailSection extends StatelessWidget {
  final Player player;
  final Round round;
  final GolfTheme t;
  final bool isExpanded;
  final VoidCallback onToggle;
  const _PlayerDetailSection({
    required this.player, required this.round, required this.t,
    required this.isExpanded, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Header (siempre visible)
            GestureDetector(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  GAvatar(name: player.name, colorIndex: player.colorIndex, size: 36),
                  const SizedBox(width: 12),
                  Expanded(child: Text(player.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14))),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: t.sub, size: 20),
                ]),
              ),
            ),
            if (isExpanded) ...[
              Divider(height: 1, color: t.divider),
              _PlayerFaceToFace(player: player, round: round, t: t),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Cara a cara: jugador seleccionado vs todos los demás ─────────────────────
class _PlayerFaceToFace extends StatelessWidget {
  final Player player;
  final Round round;
  final GolfTheme t;
  const _PlayerFaceToFace({required this.player, required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    // ── Solo rivales con quienes hay al menos un módulo de apuesta activo ────
    final Set<String> bettingOpponentIds = {};
    bool playerHasUnitsModule = false;
    for (final group in round.betGroups) {
      for (final mod in group.modules) {
        final pids = mod.participantIds.isNotEmpty ? mod.participantIds : group.playerIds;
        if (!pids.contains(player.id)) continue;
        // Añadir todos los rivales de este módulo
        for (final pid in pids) {
          if (pid != player.id) bettingOpponentIds.add(pid);
        }
        // Verificar si hay módulo units
        if (mod.type == BetModuleType.units) playerHasUnitsModule = true;
      }
    }
    final opponents = round.players
        .where((p) => bettingOpponentIds.contains(p.id))
        .toList();

    // ── Recopilar eventos de unidades SOLO si hay módulo units activo ────────
    // Estructura: { UnitEventType → [hole, hole, ...] }
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
          // ── Sección cara a cara vs cada rival ──────────────────────────────
          ...opponents.map((opp) {
            final balance   = LedgerEngine.balanceBetween(round, player.id, opp.id);
            final breakdown = LedgerEngine.breakdownBetween(round, player.id, opp.id);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  GAvatar(name: opp.name, colorIndex: opp.colorIndex, size: 28),
                  const SizedBox(width: 8),
                  Expanded(child: Text(opp.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w600, fontSize: 13))),
                  BalChip(amount: balance),
                ]),
                if (breakdown.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: breakdown.entries.map((e) {
                        // Para Match+Press, agregar detalle de segmentos debajo
                        List<Widget> subRows = [];
                        if (e.key == BetModuleType.matchAutoPress) {
                          for (final g in round.betGroups) {
                            if (!g.playerIds.contains(player.id) || !g.playerIds.contains(opp.id)) continue;
                            for (final m in g.modules.where((m) => m.type == BetModuleType.matchAutoPress)) {
                              final statuses = BetEngine.matchAutoPressLive(round, player.id, opp.id, m);
                              for (final pr in statuses) {
                                final prLabel = pr.isPrimaryMatch
                                    ? '⚔️ Match H1–${pr.endHole}'
                                    : pr.startHole == 1
                                        ? '📌 Dígito H1–${pr.endHole}'
                                        : '🔄 Press H${pr.startHole}–${pr.endHole}';
                                final prColor = pr.score == 0
                                    ? const Color(0xFF1565C0)
                                    : pr.score > 0
                                        ? const Color(0xFF2E7D32)
                                        : const Color(0xFFC62828);
                                final prResult = pr.score == 0
                                    ? 'AS'
                                    : pr.leadingPlayerId == player.id
                                        ? '+${pr.score.abs()}'
                                        : '−${pr.score.abs()}';
                                subRows.add(Padding(
                                  padding: const EdgeInsets.only(bottom: 2, left: 8),
                                  child: Row(children: [
                                    Text(prLabel, style: TextStyle(color: t.sub, fontSize: 10)),
                                    const Spacer(),
                                    Text(prResult, style: TextStyle(color: prColor, fontSize: 10, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 6),
                                    Text('\$${pr.value.toStringAsFixed(0)}', style: TextStyle(color: t.sub, fontSize: 9)),
                                  ]),
                                ));
                              }
                            }
                          }
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text('${e.key.icon}  ${e.key.label}', style: TextStyle(color: t.sub, fontSize: 11)),
                              const Spacer(),
                              Text(
                                '${e.value >= 0 ? '+' : ''}\$${e.value.toStringAsFixed(0)}',
                                style: TextStyle(color: e.value >= 0 ? t.profit : t.loss, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ]),
                            ...subRows,
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                Divider(color: t.divider.withValues(alpha: 0.5)),
              ]),
            );
          }),

          // ── Sección UNIDADES ────────────────────────────────────────────────
          if (hasUnits) _UnitsDetailSection(
            player: player,
            round: round,
            unitsByType: unitsByType,
            t: t,
          ),
        ],
      ),
    );
  }
}

// ── Sección de unidades ganadas por el jugador ────────────────────────────────
class _UnitsDetailSection extends StatelessWidget {
  final Player player;
  final Round round;
  final Map<UnitEventType, List<int>> unitsByType;
  final GolfTheme t;
  const _UnitsDetailSection({
    required this.player, required this.round,
    required this.unitsByType, required this.t,
  });

  // Icono por tipo de evento
  String _icon(UnitEventType type) => const {
    UnitEventType.birdie:       '🐦',
    UnitEventType.eagle:        '🦅',
    UnitEventType.sandyPar:     '🏖️',
    UnitEventType.parUnico:     '⭐',
    UnitEventType.birdieUnico:  '💫',
    UnitEventType.holeOut:      '🕳️',
  }[type]!;

  // Total de unidades cobradas por este tipo (desde cualquier rival)
  double _earnedFor(UnitEventType type) {
    // Buscar módulos de Units que incluyan a este jugador
    double total = 0;
    for (final group in round.betGroups) {
      for (final mod in group.modules) {
        if (mod.type != BetModuleType.units) continue;
        final pids = mod.participantIds.isNotEmpty ? mod.participantIds : group.playerIds;
        if (!pids.contains(player.id)) continue;
        final holes = unitsByType[type] ?? [];
        final value = mod.units.valueFor(type);
        // Cada evento en ese hoyo: cobran (n-1) rivales
        for (final _ in holes) {
          total += value * (pids.length - 1);
        }
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    // Total general de unidades
    final totalUnits = unitsByType.values.fold<int>(0, (sum, holes) => sum + holes.length);
    final totalEarned = unitsByType.keys.fold<double>(0, (sum, type) => sum + _earnedFor(type));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Encabezado ──────────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.accent.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Text('💫', style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('UNIDADES GANADAS',
              style: TextStyle(color: t.accent, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
          ),
          // Badge resumen: N unidades · $XXX
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$totalUnits unit${totalUnits != 1 ? 's' : ''}  ·  \$${totalEarned.toStringAsFixed(0)}',
              style: TextStyle(color: t.accent, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),

      // ── Fila por cada tipo de unidad ────────────────────────────────────────
      ...unitsByType.entries.map((entry) {
        final type  = entry.key;
        final holes = List<int>.from(entry.value)..sort();
        final count = holes.length;
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
              // Fila superior: icono + tipo + cantidad + monto
              Row(children: [
                Text(_icon(type), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(type.label,
                    style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                // Cantidad de veces
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('×$count',
                    style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 11)),
                ),
                const SizedBox(width: 8),
                // Monto ganado
                Text(
                  earned > 0 ? '+\$${earned.toStringAsFixed(0)}' : '\$0',
                  style: TextStyle(
                    color: earned > 0 ? t.profit : t.sub,
                    fontWeight: FontWeight.w800, fontSize: 13,
                  ),
                ),
              ]),
              // Chips de hoyos
              const SizedBox(height: 6),
              Wrap(spacing: 5, runSpacing: 4, children: holes.map((h) {
                final par = round.course.holes
                    .firstWhere((ch) => ch.hole == h, orElse: () => round.course.holes.first).par;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'H$h · P$par',
                    style: TextStyle(color: t.accent, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                );
              }).toList()),
            ]),
          ),
        );
      }),
    ]);
  }
}

// ── ResultsBody reutilizable (para historial) ─────────────────────────────────
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
    final round = widget.round;
    final balances = LedgerEngine.playerBalances(round);
    final netDebts = LedgerEngine.compute(round);
    final sortedPlayers = round.players.toList()
      ..sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GSectionHeader(title: 'BALANCE FINAL'),
        const SizedBox(height: 8),
        _BalanceSummaryCards(players: sortedPlayers, balances: balances, t: t),
        const SizedBox(height: 20),
        if (netDebts.isNotEmpty) ...[
          GSectionHeader(title: 'PAGOS A REALIZAR'),
          const SizedBox(height: 8),
          ...netDebts.map((d) => _PaymentCard(debt: d, round: round, t: t)),
          const SizedBox(height: 20),
        ],
        GSectionHeader(title: 'DETALLE POR JUGADOR'),
        const SizedBox(height: 8),
        ...sortedPlayers.map((p) => _PlayerDetailSection(
          player: p, round: round, t: t,
          isExpanded: _expandedPlayerId == p.id,
          onToggle: () => setState(() =>
            _expandedPlayerId = _expandedPlayerId == p.id ? null : p.id),
        )),
      ]),
    );
  }
}
