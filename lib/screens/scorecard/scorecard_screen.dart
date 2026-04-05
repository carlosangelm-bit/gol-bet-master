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

// ── Scorecard grid compartido (Bruto / Neto) ────────────────────────────────
class _ScorecardGrid extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  final bool useNet;
  const _ScorecardGrid({required this.round, required this.t, required this.useNet});

  String _first(String name) => name.split(' ').first;

  int _strokes(Player p, CourseHole h) =>
      GameEngine.strokesReceived(round.getHandicap(p.id), h);

  @override
  Widget build(BuildContext context) {
    final players = round.players;

    final isDark = t.brightness == Brightness.dark;

    // Colores derivados del tema activo
    final cCard    = t.card;
    final cSurface = t.surface;
    final cText    = t.text;
    final cSub     = t.sub;
    final cDiv     = t.divider;
    final cPrim    = t.primary;
    final cUnder   = t.scoreUnder;   // birdie / eagle
    final cOver    = t.scoreOver;    // bogey / doble+
    // Fila alternada: levemente más oscura/clara según modo
    final cRowA = isDark
        ? t.surface
        : Color.alphaBlend(Colors.black.withValues(alpha: 0.03), t.card);
    final cRowB = t.card;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calcular anchos dinámicamente para llenar el ancho disponible sin scroll
        final double available = constraints.maxWidth - 24; // padding 12 a cada lado
        const double colSub  = 44;
        const double colName = 80;
        // Los 9 hoyos + columna sub deben caber en el espacio restante
        final double holesSpace = available - colName - colSub;
        final double colHole = (holesSpace / 9).clamp(22.0, 36.0);
        final double tableW  = colName + 9 * colHole + colSub;

        return Column(
          children: [
            // ── Tabla de hoyos con scroll horizontal si es necesario ──────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableW,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Cabecera ─────────────────────────────────────
                        _header(tableW, cCard, cPrim, cText, cSub),
                        const SizedBox(height: 2),
                        // ── Front 9 ──────────────────────────────────────
                        _segment(players, 1, 9, colName, colHole, colSub, tableW,
                            cCard, cSurface, cText, cSub, cDiv, cPrim, cUnder, cOver,
                            cRowA, cRowB, 'F9'),
                        const SizedBox(height: 2),
                        // ── Back 9 ───────────────────────────────────────
                        _segment(players, 10, 18, colName, colHole, colSub, tableW,
                            cCard, cSurface, cText, cSub, cDiv, cPrim, cUnder, cOver,
                            cRowA, cRowB, 'B9'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── PANEL RESULTADOS — siempre visible, sin scroll horizontal ─
            _resultsPanel(players, constraints.maxWidth,
                cCard, cPrim, cText, cSub, cDiv, cUnder, cOver),
          ],
        );
      },
    );
  }

  // ── Cabecera ────────────────────────────────────────────────────────────────
  Widget _header(double w, Color cCard, Color cPrim, Color cText, Color cSub) {
    return Container(
      width: w,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border.all(color: cPrim.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cPrim,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            useNet ? 'NETO' : 'BRUTO',
            style: TextStyle(
              color: t.onPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            round.course.name.toUpperCase(),
            style: TextStyle(
              color: cText,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '${round.players.length} JUG',
          style: TextStyle(color: cSub, fontSize: 9, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  // ── Segmento F9 / B9 ────────────────────────────────────────────────────────
  Widget _segment(
    List<Player> players, int from, int to,
    double colName, double colHole, double colSub, double tableW,
    Color cCard, Color cSurface, Color cText, Color cSub,
    Color cDiv, Color cPrim, Color cUnder, Color cOver,
    Color cRowA, Color cRowB, String label,
  ) {
    final holes = round.course.holes
        .where((h) => h.hole >= from && h.hole <= to)
        .toList();
    final parSeg = holes.fold(0, (s, h) => s + h.par);
    // Solo mostrar si el segmento tiene hoyos jugados
    final hasAnyScore = players.any((p) =>
        holes.any((h) => round.getScore(p.id, h.hole).hasScore));
    if (!hasAnyScore && holes.isEmpty) return const SizedBox.shrink();

    return Container(
      width: tableW,
      decoration: BoxDecoration(
        color: cCard,
        border: Border.all(color: cDiv, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // Fila encabezado (Hoyo / Par / SI)
        Container(
          color: cSurface,
          child: Row(children: [
            SizedBox(
              width: colName,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                child: Text('JUGADOR',
                    style: TextStyle(
                      color: cPrim,
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    )),
              ),
            ),
            ...holes.map((h) => SizedBox(
              width: colHole,
              child: Column(children: [
                const SizedBox(height: 4),
                Text('${h.hole}',
                    style: TextStyle(
                        color: cText,
                        fontSize: 10,
                        fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center),
                Text('${h.par}',
                    style: TextStyle(color: cSub, fontSize: 7),
                    textAlign: TextAlign.center),
                Text('${h.strokeIndex}',
                    style: TextStyle(
                        color: cPrim.withValues(alpha: 0.7),
                        fontSize: 6,
                        fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
              ]),
            )),
            // Subtotal encabezado
            Container(
              width: colSub,
              decoration: BoxDecoration(
                color: cPrim.withValues(alpha: 0.08),
                border: Border(
                    left: BorderSide(color: cDiv, width: 1)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                Text(label,
                    style: TextStyle(
                        color: cPrim,
                        fontSize: 9,
                        fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center),
                Text('$parSeg',
                    style: TextStyle(color: cSub, fontSize: 7),
                    textAlign: TextAlign.center),
                Text('putts',
                    style: TextStyle(color: cSub.withValues(alpha: 0.6), fontSize: 6),
                    textAlign: TextAlign.center),
              ]),
            ),
          ]),
        ),
        // Filas de jugadores
        ...players.asMap().entries.map((e) => _playerRow(
            e.value, holes, colName, colHole, colSub,
            cText, cSub, cDiv, cPrim, cUnder, cOver,
            e.key.isEven ? cRowA : cRowB)),
      ]),
    );
  }

  // ── Fila de jugador ─────────────────────────────────────────────────────────
  Widget _playerRow(
    Player p, List<CourseHole> holes,
    double colName, double colHole, double colSub,
    Color cText, Color cSub, Color cDiv, Color cPrim,
    Color cUnder, Color cOver, Color rowBg,
  ) {
    int segTotal  = 0;
    int played    = 0;
    int segPutts  = 0;

    final cells = holes.map((h) {
      final sc = round.getScore(p.id, h.hole);
      int? disp;
      int? rel;
      int putts = 0;
      if (sc.hasScore) {
        putts = sc.putts;
        segPutts += putts;
        if (useNet) {
          final ctx = GameEngine.contextForHole(round, p.id, h.hole, true);
          disp = ctx?.netScore;
          rel  = ctx?.relativeToPar;
          segTotal += ctx?.netScore ?? 0;
        } else {
          disp = sc.grossScore;
          rel  = disp != null ? disp - h.par : null;
          segTotal += disp ?? 0;
        }
        played++;
      }
      return _ScoreGridCell(
        score: disp, relPar: rel, par: h.par,
        putts: putts,
        strokesReceived: _strokes(p, h),
        cUnder: cUnder, cOver: cOver, cSub: cSub,
      );
    }).toList();

    final parSeg = holes.fold(0, (s, h) => s + h.par);
    final diff   = played == holes.length ? segTotal - parSeg : null;
    final hcp    = round.getHandicap(p.id);

    return Container(
      color: rowBg,
      child: Row(children: [
        // Nombre + avatar
        SizedBox(
          width: colName,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Row(children: [
              GAvatar(name: p.name, colorIndex: p.colorIndex, size: 20),
              const SizedBox(width: 4),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_first(p.name),
                      style: TextStyle(
                          color: cText,
                          fontWeight: FontWeight.w800,
                          fontSize: 10),
                      overflow: TextOverflow.ellipsis),
                  Text(
                    useNet
                        ? 'HCP ${hcp.toStringAsFixed(0)}'
                        : 'GROSS',
                    style: TextStyle(
                        color: cSub,
                        fontSize: 7,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              )),
            ]),
          ),
        ),
        // Celdas de score
        ...cells.map((c) => SizedBox(
          width: colHole,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: c,
            ),
          ),
        )),
        // Subtotal del segmento + putts
        Container(
          width: colSub,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: cPrim.withValues(alpha: 0.06),
            border: Border(left: BorderSide(color: cDiv, width: 1)),
          ),
          child: played > 0
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$segTotal',
                      style: TextStyle(
                          color: cText,
                          fontWeight: FontWeight.w900,
                          fontSize: 13),
                      textAlign: TextAlign.center),
                  if (diff != null)
                    Container(
                      margin: const EdgeInsets.only(top: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: diff < 0
                            ? cUnder.withValues(alpha: 0.15)
                            : diff > 0
                                ? cOver.withValues(alpha: 0.15)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        diff > 0 ? '+$diff' : diff == 0 ? 'E' : '$diff',
                        style: TextStyle(
                            color: diff < 0
                                ? cUnder
                                : diff > 0
                                    ? cOver
                                    : cSub,
                            fontSize: 7,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  // ── Putts del segmento ──
                  if (segPutts > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '$segPutts p',
                        style: TextStyle(
                          color: segPutts <= played
                              ? cUnder
                              : segPutts >= played * 2
                                  ? cOver
                                  : cSub,
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ])
              : Center(
                  child: Text('—',
                      style: TextStyle(color: cSub, fontSize: 12),
                      textAlign: TextAlign.center),
                ),
        ),
      ]),
    );
  }

  // ── Panel de resultados — fijo al fondo, ancho completo, sin scroll ─────────
  Widget _resultsPanel(
    List<Player> players, double panelW,
    Color cCard, Color cPrim, Color cText, Color cSub,
    Color cDiv, Color cUnder, Color cOver,
  ) {
    final parT = round.course.totalPar;

    // Calcular datos por jugador
    final playerData = players.map((p) {
      final total = useNet
          ? GameEngine.netTotal(round, p.id, true)
          : GameEngine.grossTotal(round, p.id);
      final hasAny = round.course.holes
          .any((h) => round.getScore(p.id, h.hole).hasScore);
      final totalPutts = round.course.holes.fold(0, (sum, h) {
        final sc = round.getScore(p.id, h.hole);
        return sum + (sc.hasScore ? sc.putts : 0);
      });
      final playedHoles = round.course.holes
          .where((h) => round.getScore(p.id, h.hole).hasScore)
          .length;
      final f9total = useNet
          ? GameEngine.netTotal(round, p.id, true, from: 1, to: 9)
          : GameEngine.grossTotal(round, p.id, from: 1, to: 9);
      final b9total = useNet
          ? GameEngine.netTotal(round, p.id, true, from: 10, to: 18)
          : GameEngine.grossTotal(round, p.id, from: 10, to: 18);
      return (
        player: p,
        total: total,
        hasAny: hasAny,
        totalPutts: totalPutts,
        playedHoles: playedHoles,
        f9: f9total,
        b9: b9total,
      );
    }).toList();

    return Container(
      width: panelW,
      decoration: BoxDecoration(
        color: cCard,
        border: Border(top: BorderSide(color: cDiv, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Etiqueta ──────────────────────────────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cPrim,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                useNet ? 'RESULTADO NETO' : 'RESULTADO BRUTO',
                style: TextStyle(
                    color: t.onPrimary,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2),
              ),
            ),
            const SizedBox(width: 8),
            Text('Par $parT',
                style: TextStyle(color: cSub, fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          // ── Tarjetas de jugadores ─────────────────────────────────────────
          Row(
            children: playerData.asMap().entries.map((e) {
              final d = e.value;
              final isLast = e.key == playerData.length - 1;

              if (!d.hasAny || d.total == 0) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cSub.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cDiv),
                      ),
                      child: Row(children: [
                        GAvatar(name: d.player.name,
                            colorIndex: d.player.colorIndex, size: 28),
                        const SizedBox(width: 8),
                        Text('—', style: TextStyle(color: cSub, fontSize: 20,
                            fontWeight: FontWeight.w900)),
                      ]),
                    ),
                  ),
                );
              }

              final diff = d.total - parT;
              final dc = diff < 0 ? cUnder : diff > 0 ? cOver : cSub;
              final diffLabel = diff > 0 ? '+$diff' : diff == 0 ? 'E' : '$diff';

              // Color putts
              final puttColor = d.totalPutts == 0
                  ? cSub
                  : d.totalPutts <= d.playedHoles
                      ? cUnder
                      : d.totalPutts >= d.playedHoles * 2
                          ? cOver
                          : cSub;

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: dc.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: dc.withValues(alpha: 0.35), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Nombre + avatar ──────────────────────────────
                        Row(children: [
                          GAvatar(name: d.player.name,
                              colorIndex: d.player.colorIndex, size: 24),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              d.player.name.split(' ').first,
                              style: TextStyle(
                                  color: cText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        // ── Total golpes + vs par ────────────────────────
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('${d.total}',
                                style: TextStyle(
                                    color: cText,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    height: 1.0)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: dc.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(diffLabel,
                                  style: TextStyle(
                                      color: dc,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // ── F9 / B9 ──────────────────────────────────────
                        Row(children: [
                          _miniChip('F9', d.f9, cSub, cDiv),
                          const SizedBox(width: 4),
                          _miniChip('B9', d.b9, cSub, cDiv),
                        ]),
                        // ── Putts totales ─────────────────────────────────
                        if (d.totalPutts > 0) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            Icon(Icons.sports_golf_rounded,
                                color: puttColor, size: 11),
                            const SizedBox(width: 3),
                            Text('${d.totalPutts} putts',
                                style: TextStyle(
                                    color: puttColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String label, int val, Color cSub, Color cDiv) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: cSub.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: cDiv),
      ),
      child: Text('$label $val',
          style: TextStyle(
              color: cSub, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Celda de score ─────────────────────────────────────────────────────────────
class _ScoreGridCell extends StatelessWidget {
  final int? score;
  final int? relPar;
  final int par;
  final int putts;
  final int strokesReceived;
  final Color cUnder, cOver, cSub;

  const _ScoreGridCell({
    this.score, this.relPar, required this.par,
    this.putts = 0, this.strokesReceived = 0,
    required this.cUnder, required this.cOver, required this.cSub,
  });

  @override
  Widget build(BuildContext context) {
    // Sin score: celda vacía
    if (score == null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 26, height: 26,
          child: Center(
            child: Text('·', style: TextStyle(
                color: cSub.withValues(alpha: 0.4), fontSize: 16)),
          ),
        ),
        const SizedBox(height: 6), // espacio donde irían los putts
      ]);
    }

    final rel = relPar ?? (score! - par);

    // ── Paleta según resultado vs par ──────────────────────────────────────
    // Birdie / Eagle → color scoreUnder del tema
    // Bogey / Doble+ → color scoreOver del tema
    // Par             → neutro (sin color especial)
    Color bg;
    Color fg;
    Color? borderColor;
    double borderW = 0;
    BoxShape shape = BoxShape.rectangle;
    double sz = 26;
    double rad = 4;

    if (rel <= -2) {
      // Eagle o mejor — círculo, color under sólido
      bg = cUnder; fg = Colors.white;
      shape = BoxShape.circle; sz = 27;
    } else if (rel == -1) {
      // Birdie — círculo, color under con borde
      bg = cUnder.withValues(alpha: 0.15); fg = cUnder;
      borderColor = cUnder; borderW = 1.5;
      shape = BoxShape.circle;
    } else if (rel == 0) {
      // Par — cuadrado sin color destacado
      bg = Colors.transparent; fg = cSub;
    } else if (rel == 1) {
      // Bogey — cuadrado con borde over
      bg = cOver.withValues(alpha: 0.12); fg = cOver;
      borderColor = cOver; borderW = 1.5;
    } else {
      // Doble bogey o peor — cuadrado, color over sólido
      bg = cOver; fg = Colors.white;
    }

    final cell = Container(
      width: sz, height: sz,
      decoration: BoxDecoration(
        color: bg,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? BorderRadius.circular(rad) : null,
        border: borderColor != null
            ? Border.all(color: borderColor, width: borderW) : null,
      ),
      alignment: Alignment.center,
      child: Text('$score',
          style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: rel <= -2 ? 12 : 11)),
    );

    // ── Indicador de putts (solo si se registraron) ──────────────────────
    // Muestra el número de putts debajo de la celda, en pequeño.
    // 1 putt → verde (excelente), 2 putts → neutro, 3+ putts → rojo.
    Widget puttIndicator;
    if (putts > 0) {
      final puttColor = putts == 1
          ? cUnder
          : putts >= 3
              ? cOver
              : cSub;
      puttIndicator = Text(
        '$putts p',
        style: TextStyle(
          color: puttColor,
          fontSize: 7,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        textAlign: TextAlign.center,
      );
    } else {
      // Strokes de handicap (puntos) solo si no hay putts registrados
      puttIndicator = strokesReceived > 0
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                strokesReceived.clamp(0, 2),
                (_) => Container(
                  width: 3, height: 3,
                  margin: const EdgeInsets.only(left: 1),
                  decoration: BoxDecoration(
                    color: cSub.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            )
          : const SizedBox(height: 8);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      cell,
      const SizedBox(height: 1),
      puttIndicator,
    ]);
  }
}

// ── Vista 1v1 ─────────────────────────────────────────────────────────────────
class _OneVOneView extends StatefulWidget {
  final Round round;
  final GolfTheme t;
  const _OneVOneView({required this.round, required this.t});
  @override State<_OneVOneView> createState() => _OneVOneViewState();
}

class _OneVOneViewState extends State<_OneVOneView>
    with SingleTickerProviderStateMixin {
  String? _p1Id;
  String? _p2Id;
  late AnimationController _heroCtrl;
  late Animation<double>    _heroFade;
  late Animation<Offset>    _heroSlide;

  @override
  void initState() {
    super.initState();
    final players = widget.round.players;
    if (players.length >= 2) {
      _p1Id = players[0].id;
      _p2Id = players[1].id;
    }
    _heroCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
    _heroFade  = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.12), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));
    _heroCtrl.forward();
  }

  @override
  void dispose() { _heroCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t     = widget.t;
    final round = widget.round;

    if (round.players.length < 2) {
      return Center(child: Text('Necesitas al menos 2 jugadores',
          style: TextStyle(color: t.sub)));
    }

    final p1 = round.players.firstWhere(
        (p) => p.id == (_p1Id ?? round.players[0].id));
    final p2 = round.players.firstWhere(
        (p) => p.id == (_p2Id ?? round.players[1].id));

    final skinsModules      = _findModules(round, p1.id, p2.id, BetModuleType.skins);
    final nassauModules     = _findModules(round, p1.id, p2.id, BetModuleType.nassau);
    final matchPressModules = _findModules(round, p1.id, p2.id, BetModuleType.matchAutoPress);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ─────────────────────────────────────────────────────
              // BLOQUE 1 · HEADER
              // ─────────────────────────────────────────────────────
              _OneVOneHeader(round: round, t: t,
                p1: p1, p2: p2,
                onP1: (pid) => setState(() { _p1Id = pid; _heroCtrl.forward(from: 0); }),
                onP2: (pid) => setState(() { _p2Id = pid; _heroCtrl.forward(from: 0); }),
              ),
              const SizedBox(height: 16),

              // ─────────────────────────────────────────────────────
              // BLOQUE 2 · HERO DEL MATCH  (animado)
              // ─────────────────────────────────────────────────────
              FadeTransition(
                opacity: _heroFade,
                child: SlideTransition(
                  position: _heroSlide,
                  child: _MatchHeroCard(
                    round: round, p1: p1, p2: p2, t: t,
                    skinsModules:      skinsModules,
                    nassauModules:     nassauModules,
                    matchPressModules: matchPressModules,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ─────────────────────────────────────────────────────
              // BLOQUE 3 · RESUMEN RÁPIDO
              // ─────────────────────────────────────────────────────
              _MatchQuickSummary(round: round, p1: p1, p2: p2, t: t,
                nassauModules: nassauModules,
                matchPressModules: matchPressModules,
              ),
              const SizedBox(height: 16),

              // ─────────────────────────────────────────────────────
              // BLOQUE 4 · TIMELINE HOYO A HOYO
              // ─────────────────────────────────────────────────────
              _HoleTimeline(
                round: round, p1: p1, p2: p2, t: t,
                skinsMod: skinsModules.isNotEmpty ? skinsModules.first : null,
              ),
              const SizedBox(height: 16),

              // Paneles Nassau / Match+Press (lógica existente preservada)
              ...nassauModules.map((mod) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NassauLivePanel(round: round, p1: p1, p2: p2, mod: mod, t: t),
              )),
              ...matchPressModules.map((mod) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MatchPressLivePanel(round: round, p1: p1, p2: p2, mod: mod, t: t),
              )),
              const SizedBox(height: 12),

              // Carry panel
              _CarryPanel(
                round: round, p1: p1, p2: p2, t: t,
                nassauModules:     nassauModules,
                matchPressModules: matchPressModules,
                onApplyCarry: (factor) => _applyCarry(
                    context, factor, nassauModules, matchPressModules),
              ),
              const SizedBox(height: 12),

              // Desglose financiero
              _FinancialBreakdown(round: round, p1: p1, p2: p2, t: t),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ],
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

// ═══════════════════════════════════════════════════════════════════════════════
// SISTEMA DE TEMA DINÁMICO POR ESTADO DEL MATCH
// ═══════════════════════════════════════════════════════════════════════════════
enum _MatchStatus { winning, tied, losing }

class _MatchTheme {
  final List<Color> gradient;
  final Color accent;
  final Color glowColor;
  final String label;
  const _MatchTheme({
    required this.gradient, required this.accent,
    required this.glowColor, required this.label,
  });

  static _MatchTheme of(_MatchStatus s) {
    switch (s) {
      case _MatchStatus.winning:
        return const _MatchTheme(
          gradient: [Color(0xFF1F8F3A), Color(0xFF0E3D1B)],
          accent:   Color(0xFF35C759),
          glowColor: Color(0xFF1F8F3A),
          label: 'GANANDO',
        );
      case _MatchStatus.tied:
        return const _MatchTheme(
          gradient: [Color(0xFF3A3A3C), Color(0xFF1C1C1E)],
          accent:   Color(0xFFFFC857),
          glowColor: Color(0xFF3A3A3C),
          label: 'PAREJO',
        );
      case _MatchStatus.losing:
        return const _MatchTheme(
          gradient: [Color(0xFF7A1E1E), Color(0xFF2A0E0E)],
          accent:   Color(0xFFFF453A),
          glowColor: Color(0xFF7A1E1E),
          label: 'PERDIENDO',
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLOQUE 1 · HEADER  (título ronda + fecha + selector jugadores)
// ═══════════════════════════════════════════════════════════════════════════════
class _OneVOneHeader extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  final void Function(String) onP1, onP2;
  const _OneVOneHeader({
    required this.round, required this.p1, required this.p2,
    required this.t, required this.onP1, required this.onP2,
  });

  @override
  Widget build(BuildContext context) {
    // Tipo de juego
    final hasNassau = round.betGroups.any((g) =>
        g.playerIds.contains(p1.id) && g.playerIds.contains(p2.id) &&
        g.modules.any((m) => m.type == BetModuleType.nassau));
    final hasMatch  = round.betGroups.any((g) =>
        g.playerIds.contains(p1.id) && g.playerIds.contains(p2.id) &&
        g.modules.any((m) => m.type == BetModuleType.matchAutoPress));
    final hasSkins  = round.betGroups.any((g) =>
        g.playerIds.contains(p1.id) && g.playerIds.contains(p2.id) &&
        g.modules.any((m) => m.type == BetModuleType.skins));
    final gameTypeParts = <String>[
      if (hasNassau) 'Nassau',
      if (hasMatch)  'Match',
      if (hasSkins)  'Skins',
    ];
    final gameType = gameTypeParts.isEmpty ? '1v1' : gameTypeParts.join(' · ');

    return Row(children: [
      // Izquierda: info ronda
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(round.name,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w800,
                fontSize: 16, letterSpacing: -0.3),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.primary.withValues(alpha: 0.3)),
            ),
            child: Text(gameType,
                style: TextStyle(color: t.primary, fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
          const SizedBox(width: 6),
          Text('NETO · ${round.totalHoles} hoyos',
              style: TextStyle(color: t.sub, fontSize: 10)),
        ]),
      ])),

      // Derecha: selector de jugadores compacto
      GestureDetector(
        onTap: () => _showPicker(context, p1, onP1),
        child: _miniPlayerChip(p1, t),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('vs', style: TextStyle(color: t.sub, fontSize: 11,
            fontWeight: FontWeight.w700)),
      ),
      GestureDetector(
        onTap: () => _showPicker(context, p2, onP2),
        child: _miniPlayerChip(p2, t),
      ),
    ]);
  }

  Widget _miniPlayerChip(Player p, GolfTheme t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      GAvatar(name: p.name, colorIndex: p.colorIndex, size: 28),
      const SizedBox(width: 4),
      Icon(Icons.expand_more, color: t.sub, size: 14),
    ],
  );

  void _showPicker(BuildContext context, Player current, void Function(String) onSelect) {
    final t = this.t;
    showModalBottomSheet(
      context: context, backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Cambiar jugador', style: TextStyle(color: t.text,
              fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          ...round.players.map((p) => ListTile(
            leading: GAvatar(name: p.name, colorIndex: p.colorIndex, size: 32),
            title: Text(p.name, style: TextStyle(color: t.text,
                fontWeight: FontWeight.w700)),
            subtitle: Text('HCP ${p.handicapBase.toStringAsFixed(0)}',
                style: TextStyle(color: t.sub, fontSize: 11)),
            trailing: p.id == current.id
                ? Icon(Icons.check_circle, color: t.primary, size: 18) : null,
            onTap: () { onSelect(p.id); Navigator.pop(context); },
          )),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLOQUE 2 · HERO DEL MATCH
// ═══════════════════════════════════════════════════════════════════════════════
class _MatchHeroCard extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  final List<BetModuleInstance> skinsModules, nassauModules, matchPressModules;
  const _MatchHeroCard({
    required this.round, required this.p1, required this.p2, required this.t,
    required this.skinsModules, required this.nassauModules,
    required this.matchPressModules,
  });

  @override
  Widget build(BuildContext context) {
    // ── Calcular score principal (hoyos ganados cada uno en match play)
    final status    = GameEngine.matchPlayStatus(round, p1.id, p2.id, true);
    final holesWon1 = status > 0 ? status : 0;
    final holesWon2 = status < 0 ? status.abs() : 0;

    // ── Estado del match
    final _MatchStatus ms;
    if (status > 0)      ms = _MatchStatus.winning;
    else if (status < 0) ms = _MatchStatus.losing;
    else                  ms = _MatchStatus.tied;
    final mt = _MatchTheme.of(ms);

    // ── Datos secundarios (pills)
    final skinsWon1 = _skinsWon(p1.id);
    final skinsWon2 = _skinsWon(p2.id);
    final streak    = _winStreak();
    final balance   = _netBalance();
    final n1 = p1.name.split(' ').first;
    final n2 = p2.name.split(' ').first;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: mt.gradient,
        ),
        boxShadow: [
          BoxShadow(
            color: mt.glowColor.withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: mt.accent.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(children: [
          // Label de estado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(mt.label,
              style: TextStyle(
                color: mt.accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Bloque central: P1 — Score grande — P2
          Row(children: [
            // Jugador 1
            Expanded(child: Column(children: [
              GAvatar(name: p1.name, colorIndex: p1.colorIndex, size: 44),
              const SizedBox(height: 6),
              Text(n1, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              Text('HCP ${round.getHandicap(p1.id).toStringAsFixed(0)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10)),
            ])),

            // Score gigante animado
            Expanded(
              flex: 2,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Text(
                  '$holesWon1 – $holesWon2',
                  key: ValueKey('$holesWon1-$holesWon2'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    letterSpacing: -1,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                  ),
                ),
              ),
            ),

            // Jugador 2
            Expanded(child: Column(children: [
              GAvatar(name: p2.name, colorIndex: p2.colorIndex, size: 44),
              const SizedBox(height: 6),
              Text(n2, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              Text('HCP ${round.getHandicap(p2.id).toStringAsFixed(0)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10)),
            ])),
          ]),

          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: 14),

          // Pills de stats secundarios
          Wrap(
            spacing: 8, runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (skinsWon1 > 0 || skinsWon2 > 0)
                _StatPill(
                  label: skinsWon1 > skinsWon2
                      ? '+$skinsWon1 skins'
                      : skinsWon2 > skinsWon1
                          ? '+$skinsWon2 skins'
                          : '${skinsWon1+skinsWon2} skins',
                  icon: Icons.local_fire_department,
                  color: mt.accent,
                ),
              if (streak >= 2)
                _StatPill(
                  label: '🔥 racha x$streak',
                  icon: null,
                  color: const Color(0xFFFF9500),
                ),
              if (balance != 0)
                _StatPill(
                  label: balance > 0
                      ? '+\$${balance.toStringAsFixed(0)}'
                      : '-\$${balance.abs().toStringAsFixed(0)}',
                  icon: Icons.attach_money,
                  color: balance > 0 ? const Color(0xFF35C759) : const Color(0xFFFF453A),
                ),
              _StatPill(
                label: 'Thru ${_playedHoles()}',
                icon: Icons.flag_outlined,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  int _skinsWon(String pid) {
    if (skinsModules.isEmpty) return 0;
    final res = BetEngine.skinsScorecard(round, p1.id, p2.id, skinsModules.first);
    return res.where((r) => r.winner == pid).length;
  }

  int _winStreak() {
    // Racha de hoyos consecutivos ganados por el líder (p1 perspective)
    final status = GameEngine.matchPlayStatus(round, p1.id, p2.id, true);
    if (status == 0) return 0;
    int streak = 0;
    final order = round.startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(18, (i) => i + 1);
    for (final h in order.reversed) {
      final s1 = round.getScore(p1.id, h);
      final s2 = round.getScore(p2.id, h);
      if (!s1.hasScore || !s2.hasScore) continue;
      final hcp1 = round.getHandicap(p1.id);
      final hcp2 = round.getHandicap(p2.id);
      final ch   = round.course.holes.firstWhere((c) => c.hole == h);
      final strokes = GameEngine.strokesReceivedVs(
        hcpHigher: hcp1 > hcp2 ? hcp1 : hcp2,
        hcpLower:  hcp1 > hcp2 ? hcp2 : hcp1,
        ch: ch, allHoles: round.course.holes,
        startingNine: round.startingNine,
      );
      final net1 = hcp1 > hcp2 ? s1.grossScore! - strokes : s1.grossScore!;
      final net2 = hcp2 > hcp1 ? s2.grossScore! - strokes : s2.grossScore!;
      final p1Won = net1 < net2;
      final p2Won = net2 < net1;
      final leaderWon = status > 0 ? p1Won : p2Won;
      if (leaderWon) streak++;
      else break;
    }
    return streak;
  }

  double _netBalance() {
    final bd = LedgerEngine.breakdownBetween(round, p1.id, p2.id);
    return bd.values.fold(0.0, (a, b) => a + b);
  }

  int _playedHoles() {
    return List.generate(18, (i) => i + 1)
        .where((h) => round.getScore(p1.id, h).hasScore &&
                      round.getScore(p2.id, h).hasScore)
        .length;
  }
}

// Pill reutilizable para stats secundarios
class _StatPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  const _StatPill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
        ],
        Text(label, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLOQUE 3 · RESUMEN RÁPIDO
// ═══════════════════════════════════════════════════════════════════════════════
class _MatchQuickSummary extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  final List<BetModuleInstance> nassauModules, matchPressModules;
  const _MatchQuickSummary({
    required this.round, required this.p1, required this.p2, required this.t,
    required this.nassauModules, required this.matchPressModules,
  });

  @override
  Widget build(BuildContext context) {
    final hcp1   = round.getHandicap(p1.id);
    final hcp2   = round.getHandicap(p2.id);
    final rp1    = round.roundPlayers.firstWhere(
      (r) => r.playerId == p1.id,
      orElse: () => RoundPlayer(playerId: p1.id, handicapEnRonda: hcp1),
    );
    final manual = rp1.manualHandicaps[p2.id];
    final diff   = manual != null ? manual.round().abs() : (hcp1 - hcp2).round().abs();
    final receiver = (manual != null && manual > 0) || (manual == null && hcp1 > hcp2)
        ? p1 : p2;

    final played = List.generate(18, (i) => i + 1)
        .where((h) => round.getScore(p1.id, h).hasScore &&
                      round.getScore(p2.id, h).hasScore)
        .length;

    final formats = <String>[
      if (nassauModules.isNotEmpty) 'Nassau',
      if (matchPressModules.isNotEmpty) 'Match+Press',
    ];
    final formatLabel = formats.isEmpty ? 'Stroke play' : formats.join(' + ');

    final items = [
      (Icons.sports_golf_rounded,
        diff > 0
            ? '${receiver.name.split(' ').first} recibe $diff stroke${diff > 1 ? 's' : ''}'
            : 'Sin ventaja — igualdad',
        'Strokes'),
      (Icons.flag_outlined,
        'Thru $played de ${round.totalHoles}',
        'Progreso'),
      (Icons.style_outlined,
        formatLabel,
        'Formato'),
      (Icons.location_on_outlined,
        round.startingNine == StartingNine.front ? 'Salida F9' : 'Salida B9',
        'Inicio'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RESUMEN', style: TextStyle(
            color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.$1, color: t.primary, size: 15),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.$2, style: TextStyle(
                  color: t.text, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(item.$3, style: TextStyle(color: t.sub, fontSize: 10)),
              ])),
            ]),
          )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLOQUE 4 · TIMELINE HOYO A HOYO
// ═══════════════════════════════════════════════════════════════════════════════
enum _HoleState { win, tie, lose, pending }

// ── Datos calculados por hoyo (immutable, para pasar a la fila) ───────────────
class _HoleRowData {
  final int hole;
  final int par;
  final int? grossBase;
  final int? grossReceiver;
  final int? netReceiver;
  final int strokes;
  final _HoleState state;
  final bool hasSkin;
  final bool skinGoesToBase;  // true = base ganó la piel, false = receiver
  const _HoleRowData({
    required this.hole, required this.par,
    required this.grossBase, required this.grossReceiver,
    required this.netReceiver, required this.strokes,
    required this.state, required this.hasSkin,
    required this.skinGoesToBase,
  });
}

// ── Helper: color según score vs par ─────────────────────────────────────────
Color _scoreColor(int score, int par) {
  final rel = score - par;
  if (rel <= -2) return const Color(0xFFFFD60A);  // Eagle → dorado
  if (rel == -1) return const Color(0xFF30D158);  // Birdie → verde
  if (rel == 0)  return const Color(0xFF8E8E93);  // Par → gris
  if (rel == 1)  return const Color(0xFFFF6B35);  // Bogey → naranja
  return const Color(0xFFFF453A);                  // Doble+ → rojo
}

// ── Badge estilo PGA (forma según resultado vs par) ───────────────────────────
class _PGAScoreBadge extends StatelessWidget {
  final int score;
  final int par;
  final bool dimmed;   // true cuando es bruto pero hay neto
  final bool accent;   // true cuando es el score decisivo (neto)
  const _PGAScoreBadge(this.score, this.par,
      {this.dimmed = false, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final rel = score - par;
    final col = dimmed ? const Color(0xFF8E8E93) : _scoreColor(score, par);

    BoxDecoration deco;
    if (rel <= -2) {
      // Eagle: doble círculo (relleno + borde exterior delgado)
      deco = BoxDecoration(
        shape: BoxShape.circle,
        color: col.withValues(alpha: dimmed ? 0.07 : 0.18),
        border: Border.all(color: col.withValues(alpha: dimmed ? 0.3 : 0.9), width: 1.5),
      );
    } else if (rel == -1) {
      // Birdie: círculo simple
      deco = BoxDecoration(
        shape: BoxShape.circle,
        color: col.withValues(alpha: dimmed ? 0.06 : 0.12),
        border: Border.all(color: col.withValues(alpha: dimmed ? 0.3 : 0.85), width: 1.5),
      );
    } else if (rel == 1) {
      // Bogey: cuadrado con bordes redondeados
      deco = BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: col.withValues(alpha: dimmed ? 0.06 : 0.1),
        border: Border.all(color: col.withValues(alpha: dimmed ? 0.3 : 0.8), width: 1.5),
      );
    } else if (rel >= 2) {
      // Doble bogey+: cuadrado doble (relleno más fuerte)
      deco = BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: col.withValues(alpha: dimmed ? 0.08 : 0.2),
        border: Border.all(color: col.withValues(alpha: dimmed ? 0.35 : 0.85), width: 2),
      );
    } else {
      // Par: sin decoración
      deco = BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: col.withValues(alpha: 0.07),
      );
    }

    return Container(
      width: 28, height: 28,
      decoration: deco,
      alignment: Alignment.center,
      child: Text('$score',
        style: TextStyle(
          color: dimmed
              ? const Color(0xFF8E8E93)
              : col,
          fontWeight: accent ? FontWeight.w900 : FontWeight.w700,
          fontSize: accent ? 13 : 12,
        ),
      ),
    );
  }
}

class _HoleTimeline extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  final BetModuleInstance? skinsMod;
  const _HoleTimeline({
    required this.round, required this.p1, required this.p2,
    required this.t, this.skinsMod,
  });

  @override
  Widget build(BuildContext context) {
    // Calcular ventajas
    final hcp1 = round.getHandicap(p1.id);
    final hcp2 = round.getHandicap(p2.id);
    final rp1  = round.roundPlayers.firstWhere(
      (r) => r.playerId == p1.id,
      orElse: () => RoundPlayer(playerId: p1.id, handicapEnRonda: hcp1),
    );
    final manual = rp1.manualHandicaps[p2.id];
    final Player basePlayer     = (manual != null && manual > 0) || (manual == null && hcp1 <= hcp2) ? p1 : p2;
    final Player receiverPlayer = basePlayer == p1 ? p2 : p1;
    final double hcpBase        = basePlayer == p1 ? hcp1 : hcp2;
    final double hcpReceiver    = basePlayer == p1 ? hcp2 : hcp1;

    // Skins results
    final List<SkinHoleResult>? skinsResults = skinsMod != null
        ? BetEngine.skinsScorecard(round, p1.id, p2.id, skinsMod!)
        : null;

    // Orden de hoyos
    final holeMap = { for (final ch in round.course.holes) ch.hole: ch };
    final order   = round.startingNine == StartingNine.back
        ? [...List.generate(9, (i) => i + 10), ...List.generate(9, (i) => i + 1)]
        : List.generate(18, (i) => i + 1);

    // Calcular datos por hoyo + marcador acumulado
    int running = 0; // positivo = base va ganando
    final rows = <_HoleRowData>[];
    final runningPerHole = <int>[];

    for (final h in order) {
      final ch        = holeMap[h];
      if (ch == null) continue;
      final sBase     = round.getScore(basePlayer.id, h);
      final sReceiver = round.getScore(receiverPlayer.id, h);
      if (!sBase.hasScore && !sReceiver.hasScore) continue;

      final strokes    = GameEngine.strokesReceivedVs(
        hcpHigher: hcpReceiver, hcpLower: hcpBase,
        ch: ch, allHoles: round.course.holes,
        startingNine: round.startingNine,
      );
      final grossBase     = sBase.hasScore ? sBase.grossScore! : null;
      final grossReceiver = sReceiver.hasScore ? sReceiver.grossScore! : null;
      final netReceiver   = grossReceiver != null ? grossReceiver - strokes : null;

      _HoleState state = _HoleState.pending;
      if (grossBase != null && netReceiver != null) {
        if (grossBase < netReceiver)      { state = _HoleState.win;  running++; }
        else if (grossBase > netReceiver) { state = _HoleState.lose; running--; }
        else                               { state = _HoleState.tie; }
      }
      runningPerHole.add(running);

      // Skins
      final skinResult = skinsResults?.firstWhere(
        (r) => r.hole == h,
        orElse: () => SkinHoleResult(
            hole: h, winner: null, isPending: true,
            pot: skinsMod?.value ?? 0, cumP1: 0, cumP2: 0),
      );
      final hasSkin = skinResult != null && !skinResult.isPending && skinResult.winner != null;
      final skinGoesToBase = hasSkin && skinResult!.winner == basePlayer.id;

      rows.add(_HoleRowData(
        hole: h, par: ch.par,
        grossBase: grossBase, grossReceiver: grossReceiver,
        netReceiver: netReceiver, strokes: strokes,
        state: state, hasSkin: hasSkin, skinGoesToBase: skinGoesToBase,
      ));
    }

    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: t.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.divider),
        ),
        child: Column(children: [
          Icon(Icons.sports_golf_rounded, color: t.sub, size: 36),
          const SizedBox(height: 10),
          Text('Aún no hay hoyos registrados',
              style: TextStyle(color: t.sub, fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Los resultados aparecerán aquí al registrar scores',
              style: TextStyle(color: t.sub.withValues(alpha: 0.6),
                  fontSize: 11), textAlign: TextAlign.center),
        ]),
      );
    }

    // Ancho disponible para el momentum tracker (se usa LayoutBuilder abajo)
    final totalHoles = round.totalHoles;
    final played     = rows.length;
    final n1short    = basePlayer.name.split(' ').first;
    final n2short    = receiverPlayer.name.split(' ').first;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header ────────────────────────────────────────────────────────────
      Row(children: [
        Text('HOYO A HOYO',
          style: TextStyle(color: t.sub, fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        const Spacer(),
        Text('$played / $totalHoles hoyos',
          style: TextStyle(color: t.sub.withValues(alpha: 0.6), fontSize: 10)),
        if (skinsMod != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: const Color(0xFFFF9500).withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('🔥', style: TextStyle(fontSize: 9)),
              const SizedBox(width: 3),
              const Text('Skins', style: TextStyle(
                  color: Color(0xFFFF9500), fontSize: 9,
                  fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ]),
      const SizedBox(height: 10),

      // ── Momentum Tracker ──────────────────────────────────────────────────
      _MomentumTracker(
        rows: rows,
        runningPerHole: runningPerHole,
        basePlayer: basePlayer,
        receiverPlayer: receiverPlayer,
        totalHoles: totalHoles,
        t: t,
      ),
      const SizedBox(height: 14),

      // ── Columna de cabecera (nombres de jugadores) ────────────────────────
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          const SizedBox(width: 44),   // ancho del indicador de hoyo
          const SizedBox(width: 12),
          // P1 nombre
          Expanded(
            child: Text(n1short,
              style: TextStyle(color: t.sub, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 0.3),
              textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          // P2 nombre + indicador neto
          Expanded(
            child: Column(children: [
              Text(n2short,
                style: TextStyle(color: t.sub, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.3),
                textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
              if (rows.any((r) => r.strokes > 0))
                Text('neto', style: TextStyle(
                  color: t.primary.withValues(alpha: 0.7),
                  fontSize: 8, fontWeight: FontWeight.w600,
                  letterSpacing: 0.2)),
            ]),
          ),
          const SizedBox(width: 10),
          const SizedBox(width: 52), // ancho chip resultado
        ]),
      ),
      const SizedBox(height: 6),

      // ── Filas de hoyos ────────────────────────────────────────────────────
      ...rows.map((row) => _HoleTimelineRow(
        data: row,
        basePlayer: basePlayer,
        receiverPlayer: receiverPlayer,
        t: t,
      )),

      // ── Totales de Skins ──────────────────────────────────────────────────
      if (skinsResults != null && skinsResults.isNotEmpty) ...[
        const SizedBox(height: 8),
        _SkinsTotalsRow(
            results: skinsResults, round: round,
            p1: p1, p2: p2, mod: skinsMod!, t: t),
      ],
    ]);
  }
}

// ── Momentum Tracker: barrita de progreso que muestra quién lidera hoyo a hoyo
class _MomentumTracker extends StatelessWidget {
  final List<_HoleRowData> rows;
  final List<int> runningPerHole;
  final Player basePlayer, receiverPlayer;
  final int totalHoles;
  final GolfTheme t;
  const _MomentumTracker({
    required this.rows, required this.runningPerHole,
    required this.basePlayer, required this.receiverPlayer,
    required this.totalHoles, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final current = runningPerHole.isNotEmpty ? runningPerHole.last : 0;
    final n1 = basePlayer.name.split(' ').first;
    final n2 = receiverPlayer.name.split(' ').first;

    // Estado textual
    final String stateText;
    final Color stateCol;
    if (current > 0) {
      stateText = '$n1 +$current UP';
      stateCol  = const Color(0xFF35C759);
    } else if (current < 0) {
      stateText = '$n2 +${current.abs()} UP';
      stateCol  = const Color(0xFFFF453A);
    } else {
      stateText = 'ALL SQUARE';
      stateCol  = const Color(0xFFFFD60A);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Estado actual centrado
        Center(
          child: Text(stateText,
            style: TextStyle(
              color: stateCol,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Barra de momentum hoyo por hoyo
        LayoutBuilder(builder: (_, constraints) {
          final totalW = constraints.maxWidth;
          final slotW  = totalW / totalHoles;

          return SizedBox(
            height: 28,
            child: Stack(children: [
              // Fondo neutro (hoyos no jugados)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),

              // Línea central (cero)
              Positioned(
                left: 0, right: 0,
                top: 13, bottom: 13,
                child: Container(color: Colors.white.withValues(alpha: 0.12)),
              ),

              // Barras de cada hoyo
              ...List.generate(rows.length, (i) {
                final r = rows[i];
                Color barCol;
                double barH;
                double top;

                if (r.state == _HoleState.win) {
                  barCol = const Color(0xFF35C759);
                  barH   = 10;
                  top    = 4;  // arriba del centro
                } else if (r.state == _HoleState.lose) {
                  barCol = const Color(0xFFFF453A);
                  barH   = 10;
                  top    = 14; // abajo del centro
                } else if (r.state == _HoleState.tie) {
                  barCol = const Color(0xFF8E8E93);
                  barH   = 4;
                  top    = 12; // en el centro
                } else {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  left:  i * slotW + 1,
                  width: slotW - 2,
                  top:   top,
                  height: barH,
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 300 + i * 15),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: barCol,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    // Dot extra para skin
                    child: r.hasSkin
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              width: 4, height: 4, margin: const EdgeInsets.only(top: 1),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFD60A),
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                );
              }),

              // Separador mitad del recorrido (hoyo 9/10)
              Positioned(
                left:  (totalHoles ~/ 2) * slotW - 0.5,
                top: 0, bottom: 0, width: 1,
                child: Container(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),

              // Números de hoyo (cada 3)
              ...List.generate(totalHoles, (i) {
                final hNum = rows.length > i ? rows[i].hole : null;
                if (hNum == null) return const SizedBox.shrink();
                if (i % 3 != 0) return const SizedBox.shrink();
                return Positioned(
                  left: i * slotW,
                  width: slotW * 3,
                  bottom: 0,
                  child: Text('$hNum',
                    style: TextStyle(
                      color: t.sub.withValues(alpha: 0.4),
                      fontSize: 7, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.left),
                );
              }),
            ]),
          );
        }),

        // Leyenda mínima
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(n1, style: TextStyle(color: const Color(0xFF35C759),
              fontSize: 9, fontWeight: FontWeight.w700)),
          Row(children: [
            Container(width: 6, height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFFFD60A), shape: BoxShape.circle)),
            const SizedBox(width: 3),
            Text('piel', style: TextStyle(color: t.sub, fontSize: 9)),
          ]),
          Text(n2, style: TextStyle(color: const Color(0xFFFF453A),
              fontSize: 9, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}

// ── Fila individual del timeline (rediseño compacto estilo marcador deportivo) ─
class _HoleTimelineRow extends StatelessWidget {
  final _HoleRowData data;
  final Player basePlayer, receiverPlayer;
  final GolfTheme t;

  const _HoleTimelineRow({
    required this.data,
    required this.basePlayer,
    required this.receiverPlayer,
    required this.t,
  });

  Color get _stateColor {
    switch (data.state) {
      case _HoleState.win:     return const Color(0xFF35C759);
      case _HoleState.lose:    return const Color(0xFFFF453A);
      case _HoleState.tie:     return const Color(0xFF8E8E93);
      case _HoleState.pending: return const Color(0xFF48484A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc      = _stateColor;
    final isPending = data.state == _HoleState.pending;
    final hasStrokes = data.strokes > 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isPending
            ? t.surface.withValues(alpha: 0.5)
            : sc.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPending ? t.divider : sc.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [

        // ── Indicador hoyo: número + par + dots de ventaja ─────────────────
        Container(
          width: 44,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Número del hoyo (con dot de color si hay resultado)
              Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (!isPending)
                  Container(
                    width: 5, height: 5,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(color: sc, shape: BoxShape.circle),
                  ),
                Text('${data.hole}',
                  style: TextStyle(
                    color: isPending ? t.sub : t.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ]),
              Text('P${data.par}',
                style: TextStyle(color: t.sub.withValues(alpha: 0.6),
                    fontSize: 9, fontWeight: FontWeight.w500)),
              // Puntos de ventaja (strokes recibidos)
              if (hasStrokes)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Wrap(
                    spacing: 2,
                    children: List.generate(data.strokes.clamp(0, 3), (_) =>
                      Container(width: 4, height: 4,
                        decoration: BoxDecoration(
                          color: t.primary.withValues(alpha: 0.65),
                          shape: BoxShape.circle))),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // ── Score P1 (base — bruto) ────────────────────────────────────────
        Expanded(
          child: Center(
            child: data.grossBase != null
                ? _PGAScoreBadge(data.grossBase!, data.par, accent: true)
                : Text('–', style: TextStyle(color: t.sub, fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ),

        // ── Separador VS ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('vs',
            style: TextStyle(
              color: t.sub.withValues(alpha: 0.35),
              fontSize: 9, fontWeight: FontWeight.w700)),
        ),

        // ── Score P2 (receiver — neto si aplica) ──────────────────────────
        Expanded(
          child: Center(
            child: data.grossReceiver != null
                ? hasStrokes && data.netReceiver != null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _PGAScoreBadge(
                              data.netReceiver!, data.par, accent: true),
                          const SizedBox(height: 1),
                          Text('(${data.grossReceiver})',
                            style: TextStyle(
                              color: t.sub.withValues(alpha: 0.45),
                              fontSize: 8, fontWeight: FontWeight.w500)),
                        ],
                      )
                    : _PGAScoreBadge(data.grossReceiver!, data.par, accent: true)
                : Text('–', style: TextStyle(color: t.sub, fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ),

        const SizedBox(width: 10),

        // ── Resultado chip + skin ──────────────────────────────────────────
        SizedBox(
          width: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Chip resultado
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPending
                      ? Colors.white.withValues(alpha: 0.05)
                      : sc.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: isPending
                      ? null
                      : Border.all(color: sc.withValues(alpha: 0.3), width: 0.5),
                ),
                child: Text(
                  switch (data.state) {
                    _HoleState.win     => '▲ WIN',
                    _HoleState.lose    => '▼ LOST',
                    _HoleState.tie     => '= TIE',
                    _HoleState.pending => '—',
                  },
                  style: TextStyle(
                    color: isPending
                        ? t.sub.withValues(alpha: 0.4)
                        : sc,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // Skin indicator
              if (data.hasSkin) ...[
                const SizedBox(height: 3),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('🔥', style: TextStyle(fontSize: 9)),
                  const SizedBox(width: 2),
                  Text('skin', style: TextStyle(
                      color: const Color(0xFFFF9500),
                      fontSize: 7, fontWeight: FontWeight.w800)),
                ]),
              ],
            ],
          ),
        ),
      ]),
    );
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

            // Etiqueta del segmento — usa pressNumber del modelo (seq-1)
            final segTag = 'PRESS ${pr.pressNumber}';
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
