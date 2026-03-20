// ─────────────────────────────────────────────────────────────────────────────
// SCORECARD SCREEN — Tarjeta de la ronda con 3 vistas: Bruto, Neto, 1v1
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../engines/bet_engine.dart';
import '../../engines/game_engine.dart';
import '../../engines/ledger_engine.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../widgets/common_widgets.dart';

class ScorecardScreen extends StatefulWidget {
  const ScorecardScreen({super.key});
  @override State<ScorecardScreen> createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    // Sincronizar desde Firestore al abrir la tarjeta para reflejar
    // cualquier cambio remoto (ej: ventajas editadas externamente).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RoundProvider>().syncFromFirestore();
      }
    });
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final prov  = context.watch<RoundProvider>();
    final t     = prov.theme;
    GolfThemeExt.setCurrent(t);

    if (!prov.hasRound) {
      return Scaffold(backgroundColor: t.bg, body: Center(
        child: Text('No hay ronda activa', style: TextStyle(color: t.sub)),
      ));
    }

    final round = prov.round!;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: _buildAppBar(round, t),
      body: Column(children: [
        _TabBar(ctrl: _tabCtrl, t: t),
        Expanded(child: TabBarView(
          controller: _tabCtrl,
          children: [
            _GrossView(round: round, t: t),
            _NetView(round: round, t: t),
            _OneVOneView(round: round, t: t),
          ],
        )),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar(Round round, GolfTheme t) {
    return AppBar(
      backgroundColor: t.bg,
      elevation: 0,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tarjeta', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 18)),
        Text(round.name, style: TextStyle(color: t.sub, fontSize: 12)),
      ]),
      bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.divider)),
    );
  }
}

class _TabBar extends StatelessWidget {
  final TabController ctrl;
  final GolfTheme t;
  const _TabBar({required this.ctrl, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: t.bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TabBar(
        controller: ctrl,
        indicator: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(10)),
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
        labelColor: t.onPrimary,
        unselectedLabelColor: t.sub,
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Bruto'),
          Tab(text: 'Neto'),
          Tab(text: '1v1'),
        ],
      ),
    );
  }
}

// ── Vista BRUTO ───────────────────────────────────────────────────────────────
class _GrossView extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  const _GrossView({required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    return _ScorecardGrid(round: round, t: t, useNet: false);
  }
}

// ── Vista NETO ────────────────────────────────────────────────────────────────
class _NetView extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  const _NetView({required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    return _ScorecardGrid(round: round, t: t, useNet: true);
  }
}

// ── Scorecard grid compartido (bruto o neto) ──────────────────────────────────
class _ScorecardGrid extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  final bool useNet;
  const _ScorecardGrid({required this.round, required this.t, required this.useNet});

  // Strokes recibidos por un jugador en un hoyo específico
  int _strokes(Player p, CourseHole ch) {
    final hcp = round.getHandicap(p.id);
    return GameEngine.strokesReceived(hcp, ch);
  }

  @override
  Widget build(BuildContext context) {
    final players = round.players;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSegment(players, 1, 9),
              const SizedBox(height: 12),
              _buildSegment(players, 10, 18),
              const SizedBox(height: 12),
              _buildTotalRow(players),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegment(List<Player> players, int from, int to) {
    final holes = round.course.holes.where((h) => h.hole >= from && h.hole <= to).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: Par row
        _headerRow(holes, from, to),
        const SizedBox(height: 4),
        // Player rows
        ...players.map((p) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _playerRow(p, holes, from, to),
        )),
      ],
    );
  }

  Widget _headerRow(List<CourseHole> holes, int from, int to) {
    final parTotal = holes.fold(0, (s, h) => s + h.par);
    return Row(children: [
      // Name column
      SizedBox(width: 80, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(from == 1 ? 'Hoyo' : '', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700)),
          Text('Par', style: TextStyle(color: t.sub, fontSize: 9)),
          Text('SI', style: TextStyle(
            color: t.accent.withValues(alpha: 0.8), fontSize: 9, fontWeight: FontWeight.w700)),
        ],
      )),
      // Hole numbers + par + SI
      ...holes.map((h) => SizedBox(
        width: 30,
        child: Column(children: [
          Text('${h.hole}', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          Text('${h.par}', style: TextStyle(color: t.sub, fontSize: 9), textAlign: TextAlign.center),
          Text('${h.strokeIndex}', style: TextStyle(
            color: t.accent.withValues(alpha: 0.75), fontSize: 9, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        ]),
      )),
      // Subtotal
      Container(
        width: 36,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(children: [
          Text(from == 1 ? 'F9' : 'B9', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          Text('$parTotal', style: TextStyle(color: t.sub, fontSize: 9), textAlign: TextAlign.center),
          const SizedBox(height: 10), // espacio para alinear con la fila SI
        ]),
      ),
    ]);
  }

  Widget _playerRow(Player p, List<CourseHole> holes, int from, int to) {
    int segTotal = 0;
    int completedHoles = 0;

    final cells = holes.map((h) {
      final score = round.getScore(p.id, h.hole);
      int? displayScore;
      int? relPar;
      final strokesThisHole = _strokes(p, h); // strokes recibidos en este hoyo
      if (score.hasScore) {
        if (useNet) {
          final ctx = GameEngine.contextForHole(round, p.id, h.hole, true);
          displayScore = ctx?.netScore;
          relPar = ctx?.relativeToPar;
          segTotal += ctx?.netScore ?? 0;
        } else {
          displayScore = score.grossScore;
          relPar = displayScore != null ? displayScore - h.par : null;
          segTotal += displayScore ?? 0;
        }
        completedHoles++;
      }
      return _ScoreGridCell(
        score: displayScore,
        relPar: relPar,
        par: h.par,
        t: t,
        useNet: useNet,
        strokesReceived: strokesThisHole,
      );
    }).toList();

    final parTotal = holes.fold(0, (s, h) => s + h.par);
    final diff = completedHoles == holes.length ? segTotal - parTotal : null;
    // Handicap de juego del jugador para mostrarlo en el nombre
    final hcpDisplay = round.getHandicap(p.id);

    return Row(children: [
      // Player name + hcp
      SizedBox(width: 80, child: Row(children: [
        GAvatar(name: p.name, colorIndex: p.colorIndex, size: 20),
        const SizedBox(width: 4),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.name.split(' ').first,
                style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 12),
                overflow: TextOverflow.ellipsis),
            if (useNet)
              Text('HCPj ${hcpDisplay.toStringAsFixed(0)}',
                  style: TextStyle(color: t.sub, fontSize: 8)),
          ],
        )),
      ])),
      // Score cells
      ...cells.map((c) => SizedBox(width: 30, child: Center(child: c))),
      // Subtotal
      SizedBox(width: 36, child: Center(child: completedHoles > 0
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$segTotal', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 12)),
              if (diff != null)
                Text(diff > 0 ? '+$diff' : '$diff', style: TextStyle(
                  color: diff < 0 ? t.scoreUnder : diff > 0 ? t.scoreOver : t.sub,
                  fontSize: 9, fontWeight: FontWeight.w700,
                )),
            ])
          : Text('-', style: TextStyle(color: t.sub, fontSize: 12)),
      )),
    ]);
  }

  Widget _buildTotalRow(List<Player> players) {
    return GCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        const SizedBox(width: 80),
        Expanded(child: Wrap(spacing: 12, runSpacing: 4, children: players.map((p) {
          final total = useNet
              ? GameEngine.netTotal(round, p.id, true)
              : GameEngine.grossTotal(round, p.id);
          final parTotal = round.course.totalPar;
          final hasAll = round.course.holes.every((h) => round.getScore(p.id, h.hole).hasScore);
          if (!hasAll) return Row(mainAxisSize: MainAxisSize.min, children: [
            GAvatar(name: p.name, colorIndex: p.colorIndex, size: 18),
            const SizedBox(width: 4),
            Text('-', style: TextStyle(color: t.sub, fontSize: 12)),
          ]);
          final diff = total - parTotal;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            GAvatar(name: p.name, colorIndex: p.colorIndex, size: 18),
            const SizedBox(width: 4),
            Text('$total', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(width: 2),
            Text(diff > 0 ? '+$diff' : '$diff', style: TextStyle(
              color: diff < 0 ? t.scoreUnder : diff > 0 ? t.scoreOver : t.sub,
              fontSize: 10, fontWeight: FontWeight.w700,
            )),
          ]);
        }).toList())),
      ]),
    );
  }
}

class _ScoreGridCell extends StatelessWidget {
  final int? score;
  final int? relPar;
  final int par;
  final GolfTheme t;
  final bool useNet;
  /// Strokes de ventaja que recibe este jugador en este hoyo (0, 1 o 2)
  final int strokesReceived;
  const _ScoreGridCell({
    this.score, this.relPar, required this.par,
    required this.t, required this.useNet,
    this.strokesReceived = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Indicador de ventaja: un pequeño punto por cada stroke recibido
    final strokeDots = strokesReceived > 0
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: List.generate(strokesReceived, (_) => Container(
              width: 4, height: 4,
              margin: const EdgeInsets.only(left: 1),
              decoration: BoxDecoration(
                color: t.profit.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
            )),
          )
        : const SizedBox(height: 4);

    if (score == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26, height: 26,
            alignment: Alignment.center,
            child: Text('·', style: TextStyle(color: t.sub, fontSize: 14)),
          ),
          strokeDots,
        ],
      );
    }

    Color bg = Colors.transparent;
    Color fg = t.text;
    BoxShape shape = BoxShape.rectangle;
    BoxBorder? border;

    final rel = relPar ?? (score! - par);
    if (rel <= -2) { bg = t.scoreUnder; fg = Colors.white; shape = BoxShape.circle; }
    else if (rel == -1) { bg = Colors.transparent; fg = t.scoreUnder; shape = BoxShape.circle; border = Border.all(color: t.scoreUnder, width: 1.5); }
    else if (rel == 1)  { bg = Colors.transparent; fg = t.scoreOver; border = Border.all(color: t.scoreOver, width: 1.5); }
    else if (rel >= 2)  { bg = t.scoreOver; fg = Colors.white; }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: bg, shape: shape,
            borderRadius: shape == BoxShape.rectangle ? BorderRadius.circular(4) : null,
            border: border,
          ),
          alignment: Alignment.center,
          child: Text('$score', style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        strokeDots,
      ],
    );
  }
}

// ── Vista 1v1 ─────────────────────────────────────────────────────────────────
class _OneVOneView extends StatefulWidget {
  final Round round;
  final GolfTheme t;
  const _OneVOneView({required this.round, required this.t});
  @override State<_OneVOneView> createState() => _OneVOneViewState();
}

class _OneVOneViewState extends State<_OneVOneView> {
  String? _p1Id;
  String? _p2Id;

  @override
  void initState() {
    super.initState();
    final players = widget.round.players;
    if (players.length >= 2) {
      _p1Id = players[0].id;
      _p2Id = players[1].id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t     = widget.t;
    final round = widget.round;

    if (round.players.length < 2) {
      return Center(child: Text('Necesitas al menos 2 jugadores', style: TextStyle(color: t.sub)));
    }

    final p1 = round.players.firstWhere((p) => p.id == (_p1Id ?? round.players[0].id));
    final p2 = round.players.firstWhere((p) => p.id == (_p2Id ?? round.players[1].id));

    // Buscar módulos Skins, Nassau y Match+Press en los grupos que incluyen a estos dos jugadores
    final skinsModules      = _findModules(round, p1.id, p2.id, BetModuleType.skins);
    final nassauModules     = _findModules(round, p1.id, p2.id, BetModuleType.nassau);
    final matchPressModules = _findModules(round, p1.id, p2.id, BetModuleType.matchAutoPress);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // ── Selector de jugadores ──────────────────────────────────
        _PlayerSelector(players: round.players, p1: p1, p2: p2, t: t,
          onP1: (pid) => setState(() => _p1Id = pid),
          onP2: (pid) => setState(() => _p2Id = pid),
        ),
        const SizedBox(height: 14),

        // ── Estado principal: Skins (si no hay Nassau/Match) o Match play ──
        _MatchStatusCard(
          round: round, p1: p1, p2: p2, t: t,
          skinsModules:      skinsModules,
          nassauModules:     nassauModules,
          matchPressModules: matchPressModules,
        ),
        const SizedBox(height: 12),

        // ── Panel Nassau (uno por cada módulo Nassau del grupo) ────
        ...nassauModules.map((mod) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _NassauLivePanel(round: round, p1: p1, p2: p2, mod: mod, t: t),
        )),

        // ── Panel Match + Auto Press ───────────────────────────────
        ...matchPressModules.map((mod) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _MatchPressLivePanel(round: round, p1: p1, p2: p2, mod: mod, t: t),
        )),

        // ── Hoyo a hoyo + columna Skins ───────────────────────────
        _HoleByHoleMatch(
          round: round, p1: p1, p2: p2, t: t,
          skinsMod: skinsModules.isNotEmpty ? skinsModules.first : null,
        ),
        const SizedBox(height: 12),

        // ── Botón Carry (al final de la primera vuelta) ────────────
        _CarryPanel(
          round: round, p1: p1, p2: p2, t: t,
          nassauModules:     nassauModules,
          matchPressModules: matchPressModules,
          onApplyCarry: (factor) => _applyCarry(context, factor, nassauModules, matchPressModules),
        ),

        // ── Desglose financiero ────────────────────────────────────
        _FinancialBreakdown(round: round, p1: p1, p2: p2, t: t),
      ]),
    );
  }

  // ── Aplica carry SOLO a los módulos del par activo (p1, p2) ──────────────
  // Usa carryByPair para que cada duelo tenga su propio carry independiente,
  // incluso si varios duelos comparten el mismo módulo en un grupo grande.
  void _applyCarry(BuildContext context, double factor,
      List<BetModuleInstance> nassauMods, List<BetModuleInstance> matchMods) {
    final prov  = context.read<RoundProvider>();
    final round = prov.round!;
    // p1 y p2 son los jugadores activos en la vista (obtenidos del estado)
    final p1Id  = _p1Id ?? round.players[0].id;
    final p2Id  = _p2Id ?? round.players[1].id;

    final newGroups = round.betGroups.map((g) {
      final newModules = g.modules.map((m) {
        if (nassauMods.any((nm) => nm.id == m.id)) {
          // Nassau: carry global por módulo (cada grupo Nassau es típicamente 1v1)
          return m.copyWith(nassauConfig: m.nassau.copyWith(carryApplied: true, carryFactor: factor));
        }
        if (matchMods.any((mm) => mm.id == m.id)) {
          // Match+Press: carry por par para soportar grupos con múltiples duelos
          final existingByPair = Map<String, double>.from(m.matchAutoPress.carryByPair);
          existingByPair[MatchAutoPressConfig.pairKey(p1Id, p2Id)] = factor;
          return m.copyWith(
            matchAutoPressConfig: m.matchAutoPress.copyWith(
              carryByPair: existingByPair,
              // También actualizar legacy fields por si algún código antiguo los usa
              carryApplied: true,
              carryFactor: factor,
            ),
          );
        }
        return m;
      }).toList();
      return BetGroup(id: g.id, name: g.name, format: g.format, playerIds: g.playerIds, modules: newModules);
    }).toList();
    prov.updateBetGroups(newGroups);
  }

  List<BetModuleInstance> _findModules(Round round, String p1Id, String p2Id, BetModuleType type) {
    final mods = <BetModuleInstance>[];
    // Primero buscar en grupos 1v1 exactos (playerIds = exactamente esos 2 jugadores)
    // para que el carry y otros controles sean individuales por partida.
    for (final g in round.betGroups) {
      final ids = g.playerIds;
      if (ids.length == 2 && ids.contains(p1Id) && ids.contains(p2Id)) {
        mods.addAll(g.modules.where((m) => m.type == type));
      }
    }
    // Si no hay grupo exacto, ampliar búsqueda a grupos que contengan a ambos
    if (mods.isEmpty) {
      for (final g in round.betGroups) {
        if (g.playerIds.contains(p1Id) && g.playerIds.contains(p2Id)) {
          mods.addAll(g.modules.where((m) => m.type == type));
        }
      }
    }
    return mods;
  }
}

// Helper: devuelve todos los participantes reales de un módulo en la ronda
List<String> _modGroupPids(Round round, BetModuleInstance mod) {
  for (final g in round.betGroups) {
    for (final m in g.modules) {
      if (m.id == mod.id) {
        return m.participantIds.isNotEmpty ? m.participantIds : g.playerIds;
      }
    }
  }
  return [];
}

// ── Selector de jugadores ──────────────────────────────────────────────────────
class _PlayerSelector extends StatelessWidget {
  final List<Player> players;
  final Player p1, p2;
  final GolfTheme t;
  final void Function(String) onP1, onP2;
  const _PlayerSelector({required this.players, required this.p1, required this.p2,
      required this.t, required this.onP1, required this.onP2});

  @override
  Widget build(BuildContext context) {
    return GCard(child: Row(children: [
      _playerChip(context, p1, onP1),
      Expanded(child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: t.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text('VS', style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 12)),
      ))),
      _playerChip(context, p2, onP2),
    ]));
  }

  Widget _playerChip(BuildContext context, Player p, void Function(String) onSelect) {
    return GestureDetector(
      onTap: () => _showPicker(context, onSelect),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        GAvatar(name: p.name, colorIndex: p.colorIndex, size: 32),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
          Text('HCP ${p.handicapBase.toStringAsFixed(0)}', style: TextStyle(color: t.sub, fontSize: 10)),
        ]),
        const SizedBox(width: 4),
        Icon(Icons.expand_more, color: t.sub, size: 14),
      ]),
    );
  }

  void _showPicker(BuildContext context, void Function(String) onSelect) {
    final t = this.t;
    showModalBottomSheet(context: context, backgroundColor: t.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Seleccionar jugador', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          ...players.map((p) => ListTile(
            leading: GAvatar(name: p.name, colorIndex: p.colorIndex, size: 36),
            title: Text(p.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
            subtitle: Text('HCP ${p.handicapBase.toStringAsFixed(0)}', style: TextStyle(color: t.sub)),
            onTap: () { onSelect(p.id); Navigator.pop(context); },
          )),
        ]),
      ));
  }
}

// ── Match / Skins Status Card ─────────────────────────────────────────────────
// Quick-glance card: color de fondo según estado (verde/azul/rojo),
// jerarquía visual clara en 3 niveles, sin títulos innecesarios.
class _MatchStatusCard extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  final List<BetModuleInstance> skinsModules;
  final List<BetModuleInstance> nassauModules;
  final List<BetModuleInstance> matchPressModules;
  const _MatchStatusCard({
    required this.round, required this.p1, required this.p2, required this.t,
    required this.skinsModules, required this.nassauModules,
    this.matchPressModules = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Si hay Skins (con o sin Match+Press / Nassau), el card principal
    // SIEMPRE muestra _SkinsGlanceCard.
    // El _MatchPressLivePanel y NassauLivePanel ya se renderizan debajo
    // por separado, así que no duplicamos información aquí.
    if (skinsModules.isNotEmpty) {
      return _SkinsGlanceCard(
          round: round, p1: p1, p2: p2, mod: skinsModules.first, t: t);
    }

    // Sin Skins: mostrar card de match play genérico (Nassau / Match+Press)
    return _buildMatchCard(context, extraSkins: null);
  }

  // ── Panel de Match play (cuando hay Nassau o Match+Press) ──────────────────
  Widget _buildMatchCard(BuildContext context, {BetModuleInstance? extraSkins}) {
    final status      = GameEngine.matchPlayStatus(round, p1.id, p2.id, true);
    final lastH       = GameEngine.lastCompletedHole(round, [p1.id, p2.id]);
    final playedCount = List.generate(18, (i) => i + 1)
        .where((h) => round.getScore(p1.id, h).hasScore &&
                      round.getScore(p2.id, h).hasScore)
        .length;
    final n1 = p1.name.split(' ').first;
    final n2 = p2.name.split(' ').first;

    // Colores de estado
    final Color stateColor;
    final Color stateBg;
    final String stateWord;
    final String diffLabel;
    if (status == 0) {
      stateColor = const Color(0xFF1565C0);   // azul
      stateBg    = const Color(0xFF1565C0);
      stateWord  = 'EMPATADO';
      diffLabel  = 'All Square';
    } else if (status > 0) {
      stateColor = const Color(0xFF2E7D32);   // verde
      stateBg    = const Color(0xFF2E7D32);
      stateWord  = 'GANANDO';
      diffLabel  = '$n1  +$status hoyos';
    } else {
      stateColor = const Color(0xFFC62828);   // rojo
      stateBg    = const Color(0xFFC62828);
      stateWord  = 'PERDIENDO';
      diffLabel  = '$n2  +${status.abs()} hoyos';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: stateBg.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: stateBg.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(children: [
          // ── Banda de color superior ──────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: stateColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Column(children: [
              // L1: palabra de estado
              Text(stateWord,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 2),
              // L2: diferencia
              Text(diffLabel,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 22, fontWeight: FontWeight.w900,
                      letterSpacing: -0.5)),
            ]),
          ),

          // ── Datos secundarios ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Column(children: [
              // Fila: Thru + balance neto
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                // Thru
                if (playedCount > 0)
                  Text('Thru $lastH  ·  $playedCount/18',
                      style: TextStyle(color: t.sub, fontSize: 11))
                else
                  Text('Sin hoyos jugados',
                      style: TextStyle(color: t.sub, fontSize: 11)),
                // Balance neto
                _NetBalanceChip(round: round, p1: p1, p2: p2, t: t,
                    stateColor: stateColor),
              ]),
              const SizedBox(height: 8),
              // Fila avatares
              _AvatarScoreRow(
                  p1: p1, p2: p2,
                  score1: null, score2: null,
                  label1: n1, label2: n2,
                  highlightP1: status > 0, highlightP2: status < 0,
                  stateColor: stateColor, t: t),
              // Skins mini si coexisten
              if (extraSkins != null) ...[
                const SizedBox(height: 8),
                Divider(color: t.divider, height: 1),
                const SizedBox(height: 6),
                _SkinsMiniSummary(
                    round: round, p1: p1, p2: p2, mod: extraSkins, t: t),
                const SizedBox(height: 2),
              ] else
                const SizedBox(height: 8),
            ]),
          ),
        ]),
      ),
    );
  }
}

// \u2500\u2500 SKINS QUICK-GLANCE CARD \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
// Card de estado para ronda pura de Skins (sin Nassau).
// Jerarqu\u00eda: banda de color (GANANDO/EMPATADO/PERDIENDO) \u2192
//            diferencia (+2 skins / E) \u2192 score (4 vs 2) \u2192
//            datos secundarios en fila \u00fanica (carryovers, dinero, thru).
class _SkinsGlanceCard extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final BetModuleInstance mod;
  final GolfTheme t;
  const _SkinsGlanceCard({
    required this.round, required this.p1, required this.p2,
    required this.mod, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    // \u2500\u2500 C\u00e1lculos \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    // Siempre forzar path 1v1 bilateral (sin groupPids) para cumP1/cumP2 correctos
    final results  = BetEngine.skinsScorecard(round, p1.id, p2.id, mod);
    final played   = results.where((r) => !r.isPending).toList();
    final last     = played.isNotEmpty ? played.last : null;
    final skins1   = last?.cumP1 ?? 0;
    final skins2   = last?.cumP2 ?? 0;
    final tieCount = results.where((r) => r.isTie).length;
    final currentPot  = results.isNotEmpty ? results.last.pot : mod.skins.valuePerSkin;
    final skinsInPot  = (currentPot / mod.skins.valuePerSkin).round();
    // Usar totalHoles y hoyos reales de la ronda (no hardcodear 18)
    final playedCount = List.generate(round.totalHoles, (i) => i + 1)
        .where((h) => round.getScore(p1.id, h).hasScore &&
                      round.getScore(p2.id, h).hasScore)
        .length;
    final lastH = GameEngine.lastCompletedHole(round, [p1.id, p2.id]);

    // p1 es quien consulta (posici\u00f3n 0); p1Lead positivo = p1 gana
    final lead = skins1 - skins2;

    // \u2500\u2500 Paleta de estado \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    final Color bandColor;
    final String stateWord;
    final String diffLabel;

    if (playedCount == 0) {
      // Sin hoyos jugados: estado neutro
      bandColor  = const Color(0xFF455A64);   // gris azulado
      stateWord  = 'EN JUEGO';
      diffLabel  = '0 skins';
    } else if (lead == 0) {
      bandColor  = const Color(0xFF1565C0);   // azul
      stateWord  = 'EMPATADO';
      diffLabel  = 'E  \u00b7  ${skins1} vs ${skins2}';
    } else if (lead > 0) {
      bandColor  = const Color(0xFF2E7D32);   // verde
      stateWord  = 'GANANDO';
      diffLabel  = '+$lead skins  \u00b7  $skins1 vs $skins2';
    } else {
      bandColor  = const Color(0xFFC62828);   // rojo
      stateWord  = 'PERDIENDO';
      diffLabel  = '$lead skins  \u00b7  $skins1 vs $skins2';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: bandColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: bandColor.withValues(alpha: 0.30), width: 1.5),
        ),
        child: Column(children: [

          // \u2500\u2500 L1: Banda de color \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: bandColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Column(children: [
              // Estado (peque\u00f1o, espaciado)
              Text(stateWord,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w800, letterSpacing: 1.8)),
              const SizedBox(height: 4),
              // Diferencia + score (grande, protagonista)
              Text(diffLabel,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 22, fontWeight: FontWeight.w900,
                      letterSpacing: -0.5)),
            ]),
          ),

          // \u2500\u2500 L2: Fila de datos secundarios \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(children: [
              // Avatares con nombres
              GAvatar(name: p1.name, colorIndex: p1.colorIndex, size: 26),
              const SizedBox(width: 5),
              Expanded(child: Text(p1.name.split(' ').first,
                  style: TextStyle(color: t.text, fontSize: 11,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis)),

              // Pills centrales: carryovers + dinero neto
              Row(mainAxisSize: MainAxisSize.min, children: [
                // Thru
                if (playedCount > 0) ...[
                  _GlancePill(
                    label: 'Thru $lastH',
                    color: t.sub,
                    bgAlpha: 0.06,
                    t: t,
                  ),
                  const SizedBox(width: 6),
                ],
                // Carryovers (solo si hay carry activo o empates)
                if (tieCount > 0) ...[
                  _GlancePill(
                    label: skinsInPot > 1 ? '\ud83d\udd25\u00d7$skinsInPot' : '$tieCount carries',
                    color: t.accent,
                    bgAlpha: 0.10,
                    t: t,
                  ),
                  const SizedBox(width: 6),
                ],
                // Dinero neto
                _NetBalanceChip(
                    round: round, p1: p1, p2: p2, t: t,
                    stateColor: bandColor),
              ]),

              const SizedBox(width: 5),
              Expanded(child: Text(p2.name.split(' ').first,
                  textAlign: TextAlign.end,
                  style: TextStyle(color: t.text, fontSize: 11,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 5),
              GAvatar(name: p2.name, colorIndex: p2.colorIndex, size: 26),
            ]),
          ),
        ]),
      ),
    );
  }
}

// \u2500\u2500 Pill minimalista reutilizable \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
class _GlancePill extends StatelessWidget {
  final String label;
  final Color color;
  final double bgAlpha;
  final GolfTheme t;
  const _GlancePill({required this.label, required this.color,
      required this.bgAlpha, required this.t});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10,
              fontWeight: FontWeight.w700)),
    );
  }
}

// \u2500\u2500 Chip de balance neto (positivo verde, negativo rojo, cero gris) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
class _NetBalanceChip extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  final Color stateColor;
  const _NetBalanceChip({required this.round, required this.p1,
      required this.p2, required this.t, required this.stateColor});

  @override
  Widget build(BuildContext context) {
    context.watch<RoundProvider>(); // reconstruir al cambiar scores
    // Usar SOLO el balance de skins (no incluir nassau u otras apuestas)
    final bd   = LedgerEngine.breakdownBetween(round, p1.id, p2.id);
    final bal1 = bd[BetModuleType.skins] ?? 0.0;
    // balance neto desde perspectiva de p1
    final label = bal1 == 0
        ? '\$0'
        : bal1 > 0
            ? '+\$${bal1.toStringAsFixed(0)}'
            : '-\$${bal1.abs().toStringAsFixed(0)}';
    final color = bal1 == 0 ? t.sub : bal1 > 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10,
              fontWeight: FontWeight.w800)),
    );
  }
}

// \u2500\u2500 Fila de avatares con scores (reutilizado en Match card) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
class _AvatarScoreRow extends StatelessWidget {
  final Player p1, p2;
  final int? score1, score2;
  final String label1, label2;
  final bool highlightP1, highlightP2;
  final Color stateColor;
  final GolfTheme t;
  const _AvatarScoreRow({
    required this.p1, required this.p2,
    this.score1, this.score2,
    required this.label1, required this.label2,
    required this.highlightP1, required this.highlightP2,
    required this.stateColor, required this.t,
  });
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _chip(p1, score1, label1, highlightP1),
      _chip(p2, score2, label2, highlightP2),
    ]);
  }
  Widget _chip(Player p, int? score, String label, bool highlight) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      GAvatar(name: p.name, colorIndex: p.colorIndex, size: 28),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(
            color: highlight ? stateColor : t.text,
            fontSize: 11, fontWeight: FontWeight.w700)),
        if (score != null)
          Text('$score', style: TextStyle(
              color: highlight ? stateColor : t.sub,
              fontSize: 16, fontWeight: FontWeight.w900)),
      ]),
    ]);
  }
}

// \u2500\u2500 Resumen compacto de Skins para panel Match+Skins \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
class _SkinsMiniSummary extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final BetModuleInstance mod;
  final GolfTheme t;
  const _SkinsMiniSummary({
    required this.round, required this.p1, required this.p2,
    required this.mod, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    // Path 1v1 bilateral: sin groupPids para cumP1/cumP2 correctos en duelo p1 vs p2
    final results  = BetEngine.skinsScorecard(round, p1.id, p2.id, mod);
    final played   = results.where((r) => !r.isPending).toList();
    final last     = played.isNotEmpty ? played.last : null;
    final skins1   = last?.cumP1 ?? 0;
    final skins2   = last?.cumP2 ?? 0;
    final tieCount = results.where((r) => r.isTie).length;
    final currentPot = results.isNotEmpty ? results.last.pot : mod.skins.valuePerSkin;
    final skinsInPot = (currentPot / mod.skins.valuePerSkin).round();

    final n1 = p1.name.split(' ').first;
    final n2 = p2.name.split(' ').first;

    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      // Encabezado skins
      Row(children: [
        Icon(Icons.style_rounded, color: t.accent, size: 12),
        const SizedBox(width: 4),
        Text('SKINS', style: TextStyle(color: t.accent, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ]),

      // Marcador compacto
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$n1 $skins1',
            style: TextStyle(
              color: skins1 > skins2 ? t.profit : t.sub,
              fontSize: 11, fontWeight: FontWeight.w700)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('·', style: TextStyle(color: t.divider, fontSize: 14)),
        ),
        Text('$skins2 $n2',
            style: TextStyle(
              color: skins2 > skins1 ? t.profit : t.sub,
              fontSize: 11, fontWeight: FontWeight.w700)),
      ]),

      // Empates + pot
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (tieCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.divider),
            ),
            child: Text('=$tieCount',
                style: TextStyle(color: t.sub, fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
        ],
        if (mod.skins.carryOver && skinsInPot > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.accent.withValues(alpha: 0.30)),
            ),
            child: Text('×$skinsInPot 🔥',
                style: TextStyle(color: t.accent, fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
      ]),
    ]);
  }
}

class _BalanceRow extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  const _BalanceRow({required this.round, required this.p1, required this.p2, required this.t});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final bal1 = prov.balances[p1.id] ?? 0.0;
    final bal2 = prov.balances[p2.id] ?? 0.0;
    return Row(children: [
      Expanded(child: Column(children: [
        GAvatar(name: p1.name, colorIndex: p1.colorIndex, size: 32),
        const SizedBox(height: 4),
        BalChip(amount: bal1),
      ])),
      Expanded(child: Column(children: [
        GAvatar(name: p2.name, colorIndex: p2.colorIndex, size: 32),
        const SizedBox(height: 4),
        BalChip(amount: bal2),
      ])),
    ]);
  }
}

// ── Nassau Live Panel ──────────────────────────────────────────────────────────
// Muestra Front 9 / Back 9 / Total 18 con marcador en vivo + presiones abiertas
// \u2500\u2500 NASSAU QUICK-GLANCE PANEL \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
// Tres sub-cards (F9 / B9 / Total) cada una con su propia banda de color.
// Presiones como fila compacta debajo sin secci\u00f3n separada.
class _NassauLivePanel extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final BetModuleInstance mod;
  final GolfTheme t;
  const _NassauLivePanel({
    required this.round, required this.p1, required this.p2,
    required this.mod, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final status     = BetEngine.nassauLiveStatus(round, p1.id, p2.id, mod);
    final n1         = p1.name.split(' ').first;
    final n2         = p2.name.split(' ').first;
    final openPresses = status.presses.where((p) => p.isOpen).length;
    final totalPlayed = status.frontPlayed + status.backPlayed;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.divider, width: 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // \u2500\u2500 Header compacto \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              Text('NASSAU',
                  style: TextStyle(color: t.sub, fontSize: 10,
                      fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const Spacer(),
              // Thru
              if (totalPlayed > 0)
                Text('$totalPlayed/18 hoyos',
                    style: TextStyle(color: t.sub, fontSize: 10)),
              // Presiones
              if (mod.pressEnabled) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: openPresses > 0
                        ? t.accent.withValues(alpha: 0.12)
                        : t.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    openPresses > 0
                        ? '$openPresses press\u2009\ud83d\udd25'
                        : 'Press ON',
                    style: TextStyle(
                        color: openPresses > 0 ? t.accent : t.primary,
                        fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 10),

          // \u2500\u2500 Tres sub-cards quick-glance \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(children: [
              Expanded(child: _NassauSegment(
                label: 'F9', played: status.frontPlayed, total: 9,
                score: status.front, value: status.frontVal,
                p1Name: n1, p2Name: n2, t: t,
              )),
              const SizedBox(width: 6),
              Expanded(child: _NassauSegment(
                label: 'B9', played: status.backPlayed, total: 9,
                score: status.back, value: status.backVal,
                p1Name: n1, p2Name: n2, t: t,
              )),
              const SizedBox(width: 6),
              Expanded(child: _NassauSegment(
                label: '18', played: totalPlayed, total: 18,
                score: status.total, value: status.totalVal,
                p1Name: n1, p2Name: n2, t: t,
              )),
            ]),
          ),

          // \u2500\u2500 Presiones: fila compacta \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          if (status.presses.isNotEmpty) ...[
            Divider(color: t.divider.withValues(alpha: 0.5), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: status.presses.map((press) {
                  final pressLoserName = press.loser == p1.id ? n1 : n2;
                  final pressScore = press.loser == p1.id
                      ? press.score : -press.score;
                  final Color pColor = pressScore == 0
                      ? t.sub
                      : pressScore > 0
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFC62828);
                  final String pLabel = pressScore == 0
                      ? 'AS'
                      : pressScore > 0
                          ? '$n1  +$pressScore'
                          : '$n2  +${pressScore.abs()}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: press.isOpen ? t.accent : t.divider,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Press H${press.startHole}\u2013${press.endHole}',
                          style: TextStyle(color: t.sub, fontSize: 10)),
                      const SizedBox(width: 4),
                      Text('($pressLoserName)',
                          style: TextStyle(color: t.sub.withValues(alpha: 0.6),
                              fontSize: 10)),
                      const Spacer(),
                      Text(pLabel,
                          style: TextStyle(color: pColor,
                              fontSize: 11, fontWeight: FontWeight.w800)),
                      if (press.isOpen) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('EN JUEGO',
                              style: TextStyle(color: t.accent,
                                  fontSize: 8, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ]),
                  );
                }).toList(),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// \u2500\u2500 Sub-card de segmento Nassau: banda de color + dato principal \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
class _NassauSegment extends StatelessWidget {
  final String label;
  final int played, total, score;
  final double value;
  final String p1Name, p2Name;
  final GolfTheme t;

  const _NassauSegment({
    required this.label, required this.played, required this.total,
    required this.score, required this.value,
    required this.p1Name, required this.p2Name, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    // Estado del segmento
    final Color bandColor;
    final String stateWord;
    final String scoreWord;

    if (played == 0) {
      bandColor = const Color(0xFF455A64);
      stateWord = '\u2013';
      scoreWord = '';
    } else if (score == 0) {
      bandColor = const Color(0xFF1565C0);   // azul = empatado
      stateWord = 'AS';
      scoreWord = '';
    } else if (score > 0) {
      bandColor = const Color(0xFF2E7D32);   // verde = p1 gana
      stateWord = '$p1Name';
      scoreWord = '+$score';
    } else {
      bandColor = const Color(0xFFC62828);   // rojo = p2 gana
      stateWord = '$p2Name';
      scoreWord = '+${score.abs()}';
    }

    final isDone = played >= total;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bandColor.withValues(alpha: 0.35)),
        ),
        child: Column(children: [
          // Banda de color con estado
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: bandColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Column(children: [
              // Nombre del segmento (F9 / B9 / 18)
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 2),
              // Estado condensado: nombre o AS o guión
              Text(stateWord,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 13, fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
              if (scoreWord.isNotEmpty)
                Text(scoreWord,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
          // Pie: progreso o valor
          Container(
            color: bandColor.withValues(alpha: 0.07),
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Center(
              child: Text(
                isDone
                    ? '\$${value.toStringAsFixed(0)}'
                    : '$played/$total',
                style: TextStyle(
                  color: isDone ? bandColor : t.sub,
                  fontSize: 10,
                  fontWeight: isDone ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Match + Auto Press — Panel en vivo ──────────────────────────────────────
// Muestra el estado del match principal + lista dinámica de presiones.
// Usa colores: verde (arriba), azul (empate), rojo (abajo) por cada presión.
class _MatchPressLivePanel extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final BetModuleInstance mod;
  final GolfTheme t;
  const _MatchPressLivePanel({required this.round, required this.p1, required this.p2, required this.mod, required this.t});

  @override
  Widget build(BuildContext context) {
    final cfg = mod.matchAutoPress;
    final n1  = p1.name.split(' ').first;
    final n2  = p2.name.split(' ').first;

    // Estado general: quién va ganando el match (score global H1-totalHoles)
    final presses  = BetEngine.matchAutoPressLive(round, p1.id, p2.id, mod);

    // Balance SOLO de Match+Press calculado desde live status (fiable, independiente de pids del módulo)
    // Suma: para cada segmento con resultado, +value si p1 gana (leadingPlayerId == p1.id), -value si p2 gana
    double mpBal = 0.0;
    for (final pr in presses) {
      if (pr.played == 0) continue;
      if (pr.leadingPlayerId == p1.id) mpBal += pr.value;
      if (pr.leadingPlayerId == p2.id) mpBal -= pr.value;
    }
    final balColor  = mpBal > 0.005 ? t.profit : mpBal < -0.005 ? t.loss : t.sub;
    final primary  = presses.isNotEmpty ? presses.first : null; // siempre el Match principal
    final matchScore   = primary?.score ?? 0;
    final pressesWon1  = presses.skip(1).where((pr) => pr.leadingPlayerId == p1.id && pr.played > 0).length;
    final pressesWon2  = presses.skip(1).where((pr) => pr.leadingPlayerId == p2.id && pr.played > 0).length;
    final activePresses = presses.skip(1).length;

    String matchLabel;
    Color  matchColor;
    if (matchScore == 0) {
      matchLabel = 'AS';  matchColor = const Color(0xFF1565C0);
    } else if (matchScore > 0) {
      matchLabel = '$n1  ${matchScore}UP';  matchColor = t.profit;
    } else {
      matchLabel = '$n2  ${matchScore.abs()}UP';  matchColor = t.loss;
    }

    return GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Cabecera ────────────────────────────────────────────────────────
      Row(children: [
        Text('⚔️', style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Text('MATCH + PRESS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8))),
        // Balance solo Match+Press
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: balColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: balColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            mpBal.abs() < 0.005 ? 'AS' : '${mpBal > 0 ? '+' : ''}\$${mpBal.abs().toStringAsFixed(0)}',
            style: TextStyle(color: balColor, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
      ]),
      const SizedBox(height: 12),

      // ── Estado del match ─────────────────────────────────────────────────
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(matchLabel,
                style: TextStyle(color: matchColor, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(
              () {
                final matchVal = (primary?.value ?? cfg.matchValue).toStringAsFixed(0);
                if (activePresses == 0) return 'Match  •  \$$matchVal';
                // Tomar el valor de presión de la primera presión activa (ya incluye carry)
                final firstPressVal = presses.skip(1).isNotEmpty
                    ? presses.skip(1).first.value.toStringAsFixed(0)
                    : cfg.pressValue.toStringAsFixed(0);
                return 'Match  •  \$$matchVal   +  $activePresses × \$$firstPressVal press';
              }(),
              style: TextStyle(color: t.sub, fontSize: 10),
            ),
          ]),
        ),
        if (activePresses > 0)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$n1  $pressesWon1 – $pressesWon2  $n2',
                style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Presiones', style: TextStyle(color: t.sub, fontSize: 9)),
          ]),
      ]),
      const SizedBox(height: 6),
      // Trigger info
      Row(children: [
        Icon(Icons.info_outline, color: t.sub, size: 11),
        const SizedBox(width: 4),
        Text('Presión automática al llegar a ${cfg.pressTriggerValue} up',
            style: TextStyle(color: t.sub, fontSize: 10)),
      ]),

      // ── Panel visual de presiones ────────────────────────────────────────
      if (presses.length > 1) ...[
        const SizedBox(height: 10),
        Divider(height: 1, color: t.sub.withValues(alpha: 0.15)),
        const SizedBox(height: 10),
        // Título
        Text('PRESIONES ACTIVAS', style: TextStyle(color: t.sub, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.7)),
        const SizedBox(height: 8),
        // Fila de pastillas — una por segmento (excluye el match principal)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: presses.skip(1).map((pr) {
            // Color según estado: azul=AS, verde=p1 gana, rojo=p2 gana, gris=no jugado
            final Color bgBase;
            final String scoreLabel;
            final String leadLabel;
            if (pr.played == 0) {
              bgBase = t.sub;
              scoreLabel = '–';
              leadLabel = 'Abierta';
            } else if (pr.score == 0) {
              bgBase = const Color(0xFF1565C0);
              scoreLabel = 'AS';
              leadLabel = 'Empate';
            } else if (pr.leadingPlayerId == p1.id) {
              bgBase = t.profit;
              scoreLabel = '${pr.score.abs()}UP';
              leadLabel = n1;
            } else {
              bgBase = t.loss;
              scoreLabel = '${pr.score.abs()}UP';
              leadLabel = n2;
            }

            // Etiqueta del segmento
            final isDigit = pr.sequenceNumber == 2;
            final segTag = isDigit ? 'DÍGITO' : 'PRESS ${pr.sequenceNumber - 1}';
            final holeRange = 'H${pr.startHole}–${pr.endHole}';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: bgBase.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: bgBase.withValues(alpha: 0.35), width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Rango de hoyos + tag
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(segTag, style: TextStyle(color: bgBase, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    const SizedBox(width: 4),
                    Text(holeRange, style: TextStyle(color: t.sub, fontSize: 8)),
                  ]),
                  const SizedBox(height: 3),
                  // Score en grande
                  Text(scoreLabel, style: TextStyle(color: bgBase, fontSize: 13, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 1),
                  // Quién lidera + valor
                  Text('$leadLabel  •  \$${pr.value.toStringAsFixed(0)}',
                      style: TextStyle(color: t.sub, fontSize: 8)),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    ]));
  }
}

// ── Panel Carry ──────────────────────────────────────────────────────────────
// Aparece al final de la primera vuelta cuando hay módulos Nassau o Match+Press.
// Solo visible en rondas de 18 hoyos. Muestra botón para activar carry.
class _CarryPanel extends StatefulWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  final List<BetModuleInstance> nassauModules;
  final List<BetModuleInstance> matchPressModules;
  final void Function(double factor) onApplyCarry;
  const _CarryPanel({
    required this.round, required this.p1, required this.p2, required this.t,
    required this.nassauModules, required this.matchPressModules,
    required this.onApplyCarry,
  });
  @override State<_CarryPanel> createState() => _CarryPanelState();
}

class _CarryPanelState extends State<_CarryPanel> {
  // ── Determinar si mostrar el panel ──────────────────────────────────────────
  // Condiciones:
  // 1. Hay módulos Nassau o Match+Press
  // 2. La ronda es de 18 hoyos
  // 3. La primera vuelta está completada (los 9 hoyos del primer segmento)
  // 4. El carry no ha sido aplicado aún

  bool _firstNineComplete(Round round) {
    final firstHoles = round.startingNine == StartingNine.back
        ? List.generate(9, (i) => i + 10)   // hoyos 10-18
        : List.generate(9, (i) => i + 1);   // hoyos 1-9
    return firstHoles.every((h) =>
        round.getScore(widget.p1.id, h).hasScore &&
        round.getScore(widget.p2.id, h).hasScore);
  }

  bool get _carryAlreadyApplied {
    final p1Id = widget.p1.id;
    final p2Id = widget.p2.id;
    // Verificar carry por par (nuevo mecanismo) o legacy carry global
    final matchCarry = widget.matchPressModules.any((m) =>
        m.matchAutoPress.carryAppliedForPair(p1Id, p2Id));
    final nassauCarry = widget.nassauModules.any((m) => m.nassau.carryApplied);
    return nassauCarry || matchCarry;
  }

  bool get _hasCarryModules =>
      widget.nassauModules.isNotEmpty || widget.matchPressModules.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    final t = widget.t;
    if (round.totalHoles < 18) return const SizedBox.shrink();
    if (!_hasCarryModules)     return const SizedBox.shrink();

    final firstNineDone = _firstNineComplete(round);
    if (!firstNineDone && !_carryAlreadyApplied) return const SizedBox.shrink();

    final n1 = widget.p1.name.split(' ').first;
    final n2 = widget.p2.name.split(' ').first;

    // Calcular factor por defecto (×2) y qué apuestas se verían afectadas
    final defaultFactor = 2.0;
    final nassauDesc = widget.nassauModules.map((m) {
      final cfg = m.nassau;
      final b = cfg.effectiveBackValue;
      final tot = cfg.effectiveTotalValue;
      return 'Nassau B9: \$${b.toStringAsFixed(0)}  ·  18H: \$${tot.toStringAsFixed(0)}';
    }).join('\n');
    final matchDesc = widget.matchPressModules.map((m) {
      final cfg = m.matchAutoPress;
      final p1Id = widget.p1.id;
      final p2Id = widget.p2.id;
      final alreadyApplied = cfg.carryAppliedForPair(p1Id, p2Id);
      final currentFactor  = cfg.carryFactorForPair(p1Id, p2Id);
      final mv = alreadyApplied ? cfg.matchValue * currentFactor : cfg.matchValue * defaultFactor;
      final pv = alreadyApplied ? cfg.pressValue * currentFactor : cfg.pressValue * defaultFactor;
      return 'Match: \$${mv.toStringAsFixed(0)}  ·  Press: \$${pv.toStringAsFixed(0)}';
    }).join('\n');

    if (_carryAlreadyApplied) {
      // Panel indicador: carry ya activo
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GCard(child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: t.profit.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.profit.withValues(alpha: 0.4)),
            ),
            child: Text('×2', style: TextStyle(color: t.profit, fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CARRY ACTIVO', style: TextStyle(color: t.profit, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.8)),
            const SizedBox(height: 2),
            Text('Las apuestas de la 2ª vuelta están duplicadas', style: TextStyle(color: t.sub, fontSize: 11)),
          ])),
        ])),
      );
    }

    // Panel con botón para activar carry
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.currency_exchange, color: t.accent, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('CARRY', style: TextStyle(color: t.sub, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.8))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.accent.withValues(alpha: 0.3)),
            ),
            child: Text('Al entrar la 2ª vuelta', style: TextStyle(color: t.accent, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          '$n1 o $n2 pueden pedir carry: las apuestas de la 2ª vuelta se duplican.',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),
        const SizedBox(height: 10),
        // Preview de los nuevos valores
        if (nassauDesc.isNotEmpty) ...[
          Text(nassauDesc, style: TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
        ],
        if (matchDesc.isNotEmpty) ...[
          Text(matchDesc, style: TextStyle(color: t.text, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
        ],
        // Botón
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Text('×2', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            label: const Text('Activar Carry', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            onPressed: () => _showCarryDialog(context, defaultFactor, n1, n2),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ])),
    );
  }

  void _showCarryDialog(BuildContext context, double defaultFactor, String n1, String n2) {
    final t = widget.t;
    final ctrl = TextEditingController(text: defaultFactor.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Row(children: [
          Text('⚡', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text('Carry', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Las apuestas de la 2ª vuelta (Back 9 y Match total) se multiplican por el factor indicado.',
            style: TextStyle(color: t.sub, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text('FACTOR DE MULTIPLICACIÓN', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 22),
            decoration: InputDecoration(
              prefixText: '×',
              prefixStyle: TextStyle(color: t.accent, fontWeight: FontWeight.w800, fontSize: 18),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              fillColor: t.surface, filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.accent, width: 1.5)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Por defecto ×2 (dobla todas las apuestas de la 2ª vuelta)', style: TextStyle(color: t.sub, fontSize: 10)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: t.sub)),
          ),
          ElevatedButton(
            onPressed: () {
              final factor = double.tryParse(ctrl.text) ?? defaultFactor;
              if (factor > 0) {
                widget.onApplyCarry(factor);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white),
            child: Text('Confirmar Carry ×${ctrl.text}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Hoyo a hoyo + columna Skins ───────────────────────────────────────────────
// Vista 1v1: muestra bruto del jugador BASE (menor HCP) y neto del RIVAL
// Los strokes se calculan como diferencia entre handicaps (no individual vs par).
class _HoleByHoleMatch extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  final BetModuleInstance? skinsMod;
  const _HoleByHoleMatch({
    required this.round, required this.p1, required this.p2,
    required this.t, this.skinsMod,
  });

  @override
  Widget build(BuildContext context) {
    // En la vista 1v1 (_HoleByHoleMatch) siempre usar el camino bilateral (1v1),
    // sin importar cuántos participantes tenga el módulo en el grupo.
    // Esto garantiza que la columna SKINS muestre los ganadores del duelo
    // entre los dos jugadores visibles, no de un tercer jugador del grupo.
    final List<SkinHoleResult>? skinsResults = skinsMod != null
        ? BetEngine.skinsScorecard(round, p1.id, p2.id, skinsMod!)
        : null;
    final hasSkins = skinsResults != null;

    // Determinar base/receptor y diff CORRECTOS usando manualHandicaps
    // manual[p1][p2] ya ES la diferencia de strokes:
    //   > 0 → p1 recibe esos strokes de p2  → p1 es receptor
    //   < 0 → p1 da esos strokes a p2       → p2 es receptor
    //   null → usar diferencia de HCPs normales
    final hcp1 = round.getHandicap(p1.id);
    final hcp2 = round.getHandicap(p2.id);
    final rp1 = round.roundPlayers.firstWhere(
      (r) => r.playerId == p1.id,
      orElse: () => RoundPlayer(playerId: p1.id, handicapEnRonda: hcp1),
    );
    final manual = rp1.manualHandicaps[p2.id];

    final Player basePlayer;
    final Player receiverPlayer;
    final double hcpBase;
    final double hcpReceiver;

    if (manual != null && manual != 0) {
      // manual > 0: p1 recibe de p2  → p2=base, p1=receptor, diff=manual
      // manual < 0: p1 da a p2       → p1=base, p2=receptor, diff=|manual|
      if (manual > 0) {
        basePlayer     = p2;
        receiverPlayer = p1;
        hcpBase        = hcp2;
        hcpReceiver    = hcp2 + manual; // diff = manual
      } else {
        basePlayer     = p1;
        receiverPlayer = p2;
        hcpBase        = hcp1;
        hcpReceiver    = hcp1 + (-manual); // diff = |manual|
      }
    } else {
      // Sin manual: usar diferencia de HCPs normales
      final p1IsBase = hcp1 <= hcp2;
      basePlayer     = p1IsBase ? p1 : p2;
      receiverPlayer = p1IsBase ? p2 : p1;
      hcpBase        = p1IsBase ? hcp1 : hcp2;
      hcpReceiver    = p1IsBase ? hcp2 : hcp1;
    }

    final allHoles = round.course.holes;

    return GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header card ─────────────────────────────────────────────────────
      Row(children: [
        Expanded(child: Text('HOYO A HOYO',
            style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8))),
        if (hasSkins) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.accent.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.local_fire_department, color: t.accent, size: 11),
              const SizedBox(width: 3),
              Text('Skins ${skinsMod!.carryOver ? "+ carry" : "sin carry"}',
                  style: TextStyle(color: t.accent, fontSize: 9, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ]),

      // ── Leyenda de ventaja ───────────────────────────────────────────────
      const SizedBox(height: 6),
      _handicapLegend(basePlayer, receiverPlayer, hcpBase, hcpReceiver, allHoles, t, round.startingNine),
      const SizedBox(height: 8),

      // ── Cabecera de columnas ─────────────────────────────────────────────
      Row(children: [
        // Hoyo
        SizedBox(width: 28, child: Text('H',
            style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700))),
        // Jugador base (bruto) — izquierda
        Expanded(child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(basePlayer.name.split(' ').first,
                style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: t.divider),
              ),
              child: Text('BRUTO', style: TextStyle(color: t.sub, fontSize: 7, fontWeight: FontWeight.w700)),
            ),
          ],
        )),
        const SizedBox(width: 4),
        // Centro (flecha / resultado)
        const SizedBox(width: 24),
        const SizedBox(width: 4),
        // Jugador receptor (neto) — derecha
        Expanded(child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: t.primary.withValues(alpha: 0.3)),
            ),
            child: Text('NETO', style: TextStyle(color: t.primary, fontSize: 7, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
          Text(receiverPlayer.name.split(' ').first,
              style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w600)),
        ])),
        if (hasSkins)
          SizedBox(width: 68, child: Text('SKINS',
              style: TextStyle(color: t.accent, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              textAlign: TextAlign.center)),
      ]),
      const SizedBox(height: 4),
      Divider(color: t.divider, height: 1),

      // ── Filas de hoyos (en el orden de la ronda: startingNine) ──────────────
      // Mostrar en el orden que se jugaron para que los skins y el marcador
      // sean coherentes visualmente con la secuencia real de la partida.
      ...() {
        final holeMap = { for (final ch in round.course.holes) ch.hole: ch };
        final order = round.startingNine == StartingNine.back
            ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
            : List.generate(18, (i) => i + 1);
        return order.map((hNum) {
          final ch = holeMap[hNum]!;
          final sBase     = round.getScore(basePlayer.id,     ch.hole);
          final sReceiver = round.getScore(receiverPlayer.id, ch.hole);
          if (!sBase.hasScore && !sReceiver.hasScore) return const SizedBox.shrink();

          // Strokes que recibe el rival (diferencia de HCPs en este hoyo)
          final strokesHere = GameEngine.strokesReceivedVs(
            hcpHigher:    hcpReceiver,
          hcpLower:     hcpBase,
          ch:           ch,
          allHoles:     allHoles,
          startingNine: round.startingNine,
        );

        // Scores a mostrar
        final grossBase     = sBase.hasScore     ? sBase.grossScore!     : null;
        final grossReceiver = sReceiver.hasScore ? sReceiver.grossScore! : null;
        final netReceiver   = grossReceiver != null ? grossReceiver - strokesHere : null;

        // Ganador del hoyo: compara bruto base vs neto receptor
        bool? baseWins;
        if (grossBase != null && netReceiver != null) {
          if (grossBase < netReceiver)       baseWins = true;
          else if (grossBase > netReceiver)  baseWins = false;
          // null = empate
        }

        final skinResult = (hasSkins && skinsResults != null)
            ? skinsResults.firstWhere(
                (r) => r.hole == ch.hole,
                orElse: () => SkinHoleResult(
                    hole: ch.hole, winner: null, isPending: true,
                    pot: skinsMod?.value ?? 0, cumP1: 0, cumP2: 0))
            : null;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            // Resaltar filas donde hay ventaja asignada
            color: strokesHere > 0
                ? t.primary.withValues(alpha: 0.03)
                : Colors.transparent,
            border: Border(bottom: BorderSide(color: t.divider.withValues(alpha: 0.4))),
          ),
          child: Row(children: [
            // Número de hoyo + indicador de ventaja
            SizedBox(width: 28, child: Row(children: [
              Text('${ch.hole}', style: TextStyle(
                color: strokesHere > 0 ? t.primary : t.sub,
                fontSize: 12,
                fontWeight: strokesHere > 0 ? FontWeight.w800 : FontWeight.w600,
              )),
              // Punto(s) de ventaja
              if (strokesHere > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(strokesHere, (_) => Container(
                      width: 5, height: 5,
                      margin: const EdgeInsets.only(bottom: 1),
                      decoration: BoxDecoration(
                        color: t.profit,
                        shape: BoxShape.circle,
                      ),
                    )),
                  ),
                ),
            ])),

            // Score BASE (bruto)
            Expanded(child: Align(
              alignment: Alignment.centerRight,
              child: grossBase != null
                  ? _miniScore(grossBase, ch.par, baseWins == true, false, t)
                  : _dash(t),
            )),

            // Flecha / resultado central
            SizedBox(width: 28, child: Center(
              child: baseWins == null
                ? (sBase.hasScore && sReceiver.hasScore
                    ? Text('=', style: TextStyle(color: t.sub, fontSize: 12, fontWeight: FontWeight.w700))
                    : Text('·', style: TextStyle(color: t.divider, fontSize: 16)))
                : Icon(
                    baseWins ? Icons.arrow_back_ios : Icons.arrow_forward_ios,
                    color: t.primary, size: 11,
                  ),
            )),

            // Score RECEPTOR (neto = bruto − ventaja)
            Expanded(child: netReceiver != null
                ? _netScoreCell(netReceiver, grossReceiver!, ch.par, baseWins == false, strokesHere, t)
                : (grossReceiver != null ? _dash(t) : _dash(t))),

            // Columna Skins
            if (hasSkins)
              SizedBox(width: 68, child: _SkinsCellWidget(
                  result: skinResult!, mod: skinsMod!, p1: p1, p2: p2, t: t)),
          ]),
        );
        }).whereType<Widget>();
      }(),

      // ── Totales Skins al final ───────────────────────────────────────────
      if (hasSkins && skinsResults.isNotEmpty) ...[
        const SizedBox(height: 8),
        _SkinsTotalsRow(results: skinsResults, round: round, p1: p1, p2: p2, mod: skinsMod!, t: t),
      ],
    ]));
  }

  // Leyenda compacta: muestra la diferencia y cómo se distribuye
  Widget _handicapLegend(
    Player base, Player receiver,
    double hcpBase, double hcpReceiver,
    List<CourseHole> allHoles, GolfTheme t,
    StartingNine startingNine,
  ) {
    final diff = (hcpReceiver - hcpBase).round();
    if (diff <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.divider),
        ),
        child: Row(children: [
          Icon(Icons.sports_golf, color: t.sub, size: 13),
          const SizedBox(width: 6),
          Text('Sin ventaja — handicaps iguales',
              style: TextStyle(color: t.sub, fontSize: 11)),
        ]),
      );
    }

    // Distribuir strokes por vuelta según la vuelta de inicio
    final firstStrokes  = (diff / 2).ceil();   // vuelta de inicio: más strokes
    final secondStrokes = (diff / 2).floor();  // vuelta secundaria
    final startIsFront = startingNine == StartingNine.front;
    final frontStrokes = startIsFront ? firstStrokes : secondStrokes;
    final backStrokes  = startIsFront ? secondStrokes : firstStrokes;
    final startLabel   = startIsFront ? 'F9 primero' : 'B9 primero';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: t.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.primary.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        // Avatar receptor + nombre
        GAvatar(name: receiver.name, colorIndex: receiver.colorIndex, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RichText(text: TextSpan(children: [
            TextSpan(
              text: receiver.name.split(' ').first,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 12),
            ),
            TextSpan(
              text: ' recibe ',
              style: TextStyle(color: t.sub, fontSize: 11),
            ),
            TextSpan(
              text: '$diff stroke${diff > 1 ? 's' : ''}',
              style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 12),
            ),
            TextSpan(
              text: ' de ${base.name.split(' ').first}',
              style: TextStyle(color: t.sub, fontSize: 11),
            ),
          ])),
          const SizedBox(height: 2),
          Text(
            'F9: $frontStrokes stroke${frontStrokes != 1 ? 's' : ''} · B9: $backStrokes stroke${backStrokes != 1 ? 's' : ''} · $startLabel',
            style: TextStyle(color: t.sub, fontSize: 10),
          ),
        ])),
        // Chips HCP
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _hcpChip(base.name.split(' ').first,     hcpBase,     t),
          const SizedBox(height: 3),
          _hcpChip(receiver.name.split(' ').first, hcpReceiver, t, isHigher: true),
        ]),
      ]),
    );
  }

  Widget _hcpChip(String name, double hcp, GolfTheme t, {bool isHigher = false}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$name ', style: TextStyle(color: t.sub, fontSize: 9)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isHigher ? t.primary.withValues(alpha: 0.12) : t.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isHigher ? t.primary.withValues(alpha: 0.4) : t.divider),
        ),
        child: Text(
          'HCPj ${hcp.toStringAsFixed(0)}',
          style: TextStyle(
            color: isHigher ? t.primary : t.sub,
            fontSize: 9, fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ]);

  // Score bruto del jugador BASE coloreado vs par del hoyo
  Widget _miniScore(int score, int par, bool winner, bool isNet, GolfTheme t) {
    final rel = score - par;
    final color = rel < 0 ? t.scoreUnder : rel > 0 ? t.scoreOver : t.sub;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: winner
          ? BoxDecoration(color: t.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6))
          : null,
      child: Text('$score', style: TextStyle(
        color: winner ? t.primary : color,
        fontWeight: winner ? FontWeight.w800 : FontWeight.w600,
        fontSize: 13,
      )),
    );
  }

  // Score neto del RECEPTOR: cuando hay ventaja muestra "bruto → neto"
  // para dejar claro el impacto del stroke recibido.
  Widget _netScoreCell(int netScore, int grossScore, int par, bool winner, int strokesHere, GolfTheme t) {
    final netRel   = netScore - par;
    final grossRel = grossScore - par;
    final netColor   = netRel  < 0 ? t.scoreUnder : netRel  > 0 ? t.scoreOver : t.sub;
    final grossColor = grossRel < 0 ? t.scoreUnder : grossRel > 0 ? t.scoreOver : t.sub;

    if (strokesHere > 0) {
      // Formato: "5 > 5 → 4" — bruto gris/color, flecha, neto resaltado
      return Row(mainAxisSize: MainAxisSize.min, children: [
        // Score bruto (sin ventaja)
        Text(
          '$grossScore',
          style: TextStyle(
            color: grossColor.withValues(alpha: 0.55),
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(Icons.arrow_forward, size: 9,
              color: t.profit.withValues(alpha: 0.7)),
        ),
        // Score neto (con ventaja) — valor real de comparación
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: winner
              ? BoxDecoration(color: t.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6))
              : BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.profit.withValues(alpha: 0.7), width: 1.5)),
                ),
          child: Text('$netScore', style: TextStyle(
            color: winner ? t.primary : netColor,
            fontWeight: winner ? FontWeight.w800 : FontWeight.w700,
            fontSize: 13,
          )),
        ),
      ]);
    }

    // Sin ventaja: mostrar solo el score
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: winner
          ? BoxDecoration(color: t.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6))
          : null,
      child: Text('$netScore', style: TextStyle(
        color: winner ? t.primary : netColor,
        fontWeight: winner ? FontWeight.w800 : FontWeight.w600,
        fontSize: 13,
      )),
    );
  }

  Widget _dash(GolfTheme t) => Text('·', style: TextStyle(color: t.divider, fontSize: 16));
}

// ── Celda de Skins por hoyo ───────────────────────────────────────────────────
class _SkinsCellWidget extends StatelessWidget {
  final SkinHoleResult result;
  final BetModuleInstance mod;
  final Player p1, p2;
  final GolfTheme t;
  const _SkinsCellWidget({required this.result, required this.mod,
      required this.p1, required this.p2, required this.t});

  @override
  Widget build(BuildContext context) {
    // ── Hoyo pendiente (sin score) ─────────────────────────────────────────
    if (result.isPending) {
      // Mostrar saldo acumulado hasta ahora + carry si aplica
      final lead = result.p1Lead;
      final hasCarry = mod.carryOver && result.pot > mod.value;
      final skins = hasCarry ? (result.pot / mod.value).round() : 0;

      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Saldo acumulado
        _LeadLabel(lead: lead, t: t, fontSize: 11),
        if (hasCarry)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: t.accent.withValues(alpha: 0.3)),
            ),
            child: Text('×$skins 🔥', style: TextStyle(color: t.accent, fontSize: 8, fontWeight: FontWeight.w800)),
          ),
      ]));
    }

    // ── Hoyo jugado ────────────────────────────────────────────────────────
    final lead = result.p1Lead; // positivo = p1 va ganando en total de skins

    if (result.isTie) {
      // Empate: mostrar saldo acumulado + indicador de empate
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _LeadLabel(lead: lead, t: t, fontSize: 11),
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: t.divider),
          ),
          child: Text(
            mod.carryOver ? '= →' : '=',
            style: TextStyle(color: t.sub, fontSize: 8, fontWeight: FontWeight.w600),
          ),
        ),
      ]));
    }

    // Hoyo con ganador: mostrar saldo acumulado + quién ganó el skin
    // El ganador puede ser un tercero (en grupos de 3+)
    final bool winnerIsP1 = result.winner == p1.id;
    final bool winnerIsP2 = result.winner == p2.id;
    final bool winnerIsOther = result.winner != null && !winnerIsP1 && !winnerIsP2;

    final skinWinnerName = winnerIsP1
        ? p1.name.split(' ').first
        : winnerIsP2
            ? p2.name.split(' ').first
            : '▶ otro';
    final skinColor = winnerIsOther
        ? t.sub
        : winnerIsP1 ? t.profit : t.loss;

    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _LeadLabel(lead: lead, t: t, fontSize: 12),
      Text(
        skinWinnerName,
        style: TextStyle(color: skinColor.withValues(alpha: 0.75), fontSize: 8, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    ]));
  }
}

/// Widget reutilizable para mostrar el marcador acumulado de skins: +2, =, -1
class _LeadLabel extends StatelessWidget {
  final int lead;
  final GolfTheme t;
  final double fontSize;
  const _LeadLabel({required this.lead, required this.t, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    final label = lead == 0 ? '=' : lead > 0 ? '+$lead' : '$lead';
    final color = lead == 0 ? t.sub : lead > 0 ? t.profit : t.loss;
    return Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: fontSize),
      textAlign: TextAlign.center,
    );
  }
}

// ── Totales Skins al final de la lista ───────────────────────────────────────
class _SkinsTotalsRow extends StatelessWidget {
  final List<SkinHoleResult> results;
  final Round round;
  final Player p1, p2;
  final BetModuleInstance mod;
  final GolfTheme t;
  const _SkinsTotalsRow({required this.results, required this.round, required this.p1,
      required this.p2, required this.mod, required this.t});

  @override
  Widget build(BuildContext context) {
    final last = results.last;
    final total1 = last.cumP1;
    final total2 = last.cumP2;
    // Balance SOLO de skins (excluye nassau u otras apuestas del mismo grupo)
    final _bd   = LedgerEngine.breakdownBetween(round, p1.id, p2.id);
    final gain1 = _bd[BetModuleType.skins] ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.accent.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.local_fire_department, color: t.accent, size: 14),
        const SizedBox(width: 6),
        Text('SKINS TOTALES', style: TextStyle(color: t.accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        const Spacer(),
        _skinChip(p1.name.split(' ').first, total1, t),
        const SizedBox(width: 8),
        Text('–', style: TextStyle(color: t.sub, fontSize: 12)),
        const SizedBox(width: 8),
        _skinChip(p2.name.split(' ').first, total2, t),
        const SizedBox(width: 12),
        BalChip(amount: gain1),  // balance neto p1 SOLO skins (incluye carry-overs)
      ]),
    );
  }

  Widget _skinChip(String name, int count, GolfTheme t) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$count', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 14)),
      Text(name, style: TextStyle(color: t.sub, fontSize: 9), overflow: TextOverflow.ellipsis),
    ],
  );
}

// ── Desglose financiero ───────────────────────────────────────────────────────
class _FinancialBreakdown extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  const _FinancialBreakdown({required this.round, required this.p1, required this.p2, required this.t});

  // Obtiene los módulos de un tipo dado que incluyen a p1 y p2
  List<BetModuleInstance> _modsOf(BetModuleType type) {
    final result = <BetModuleInstance>[];
    for (final g in round.betGroups) {
      if (g.playerIds.contains(p1.id) && g.playerIds.contains(p2.id)) {
        result.addAll(g.modules.where((m) => m.type == type));
      }
    }
    return result;
  }

  // Devuelve todos los BetModuleType configurados para el par p1/p2
  List<BetModuleType> _allModuleTypes() {
    final types = <BetModuleType>{};
    for (final g in round.betGroups) {
      final pids = g.playerIds;
      if (!pids.contains(p1.id) || !pids.contains(p2.id)) continue;
      for (final m in g.modules) {
        types.add(m.type);
      }
    }
    // Mantener orden canónico
    final order = [
      BetModuleType.skins,
      BetModuleType.nassau,
      BetModuleType.matchAutoPress,
      BetModuleType.medal,
      BetModuleType.putts,
      BetModuleType.oyeses,
      BetModuleType.units,
    ];
    return order.where((t) => types.contains(t)).toList();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<RoundProvider>(); // rebuilda al cambiar la ronda
    final breakdown = LedgerEngine.breakdownBetween(round, p1.id, p2.id);

    // Para Match+Press: calcular balance desde matchAutoPressLive (siempre correcto, independiente
    // del orden de pids en el módulo). Sobreescribir el valor del breakdown si hay módulos activos.
    final mpMods = _modsOf(BetModuleType.matchAutoPress);
    if (mpMods.isNotEmpty) {
      double mpBal = 0.0;
      for (final mod in mpMods) {
        final presses = BetEngine.matchAutoPressLive(round, p1.id, p2.id, mod);
        for (final pr in presses) {
          if (pr.played == 0) continue;
          if (pr.leadingPlayerId == p1.id) mpBal += pr.value;
          if (pr.leadingPlayerId == p2.id) mpBal -= pr.value;
        }
      }
      breakdown[BetModuleType.matchAutoPress] = mpBal;
    }

    // Obtener todos los tipos de módulo configurados para este par
    final allTypes = _allModuleTypes();
    if (allTypes.isEmpty) return const SizedBox.shrink();

    // El total neto es la suma del breakdown corregido (incluye match+press por liveStatus)
    final total = breakdown.values.fold<double>(0, (sum, v) => sum + v);
    final totalColor = total > 0.005 ? t.profit : total < -0.005 ? t.loss : t.sub;

    final n1 = p1.name.split(' ').first;
    final n2 = p2.name.split(' ').first;

    return GCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Cabecera con nombres de los jugadores
        Row(children: [
          Expanded(
            child: Text(
              'DESGLOSE  ${n1.toUpperCase()} VS ${n2.toUpperCase()}',
              style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        // Filas por tipo de apuesta — se muestran TODOS los módulos configurados,
        // incluso si el monto es 0 (empate / ronda en progreso)
        ...allTypes.map((betType) {
          final amount  = breakdown[betType] ?? 0.0;
          final color   = amount > 0.005 ? t.profit : amount < -0.005 ? t.loss : t.sub;
          final sign    = amount > 0.005 ? '+' : '';
          final absAmt  = amount.abs();
          final label   = betType.label;
          final icon    = betType.icon;

          // Para Skins: mostrar marcador de skins (cuántos ganó cada jugador)
          // calculado directamente desde skinsScorecard para ser consistente
          // con la tarjeta de skins visible en la parte superior.
          Widget? skinsSubtitle;
          if (betType == BetModuleType.skins) {
            final skinsMods = _modsOf(BetModuleType.skins);
            if (skinsMods.isNotEmpty) {
              final mod = skinsMods.first;
              // Path 1v1 bilateral (sin groupPids) para consistencia con la tarjeta de skins
              final results = BetEngine.skinsScorecard(round, p1.id, p2.id, mod);
              final played  = results.where((r) => !r.isPending).toList();
              final last    = played.isNotEmpty ? played.last : null;
              final s1 = last?.cumP1 ?? 0;
              final s2 = last?.cumP2 ?? 0;
              // Pot acumulado (skins en juego aún no ganados)
              final currentPot   = results.isNotEmpty ? results.last.pot : mod.skins.valuePerSkin;
              final skinsInPot   = (currentPot / mod.skins.valuePerSkin).round();
              final hasPendingPot = skinsInPot > 1 && mod.skins.carryOver;

              skinsSubtitle = Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  Text(
                    '$n1 $s1  ·  $s2 $n2',
                    style: TextStyle(color: t.sub, fontSize: 10),
                  ),
                  if (hasPendingPot) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '🔥×$skinsInPot en pot',
                        style: const TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ]),
              );
            }
          }

          // Para Match+Press: sin sub-filas, solo encabezado
          // (el detalle lo muestra el panel _MatchPressLivePanel)

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: TextStyle(color: t.text, fontSize: 13))),
                // Indicador visual del estado
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    absAmt < 0.005 ? 'AS' : '$sign\$${absAmt.toStringAsFixed(0)}',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              if (skinsSubtitle != null)
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: skinsSubtitle,
                ),
            ]),
          );
        }),

        // Divider + total neto
        Divider(color: t.sub.withValues(alpha: 0.2), thickness: 1),
        Row(children: [
          Expanded(
            child: Text(
              'NETO  ${n1.toUpperCase()}',
              style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: totalColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: totalColor.withValues(alpha: 0.5)),
            ),
            child: Text(
              '${total > 0.005 ? '+' : ''}\$${total.abs().toStringAsFixed(0)}',
              style: TextStyle(color: totalColor, fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ),
        ]),
      ]),
    );
  }
}
