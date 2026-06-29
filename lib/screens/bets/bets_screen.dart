// ─────────────────────────────────────────────────────────────────────────────
// BETS SCREEN — Gestión colaborativa de apuestas agrupadas por duelo
//
// Modelo de permisos:
//   owner       → edita directamente; cambios se aplican en tiempo real
//   participant (open)  → puede proponer cambios; la contraparte debe aprobar
//   participant (admin) → solo lectura
//   outsider    → solo lectura
//
// Flujo de propuesta:
//   1. Participante abre "Proponer cambio" → rellena payload → llama proposeBetChange()
//   2. La otra parte ve _PendingProposalBanner con Aceptar/Rechazar
//   3. Aceptar → approveBetChange() → se aplica payload si hay quórum
//   4. Rechazar → rejectBetChange()
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../engines/bet_engine.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/bet_module_edit_sheet.dart';
import '../../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelo de permisos por duelo
// ─────────────────────────────────────────────────────────────────────────────
enum _Permission { owner, participantEditable, participantReadOnly, outsider }

class _DuelPermission {
  final _Permission level;
  const _DuelPermission(this.level);

  bool get canEdit       => level == _Permission.owner;
  bool get canPropose    => level == _Permission.participantEditable;
  bool get isReadOnly    => level == _Permission.participantReadOnly || level == _Permission.outsider;
  bool get isOutsider    => level == _Permission.outsider;

  String get bannerLabel {
    switch (level) {
      case _Permission.owner:               return '✏️ Puedes editar este duelo';
      case _Permission.participantEditable: return '💬 Puedes proponer cambios';
      case _Permission.participantReadOnly: return '👁 Solo lectura (modo admin)';
      case _Permission.outsider:            return '🔒 No participas en este duelo';
    }
  }

  Color bannerColor(GolfTheme t) {
    switch (level) {
      case _Permission.owner:               return t.primary;
      case _Permission.participantEditable: return t.accent;
      case _Permission.participantReadOnly: return t.sub;
      case _Permission.outsider:            return t.sub;
    }
  }
}

_DuelPermission _computePermission(RoundProvider prov, String p1Id, String p2Id) {
  if (prov.isLiveOwner) return const _DuelPermission(_Permission.owner);
  if (!prov.isLiveRound) return const _DuelPermission(_Permission.owner); // local: edit libre
  if (!prov.isParticipantInDuel(p1Id, p2Id)) {
    return const _DuelPermission(_Permission.outsider);
  }
  if (prov.round?.isAdminScoring ?? false) {
    return const _DuelPermission(_Permission.participantReadOnly);
  }
  return const _DuelPermission(_Permission.participantEditable);
}

// ─────────────────────────────────────────────────────────────────────────────
// Punto de entrada del tab
// ─────────────────────────────────────────────────────────────────────────────
class BetsScreen extends StatelessWidget {
  const BetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final t    = prov.theme;

    if (!prov.hasRound) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Center(
          child: Text('Sin ronda activa', style: TextStyle(color: t.sub)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: _BetsBody(prov: prov, t: t),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo interno: un duelo entre dos jugadores con sus apuestas
// ─────────────────────────────────────────────────────────────────────────────
class _DuelInfo {
  final Player p1;
  final Player p2;
  final List<_ModuleRef> modules;
  final double? manualStrokes;
  final double hcpDiff;

  const _DuelInfo({
    required this.p1,
    required this.p2,
    required this.modules,
    required this.manualStrokes,
    required this.hcpDiff,
  });

  String get handicapLabel {
    final s = (manualStrokes ?? hcpDiff).round();
    if (s == 0) return 'Igualados';
    final receiver = s > 0 ? p1.name.split(' ').first : p2.name.split(' ').first;
    final giver    = s > 0 ? p2.name.split(' ').first : p1.name.split(' ').first;
    return '$receiver recibe ${s.abs()} de $giver';
  }

  bool get hasManualOverride => manualStrokes != null;
}

class _ModuleRef {
  final BetGroup group;
  final BetModuleInstance module;
  const _ModuleRef({required this.group, required this.module});
}

// ─────────────────────────────────────────────────────────────────────────────
// Lógica de agrupación
// ─────────────────────────────────────────────────────────────────────────────
List<_DuelInfo> _buildDuels(Round round) {
  final activePlayers = round.players
      .where((p) => round.scores.containsKey(p.id))
      .toList();

  final duels = <String, _DuelInfo>{};
  for (int i = 0; i < activePlayers.length; i++) {
    for (int j = i + 1; j < activePlayers.length; j++) {
      final pA = activePlayers[i];
      final pB = activePlayers[j];
      final key = BetModuleInstance.pairKey(pA.id, pB.id);

      final rpA = round.roundPlayers.firstWhere(
        (r) => r.playerId == pA.id,
        orElse: () => RoundPlayer(playerId: pA.id, handicapEnRonda: 0),
      );
      final rpB = round.roundPlayers.firstWhere(
        (r) => r.playerId == pB.id,
        orElse: () => RoundPlayer(playerId: pB.id, handicapEnRonda: 0),
      );

      double? manual;
      if (rpA.manualHandicaps.containsKey(pB.id)) {
        manual = rpA.manualHandicaps[pB.id];
      } else if (rpB.manualHandicaps.containsKey(pA.id)) {
        manual = -(rpB.manualHandicaps[pA.id]!);
      }

      final canonical = BetEngine.canonicalSlidingBetween(round, pA.id, pB.id);
      if (manual == null && canonical != null) {
        manual = canonical;
      }

      final hcpA = round.getHandicap(pA.id);
      final hcpB = round.getHandicap(pB.id);

      duels[key] = _DuelInfo(
        p1: pA, p2: pB, modules: [],
        manualStrokes: manual, hcpDiff: hcpA - hcpB,
      );
    }
  }

  final duelModules = <String, List<_ModuleRef>>{};
  for (final g in round.betGroups) {
    for (final mod in g.modules) {
      final pids = mod.participantIds;
      if (pids.length == 2) {
        final k = BetModuleInstance.pairKey(pids[0], pids[1]);
        duelModules[k] = [...(duelModules[k] ?? []), _ModuleRef(group: g, module: mod)];
      } else {
        for (int i = 0; i < pids.length; i++) {
          for (int j = i + 1; j < pids.length; j++) {
            final k = BetModuleInstance.pairKey(pids[i], pids[j]);
            if (duels.containsKey(k)) {
              duelModules[k] = [...(duelModules[k] ?? []), _ModuleRef(group: g, module: mod)];
            }
          }
        }
      }
    }
  }

  return duels.entries.map((e) {
    final d = e.value;
    return _DuelInfo(
      p1: d.p1, p2: d.p2,
      modules: duelModules[e.key] ?? [],
      manualStrokes: d.manualStrokes, hcpDiff: d.hcpDiff,
    );
  }).toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// Body principal
// ─────────────────────────────────────────────────────────────────────────────
class _BetsBody extends StatelessWidget {
  final RoundProvider prov;
  final GolfTheme t;
  const _BetsBody({required this.prov, required this.t});

  @override
  Widget build(BuildContext context) {
    final round = prov.round!;
    final duels = _buildDuels(round);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _BetsHeader(round: round, prov: prov, t: t)),
        if (duels.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.paid_outlined, color: t.sub, size: 48),
                  const SizedBox(height: 12),
                  Text('No hay apuestas configuradas',
                      style: TextStyle(color: t.sub, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(
                    'Configura apuestas desde la pantalla de inicio',
                    style: TextStyle(color: t.sub.withValues(alpha: 0.6), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _DuelCard(
                  duel: duels[i], round: round, prov: prov, t: t,
                ),
                childCount: duels.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header de la pantalla
// ─────────────────────────────────────────────────────────────────────────────
class _BetsHeader extends StatelessWidget {
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  const _BetsHeader({required this.round, required this.prov, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('💰 Apuestas',
            style: TextStyle(color: t.text, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(round.name, style: TextStyle(color: t.sub, fontSize: 13)),
        // Banner de modo en rondas live
        if (round.isLive) ...[
          const SizedBox(height: 10),
          _LiveModeBanner(prov: prov, t: t),
        ],
        const SizedBox(height: 12),
        Row(children: [
          _QuickStat(
            icon: Icons.people_outline,
            label: '${round.players.where((p) => round.scores.containsKey(p.id)).length} jugadores',
            t: t,
          ),
          const SizedBox(width: 12),
          _QuickStat(icon: Icons.compare_arrows,
              label: '${_countDuels(round)} duelos', t: t),
          const SizedBox(width: 12),
          _QuickStat(icon: Icons.list_alt,
              label: '${_countModules(round)} apuestas', t: t),
        ]),
      ]),
    );
  }

  int _countDuels(Round r) {
    final active = r.players.where((p) => r.scores.containsKey(p.id)).toList();
    return active.length * (active.length - 1) ~/ 2;
  }
  int _countModules(Round r) => r.betGroups.fold(0, (s, g) => s + g.modules.length);
}

// Banner informativo del modo de la ronda live
class _LiveModeBanner extends StatelessWidget {
  final RoundProvider prov;
  final GolfTheme t;
  const _LiveModeBanner({required this.prov, required this.t});

  @override
  Widget build(BuildContext context) {
    final isOwner = prov.isLiveOwner;
    final isAdmin = prov.round?.isAdminScoring ?? false;
    final myPlayer = prov.myPlayerInRound;

    String label;
    Color color;
    IconData icon;

    if (isOwner) {
      label = 'Organizador · Puedes editar todas las apuestas';
      color = t.primary;
      icon  = Icons.manage_accounts_outlined;
    } else if (myPlayer == null) {
      label = 'Observador · Solo lectura';
      color = t.sub;
      icon  = Icons.visibility_outlined;
    } else if (isAdmin) {
      label = 'Modo admin · Solo el organizador edita';
      color = t.sub;
      icon  = Icons.lock_outline;
    } else {
      label = 'Puedes proponer cambios en tus duelos';
      color = t.accent;
      icon  = Icons.handshake_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final GolfTheme t;
  const _QuickStat({required this.icon, required this.label, required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: t.sub, size: 13),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: t.sub, fontSize: 11)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tarjeta de duelo
// ─────────────────────────────────────────────────────────────────────────────
class _DuelCard extends StatefulWidget {
  final _DuelInfo duel;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  const _DuelCard({
    required this.duel, required this.round,
    required this.prov, required this.t,
  });

  @override
  State<_DuelCard> createState() => _DuelCardState();
}

class _DuelCardState extends State<_DuelCard> {
  bool _expanded = true;

  GolfTheme get t => widget.t;

  @override
  Widget build(BuildContext context) {
    final duel  = widget.duel;
    final perm  = _computePermission(widget.prov, duel.p1.id, duel.p2.id);
    final proposals = widget.prov.pendingProposalsForDuel(duel.p1.id, duel.p2.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: proposals.isNotEmpty
              ? Colors.orange.withValues(alpha: 0.5)
              : t.divider,
          width: proposals.isNotEmpty ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DuelHeader(
            duel: duel, t: t, perm: perm,
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
            onEditHandicap: () => _openHandicapEdit(context, perm),
          ),

          // ── Banners de propuestas pendientes ─────────────────────────────
          if (proposals.isNotEmpty)
            ...proposals.map((pr) => _PendingProposalBanner(
              proposal: pr,
              round: widget.round,
              prov: widget.prov,
              t: t,
            )),

          if (_expanded) ...[
            const Divider(height: 1),
            _DuelBetsSection(
              duel: duel, round: widget.round,
              prov: widget.prov, t: t, perm: perm,
            ),
          ],
        ],
      ),
    );
  }

  void _openHandicapEdit(BuildContext context, _DuelPermission perm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _HandicapEditSheet(
        duel: widget.duel, round: widget.round,
        prov: widget.prov, t: t, perm: perm,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header del duelo
// ─────────────────────────────────────────────────────────────────────────────
class _DuelHeader extends StatelessWidget {
  final _DuelInfo duel;
  final GolfTheme t;
  final _DuelPermission perm;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onEditHandicap;
  const _DuelHeader({
    required this.duel, required this.t, required this.perm,
    required this.expanded, required this.onTap, required this.onEditHandicap,
  });

  @override
  Widget build(BuildContext context) {
    final p1 = duel.p1;
    final p2 = duel.p2;
    final hasApuestas = duel.modules.isNotEmpty;
    final tappableHandicap = !perm.isOutsider;

    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: [
          // Avatares apilados
          Stack(children: [
            GAvatar(name: p1.name, colorIndex: p1.colorIndex, size: 34),
            Positioned(
              left: 22,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.card, width: 1.5),
                ),
                child: GAvatar(name: p2.name, colorIndex: p2.colorIndex, size: 34),
              ),
            ),
          ]),
          const SizedBox(width: 28),

          // Nombres + ventaja
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${p1.name.split(' ').first} vs ${p2.name.split(' ').first}',
                style: TextStyle(
                    color: t.text, fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 2),
              // Ventaja: solo tappable si no es outsider
              GestureDetector(
                onTap: tappableHandicap ? onEditHandicap : null,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    duel.hasManualOverride ? Icons.tune : Icons.compare_arrows,
                    color: duel.hasManualOverride ? t.accent : t.sub,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    duel.handicapLabel,
                    style: TextStyle(
                      color: duel.hasManualOverride ? t.accent : t.sub,
                      fontSize: 11,
                      fontWeight: duel.hasManualOverride
                          ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  if (tappableHandicap) ...[
                    const SizedBox(width: 3),
                    Icon(
                      perm.canEdit ? Icons.edit_outlined : Icons.visibility_outlined,
                      color: (duel.hasManualOverride ? t.accent : t.sub)
                          .withValues(alpha: 0.6),
                      size: 10,
                    ),
                  ],
                ]),
              ),
            ]),
          ),

          // Badge permiso (solo en live)
          if (perm.isReadOnly)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: t.sub.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.lock_outline, color: t.sub, size: 11),
            ),

          // Badge cantidad apuestas
          if (hasApuestas)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${duel.modules.length}',
                style: TextStyle(
                    color: t.primary, fontWeight: FontWeight.w800, fontSize: 11),
              ),
            ),

          // Chevron
          Icon(
            expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: t.sub, size: 20,
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner de propuesta pendiente
// ─────────────────────────────────────────────────────────────────────────────
class _PendingProposalBanner extends StatelessWidget {
  final BetChangeProposal proposal;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  const _PendingProposalBanner({
    required this.proposal, required this.round,
    required this.prov, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.uid;
    final isMine = proposal.proposedByUid == uid;
    final canAct  = !isMine && !prov.isOutsiderForProposal(proposal);

    // Nombre del proponente
    final proposerPlayer = round.players
        .where((p) => p.id == proposal.proposedByPlayerId)
        .firstOrNull;
    final proposerName = proposerPlayer?.name.split(' ').first ?? 'Alguien';

    final summary = _proposalSummary(proposal);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(color: Colors.orange, width: 3),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.pending_outlined, color: Colors.orange, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isMine
                  ? 'Cambio pendiente de aprobación'
                  : '$proposerName propone un cambio',
              style: TextStyle(
                  color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(summary, style: TextStyle(color: t.sub, fontSize: 11)),

        if (canAct) ...[
          const SizedBox(height: 8),
          Row(children: [
            // Botón Rechazar
            Expanded(
              child: OutlinedButton(
                onPressed: () => prov.rejectBetChange(proposal.id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.loss,
                  side: BorderSide(color: t.loss.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Rechazar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            // Botón Aceptar
            Expanded(
              child: ElevatedButton(
                onPressed: () => prov.approveBetChange(proposal.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: t.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: const Size(0, 32),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Aceptar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],

        if (isMine)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Esperando aprobación de la contraparte…',
              style: TextStyle(
                  color: t.sub.withValues(alpha: 0.7), fontSize: 10),
            ),
          ),
      ]),
    );
  }

  String _proposalSummary(BetChangeProposal p) {
    switch (p.changeType) {
      case 'handicap':
        final strokes = p.payload['manualStrokes'];
        final rcv     = p.payload['p1ReceivesFrom'];
        final rcvName = round.players
            .where((pl) => pl.id == rcv)
            .firstOrNull?.name.split(' ').first ?? rcv ?? '?';
        return 'Ventaja: $rcvName recibe $strokes strokes';
      case 'amount':
        final entries = p.payload.entries
            .where((e) => e.key != 'moduleId')
            .map((e) => '${e.key}: ${e.value}')
            .join(', ');
        return 'Cambio de monto: $entries';
      case 'mode':
        return 'Cambio de modo: ${p.payload['mode'] ?? ''}';
      case 'rules':
        return 'Cambio de reglas';
      default:
        return 'Cambio propuesto';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sección de apuestas dentro de la tarjeta
// ─────────────────────────────────────────────────────────────────────────────
class _DuelBetsSection extends StatelessWidget {
  final _DuelInfo duel;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  final _DuelPermission perm;
  const _DuelBetsSection({
    required this.duel, required this.round,
    required this.prov, required this.t, required this.perm,
  });

  @override
  Widget build(BuildContext context) {
    final modules = duel.modules;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Banner de permisos en rondas live ─────────────────────────────
          if (prov.isLiveRound && !perm.canEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PermissionBadge(perm: perm, t: t),
            ),

          // ── Filas de apuestas ─────────────────────────────────────────────
          if (modules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Sin apuestas en este duelo',
                  style: TextStyle(color: t.sub, fontSize: 12)),
            )
          else
            ...modules.map((ref) => _BetRow(
              ref: ref, duel: duel, round: round,
              prov: prov, t: t, perm: perm,
            )),

          const SizedBox(height: 6),

          // ── Botón añadir apuesta (solo si puede editar) ───────────────────
          if (perm.canEdit)
            GestureDetector(
              onTap: () => _openAddBet(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: t.accent.withValues(alpha: 0.30),
                  ),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add, color: t.accent, size: 14),
                  const SizedBox(width: 6),
                  Text('Añadir apuesta a este duelo',
                      style: TextStyle(
                          color: t.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  void _openAddBet(BuildContext context) {
    BetGroup? existingGroup;
    for (final g in round.betGroups) {
      if (g.playerIds.contains(duel.p1.id) && g.playerIds.contains(duel.p2.id)) {
        existingGroup = g;
        break;
      }
    }

    final group = existingGroup ?? BetGroup(
      id: 'group_${duel.p1.id}_${duel.p2.id}_${DateTime.now().millisecondsSinceEpoch}',
      name: '${duel.p1.name.split(' ').first} vs ${duel.p2.name.split(' ').first}',
      format: PartidaFormat.allInOnePot,
      playerIds: [duel.p1.id, duel.p2.id],
      modules: [],
    );

    final newMod = BetModuleInstance(
      id: 'mod_${DateTime.now().millisecondsSinceEpoch}',
      type: BetModuleType.skins,
      name: BetModuleType.skins.label,
      participantIds: [duel.p1.id, duel.p2.id],
      skinsConfig: SkinsConfig.def,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => BetModuleEditSheet(
        group: group, mod: newMod, t: t,
        courseInfo: round.course, players: round.players,
        onSave: (saved) {
          Navigator.pop(ctx);
          if (existingGroup == null) {
            prov.updateBetGroups([...round.betGroups, group.copyWith(modules: [saved])]);
          } else {
            prov.updateBetModule(group.id, saved);
          }
        },
      ),
    );
  }
}

// Pequeño badge de permiso dentro de la sección de apuestas
class _PermissionBadge extends StatelessWidget {
  final _DuelPermission perm;
  final GolfTheme t;
  const _PermissionBadge({required this.perm, required this.t});

  @override
  Widget build(BuildContext context) {
    final color = perm.bannerColor(t);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          perm.isOutsider ? Icons.block_outlined
              : perm.canPropose ? Icons.handshake_outlined
              : Icons.lock_outline,
          color: color, size: 12,
        ),
        const SizedBox(width: 5),
        Text(perm.bannerLabel,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fila individual de una apuesta
// ─────────────────────────────────────────────────────────────────────────────
class _BetRow extends StatelessWidget {
  final _ModuleRef ref;
  final _DuelInfo duel;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  final _DuelPermission perm;
  const _BetRow({
    required this.ref, required this.duel, required this.round,
    required this.prov, required this.t, required this.perm,
  });

  BetGroup get group => ref.group;
  BetModuleInstance get mod => ref.module;

  @override
  Widget build(BuildContext context) {
    final isMatch = mod.type == BetModuleType.nassau ||
        mod.type == BetModuleType.matchAutoPress;
    final accentColor = isMatch ? t.accent : t.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        Text(mod.type.icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _buildLabel(),
              style: TextStyle(
                  color: t.text, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Wrap(spacing: 6, children: [
              if (_modeLabel() != null)
                _MiniChip(label: _modeLabel()!, color: accentColor, t: t),
              if (_statusLabel() != null)
                _StatusChip(label: _statusLabel()!, status: mod.status, t: t),
              // Chip "Solo lectura" si está en modo read-only
              if (perm.isReadOnly)
                _MiniChip(label: '🔒 Solo lectura', color: t.sub, t: t),
            ]),
          ]),
        ),

        // ── Acciones según permisos ────────────────────────────────────────
        if (perm.canEdit) ...[
          // Owner: editar + eliminar
          _ActionBtn(
            icon: Icons.edit_outlined, color: accentColor,
            onTap: () => _openEdit(context),
          ),
          const SizedBox(width: 6),
          _ActionBtn(
            icon: Icons.delete_outline, color: t.loss,
            onTap: () => _confirmDelete(context),
          ),
        ] else if (perm.canPropose) ...[
          // Participante en modo open: proponer cambio
          GestureDetector(
            onTap: () => _openProposeChange(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.accent.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_note_outlined, color: t.accent, size: 13),
                const SizedBox(width: 4),
                Text('Proponer',
                    style: TextStyle(
                        color: t.accent, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
        // outsider: sin botones
      ]),
    );
  }

  String _buildLabel() {
    final label = mod.type.label;
    switch (mod.type) {
      case BetModuleType.skins:
        return '$label · \$${mod.skins.valuePerSkin.toStringAsFixed(0)}/skin';
      case BetModuleType.nassau:
        final n = mod.nassau;
        final pressTag = n.pressEnabled ? ' + Press' : '';
        return '$label$pressTag · F\$${n.frontValue.toStringAsFixed(0)} B\$${n.backValue.toStringAsFixed(0)} T\$${n.totalValue.toStringAsFixed(0)}';
      case BetModuleType.matchAutoPress:
        return '$label · \$${mod.matchAutoPress.matchValue.toStringAsFixed(0)}';
      case BetModuleType.medal:
        return '$label · \$${mod.medal.value.toStringAsFixed(0)}';
      case BetModuleType.putts:
        return '$label · \$${mod.putts.value.toStringAsFixed(0)}/putt';
      case BetModuleType.oyeses:
        return '$label · \$${mod.oyeses.value.toStringAsFixed(0)}/oyés';
      case BetModuleType.units:
        final rv = mod.units.representativeValue;
        return '$label · \$${rv.toStringAsFixed(0)}/u';
    }
  }

  String? _modeLabel() {
    switch (mod.type) {
      case BetModuleType.skins:
        return mod.skins.mode == GrossNetMode.gross ? 'Gross' : 'Net';
      case BetModuleType.nassau:
        return mod.nassau.mode == GrossNetMode.gross ? 'Gross' : 'Net';
      case BetModuleType.matchAutoPress:
        return mod.matchAutoPress.mode == GrossNetMode.gross ? 'Gross' : 'Net';
      case BetModuleType.medal:
        return mod.medal.mode == GrossNetMode.gross ? 'Gross' : 'Net';
      case BetModuleType.putts:
      case BetModuleType.oyeses:
      case BetModuleType.units:
        return null;
    }
  }

  String? _statusLabel() {
    switch (mod.status) {
      case BetModuleStatus.active:      return null;
      case BetModuleStatus.closed:      return 'Finalizada';
      case BetModuleStatus.draft:       return 'Borrador';
      case BetModuleStatus.configured:  return null;
    }
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => BetModuleEditSheet(
        group: group, mod: mod, t: t,
        courseInfo: round.course, players: round.players,
        onSave: (saved) {
          Navigator.pop(ctx);
          prov.updateBetModule(group.id, saved);
        },
      ),
    );
  }

  void _openProposeChange(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ProposeBetChangeSheet(
        duel: duel, mod: mod, group: group,
        prov: prov, round: round, t: t,
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Text('Eliminar apuesta',
            style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        content: Text('¿Eliminar ${mod.type.label} de este duelo?',
            style: TextStyle(color: t.sub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: t.sub)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              prov.removeBetModule(group.id, mod.id);
            },
            child: Text('Eliminar',
                style: TextStyle(color: t.loss, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// Botón de acción reutilizable
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 14),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet: proponer un cambio de apuesta
// ─────────────────────────────────────────────────────────────────────────────
class _ProposeBetChangeSheet extends StatefulWidget {
  final _DuelInfo duel;
  final BetModuleInstance mod;
  final BetGroup group;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  const _ProposeBetChangeSheet({
    required this.duel, required this.mod, required this.group,
    required this.round, required this.prov, required this.t,
  });

  @override
  State<_ProposeBetChangeSheet> createState() => _ProposeBetChangeSheetState();
}

class _ProposeBetChangeSheetState extends State<_ProposeBetChangeSheet> {
  final _amountCtrl = TextEditingController();

  GolfTheme get t => widget.t;
  BetModuleInstance get mod => widget.mod;

  @override
  void initState() {
    super.initState();
    // Pre-rellenar con el valor actual
    final curVal = _currentValue();
    _amountCtrl.text = curVal.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double _currentValue() {
    switch (mod.type) {
      case BetModuleType.skins:        return mod.skins.valuePerSkin;
      case BetModuleType.nassau:       return mod.nassau.frontValue;
      case BetModuleType.matchAutoPress: return mod.matchAutoPress.matchValue;
      case BetModuleType.medal:        return mod.medal.value;
      case BetModuleType.putts:        return mod.putts.value;
      case BetModuleType.oyeses:       return mod.oyeses.value;
      case BetModuleType.units:        return mod.units.representativeValue;
    }
  }

  Map<String, dynamic> _buildPayload() {
    final newVal = double.tryParse(_amountCtrl.text) ?? _currentValue();
    switch (mod.type) {
      case BetModuleType.skins:        return {'valuePerSkin': newVal};
      case BetModuleType.nassau:       return {'nassauFront': newVal, 'nassauBack': newVal, 'nassauTotal': newVal * 2};
      case BetModuleType.matchAutoPress: return {'matchValue': newVal};
      case BetModuleType.medal:        return {'valuePerStroke': newVal};
      case BetModuleType.putts:        return {'valuePerPutt': newVal};
      case BetModuleType.oyeses:       return {'value': newVal};
      case BetModuleType.units:        return {'value': newVal};
    }
  }

  @override
  Widget build(BuildContext context) {
    final p1Name = widget.duel.p1.name.split(' ').first;
    final p2Name = widget.duel.p2.name.split(' ').first;
    final myUid = AuthService.uid ?? '';
    final myPlayer = widget.prov.myPlayerInRound;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Proponer cambio',
                      style: TextStyle(
                          color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('${mod.type.label} · $p1Name vs $p2Name',
                      style: TextStyle(color: t.sub, fontSize: 12)),
                ]),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, color: t.sub),
              ),
            ]),
            const SizedBox(height: 20),

            // Info: requiere aprobación
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.accent.withValues(alpha: 0.22)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: t.accent, size: 13),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'El otro jugador deberá aprobar el cambio para que tenga efecto.',
                    style: TextStyle(color: t.accent, fontSize: 11),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // Nuevo valor
            Text('Nuevo valor (\$)',
                style: TextStyle(
                    color: t.sub, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              _StepBtn(
                icon: Icons.remove, t: t,
                onTap: () {
                  final v = double.tryParse(_amountCtrl.text) ?? 0;
                  if (v > 0) setState(() => _amountCtrl.text = '${(v - 5).round()}');
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: t.text, fontSize: 22, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      filled: true, fillColor: t.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: t.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: t.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: t.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              _StepBtn(
                icon: Icons.add, t: t,
                onTap: () {
                  final v = double.tryParse(_amountCtrl.text) ?? 0;
                  setState(() => _amountCtrl.text = '${(v + 5).round()}');
                },
              ),
            ]),
            const SizedBox(height: 24),

            // Botón enviar propuesta
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: myPlayer == null ? null : () {
                  final proposal = BetChangeProposal(
                    id: 'prop_${DateTime.now().millisecondsSinceEpoch}',
                    groupId: widget.group.id,
                    moduleId: mod.id,
                    p1Id: widget.duel.p1.id,
                    p2Id: widget.duel.p2.id,
                    proposedByUid: myUid,
                    proposedByPlayerId: myPlayer.id,
                    payload: _buildPayload(),
                    changeType: 'amount',
                    createdAt: DateTime.now().toIso8601String(),
                  );
                  widget.prov.proposeBetChange(proposal);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Propuesta enviada. Esperando aprobación.'),
                      backgroundColor: t.primary,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: t.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  elevation: 0,
                ),
                child: const Text('Enviar propuesta de cambio',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final GolfTheme t;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.divider),
        ),
        child: Icon(icon, color: t.text, size: 20),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chips de estado y modo
// ─────────────────────────────────────────────────────────────────────────────
class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  final GolfTheme t;
  const _MiniChip({required this.label, required this.color, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final BetModuleStatus status;
  final GolfTheme t;
  const _StatusChip(
      {required this.label, required this.status, required this.t});

  @override
  Widget build(BuildContext context) {
    final color = status == BetModuleStatus.closed ? t.sub : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet: editar ventaja del duelo (con permisos)
// ─────────────────────────────────────────────────────────────────────────────
class _HandicapEditSheet extends StatefulWidget {
  final _DuelInfo duel;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  final _DuelPermission perm;
  const _HandicapEditSheet({
    required this.duel, required this.round,
    required this.prov, required this.t, required this.perm,
  });

  @override
  State<_HandicapEditSheet> createState() => _HandicapEditSheetState();
}

class _HandicapEditSheetState extends State<_HandicapEditSheet> {
  late TextEditingController _ctrl;
  late bool _p1Receives;

  GolfTheme get t => widget.t;
  _DuelInfo get duel => widget.duel;
  _DuelPermission get perm => widget.perm;

  @override
  void initState() {
    super.initState();
    final s = duel.manualStrokes ?? duel.hcpDiff;
    _p1Receives = s >= 0;
    _ctrl = TextEditingController(text: s.abs().round().toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p1Name = duel.p1.name.split(' ').first;
    final p2Name = duel.p2.name.split(' ').first;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Expanded(
                child: Text('Ventaja del duelo',
                    style: TextStyle(
                        color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, color: t.sub),
              ),
            ]),
            const SizedBox(height: 4),
            Text('$p1Name vs $p2Name',
                style: TextStyle(color: t.sub, fontSize: 13)),
            const SizedBox(height: 12),

            // Banner si solo lectura
            if (perm.isReadOnly || perm.canPropose)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (perm.isOutsider ? t.sub : t.accent)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (perm.isOutsider ? t.sub : t.accent)
                          .withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      perm.isReadOnly ? Icons.lock_outline : Icons.handshake_outlined,
                      color: perm.isOutsider ? t.sub : t.accent,
                      size: 13,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        perm.isReadOnly
                            ? 'No tienes permiso para modificar esta ventaja.'
                            : 'Tu cambio requerirá la aprobación de la contraparte.',
                        style: TextStyle(
                          color: perm.isOutsider ? t.sub : t.accent,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),

            // HCP automático
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.divider),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: t.sub, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'HCP automático: ${_hcpAutoLabel(p1Name, p2Name)}',
                    style: TextStyle(color: t.sub, fontSize: 12),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Editor (bloqueado si no tiene permisos)
            if (!perm.isReadOnly) ...[
              Text('¿Quién recibe strokes?',
                  style: TextStyle(
                      color: t.sub, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _ToggleOption(
                    label: p1Name, selected: _p1Receives,
                    avatar: GAvatar(
                        name: duel.p1.name,
                        colorIndex: duel.p1.colorIndex, size: 28),
                    t: t,
                    onTap: () => setState(() => _p1Receives = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ToggleOption(
                    label: p2Name, selected: !_p1Receives,
                    avatar: GAvatar(
                        name: duel.p2.name,
                        colorIndex: duel.p2.colorIndex, size: 28),
                    t: t,
                    onTap: () => setState(() => _p1Receives = false),
                  ),
                ),
              ]),
              const SizedBox(height: 16),

              Text('Strokes',
                  style: TextStyle(
                      color: t.sub, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                _StepBtn(
                  icon: Icons.remove, t: t,
                  onTap: () {
                    final v = int.tryParse(_ctrl.text) ?? 0;
                    if (v > 0) setState(() => _ctrl.text = '${v - 1}');
                  },
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: TextField(
                      controller: _ctrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: t.text, fontSize: 24, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        filled: true, fillColor: t.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: t.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: t.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: t.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                _StepBtn(
                  icon: Icons.add, t: t,
                  onTap: () {
                    final v = int.tryParse(_ctrl.text) ?? 0;
                    setState(() => _ctrl.text = '${v + 1}');
                  },
                ),
              ]),
              const SizedBox(height: 24),

              // Botones de acción
              Row(children: [
                if (duel.hasManualOverride && perm.canEdit)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.prov
                            .updateManualHandicap(duel.p1.id, duel.p2.id, null);
                        widget.prov
                            .updateManualHandicap(duel.p2.id, duel.p1.id, null);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: t.sub,
                        side: BorderSide(color: t.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Usar HCP auto'),
                    ),
                  ),
                if (duel.hasManualOverride && perm.canEdit)
                  const SizedBox(width: 10),

                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: perm.canEdit ? _saveHandicap : _proposeHandicap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: perm.canEdit ? t.primary : t.accent,
                      foregroundColor: t.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      elevation: 0,
                    ),
                    child: Text(
                      perm.canEdit ? 'Guardar ventaja' : 'Proponer cambio',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ]),
            ] else
              // Sólo lectura: mostrar valor actual sin edición
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.divider),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.compare_arrows,
                        color: duel.hasManualOverride ? t.accent : t.sub,
                        size: 18),
                    const SizedBox(width: 10),
                    Text(
                      duel.handicapLabel,
                      style: TextStyle(
                        color: duel.hasManualOverride ? t.accent : t.text,
                        fontSize: 15, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _hcpAutoLabel(String p1Name, String p2Name) {
    final diff = duel.hcpDiff.round();
    if (diff == 0) return '$p1Name y $p2Name igualados';
    final receiver = diff > 0 ? p1Name : p2Name;
    final giver    = diff > 0 ? p2Name : p1Name;
    return '$receiver recibe ${diff.abs()} de $giver';
  }

  void _saveHandicap() {
    Navigator.pop(context);
    final strokes = (double.tryParse(_ctrl.text) ?? 0).abs();
    final val = _p1Receives ? strokes : -strokes;
    widget.prov.updateManualHandicap(duel.p1.id, duel.p2.id, val);
    widget.prov.updateManualHandicap(duel.p2.id, duel.p1.id, null);
  }

  void _proposeHandicap() {
    final myUid    = AuthService.uid ?? '';
    final myPlayer = widget.prov.myPlayerInRound;
    if (myPlayer == null) return;

    final strokes = (double.tryParse(_ctrl.text) ?? 0).abs();
    final receiverId = _p1Receives ? duel.p1.id : duel.p2.id;

    final proposal = BetChangeProposal(
      id: 'prop_hcp_${DateTime.now().millisecondsSinceEpoch}',
      groupId: '',   // ventaja del duelo, no de un grupo específico
      moduleId: null,
      p1Id: duel.p1.id,
      p2Id: duel.p2.id,
      proposedByUid: myUid,
      proposedByPlayerId: myPlayer.id,
      payload: {
        'manualStrokes': strokes,
        'p1ReceivesFrom': receiverId,
      },
      changeType: 'handicap',
      createdAt: DateTime.now().toIso8601String(),
    );

    widget.prov.proposeBetChange(proposal);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Propuesta de ventaja enviada.'),
        backgroundColor: t.accent,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool selected;
  final Widget avatar;
  final GolfTheme t;
  final VoidCallback onTap;
  const _ToggleOption({
    required this.label, required this.selected,
    required this.avatar, required this.t, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? t.primary.withValues(alpha: 0.12) : t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? t.primary : t.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          avatar,
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: selected ? t.primary : t.text,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              fontSize: 13,
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 6),
            Icon(Icons.check_circle, color: t.primary, size: 14),
          ],
        ]),
      ),
    );
  }
}
