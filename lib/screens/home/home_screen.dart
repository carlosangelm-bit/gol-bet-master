// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN — Pantalla principal: iniciar ronda, estado de ronda activa
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common_widgets.dart';
import '../setup/setup_screen.dart';
import '../templates/templates_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final t    = prov.theme;
    GolfThemeExt.setCurrent(t);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, t, prov),
            Expanded(
              child: prov.hasRound
                  ? _ActiveRoundView(prov: prov, t: t)
                  : _EmptyView(t: t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, GolfTheme t, RoundProvider prov) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          // App icon / logo
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Icon(Icons.golf_course, color: t.onPrimary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Golf Bet Master', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -0.3)),
              if (prov.hasRound)
                Text(prov.round!.name, style: TextStyle(color: t.sub, fontSize: 12)),
            ]),
          ),
          // Theme selector
          _ThemeToggle(t: t),
        ],
      ),
    );
  }
}

// ── Vista sin ronda activa ────────────────────────────────────────────────────
class _EmptyView extends StatelessWidget {
  final GolfTheme t;
  const _EmptyView({required this.t});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.golf_course, size: 48, color: t.primary),
          ),
          const SizedBox(height: 24),
          Text('Bienvenido', style: TextStyle(color: t.text, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text(
            'Configura jugadores, apuestas y empieza a jugar',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.sub, fontSize: 15),
          ),
          const SizedBox(height: 40),
          GPrimaryButton(
            label: '⛳ Nueva Ronda',
            icon: null,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupScreen())),
          ),
          const SizedBox(height: 32),
          _QuickInfoCards(t: t),
        ],
      ),
    );
  }
}

class _QuickInfoCards extends StatelessWidget {
  final GolfTheme t;
  const _QuickInfoCards({required this.t});

  @override
  Widget build(BuildContext context) {
    final cards = [
      (Icons.attach_money,   'Nassau',   'Front 9, Back 9 y Total'),
      (Icons.flash_on,       'Skins',    'Carry-over por empate'),
      (Icons.emoji_events,   'Medal',    'Score neto total'),
      (Icons.sports_golf,    'Oyeses',   'Ranking en par 3s'),
      (Icons.touch_app,      'Units',    'Birdie, Eagle, Sandy...'),
      (Icons.track_changes,  'Putts',    'Menos putts gana'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GSectionHeader(title: 'APUESTAS DISPONIBLES'),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.6,
          children: cards.map((c) => GCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: t.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(c.$1, color: t.primary, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(c.$2, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
                Text(c.$3, style: TextStyle(color: t.sub, fontSize: 10), overflow: TextOverflow.ellipsis),
              ])),
            ]),
          )).toList(),
        ),
      ],
    );
  }
}

// ── Vista con ronda activa ────────────────────────────────────────────────────
class _ActiveRoundView extends StatelessWidget {
  final RoundProvider prov;
  final GolfTheme t;
  const _ActiveRoundView({required this.prov, required this.t});

  @override
  Widget build(BuildContext context) {
    final round    = prov.round!;
    final balances = prov.balances;
    final completed = round.players.isNotEmpty
        ? _countCompletedHoles(round)
        : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Round header card
        GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(round.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 18))),
            if (!round.isFinished)
              GestureDetector(
                onTap: () => _confirmFinish(context, prov, t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(20)),
                  child: Text('Finalizar', style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.sports_golf, color: t.sub, size: 14),
            const SizedBox(width: 4),
            Text('${round.players.length} jugadores', style: TextStyle(color: t.sub, fontSize: 12)),
            const SizedBox(width: 16),
            Icon(Icons.flag, color: t.sub, size: 14),
            const SizedBox(width: 4),
            Text('Hoyo $completed/${round.totalHoles}', style: TextStyle(color: t.sub, fontSize: 12)),
          ]),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: round.totalHoles > 0 ? completed / round.totalHoles : 0,
              backgroundColor: t.divider,
              valueColor: AlwaysStoppedAnimation<Color>(t.primary),
              minHeight: 6,
            ),
          ),
        ])),

        const SizedBox(height: 20),
        GSectionHeader(title: 'BALANCE ACTUAL'),

        // Player balances
        ...round.players.map((p) {
          final bal = balances[p.id] ?? 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GCard(child: Row(children: [
              GAvatar(name: p.name, colorIndex: p.colorIndex, size: 40),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 15)),
                Text('HCP ${p.handicapBase.toStringAsFixed(0)}', style: TextStyle(color: t.sub, fontSize: 12)),
              ])),
              BalChip(amount: bal),
            ])),
          );
        }),

        const SizedBox(height: 20),
        GSectionHeader(title: 'PARTIDAS'),
        ...round.betGroups.map((g) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: g.modules.map((m) => GestureDetector(
              onTap: () => _openBetEdit(context, prov, g, m, t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.primary.withValues(alpha: 0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(m.type.icon, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(m.type.label, style: TextStyle(color: t.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(width: 4),
                  Text('\$${m.value.toStringAsFixed(0)}', style: TextStyle(color: t.primary.withValues(alpha: 0.75), fontSize: 11)),
                  const SizedBox(width: 4),
                  Icon(Icons.edit_outlined, color: t.primary.withValues(alpha: 0.6), size: 11),
                ]),
              ),
            )).toList()),
          ])),
        )),

        const SizedBox(height: 20),
        // Action buttons
        GPrimaryButton(
          label: '+ Capturar Score',
          icon: Icons.edit,
          onTap: () => context.read<RoundProvider>().setTab(1),
        ),
        const SizedBox(height: 10),
        GSecButton(
          label: '📋  Guardar como plantilla',
          onTap: () => _saveAsTemplate(context, prov, t),
        ),
        const SizedBox(height: 6),
        GSecButton(
          label: '🗑  Abandonar Ronda',
          onTap: () => _confirmAbandon(context, prov, t),
        ),
      ]),
    );
  }

  Future<void> _saveAsTemplate(BuildContext context, RoundProvider prov, GolfTheme t) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para guardar plantillas')));
      return;
    }
    final round = prov.round!;
    await showDialog(
      context: context,
      builder: (_) => SaveTemplateDialog(betGroups: round.betGroups, players: round.players, t: t),
    );
  }

  void _openBetEdit(BuildContext context, RoundProvider prov, BetGroup group, BetModuleInstance mod, GolfTheme t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BetModuleEditSheet(
        group: group,
        mod: mod,
        t: t,
        courseInfo: prov.round!.course,
        onSave: (updatedMod) {
          final newModules = group.modules.map((m) => m.id == updatedMod.id ? updatedMod : m).toList();
          final newGroup   = BetGroup(id: group.id, name: group.name, format: group.format, playerIds: group.playerIds, modules: newModules);
          final newGroups  = prov.round!.betGroups.map((g) => g.id == group.id ? newGroup : g).toList();
          prov.updateBetGroups(newGroups);
        },
      ),
    );
  }

  int _countCompletedHoles(Round round) {
    final maxHole = round.totalHoles;
    for (int h = maxHole; h >= 1; h--) {
      if (round.players.every((p) => round.getScore(p.id, h).hasScore)) return h;
    }
    return 0;
  }

  void _confirmFinish(BuildContext context, RoundProvider prov, GolfTheme t) {
    final completed = _countCompletedHoles(prov.round!);
    final total = prov.round!.totalHoles;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      title: Text('Finalizar ronda', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Se guardarán los resultados y la ronda pasará al historial.', style: TextStyle(color: t.sub)),
        if (completed < total) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Hoyos completados: $completed/$total',
              style: TextStyle(color: t.accent, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: t.sub))),
        TextButton(onPressed: () {
          Navigator.pop(ctx);
          prov.finishRound();
        }, child: Text('Finalizar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  void _confirmAbandon(BuildContext context, RoundProvider prov, GolfTheme t) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      title: Text('Abandonar ronda', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
      content: Text('Se perderán todos los datos de esta ronda.', style: TextStyle(color: t.sub)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: t.sub))),
        TextButton(onPressed: () { prov.resetRound(); Navigator.pop(ctx); }, child: Text('Abandonar', style: TextStyle(color: t.loss, fontWeight: FontWeight.w700))),
      ],
    ));
  }
}

// ── Mini navigator para seleccionar hoyo y jugador ────────────────────────────
class _ScoreEntryNavigator extends StatefulWidget {
  final Round round;
  final GolfTheme t;
  const _ScoreEntryNavigator({required this.round, required this.t});
  @override State<_ScoreEntryNavigator> createState() => _ScoreEntryNavigatorState();
}

class _ScoreEntryNavigatorState extends State<_ScoreEntryNavigator> {
  int _selectedHole = 1;

  @override
  void initState() {
    super.initState();
    // Auto-seleccionar el siguiente hoyo sin scores
    final r = widget.round;
    final maxHole = r.totalHoles;
    for (int h = 1; h <= maxHole; h++) {
      if (!r.players.every((p) => r.getScore(p.id, h).hasScore)) {
        _selectedHole = h;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final round = context.watch<RoundProvider>().round ?? widget.round;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: gAppBar('Capturar Score', t, showBack: true, ctx: context),
      body: Column(children: [
        // Hole selector
        Container(
          height: 52,
          color: t.surface,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: 18,
            itemBuilder: (context, i) {
              final h = i + 1;
              final allDone = round.players.every((p) => round.getScore(p.id, h).hasScore);
              final isSel = h == _selectedHole;
              return GestureDetector(
                onTap: () => setState(() => _selectedHole = h),
                child: Container(
                  width: 36, height: 36, alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: isSel ? t.primary : allDone ? t.primary.withValues(alpha: 0.15) : t.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: isSel ? t.primary : t.divider),
                  ),
                  child: Text('$h', style: TextStyle(
                    color: isSel ? t.onPrimary : allDone ? t.primary : t.text,
                    fontWeight: FontWeight.w700, fontSize: 12,
                  )),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _HoleEntryPanel(hole: _selectedHole, t: t)),
      ]),
    );
  }
}

// ── Panel de entrada de un hoyo ───────────────────────────────────────────────
class _HoleEntryPanel extends StatelessWidget {
  final int hole;
  final GolfTheme t;
  const _HoleEntryPanel({required this.hole, required this.t});

  @override
  Widget build(BuildContext context) {
    final prov  = context.watch<RoundProvider>();
    final round = prov.round!;
    final ch    = round.course.holes.firstWhere((h) => h.hole == hole);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Hole info header
        GCard(child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text('$hole', style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w800, fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hoyo $hole', style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 16)),
            Row(children: [
              _InfoChip('Par ${ch.par}', t),
              const SizedBox(width: 8),
              _InfoChip('SI ${ch.strokeIndex}', t),
              if (ch.isPar3) ...[const SizedBox(width: 8), _InfoChip('Par 3 · Oyes', t, accent: true)],
            ]),
          ]),
        ])),
        const SizedBox(height: 16),

        // Per player entry
        ...round.players.map((p) => _PlayerEntry(player: p, hole: hole, ch: ch, t: t)),

        // Oyese ranking (only for par 3s)
        if (ch.isPar3) ...[
          const SizedBox(height: 8),
          _OyeseRankingCard(hole: hole, t: t),
        ],

        const SizedBox(height: 16),
        GPrimaryButton(
          label: 'Guardar Hoyo $hole',
          icon: Icons.check,
          onTap: () => Navigator.pop(context),
        ),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final GolfTheme t;
  final bool accent;
  const _InfoChip(this.label, this.t, {this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent ? t.accent.withValues(alpha: 0.15) : t.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent ? t.accent.withValues(alpha: 0.4) : t.divider),
      ),
      child: Text(label, style: TextStyle(color: accent ? t.accent : t.sub, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _PlayerEntry extends StatefulWidget {
  final Player player;
  final int hole;
  final CourseHole ch;
  final GolfTheme t;
  const _PlayerEntry({required this.player, required this.hole, required this.ch, required this.t});
  @override State<_PlayerEntry> createState() => _PlayerEntryState();
}

class _PlayerEntryState extends State<_PlayerEntry> {
  @override
  Widget build(BuildContext context) {
    final prov  = context.watch<RoundProvider>();
    final score = prov.round!.getScore(widget.player.id, widget.hole);
    final t     = widget.t;
    final gross = score.grossScore ?? 0;
    final putts = score.putts;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Player header
        Row(children: [
          GAvatar(name: widget.player.name, colorIndex: widget.player.colorIndex, size: 32),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.player.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14))),
          if (score.hasScore)
            ScoreCell(score: gross, par: widget.ch.par, size: 32),
        ]),
        const SizedBox(height: 10),
        const GDivider(),
        const SizedBox(height: 10),

        // Score y Putts en la misma fila
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SCORE BRUTO', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            GCounter(
              value: gross,
              onDec: () => prov.updateScore(widget.player.id, widget.hole, gross > 1 ? gross - 1 : null, putts),
              onInc: () => prov.updateScore(widget.player.id, widget.hole, gross + 1, putts),
            ),
          ])),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PUTTS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            GCounter(
              value: putts,
              onDec: () => prov.updateScore(widget.player.id, widget.hole, score.grossScore, putts > 0 ? putts - 1 : 0),
              onInc: () => prov.updateScore(widget.player.id, widget.hole, score.grossScore, putts + 1),
            ),
          ])),
        ]),

        const SizedBox(height: 10),
        // Unit events
        _UnitChips(player: widget.player, hole: widget.hole, t: t),
      ])),
    );
  }
}

// ── Unit event chips ──────────────────────────────────────────────────────────
class _UnitChips extends StatelessWidget {
  final Player player;
  final int hole;
  final GolfTheme t;
  const _UnitChips({required this.player, required this.hole, required this.t});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('UNITS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: UnitEventType.values.map((evt) {
        final active = prov.hasEvent(player.id, hole, evt);
        return GestureDetector(
          onTap: () => prov.toggleEvent(player.id, hole, evt),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: active ? t.accent.withValues(alpha: 0.2) : t.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: active ? t.accent : t.divider),
            ),
            child: Text(evt.label, style: TextStyle(
              color: active ? t.accent : t.sub,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              fontSize: 12,
            )),
          ),
        );
      }).toList()),
    ]);
  }
}

// ── Oyese ranking card ────────────────────────────────────────────────────────
class _OyeseRankingCard extends StatelessWidget {
  final int hole;
  final GolfTheme t;
  const _OyeseRankingCard({required this.hole, required this.t});

  @override
  Widget build(BuildContext context) {
    final prov    = context.watch<RoundProvider>();
    final round   = prov.round!;
    final ranking = round.getOyese(hole);
    final pids    = ranking?.ranking ?? [];

    // All players not yet ranked
    final ranked   = pids.toList();
    final unranked = round.players.map((p) => p.id).where((id) => !ranked.contains(id)).toList();

    return GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.emoji_events, color: t.accent, size: 16),
        const SizedBox(width: 6),
        Text('Oyes — Ranking (arrastrar para ordenar)', style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 10),
      if (ranked.isEmpty)
        Text('Toca los jugadores para asignar posición', style: TextStyle(color: t.sub, fontSize: 12))
      else
        ...ranked.asMap().entries.map((e) {
          final p = round.players.firstWhere((pl) => pl.id == e.value);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('${e.key + 1}', style: TextStyle(color: t.onPrimary, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(p.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w600, fontSize: 13))),
              GestureDetector(
                onTap: () {
                  final newRanking = List<String>.from(ranked)..removeAt(e.key);
                  prov.setOyeseRanking(hole, newRanking);
                },
                child: Icon(Icons.close, color: t.sub, size: 16),
              ),
            ]),
          );
        }),
      const SizedBox(height: 8),
      if (unranked.isNotEmpty)
        Wrap(spacing: 6, children: unranked.map((pid) {
          final p = round.players.firstWhere((pl) => pl.id == pid);
          return GestureDetector(
            onTap: () {
              final newRanking = [...ranked, pid];
              prov.setOyeseRanking(hole, newRanking);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: t.divider)),
              child: Text('+ ${p.name}', style: TextStyle(color: t.primary, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          );
        }).toList()),
    ]));
  }
}

// ── Theme toggle ──────────────────────────────────────────────────────────────
class _ThemeToggle extends StatelessWidget {
  final GolfTheme t;
  const _ThemeToggle({required this.t});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    return GestureDetector(
      onTap: () => _showThemePicker(context, prov, t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.divider)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_themeIcon(prov.themeMode), color: t.primary, size: 14),
          const SizedBox(width: 4),
          Text(_themeLabel(prov.themeMode), style: TextStyle(color: t.text, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  IconData _themeIcon(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.light:   return Icons.wb_sunny_outlined;
      case AppThemeMode.dark:    return Icons.nights_stay_outlined;
      case AppThemeMode.classic: return Icons.filter_vintage_outlined;
    }
  }

  String _themeLabel(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.light:   return 'Claro';
      case AppThemeMode.dark:    return 'Oscuro';
      case AppThemeMode.classic: return 'Clásico';
    }
  }

  void _showThemePicker(BuildContext context, RoundProvider prov, GolfTheme t) {
    showModalBottomSheet(context: context, backgroundColor: t.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Seleccionar tema', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 16),
          ...AppThemeMode.values.map((m) {
            final sel = prov.themeMode == m;
            return GestureDetector(
              onTap: () { prov.setTheme(m); Navigator.pop(context); },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: sel ? t.primary.withValues(alpha: 0.1) : t.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? t.primary : t.divider),
                ),
                child: Row(children: [
                  Icon(_themeIcon(m), color: sel ? t.primary : t.sub, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_themeLabel(m), style: TextStyle(color: sel ? t.primary : t.text, fontWeight: FontWeight.w700)),
                    Text(_themeDesc(m), style: TextStyle(color: t.sub, fontSize: 12)),
                  ])),
                  if (sel) Icon(Icons.check_circle, color: t.primary, size: 20),
                ]),
              ),
            );
          }),
        ]),
      ));
  }

  String _themeDesc(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.light:   return 'Fondo blanco · Verde forestal';
      case AppThemeMode.dark:    return 'Fondo carbón · Verde brillante';
      case AppThemeMode.classic: return 'Verde fairway · Crema · Dorado';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDICIÓN DE APUESTA EN VIVO
// Bottom sheet que permite editar la configuración de un BetModuleInstance
// sin salir de la ronda activa.
// ─────────────────────────────────────────────────────────────────────────────
class _BetModuleEditSheet extends StatefulWidget {
  final BetGroup group;
  final BetModuleInstance mod;
  final GolfTheme t;
  final CourseInfo? courseInfo;
  final void Function(BetModuleInstance) onSave;
  const _BetModuleEditSheet({required this.group, required this.mod, required this.t, required this.onSave, this.courseInfo});
  @override State<_BetModuleEditSheet> createState() => _BetModuleEditSheetState();
}

class _BetModuleEditSheetState extends State<_BetModuleEditSheet> {
  late BetModuleInstance _current;

  // Controllers declarados en State para sobrevivir rebuilds
  late final TextEditingController _skinCtrl;
  late final TextEditingController _nassauF, _nassauB, _nassauT;
  late final TextEditingController _matchM, _matchP;
  late final TextEditingController _medalCtrl;
  late final TextEditingController _puttsCtrl;
  late final TextEditingController _oyesCtrl, _zapatoCtrl;
  late final Map<UnitEventType, TextEditingController> _unitCtrls;

  @override
  void initState() {
    super.initState();
    _current = widget.mod;
    final m = _current;
    _skinCtrl   = TextEditingController(text: m.skins.valuePerSkin.toStringAsFixed(0));
    _nassauF    = TextEditingController(text: m.nassau.frontValue.toStringAsFixed(0));
    _nassauB    = TextEditingController(text: m.nassau.backValue.toStringAsFixed(0));
    _nassauT    = TextEditingController(text: m.nassau.totalValue.toStringAsFixed(0));
    _matchM     = TextEditingController(text: m.matchAutoPress.matchValue.toStringAsFixed(0));
    _matchP     = TextEditingController(text: m.matchAutoPress.pressValue.toStringAsFixed(0));
    _medalCtrl  = TextEditingController(text: m.medal.value.toStringAsFixed(0));
    _puttsCtrl  = TextEditingController(text: m.putts.value.toStringAsFixed(0));
    _oyesCtrl   = TextEditingController(text: m.oyeses.value.toStringAsFixed(0));
    _zapatoCtrl = TextEditingController(
        text: m.oyeses.zapatoValue > 0 ? m.oyeses.zapatoValue.toStringAsFixed(0) : '');
    _unitCtrls  = {
      for (final e in UnitEventType.values)
        e: TextEditingController(text: m.units.valueFor(e).toStringAsFixed(0)),
    };
  }

  @override
  void dispose() {
    _skinCtrl.dispose();
    _nassauF.dispose(); _nassauB.dispose(); _nassauT.dispose();
    _matchM.dispose(); _matchP.dispose();
    _medalCtrl.dispose();
    _puttsCtrl.dispose();
    _oyesCtrl.dispose(); _zapatoCtrl.dispose();
    for (final c in _unitCtrls.values) c.dispose();
    super.dispose();
  }

  void _update(BetModuleInstance updated) => setState(() => _current = updated);

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        // Handle
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(color: t.divider, borderRadius: BorderRadius.circular(2)),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text(_current.type.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Editar ${_current.type.label}', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 17)),
              Text(widget.group.name, style: TextStyle(color: t.sub, fontSize: 12)),
            ])),
          ]),
        ),
        Divider(height: 20, color: t.divider),
        // Body con campos según tipo
        Expanded(
          child: SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildFields(t),
            ),
          ),
        ),
        // Guardar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () { widget.onSave(_current); Navigator.pop(context); },
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: t.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Guardar cambios', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Campos según tipo ──────────────────────────────────────────────────────
  List<Widget> _buildFields(GolfTheme t) {
    switch (_current.type) {
      case BetModuleType.skins:    return _skinsFields(t);
      case BetModuleType.nassau:   return _nassauFields(t);
      case BetModuleType.matchAutoPress: return _matchFields(t);
      case BetModuleType.medal:    return _medalFields(t);
      case BetModuleType.putts:    return _puttsFields(t);
      case BetModuleType.oyeses:   return _oyesesFields(t);
      case BetModuleType.units:    return _unitsFields(t);
    }
  }

  // ── SKINS ──────────────────────────────────────────────────────────────────
  List<Widget> _skinsFields(GolfTheme t) {
    final s = _current.skins;
    return [
      _label('VALOR POR SKIN', t),
      _amountField('Monto', _skinCtrl, t, onChanged: (v) {
        _update(_current.copyWith(skinsConfig: s.copyWith(valuePerSkin: v)));
      }),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], s.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(skinsConfig: s.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
      const SizedBox(height: 16),
      _toggle('Carry-over', s.carryOver ? 'Empates acumulan al siguiente hoyo 🔥' : 'Sin acumulación', s.carryOver, t, (v) {
        _update(_current.copyWith(skinsConfig: s.copyWith(carryOver: v)));
      }),
    ];
  }

  // ── NASSAU ─────────────────────────────────────────────────────────────────
  List<Widget> _nassauFields(GolfTheme t) {
    final n = _current.nassau;
    void saveNassau() {
      final fv = double.tryParse(_nassauF.text) ?? n.frontValue;
      final bv = double.tryParse(_nassauB.text) ?? n.backValue;
      final tv = double.tryParse(_nassauT.text) ?? n.totalValue;
      _update(_current.copyWith(nassauConfig: n.copyWith(frontValue: fv, backValue: bv, totalValue: tv)));
    }
    return [
      _label('VALORES', t),
      _amountField('Front 9', _nassauF, t, onChanged: (_) => saveNassau()),
      const SizedBox(height: 8),
      _amountField('Back 9', _nassauB, t, onChanged: (_) => saveNassau()),
      const SizedBox(height: 8),
      _amountField('Total 18', _nassauT, t, onChanged: (_) => saveNassau()),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], n.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(nassauConfig: n.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
      const SizedBox(height: 16),
      _toggle('Activar Press automático', n.pressEnabled ? 'Trigger: ${n.autoPressTrigger} down' : 'Sin press', n.pressEnabled, t, (v) {
        _update(_current.copyWith(nassauConfig: n.copyWith(pressEnabled: v)));
      }),
      if (n.pressEnabled) ...[
        const SizedBox(height: 12),
        _label('TRIGGER', t),
        _segmented(['1 down', '2 down', '3 down'], n.autoPressTrigger - 1, t, (i) {
          _update(_current.copyWith(nassauConfig: n.copyWith(autoPressTrigger: i + 1)));
        }),
      ],
    ];
  }

  // ── MATCH + PRESS ──────────────────────────────────────────────────────────
  List<Widget> _matchFields(GolfTheme t) {
    final m = _current.matchAutoPress;
    return [
      _label('VALORES', t),
      _amountField('Valor del match', _matchM, t, onChanged: (v) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(matchValue: v)));
      }),
      const SizedBox(height: 8),
      _amountField('Valor por press', _matchP, t, onChanged: (v) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(pressValue: v)));
      }),
      const SizedBox(height: 16),
      _label('TRIGGER (hoyos de diferencia)', t),
      _segmented(['1 up', '2 up', '3 up'], m.pressTriggerValue - 1, t, (i) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(pressTriggerValue: i + 1)));
      }),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], m.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
    ];
  }

  // ── MEDAL ──────────────────────────────────────────────────────────────────
  List<Widget> _medalFields(GolfTheme t) {
    final m = _current.medal;
    return [
      _label('VALOR', t),
      _amountField('Monto', _medalCtrl, t, onChanged: (v) {
        _update(_current.copyWith(medalConfig: m.copyWith(value: v)));
      }),
      const SizedBox(height: 16),
      _label('HOYOS', t),
      _segmented(['9 hoyos', '18 hoyos'], m.holes == 18 ? 1 : 0, t, (i) {
        _update(_current.copyWith(medalConfig: m.copyWith(holes: i == 1 ? 18 : 9)));
      }),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], m.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(medalConfig: m.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
    ];
  }

  // ── PUTTS ──────────────────────────────────────────────────────────────────
  List<Widget> _puttsFields(GolfTheme t) {
    final p = _current.putts;
    return [
      _label('VALOR POR SEGMENTO', t),
      _amountField('Monto', _puttsCtrl, t, onChanged: (v) {
        _update(_current.copyWith(puttsConfig: p.copyWith(value: v)));
      }),
      const SizedBox(height: 16),
      _label('MODO', t),
      _segmented(['Total 18H', 'F9 + B9'], p.puttsMode == PuttsMode.total ? 0 : 1, t, (i) {
        _update(_current.copyWith(puttsConfig: p.copyWith(puttsMode: i == 0 ? PuttsMode.total : PuttsMode.perHole)));
      }),
      const SizedBox(height: 8),
      Text(
        p.puttsMode == PuttsMode.total
            ? '1 apuesta: el que menos putts en 18 hoyos gana \$${p.value.toStringAsFixed(0)}'
            : '2 apuestas: F9 (\$${p.value.toStringAsFixed(0)}) + B9 (\$${p.value.toStringAsFixed(0)})',
        style: TextStyle(color: t.sub, fontSize: 11),
      ),
      const SizedBox(height: 16),
      _toggle('Penalti 3-putt', p.threePuttPenalty ? 'Se cobra penalti por cada 3-putt' : 'Sin penalti', p.threePuttPenalty, t, (v) {
        _update(_current.copyWith(puttsConfig: p.copyWith(threePuttPenalty: v)));
      }),
    ];
  }

  // ── OYESES ─────────────────────────────────────────────────────────────────
  List<Widget> _oyesesFields(GolfTheme t) {
    final o = _current.oyeses;
    // controllers _oyesCtrl y _zapatoCtrl declarados en State

    // Par-3 reales del campo de la ronda (fallback: estándar)
    final realPar3Holes = (widget.courseInfo?.holes ?? CourseInfo.standard.holes)
        .where((h) => h.isPar3)
        .map((h) => h.hole)
        .toList()
      ..sort();
    final par3count = o.eligibleHoles.isEmpty ? realPar3Holes.length : o.eligibleHoles.length;

    return [
      _label('VALOR POR OYÉS', t),
      _amountField('Monto', _oyesCtrl, t, onChanged: (v) {
        _update(_current.copyWith(oyesesConfig: o.copyWith(value: v)));
      }),
      const SizedBox(height: 20),
      _label('👟 ZAPATO', t),
      Text('El jugador que gana TODOS los oyeses cobra el zapato.', style: TextStyle(color: t.sub, fontSize: 11)),
      const SizedBox(height: 10),
      _toggle('Activar zapato', o.zapatoEnabled ? 'Ganador de todos los oyeses cobra extra' : 'Sin regla de zapato', o.zapatoEnabled, t, (v) {
        _update(_current.copyWith(oyesesConfig: o.copyWith(zapatoEnabled: v)));
      }),
      if (o.zapatoEnabled) ...[
        const SizedBox(height: 12),
        _label('VALOR DEL ZAPATO', t),
        Text(
          o.zapatoValue == 0
              ? 'Automático: $par3count oyeses × \$${o.value.toStringAsFixed(0)} = \$${(par3count * o.value).toStringAsFixed(0)}'
              : 'Valor fijo configurado',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _zapatoCtrl,
          onChanged: (txt) {
            final v = double.tryParse(txt) ?? 0;
            _update(_current.copyWith(oyesesConfig: _current.oyeses.copyWith(zapatoValue: v)));
          },
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          textAlign: TextAlign.right,
          style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Monto fijo (vacío = automático)',
            labelStyle: TextStyle(color: t.sub, fontSize: 12),
            prefixText: '\$ ',
            prefixStyle: TextStyle(color: t.sub, fontSize: 13),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            fillColor: t.surface, filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 12),
        _label('APLICA EN', t),
        _segmented(['Solo 18 hoyos', 'También 9 hoyos'], o.zapatoRequires18 ? 0 : 1, t, (i) {
          _update(_current.copyWith(oyesesConfig: _current.oyeses.copyWith(zapatoRequires18: i == 0)));
        }),
        const SizedBox(height: 6),
        Text(
          o.zapatoRequires18
              ? 'Solo aplica si se juegan todos los par-3 del campo.'
              : 'Aplica con 2 o más oyeses registrados (válido en 9H).',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),
      ],
    ];
  }

  // ── UNITS ──────────────────────────────────────────────────────────────────
  List<Widget> _unitsFields(GolfTheme t) {
    final u = _current.units;
    // controllers _unitCtrls declarados en State
    // u se usa para mostrar descripciones en la UI

    final icons = {
      UnitEventType.birdie:      '🐦',
      UnitEventType.eagle:       '🦅',
      UnitEventType.sandyPar:    '🏖️',
      UnitEventType.parUnico:    '⭐',
      UnitEventType.birdieUnico: '💫',
      UnitEventType.holeOut:     '🕳️',
    };

    return [
      _label('VALOR POR EVENTO', t),
      const SizedBox(height: 4),
      Text('Cada jugador que logra el evento cobra este monto de cada rival.', style: TextStyle(color: t.sub, fontSize: 11)),
      const SizedBox(height: 12),
      ...UnitEventType.values.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text(icons[e]!, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.label, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(e.description, style: TextStyle(color: t.sub, fontSize: 10)),
          ])),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _unitCtrls[e],
              onChanged: (_) {
                final newMap = <UnitEventType, double>{};
                for (final ev in UnitEventType.values) {
                  final v = double.tryParse(_unitCtrls[ev]!.text);
                  if (v != null) newMap[ev] = v;
                }
                _update(_current.copyWith(unitsConfig: UnitsConfig(eventValues: newMap)));
              },
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              textAlign: TextAlign.right,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: t.sub, fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                fillColor: t.surface,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.primary, width: 1.5)),
              ),
            ),
          ),
        ]),
      )),
    ];
  }

  // ── Helpers UI ─────────────────────────────────────────────────────────────
  Widget _label(String text, GolfTheme t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
  );

  Widget _amountField(String hint, TextEditingController ctrl, GolfTheme t,
      {void Function(double)? onChanged}) =>
    TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      textAlign: TextAlign.right,
      style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 16),
      onChanged: onChanged == null ? null : (txt) {
        final v = double.tryParse(txt);
        if (v != null) onChanged(v);
      },
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(color: t.sub, fontSize: 13),
        prefixText: '\$ ',
        prefixStyle: TextStyle(color: t.sub, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        fillColor: t.surface,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
      ),
    );

  Widget _segmented(List<String> labels, int selected, GolfTheme t, void Function(int) onTap) => Row(
    children: labels.asMap().entries.map((e) {
      final sel = e.key == selected;
      return Expanded(child: GestureDetector(
        onTap: () => setState(() => onTap(e.key)),
        child: Container(
          margin: EdgeInsets.only(right: e.key < labels.length - 1 ? 6 : 0),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? t.primary : t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? t.primary : t.divider),
          ),
          alignment: Alignment.center,
          child: Text(e.value, style: TextStyle(
            color: sel ? t.onPrimary : t.text,
            fontWeight: FontWeight.w700, fontSize: 13,
          )),
        ),
      ));
    }).toList(),
  );

  Widget _toggle(String title, String subtitle, bool value, GolfTheme t, void Function(bool) onChanged) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.divider)),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(color: t.sub, fontSize: 11)),
      ])),
      Switch(
        value: value,
        onChanged: (v) { setState(() => onChanged(v)); },
        activeThumbColor: t.accent,
        activeTrackColor: t.accent.withValues(alpha: 0.4),
        inactiveTrackColor: t.divider,
      ),
    ]),
  );
}
