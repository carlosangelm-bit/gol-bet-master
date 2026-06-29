// ─────────────────────────────────────────────────────────────────────────────
// BETS SCREEN — Gestión de apuestas agrupadas por duelo
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../engines/bet_engine.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/bet_module_edit_sheet.dart';

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
  /// Módulos que involucran exactamente a este par (participantIds contiene ambos IDs).
  final List<_ModuleRef> modules;
  /// Ventaja: cuántos strokes recibe p1 de p2.
  /// positivo = p1 recibe; negativo = p2 recibe; null = usa diff de HCP.
  final double? manualStrokes;
  final double hcpDiff; // p1HCP - p2HCP redondeado

  const _DuelInfo({
    required this.p1,
    required this.p2,
    required this.modules,
    required this.manualStrokes,
    required this.hcpDiff,
  });

  /// Descripción legible de la ventaja
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
// Lógica de agrupación: deriva los duelos desde los BetGroups
// ─────────────────────────────────────────────────────────────────────────────
List<_DuelInfo> _buildDuels(Round round) {
  final activePlayers = round.players
      .where((p) => round.scores.containsKey(p.id))
      .toList();

  // Generar todos los pares únicos
  final duels = <String, _DuelInfo>{};
  for (int i = 0; i < activePlayers.length; i++) {
    for (int j = i + 1; j < activePlayers.length; j++) {
      final pA = activePlayers[i];
      final pB = activePlayers[j];
      final key = BetModuleInstance.pairKey(pA.id, pB.id);

      // Ventaja manual (buscamos en los RoundPlayers de ambos)
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
        // rpB tiene manual hacia pA → p1 da a p2 → negativo desde perspectiva p1
        manual = -(rpB.manualHandicaps[pA.id]!);
      }

      // También revisar pairSliding canónico
      final canonical = BetEngine.canonicalSlidingBetween(round, pA.id, pB.id);
      if (manual == null && canonical != null) {
        manual = canonical;
      }

      final hcpA = round.getHandicap(pA.id);
      final hcpB = round.getHandicap(pB.id);

      duels[key] = _DuelInfo(
        p1: pA,
        p2: pB,
        modules: [],
        manualStrokes: manual,
        hcpDiff: hcpA - hcpB,
      );
    }
  }

  // Asignar módulos a los duelos
  final duelModules = <String, List<_ModuleRef>>{};
  for (final g in round.betGroups) {
    for (final mod in g.modules) {
      final pids = mod.participantIds;
      if (pids.length == 2) {
        final k = BetModuleInstance.pairKey(pids[0], pids[1]);
        duelModules[k] = [...(duelModules[k] ?? []), _ModuleRef(group: g, module: mod)];
      } else {
        // Módulo de grupo (más de 2 participantes): asignarlo a todos los pares
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

  // Reconstruir con los módulos asignados
  return duels.entries.map((e) {
    final d = e.value;
    return _DuelInfo(
      p1: d.p1,
      p2: d.p2,
      modules: duelModules[e.key] ?? [],
      manualStrokes: d.manualStrokes,
      hcpDiff: d.hcpDiff,
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
        // ── Header ──────────────────────────────────────────────────────────
        SliverToBoxAdapter(child: _BetsHeader(round: round, t: t)),

        // ── Lista de duelos ──────────────────────────────────────────────────
        if (duels.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.paid_outlined, color: t.sub, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No hay apuestas configuradas',
                    style: TextStyle(color: t.sub, fontSize: 15),
                  ),
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
                  duel: duels[i],
                  round: round,
                  prov: prov,
                  t: t,
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
  final GolfTheme t;
  const _BetsHeader({required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '💰 Apuestas',
          style: TextStyle(
            color: t.text,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          round.name,
          style: TextStyle(color: t.sub, fontSize: 13),
        ),
        const SizedBox(height: 12),
        // Resumen rápido
        Row(children: [
          _QuickStat(
            icon: Icons.people_outline,
            label: '${round.players.where((p) => round.scores.containsKey(p.id)).length} jugadores',
            t: t,
          ),
          const SizedBox(width: 12),
          _QuickStat(
            icon: Icons.compare_arrows,
            label: '${_countDuels(round)} duelos',
            t: t,
          ),
          const SizedBox(width: 12),
          _QuickStat(
            icon: Icons.list_alt,
            label: '${_countModules(round)} apuestas',
            t: t,
          ),
        ]),
      ]),
    );
  }

  int _countDuels(Round round) {
    final active = round.players.where((p) => round.scores.containsKey(p.id)).toList();
    return active.length * (active.length - 1) ~/ 2;
  }

  int _countModules(Round round) =>
      round.betGroups.fold(0, (s, g) => s + g.modules.length);
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
    final duel = widget.duel;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header del duelo ─────────────────────────────────────────────
          _DuelHeader(
            duel: duel,
            t: t,
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
            onEditHandicap: () => _openHandicapEdit(context),
          ),

          // ── Contenido expandible ─────────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1),
            _DuelBetsSection(
              duel: duel,
              round: widget.round,
              prov: widget.prov,
              t: t,
            ),
          ],
        ],
      ),
    );
  }

  void _openHandicapEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _HandicapEditSheet(
        duel: widget.duel,
        round: widget.round,
        prov: widget.prov,
        t: t,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header interno de una tarjeta de duelo
// ─────────────────────────────────────────────────────────────────────────────
class _DuelHeader extends StatelessWidget {
  final _DuelInfo duel;
  final GolfTheme t;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onEditHandicap;
  const _DuelHeader({
    required this.duel,
    required this.t,
    required this.expanded,
    required this.onTap,
    required this.onEditHandicap,
  });

  @override
  Widget build(BuildContext context) {
    final p1 = duel.p1;
    final p2 = duel.p2;
    final hasApuestas = duel.modules.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: [
          // Avatares
          Stack(
            children: [
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
            ],
          ),
          const SizedBox(width: 28),
          // Nombres y ventaja
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${p1.name.split(' ').first} vs ${p2.name.split(' ').first}',
                style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: onEditHandicap,
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
                      fontWeight: duel.hasManualOverride ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.edit_outlined,
                      color: (duel.hasManualOverride ? t.accent : t.sub).withValues(alpha: 0.6),
                      size: 10),
                ]),
              ),
            ]),
          ),
          // Badge de cantidad de apuestas
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
                  color: t.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          // Chevron
          Icon(
            expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            color: t.sub,
            size: 20,
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sección de apuestas dentro de la tarjeta de duelo
// ─────────────────────────────────────────────────────────────────────────────
class _DuelBetsSection extends StatelessWidget {
  final _DuelInfo duel;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  const _DuelBetsSection({
    required this.duel, required this.round,
    required this.prov, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final modules = duel.modules;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Filas de apuestas ─────────────────────────────────────────────
          if (modules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Sin apuestas en este duelo',
                style: TextStyle(color: t.sub, fontSize: 12),
              ),
            )
          else
            ...modules.map((ref) => _BetRow(
              ref: ref,
              duel: duel,
              round: round,
              prov: prov,
              t: t,
            )),

          const SizedBox(height: 6),
          // ── Botón añadir apuesta ──────────────────────────────────────────
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
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add, color: t.accent, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Añadir apuesta a este duelo',
                  style: TextStyle(
                    color: t.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // Abrir selector de tipo de apuesta + editor
  void _openAddBet(BuildContext context) {
    // Encontrar o crear un BetGroup que contenga a estos dos jugadores
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

    // Nuevo módulo vacío tipo Skins como punto de partida
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => BetModuleEditSheet(
        group: group,
        mod: newMod,
        t: t,
        courseInfo: round.course,
        players: round.players,
        onSave: (saved) {
          Navigator.pop(ctx);
          // Si el grupo era nuevo, añadirlo con el módulo
          if (existingGroup == null) {
            final newGroups = [...round.betGroups, group.copyWith(modules: [saved])];
            prov.updateBetGroups(newGroups);
          } else {
            prov.updateBetModule(group.id, saved);
          }
        },
      ),
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
  const _BetRow({
    required this.ref, required this.duel,
    required this.round, required this.prov, required this.t,
  });

  BetGroup get group => ref.group;
  BetModuleInstance get mod => ref.module;

  @override
  Widget build(BuildContext context) {
    final isMatch = mod.type == BetModuleType.nassau || mod.type == BetModuleType.matchAutoPress;
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
        // Ícono
        Text(mod.type.icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        // Descripción
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Tipo + valor
            Text(
              _buildLabel(),
              style: TextStyle(
                color: t.text,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            // Modo gross/net + ventaja si aplica
            Wrap(spacing: 6, children: [
              if (_modeLabel() != null)
                _MiniChip(label: _modeLabel()!, color: accentColor, t: t),
              if (_statusLabel() != null)
                _StatusChip(label: _statusLabel()!, status: mod.status, t: t),
            ]),
          ]),
        ),
        // Botón editar
        GestureDetector(
          onTap: () => _openEdit(context),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.edit_outlined, color: accentColor, size: 14),
          ),
        ),
        const SizedBox(width: 6),
        // Botón eliminar
        GestureDetector(
          onTap: () => _confirmDelete(context),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.loss.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.delete_outline, color: t.loss, size: 14),
          ),
        ),
      ]),
    );
  }

  // Construye la etiqueta de tipo + valores
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
        final m = mod.matchAutoPress;
        return '$label · \$${m.matchValue.toStringAsFixed(0)}';
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
      case BetModuleStatus.active:   return null; // no mostrar chip si está activa (default)
      case BetModuleStatus.closed:   return 'Finalizada';
      case BetModuleStatus.draft:    return 'Borrador';
      case BetModuleStatus.configured: return null;
    }
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => BetModuleEditSheet(
        group: group,
        mod: mod,
        t: t,
        courseInfo: round.course,
        players: round.players,
        onSave: (saved) {
          Navigator.pop(ctx);
          prov.updateBetModule(group.id, saved);
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Text(
          'Eliminar apuesta',
          style: TextStyle(color: t.text, fontWeight: FontWeight.w800),
        ),
        content: Text(
          '¿Eliminar ${mod.type.label} de este duelo?',
          style: TextStyle(color: t.sub),
        ),
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
            child: Text(
              'Eliminar',
              style: TextStyle(color: t.loss, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final BetModuleStatus status;
  final GolfTheme t;
  const _StatusChip({required this.label, required this.status, required this.t});

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
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet: editar ventaja de un duelo
// ─────────────────────────────────────────────────────────────────────────────
class _HandicapEditSheet extends StatefulWidget {
  final _DuelInfo duel;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  const _HandicapEditSheet({
    required this.duel, required this.round,
    required this.prov, required this.t,
  });

  @override
  State<_HandicapEditSheet> createState() => _HandicapEditSheetState();
}

class _HandicapEditSheetState extends State<_HandicapEditSheet> {
  late TextEditingController _ctrl;
  // true = p1 recibe de p2, false = p2 recibe de p1
  late bool _p1Receives;

  GolfTheme get t => widget.t;
  _DuelInfo get duel => widget.duel;

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
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Expanded(
                child: Text(
                  'Ventaja del duelo',
                  style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, color: t.sub),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              '$p1Name vs $p2Name',
              style: TextStyle(color: t.sub, fontSize: 13),
            ),
            const SizedBox(height: 20),

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

            // Quién recibe
            Text('¿Quién recibe strokes?',
                style: TextStyle(color: t.sub, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _ToggleOption(
                  label: p1Name,
                  selected: _p1Receives,
                  avatar: GAvatar(name: duel.p1.name, colorIndex: duel.p1.colorIndex, size: 28),
                  t: t,
                  onTap: () => setState(() => _p1Receives = true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToggleOption(
                  label: p2Name,
                  selected: !_p1Receives,
                  avatar: GAvatar(name: duel.p2.name, colorIndex: duel.p2.colorIndex, size: 28),
                  t: t,
                  onTap: () => setState(() => _p1Receives = false),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // Cantidad de strokes
            Text('Strokes',
                style: TextStyle(color: t.sub, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              GestureDetector(
                onTap: () {
                  final v = int.tryParse(_ctrl.text) ?? 0;
                  if (v > 0) _ctrl.text = '${v - 1}';
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.divider),
                  ),
                  child: Icon(Icons.remove, color: t.text, size: 20),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: t.surface,
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
              GestureDetector(
                onTap: () {
                  final v = int.tryParse(_ctrl.text) ?? 0;
                  _ctrl.text = '${v + 1}';
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.divider),
                  ),
                  child: Icon(Icons.add, color: t.text, size: 20),
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // Botones
            Row(children: [
              // Quitar override
              if (duel.hasManualOverride)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // Quitar overrides de ambos jugadores
                      widget.prov.updateManualHandicap(duel.p1.id, duel.p2.id, null);
                      widget.prov.updateManualHandicap(duel.p2.id, duel.p1.id, null);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.sub,
                      side: BorderSide(color: t.divider),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Usar HCP auto'),
                  ),
                ),
              if (duel.hasManualOverride) const SizedBox(width: 10),
              // Guardar
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: t.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                  ),
                  child: const Text('Guardar ventaja',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
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

  void _save() {
    Navigator.pop(context);
    final strokes = (double.tryParse(_ctrl.text) ?? 0).abs();
    // p1Receives → p1 recibe de p2 → guardamos en rpA.manualHandicaps[p2.id] = strokes
    // !p1Receives → p2 recibe de p1 → guardamos en rpA.manualHandicaps[p2.id] = -strokes
    final val = _p1Receives ? strokes : -strokes;
    widget.prov.updateManualHandicap(duel.p1.id, duel.p2.id, val);
    // Limpiar el sentido inverso para evitar contradicción
    widget.prov.updateManualHandicap(duel.p2.id, duel.p1.id, null);
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
