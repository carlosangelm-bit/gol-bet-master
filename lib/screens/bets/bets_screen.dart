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
import '../../engines/ledger_engine.dart';
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

// ═════════════════════════════════════════════════════════════════════════════
// PROYECCIÓN «REGLAS + EXCEPCIONES»
// ═════════════════════════════════════════════════════════════════════════════
//
// La configuración real vive en BetGroup.modules. Esta vista no introduce
// modelo nuevo: reinterpreta lo que ya hay en dos listas cortas.
//
//   REGLA      → módulo que aplica a toda la partida (alcance everyone/subset)
//                o a un equipo. Son 2-4 filas en vez de 28.
//   EXCEPCIÓN  → algo que se sale de la regla:
//                  a) un módulo de alcance `pair` (apuesta solo de ese duelo)
//                  b) una entrada de pairConfigOverrides (mismo tipo de apuesta,
//                     importe distinto para ese duelo)

class _BetRule {
  final BetGroup group;
  final BetModuleInstance module;
  const _BetRule({required this.group, required this.module});

  BetScope get scope => module.effectiveScope;

  /// Cuántos jugadores cubre ahora mismo.
  int get playerCount => module.resolveParticipants(group.playerIds).length;

  String get scopeLabel => switch (scope.kind) {
        BetScopeKind.everyone => 'Toda la partida ($playerCount)',
        BetScopeKind.subset   => '$playerCount jugadores',
        BetScopeKind.teams    => '${module.sideA.name} vs ${module.sideB.name}',
        BetScopeKind.pair     => 'Duelo',
      };

  String get formatLabel =>
      module.isAllVsAll ? 'Todos vs todos' : '1 Pot';
}

enum _ExceptionKind {
  /// Apuesta que solo existe para ese duelo.
  extraBet,
  /// Mismo tipo de apuesta que la regla, pero con otro importe para el duelo.
  differentValue,
}

class _BetException {
  final _ExceptionKind kind;
  final BetGroup group;
  final BetModuleInstance module;
  final String p1Id;
  final String p2Id;
  /// Importe pactado (solo en [differentValue]).
  final double? pairValue;
  /// Importe base del módulo (solo en [differentValue]).
  final double? baseValue;

  const _BetException({
    required this.kind,
    required this.group,
    required this.module,
    required this.p1Id,
    required this.p2Id,
    this.pairValue,
    this.baseValue,
  });
}

/// Resumen textual de la proyección, para tests.
///
/// Se devuelven descripciones en vez de los tipos internos: lo que importa
/// verificar es QUÉ acaba en cada lista, no la forma de las clases privadas.
@visibleForTesting
({List<String> rules, List<String> exceptions}) describeBetProjection(
    Round round) {
  final p = _projectRules(round);
  return (
    rules: p.rules
        .map((r) => '${r.module.type.name}:${r.scope.kind.name}')
        .toList(),
    exceptions: p.exceptions
        .map((e) => '${e.module.type.name}:${e.kind.name}:'
            '${([e.p1Id, e.p2Id]..sort()).join("-")}')
        .toList(),
  );
}

({List<_BetRule> rules, List<_BetException> exceptions}) _projectRules(
    Round round) {
  final rules      = <_BetRule>[];
  final exceptions = <_BetException>[];

  for (final g in round.betGroups) {
    for (final m in g.modules) {
      final scope = m.effectiveScope;

      // a) Módulo de duelo suelto → excepción "apuesta extra"
      if (scope.kind == BetScopeKind.pair && m.participantIds.length == 2) {
        exceptions.add(_BetException(
          kind:   _ExceptionKind.extraBet,
          group:  g,
          module: m,
          p1Id:   m.participantIds[0],
          p2Id:   m.participantIds[1],
        ));
        continue;
      }

      // b) Módulo de partida → es una regla
      rules.add(_BetRule(group: g, module: m));

      // …y cada override por par cuelga de ella como excepción de importe
      final ovs = m.pairConfigOverrides;
      if (ovs == null || ovs.isEmpty) continue;
      final participants = m.resolveParticipants(g.playerIds);
      for (int i = 0; i < participants.length; i++) {
        for (int j = i + 1; j < participants.length; j++) {
          final a = participants[i], b = participants[j];
          if (!ovs.containsKey(BetModuleInstance.pairKey(a, b))) continue;
          final pv = m.overrideForPair(a, b);
          if (pv == null) continue;
          exceptions.add(_BetException(
            kind:      _ExceptionKind.differentValue,
            group:     g,
            module:    m,
            p1Id:      a,
            p2Id:      b,
            pairValue: pv,
            baseValue: m.baseValue,
          ));
        }
      }
    }
  }
  return (rules: rules, exceptions: exceptions);
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

      // MISMA prioridad que BetEngine._strokesP1ReceivesFromP2:
      //   1. pairSliding (fuente canónica)
      //   2. manualHandicaps legacy (directo, luego invertido)
      // Si se leyera el legacy primero, la UI mostraría un número distinto del
      // que el ledger cobra en cuanto ambos existan y difieran.
      double? manual = BetEngine.canonicalSlidingBetween(round, pA.id, pB.id);

      if (manual == null) {
        final rpA = round.roundPlayers.firstWhere(
          (r) => r.playerId == pA.id,
          orElse: () => RoundPlayer(playerId: pA.id, handicapEnRonda: 0),
        );
        final rpB = round.roundPlayers.firstWhere(
          (r) => r.playerId == pB.id,
          orElse: () => RoundPlayer(playerId: pB.id, handicapEnRonda: 0),
        );
        if (rpA.manualHandicaps.containsKey(pB.id)) {
          manual = rpA.manualHandicaps[pB.id];
        } else if (rpB.manualHandicaps.containsKey(pA.id)) {
          manual = -(rpB.manualHandicaps[pA.id]!);
        }
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
class _BetsBody extends StatefulWidget {
  final RoundProvider prov;
  final GolfTheme t;
  const _BetsBody({required this.prov, required this.t});

  @override
  State<_BetsBody> createState() => _BetsBodyState();
}

/// Dos lecturas de la MISMA configuración:
///   Reglas → qué se juega y para quién (pocas filas, es donde se configura)
///   Duelos → cuánto va cada quien con cada quien (consulta, decenas de filas)
enum _BetsView { reglas, duelos }

class _BetsBodyState extends State<_BetsBody> {
  _BetsView _view = _BetsView.reglas;

  RoundProvider get prov => widget.prov;
  GolfTheme get t => widget.t;

  @override
  Widget build(BuildContext context) {
    final round = prov.round!;
    // Módulos que no se pudieron liquidar por ventajas contradictorias.
    final integrityErrors = LedgerEngine.integrityErrors(round);
    // Jugadores de la ronda que no pertenecen a ninguna partida de apuestas.
    final orphans = _playersOutsideBets(round);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _BetsHeader(round: round, prov: prov, t: t)),
        if (integrityErrors.isNotEmpty)
          SliverToBoxAdapter(
            child: _IntegrityBanner(errors: integrityErrors, t: t),
          ),
        if (orphans.isNotEmpty && prov.canEditBets)
          SliverToBoxAdapter(
            child: _OrphanPlayersCard(
                players: orphans, round: round, prov: prov, t: t),
          ),
        if (prov.canEditBets && prov.openableBetsCount > 0)
          SliverToBoxAdapter(child: _OpenScopeCard(prov: prov, t: t)),

        // ── Selector de vista ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _ViewSwitcher(
            value: _view,
            t: t,
            onChanged: (v) => setState(() => _view = v),
          ),
        ),

        if (_view == _BetsView.reglas)
          ..._rulesSlivers(round)
        else
          ..._duelSlivers(round),
      ],
    );
  }

  // ── Vista REGLAS ──────────────────────────────────────────────────────────
  List<Widget> _rulesSlivers(Round round) {
    final p = _projectRules(round);
    return [
      SliverToBoxAdapter(
        child: _RulesSection(
          rules: p.rules, round: round, prov: prov, t: t,
        ),
      ),
      SliverToBoxAdapter(
        child: _ExceptionsSection(
          exceptions: p.exceptions, round: round, prov: prov, t: t,
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  // ── Vista DUELOS (la de siempre) ──────────────────────────────────────────
  List<Widget> _duelSlivers(Round round) {
    final duels = _buildDuels(round);
    return [
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
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sección REGLAS — qué se juega y para quién
// ─────────────────────────────────────────────────────────────────────────────
class _RulesSection extends StatelessWidget {
  final List<_BetRule> rules;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  const _RulesSection({
    required this.rules, required this.round,
    required this.prov, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('APUESTAS DE LA RONDA',
              style: TextStyle(
                  color: t.sub, fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          const Spacer(),
          Text('${rules.length}',
              style: TextStyle(
                  color: t.sub, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),

        if (rules.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.divider),
            ),
            child: Text('Sin apuestas de partida',
                style: TextStyle(color: t.sub, fontSize: 13)),
          )
        else
          ...rules.map((r) => _RuleCard(rule: r, prov: prov, t: t)),
      ]),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final _BetRule rule;
  final RoundProvider prov;
  final GolfTheme t;
  const _RuleCard({required this.rule, required this.prov, required this.t});

  @override
  Widget build(BuildContext context) {
    final m = rule.module;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.divider),
      ),
      child: Row(children: [
        Text(m.type.icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(m.type.label,
                  style: TextStyle(
                      color: t.text, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(m.summaryLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.primary, fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              _ScopeChip(
                icon: rule.scope.isEveryone
                    ? Icons.lock_open_outlined
                    : Icons.lock_outline,
                label: rule.scopeLabel,
                t: t,
              ),
              const SizedBox(width: 6),
              _ScopeChip(icon: Icons.swap_horiz, label: rule.formatLabel, t: t),
            ]),
          ]),
        ),
        if (prov.canEditBets)
          IconButton(
            icon: Icon(Icons.edit_outlined, color: t.sub, size: 18),
            tooltip: 'Editar',
            onPressed: () => _openEdit(context),
          ),
      ]),
    );
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BetModuleEditSheet(
        group: rule.group,
        mod: rule.module,
        t: t,
        courseInfo: prov.round?.course,
        players: prov.round?.players,
        roundHandicaps: {
          for (final rp in (prov.round?.roundPlayers ?? const <RoundPlayer>[]))
            rp.playerId: rp.handicapEnRonda,
        },
        onSave: (updated) => prov.updateBetModule(rule.group.id, updated),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final GolfTheme t;
  const _ScopeChip({required this.icon, required this.label, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.divider),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: t.sub),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: t.sub, fontSize: 10.5)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sección EXCEPCIONES — lo que se sale de la regla
// ─────────────────────────────────────────────────────────────────────────────
class _ExceptionsSection extends StatelessWidget {
  final List<_BetException> exceptions;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  const _ExceptionsSection({
    required this.exceptions, required this.round,
    required this.prov, required this.t,
  });

  String _name(String id) => round.players
      .firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id))
      .name
      .split(' ')
      .first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('EXCEPCIONES',
              style: TextStyle(
                  color: t.sub, fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          const Spacer(),
          Text('${exceptions.length}',
              style: TextStyle(
                  color: t.sub, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),

        if (exceptions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.divider),
            ),
            child: Text(
              'Todos juegan lo mismo. Para pactar algo distinto con alguien, '
              'abre su duelo en la pestaña Duelos.',
              style: TextStyle(color: t.sub, fontSize: 12, height: 1.35),
            ),
          )
        else
          ...exceptions.map((e) => _ExceptionRow(
                exception: e, p1Name: _name(e.p1Id), p2Name: _name(e.p2Id),
                t: t,
              )),
      ]),
    );
  }
}

class _ExceptionRow extends StatelessWidget {
  final _BetException exception;
  final String p1Name;
  final String p2Name;
  final GolfTheme t;
  const _ExceptionRow({
    required this.exception, required this.p1Name,
    required this.p2Name, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final e = exception;
    final isExtra = e.kind == _ExceptionKind.extraBet;

    final detail = isExtra
        ? 'Apuesta solo de este duelo · ${e.module.summaryLabel}'
        : '${e.module.type.label}: ${e.pairValue?.toStringAsFixed(0)} '
          'en vez de ${e.baseValue?.toStringAsFixed(0)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.accent.withValues(alpha: 0.28)),
      ),
      child: Row(children: [
        Icon(isExtra ? Icons.add_circle_outline : Icons.tune,
            color: t.accent, size: 17),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$p1Name vs $p2Name',
                style: TextStyle(
                    color: t.text, fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 2),
            Text(detail,
                style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.25)),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selector Reglas / Duelos
// ─────────────────────────────────────────────────────────────────────────────
class _ViewSwitcher extends StatelessWidget {
  final _BetsView value;
  final GolfTheme t;
  final ValueChanged<_BetsView> onChanged;
  const _ViewSwitcher(
      {required this.value, required this.t, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(_BetsView v, IconData icon, String label) {
      final sel = v == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(v),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: sel ? t.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 15, color: sel ? t.onPrimary : t.sub),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    color: sel ? t.onPrimary : t.sub,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  )),
            ]),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.divider),
      ),
      child: Row(children: [
        seg(_BetsView.reglas, Icons.rule_outlined, 'Reglas'),
        seg(_BetsView.duelos, Icons.compare_arrows, 'Duelos'),
      ]),
    );
  }
}

/// Jugadores activos de la ronda que NO pertenecen a ninguna partida de
/// apuestas. Son los que, hoy, quedan fuera de todo sin ninguna señal visible.
///
/// NO cuentan como "fuera":
///   • Los jugadores virtuales de equipo — ellos SON la entrada en la partida.
///   • Los miembros de un equipo (Best Ball / Scramble). Apuestan a través de
///     su lado, por eso no están en group.playerIds. Ofrecer añadirlos crearía
///     apuestas individuales encima de la de equipo, que es justo lo que no
///     se quiere.
@visibleForTesting
List<String> playersOutsideBetsForTest(Round round) =>
    _playersOutsideBets(round).map((p) => p.id).toList();

List<Player> _playersOutsideBets(Round round) {
  final inSomeGroup = <String>{
    for (final g in round.betGroups) ...g.playerIds,
  };

  // Jugadores que ya compiten como parte de un lado de equipo
  final inSomeSide = <String>{
    for (final g in round.betGroups)
      for (final m in g.modules)
        if (m.sides != null)
          for (final s in m.sides!) ...s.playerIds,
  };

  // Miembros representados por un jugador virtual (bb_team_* / team_*)
  final teamMembers = <String>{
    for (final p in round.players)
      if (p.isVirtual) ...p.teamMemberIds,
  };

  return round.players
      .where((p) => round.scores.containsKey(p.id))
      .where((p) => !p.isVirtual)
      .where((p) => !inSomeGroup.contains(p.id))
      .where((p) => !inSomeSide.contains(p.id))
      .where((p) => !teamMembers.contains(p.id))
      .toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// Abrir el alcance de apuestas creadas antes de que existieran los alcances
// ─────────────────────────────────────────────────────────────────────────────
// Solo aparece para apuestas cuyos participantes YA son toda la partida, así
// que abrirlas no cambia quién juega hoy: únicamente hace que quien se sume
// después entre solo, en vez de quedar fuera en silencio.
class _OpenScopeCard extends StatelessWidget {
  final RoundProvider prov;
  final GolfTheme t;
  const _OpenScopeCard({required this.prov, required this.t});

  @override
  Widget build(BuildContext context) {
    final n = prov.openableBetsCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.primary.withValues(alpha: 0.30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lock_open_outlined, color: t.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              n == 1
                  ? '1 apuesta está fijada a los jugadores actuales'
                  : '$n apuestas están fijadas a los jugadores actuales',
              style: TextStyle(
                  color: t.primary, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Ábrelas a toda la partida y quien se sume más tarde entrará solo. '
          'No cambia quién juega ahora mismo.',
          style: TextStyle(color: t.sub, fontSize: 12, height: 1.3),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              final changed = prov.openAllWholeGroupBets();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                backgroundColor: t.primary,
                content: Text(changed == 1
                    ? '1 apuesta abierta a toda la partida'
                    : '$changed apuestas abiertas a toda la partida'),
              ));
            },
            icon: const Icon(Icons.lock_open, size: 16),
            label: Text(n == 1 ? 'Abrir la apuesta' : 'Abrir las $n apuestas',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: t.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Jugadores fuera de las apuestas — alta en una partida
// ─────────────────────────────────────────────────────────────────────────────
class _OrphanPlayersCard extends StatelessWidget {
  final List<Player> players;
  final Round round;
  final RoundProvider prov;
  final GolfTheme t;
  const _OrphanPlayersCard({
    required this.players, required this.round,
    required this.prov, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final names = players.map((p) => p.name.split(' ').first).join(', ');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.accent.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.person_add_alt_1_outlined, color: t.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              players.length == 1
                  ? '$names está fuera de las apuestas'
                  : '${players.length} jugadores fuera de las apuestas',
              style: TextStyle(
                  color: t.accent, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          players.length == 1 ? '' : names,
          style: TextStyle(color: t.sub, fontSize: 12),
        ),
        const SizedBox(height: 10),
        ...players.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _addToPartida(context, p),
                  icon: Icon(Icons.add, size: 16, color: t.accent),
                  label: Text('Añadir a ${p.name.split(' ').first} a una partida',
                      style: TextStyle(
                          color: t.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.accent.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            )),
      ]),
    );
  }

  /// Si solo hay una partida se añade directo; si hay varias, se pregunta.
  Future<void> _addToPartida(BuildContext context, Player player) async {
    final groups = round.betGroups;
    if (groups.isEmpty) return;

    String? groupId = groups.length == 1 ? groups.first.id : null;

    groupId ??= await showModalBottomSheet<String>(
        context: context,
        backgroundColor: t.card,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('¿A qué partida añades a ${player.name}?',
                  style: TextStyle(
                      color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            ...groups.map((g) => ListTile(
                  leading: Icon(Icons.groups_outlined, color: t.primary),
                  title: Text(g.name, style: TextStyle(color: t.text)),
                  subtitle: Text(
                      '${g.playerIds.length} jugadores · ${g.modules.length} apuestas',
                      style: TextStyle(color: t.sub, fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, g.id),
                )),
            const SizedBox(height: 8),
          ]),
        ),
    );
    if (groupId == null) return;

    final openBets = prov.addPlayerToGroupBets(player.id, groupId);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: openBets > 0 ? t.primary : t.accent,
      content: Text(openBets > 0
          ? '${player.name} entra en $openBets apuesta${openBets == 1 ? "" : "s"} de la partida'
          : '${player.name} se añadió, pero ninguna apuesta tiene alcance '
            '"Todos". Ábrelas o créale duelos propios.'),
      duration: const Duration(seconds: 4),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Aviso de integridad: módulos que no se pudieron liquidar
// ─────────────────────────────────────────────────────────────────────────────
// Ocurre cuando un par tiene ventajas contradictorias guardadas (típico de
// rondas antiguas migradas). El motor prefiere no liquidar antes que cobrar
// mal, así que hay que avisar en vez de mostrar un cero silencioso.
class _IntegrityBanner extends StatelessWidget {
  final List<String> errors;
  final GolfTheme t;
  const _IntegrityBanner({required this.errors, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.loss.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.loss.withValues(alpha: 0.40)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: t.loss, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errors.length == 1
                  ? '1 apuesta sin liquidar'
                  : '${errors.length} apuestas sin liquidar',
              style: TextStyle(
                  color: t.loss, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'Hay ventajas contradictorias entre jugadores. Corrige la ventaja '
          'del duelo afectado para que vuelva a calcularse.',
          style: TextStyle(color: t.sub, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ...errors.map((e) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $e',
                  style: TextStyle(color: t.sub, fontSize: 11, height: 1.3)),
            )),
      ]),
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

    // Tipos que YA existen como apuesta EXCLUSIVA de este par.
    //
    // Solo cuentan los módulos 1v1 (participantIds == exactamente estos dos).
    // Los módulos grupales (Nassau de la partida, 1 Pot, equipos…) también
    // aparecen en duel.modules porque afectan al par, pero NO deben bloquear
    // el picker: tener un Nassau grupal de 100 no impide acordar un Nassau
    // 1v1 aparte con otro importe.
    final existingTypes = modules
        .where((r) => r.module.participantIds.length == 2)
        .map((r) => r.module.type)
        .toSet();
    final hasAllTypes =
        existingTypes.containsAll(BetModuleType.values.toSet());

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

          // ── Botón añadir apuesta (solo si puede editar y quedan tipos) ────
          if (perm.canEdit && !hasAllTypes) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _openAddBet(context, existingTypes),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: t.accent.withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.add_circle_outline, color: t.accent, size: 15),
                  const SizedBox(width: 6),
                  Text('Añadir apuesta a este duelo',
                      style: TextStyle(
                          color: t.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openAddBet(BuildContext context, Set<BetModuleType> existingTypes) {
    // Resolver / crear el BetGroup antes de mostrar el sheet
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

    // Un único sheet con navegación interna: picker → editor
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => _AddBetFlow(
        t: t,
        p1Name: duel.p1.name.split(' ').first,
        p2Name: duel.p2.name.split(' ').first,
        p1Id: duel.p1.id,
        p2Id: duel.p2.id,
        group: group,
        round: round,
        isNewGroup: existingGroup == null,
        existingTypes: existingTypes,
        onSave: (saved) {
          Navigator.pop(sheetCtx);
          if (existingGroup == null) {
            prov.updateBetGroups(
                [...round.betGroups, group.copyWith(modules: [saved])]);
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
        roundHandicaps: {
          for (final rp in round.roundPlayers) rp.playerId: rp.handicapEnRonda,
        },
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
                        // Una sola llamada: setPairSliding limpia ambos lados.
                        widget.prov
                            .setPairSliding(duel.p1.id, duel.p2.id, null);
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
    // Una sola llamada: setPairSliding escribe pairSliding y espeja el legacy
    // en ambos jugadores. Dos llamadas invertidas se pisarían entre sí.
    widget.prov.setPairSliding(duel.p1.id, duel.p2.id, val);
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

// ─────────────────────────────────────────────────────────────────────────────
// Helper: construye un BetModuleInstance nuevo con defaults según el tipo
// ─────────────────────────────────────────────────────────────────────────────
BetModuleInstance _buildNewModuleForType(
    BetModuleType type, String p1Id, String p2Id) {
  final id = 'mod_${DateTime.now().millisecondsSinceEpoch}';
  final participants = [p1Id, p2Id];

  switch (type) {
    case BetModuleType.skins:
      return BetModuleInstance(
        id: id, type: type, name: type.label,
        participantIds: participants,
        skinsConfig: SkinsConfig.def,
      );
    case BetModuleType.nassau:
      return BetModuleInstance(
        id: id, type: type, name: type.label,
        participantIds: participants,
        nassauConfig: NassauConfig.def,
      );
    case BetModuleType.matchAutoPress:
      return BetModuleInstance(
        id: id, type: type, name: type.label,
        participantIds: participants,
        matchAutoPressConfig: MatchAutoPressConfig.def,
      );
    case BetModuleType.medal:
      return BetModuleInstance(
        id: id, type: type, name: type.label,
        participantIds: participants,
        medalConfig: MedalConfig.def,
      );
    case BetModuleType.putts:
      return BetModuleInstance(
        id: id, type: type, name: type.label,
        participantIds: participants,
        puttsConfig: PuttsConfig.def,
      );
    case BetModuleType.oyeses:
      return BetModuleInstance(
        id: id, type: type, name: type.label,
        participantIds: participants,
        oyesesConfig: OyesesConfig.def,
      );
    case BetModuleType.units:
      return BetModuleInstance(
        id: id, type: type, name: type.label,
        participantIds: participants,
        unitsConfig: UnitsConfig.def,
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet: selector de tipo de apuesta
// ─────────────────────────────────────────────────────────────────────────────
class _BetTypePickerSheet extends StatefulWidget {
  final GolfTheme t;
  final String p1Name;
  final String p2Name;
  final void Function(BetModuleType) onTypePicked;

  const _BetTypePickerSheet({
    required this.t,
    required this.p1Name,
    required this.p2Name,
    required this.onTypePicked,
  });

  @override
  State<_BetTypePickerSheet> createState() => _BetTypePickerSheetState();
}

class _BetTypePickerSheetState extends State<_BetTypePickerSheet> {
  BetModuleType? _selected;

  GolfTheme get t => widget.t;

  static const _allTypes = BetModuleType.values;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Column(
          children: [
            // ── Handle + Header ──────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: t.card,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: t.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Seleccionar tipo de apuesta',
                              style: TextStyle(
                                color: t.text, fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.p1Name} vs ${widget.p2Name}',
                              style: TextStyle(color: t.sub, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.close, color: t.sub),
                      ),
                    ]),
                  ),
                  Divider(height: 1, color: t.divider),
                ],
              ),
            ),

            // ── Lista de tipos ───────────────────────────────────────────────
            Expanded(
              child: Container(
                color: t.card,
                child: ListView.separated(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _allTypes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final type = _allTypes[i];
                    final isSelected = _selected == type;
                    return _BetTypeCard(
                      type: type,
                      selected: isSelected,
                      t: t,
                      onTap: () => setState(() => _selected = type),
                    );
                  },
                ),
              ),
            ),

            // ── Botón Continuar ──────────────────────────────────────────────
            Container(
              color: t.card,
              padding: EdgeInsets.fromLTRB(
                16, 12, 16,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected == null
                      ? null
                      : () => widget.onTypePicked(_selected!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: t.onPrimary,
                    disabledBackgroundColor: t.divider,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: Text(
                    _selected == null
                        ? 'Elige un tipo de apuesta'
                        : 'Continuar con ${_selected!.label}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AddBetFlow — Un único bottom sheet con navegación interna picker → editor
// ─────────────────────────────────────────────────────────────────────────────
class _AddBetFlow extends StatefulWidget {
  final GolfTheme t;
  final String p1Name;
  final String p2Name;
  final String p1Id;
  final String p2Id;
  final BetGroup group;
  final Round round;
  final bool isNewGroup;
  final Set<BetModuleType> existingTypes;
  final void Function(BetModuleInstance saved) onSave;

  const _AddBetFlow({
    required this.t,
    required this.p1Name,
    required this.p2Name,
    required this.p1Id,
    required this.p2Id,
    required this.group,
    required this.round,
    required this.isNewGroup,
    required this.existingTypes,
    required this.onSave,
  });

  @override
  State<_AddBetFlow> createState() => _AddBetFlowState();
}

class _AddBetFlowState extends State<_AddBetFlow> {
  /// null → mostrando picker; non-null → mostrando editor con ese tipo
  BetModuleType? _selectedType;

  GolfTheme get t => widget.t;

  void _goToEditor(BetModuleType type) {
    setState(() => _selectedType = type);
  }

  void _goBackToPicker() {
    setState(() => _selectedType = null);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: _selectedType != null
                ? const Offset(0.06, 0)
                : const Offset(-0.06, 0),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: _selectedType == null
          ? _PickerView(
              key: const ValueKey('picker'),
              t: t,
              p1Name: widget.p1Name,
              p2Name: widget.p2Name,
              existingTypes: widget.existingTypes,
              onTypePicked: _goToEditor,
            )
          : _EditorView(
              key: ValueKey('editor_${_selectedType!.name}'),
              t: t,
              type: _selectedType!,
              group: widget.group,
              round: widget.round,
              p1Id: widget.p1Id,
              p2Id: widget.p2Id,
              onBack: _goBackToPicker,
              onSave: widget.onSave,
            ),
    );
  }
}

// ── Vista 1: Picker de tipo ──────────────────────────────────────────────────
class _PickerView extends StatefulWidget {
  final GolfTheme t;
  final String p1Name;
  final String p2Name;
  final Set<BetModuleType> existingTypes;
  final void Function(BetModuleType) onTypePicked;

  const _PickerView({
    super.key,
    required this.t,
    required this.p1Name,
    required this.p2Name,
    required this.existingTypes,
    required this.onTypePicked,
  });

  @override
  State<_PickerView> createState() => _PickerViewState();
}

class _PickerViewState extends State<_PickerView> {
  BetModuleType? _selected;

  GolfTheme get t => widget.t;

  /// Se muestran TODOS los tipos. Los que el par ya tiene como apuesta 1v1
  /// salen atenuados y no seleccionables (ver [_BetTypeCard.alreadyConfigured]),
  /// en vez de desaparecer: ocultarlos hacía parecer que la app no permitía
  /// añadir esos tipos.
  List<BetModuleType> get _availableTypes => BetModuleType.values.toList();

  bool _isTaken(BetModuleType type) => widget.existingTypes.contains(type);

  @override
  Widget build(BuildContext context) {
    // Usar ConstrainedBox + Column con ListView propio en lugar de
    // DraggableScrollableSheet, que en web comparte scrollCtrl con el
    // ListView y bloquea el scroll interno (solo se veía la primera card).
    final screenH = MediaQuery.of(context).size.height;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom
        + MediaQuery.of(context).padding.bottom;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle + Header ──────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: t.card,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: t.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Seleccionar tipo de apuesta',
                            style: TextStyle(
                              color: t.text, fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.p1Name} vs ${widget.p2Name}',
                            style: TextStyle(color: t.sub, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close, color: t.sub),
                    ),
                  ]),
                ),
                Divider(height: 1, color: t.divider),
              ],
            ),
          ),

          // ── Lista de tipos — scroll propio, sin DraggableScrollableSheet ──
          Flexible(
            child: Container(
              color: t.card,
              child: ListView.separated(
                // Sin controller externo: el ListView maneja su propio scroll
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: _availableTypes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final type  = _availableTypes[i];
                  final taken = _isTaken(type);
                  return _BetTypeCard(
                    type: type,
                    selected: _selected == type,
                    alreadyConfigured: taken,
                    t: t,
                    onTap: taken
                        ? () {}
                        : () => setState(() => _selected = type),
                  );
                },
              ),
            ),
          ),

          // ── Botón Continuar ──────────────────────────────────────────────
          Container(
            color: t.card,
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected == null
                    ? null
                    : () => widget.onTypePicked(_selected!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: t.onPrimary,
                  disabledBackgroundColor: t.divider,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Text(
                  _selected == null
                      ? 'Elige un tipo de apuesta'
                      : 'Continuar con ${_selected!.label}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vista 2: Editor de módulo con back button ────────────────────────────────
class _EditorView extends StatelessWidget {
  final GolfTheme t;
  final BetModuleType type;
  final BetGroup group;
  final Round round;
  final String p1Id;
  final String p2Id;
  final VoidCallback onBack;
  final void Function(BetModuleInstance saved) onSave;

  const _EditorView({
    super.key,
    required this.t,
    required this.type,
    required this.group,
    required this.round,
    required this.p1Id,
    required this.p2Id,
    required this.onBack,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final newMod = _buildNewModuleForType(type, p1Id, p2Id);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Back button header ───────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: t.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 16, 8),
                child: Row(children: [
                  // Botón atrás
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new,
                        color: t.sub, size: 18),
                    onPressed: onBack,
                    tooltip: 'Cambiar tipo',
                  ),
                  Expanded(
                    child: Text(
                      type.label,
                      style: TextStyle(
                        color: t.text, fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close, color: t.sub),
                  ),
                ]),
              ),
              Divider(height: 1, color: t.divider),
            ],
          ),
        ),

        // ── Editor del módulo (sin su propio header) ─────────────────────────
        Flexible(
          child: SingleChildScrollView(
            child: BetModuleEditSheet(
              group: group,
              mod: newMod,
              t: t,
              courseInfo: round.course,
              players: round.players,
              roundHandicaps: {
                for (final rp in round.roundPlayers)
                  rp.playerId: rp.handicapEnRonda,
              },
              onSave: onSave,
            ),
          ),
        ),
      ],
    );
  }
}

// Tarjeta individual de tipo de apuesta
class _BetTypeCard extends StatelessWidget {
  final BetModuleType type;
  final bool selected;
  /// true si el par ya tiene una apuesta 1v1 de este tipo. Se muestra atenuada
  /// y no seleccionable, en vez de desaparecer de la lista: así queda claro
  /// POR QUÉ no se puede añadir (hay que editar la existente).
  final bool alreadyConfigured;
  final GolfTheme t;
  final VoidCallback onTap;

  const _BetTypeCard({
    required this.type, required this.selected,
    required this.t, required this.onTap,
    this.alreadyConfigured = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? t.primary : t.divider;
    final bgColor     = selected
        ? t.primary.withValues(alpha: 0.08)
        : t.surface;

    if (alreadyConfigured) {
      return Opacity(
        opacity: 0.45,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.divider),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.divider),
              ),
              child: Center(
                child: Text(type.icon, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.label,
                      style: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  const SizedBox(height: 3),
                  Text('Ya configurada en este duelo · edítala desde la lista',
                      style: TextStyle(color: t.sub, fontSize: 11, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.check_circle_outline, color: t.sub, size: 22),
          ]),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          // Ícono grande
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: selected
                  ? t.primary.withValues(alpha: 0.12)
                  : t.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? t.primary.withValues(alpha: 0.3)
                    : t.divider,
              ),
            ),
            child: Center(
              child: Text(type.icon, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 14),

          // Nombre + descripción
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                type.label,
                style: TextStyle(
                  color: selected ? t.primary : t.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                type.description,
                style: TextStyle(
                  color: t.sub,
                  fontSize: 11,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),

          // Check de selección
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: selected
                ? Icon(Icons.check_circle, color: t.primary, size: 22,
                    key: const ValueKey('check'))
                : Icon(Icons.radio_button_unchecked, color: t.sub, size: 22,
                    key: const ValueKey('empty')),
          ),
        ]),
      ),
    );
  }
}
