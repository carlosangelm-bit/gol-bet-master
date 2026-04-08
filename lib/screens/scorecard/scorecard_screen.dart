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
import '../../services/auth_service.dart';
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
          // Con 5+ jugadores se usa modo compacto: solo inicial, medal y putts
          Builder(builder: (context) {
            final compact = players.length >= 5;
            return Row(
              children: playerData.asMap().entries.map((e) {
                final d = e.value;
                final isLast = e.key == playerData.length - 1;
                final gap = EdgeInsets.only(right: isLast ? 0 : (compact ? 5 : 8));

                // ── Sin scores aún ────────────────────────────────────────
                if (!d.hasAny || d.total == 0) {
                  if (compact) {
                    // Compacto vacío: apodo (primer nombre) + guión
                    final nickname = d.player.name.split(' ').first;
                    return Expanded(
                      child: Padding(
                        padding: gap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          decoration: BoxDecoration(
                            color: cSub.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cDiv),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(nickname,
                                  style: TextStyle(color: cSub,
                                      fontSize: 11, fontWeight: FontWeight.w800),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis),
                              Text('—', style: TextStyle(color: cSub,
                                  fontSize: 16, fontWeight: FontWeight.w900),
                                  textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return Expanded(
                    child: Padding(
                      padding: gap,
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

                // ── Modo COMPACTO (5+ jugadores) ─────────────────────────
                if (compact) {
                  final nickname = d.player.name.split(' ').first;
                  return Expanded(
                    child: Padding(
                      padding: gap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        decoration: BoxDecoration(
                          color: dc.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: dc.withValues(alpha: 0.35), width: 1.5),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Apodo (primer nombre) del jugador
                            Text(nickname,
                                style: TextStyle(
                                    color: cText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            // Score medal grande
                            Text('${d.total}',
                                style: TextStyle(
                                    color: cText,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    height: 1.0),
                                textAlign: TextAlign.center),
                            // Vs par (chip pequeño)
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: dc.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(diffLabel,
                                  style: TextStyle(
                                      color: dc,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900),
                                  textAlign: TextAlign.center),
                            ),
                            // Putts (si existen)
                            if (d.totalPutts > 0) ...[
                              const SizedBox(height: 5),
                              Text('${d.totalPutts}p',
                                  style: TextStyle(
                                      color: puttColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700),
                                  textAlign: TextAlign.center),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // ── Modo NORMAL (≤4 jugadores) ────────────────────────────
                return Expanded(
                  child: Padding(
                    padding: gap,
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
            );
          }),
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

// Filtro de estado de duelo
enum _DuelFilter { todos, ganados, acumulados, perdidos }

class _OneVOneViewState extends State<_OneVOneView> {
  bool         _onlyMine    = false;
  String?      _myPlayerId;   // ID del jugador "yo" — se resuelve automáticamente o el usuario elige
  _DuelFilter  _duelFilter  = _DuelFilter.todos;

  // Resuelve quién es "mi jugador" en la ronda:
  // 1. Jugador con linkedUserId == uid autenticado
  // 2. Jugador con linkedUserId == ownerUid de la ronda
  // 3. null → no se puede determinar automáticamente
  Player? _resolveMyPlayer(Round round) {
    final uid = AuthService.uid;

    // Prioridad 1: linkedUserId == uid actual
    if (uid != null) {
      final linked = round.players
          .where((p) => p.linkedUserId == uid)
          .firstOrNull;
      if (linked != null) return linked;
    }

    // Prioridad 2: ownerUid de la ronda
    final ownerUid = round.ownerUid;
    if (ownerUid != null) {
      final owner = round.players
          .where((p) => p.linkedUserId == ownerUid)
          .firstOrNull;
      if (owner != null) return owner;
    }

    // Prioridad 3: _myPlayerId elegido manualmente por el usuario
    if (_myPlayerId != null) {
      return round.players.where((p) => p.id == _myPlayerId).firstOrNull;
    }

    return null;
  }

  /// Calcula el estado del duelo desde la perspectiva del jugador [myPlayer].
  /// Devuelve: ganados / perdidos / acumulados / todos (en juego / sin datos).
  _DuelFilter _duelStateFor(Round round, Player p1, Player p2, Player? myPlayer) {
    if (myPlayer == null) return _DuelFilter.todos;

    // Buscar módulos para este par
    BetModuleInstance? skinsMod;
    int matchStatus = 0;
    bool foundSkins = false;

    for (final g in round.betGroups) {
      for (final m in g.modules) {
        final pids = m.hasTeamSides
            ? [m.sideA.playerIds.first, m.sideB.playerIds.first]
            : (m.participantIds.isNotEmpty ? m.participantIds : g.playerIds);
        if (!pids.contains(p1.id) || !pids.contains(p2.id)) continue;

        if (m.type == BetModuleType.skins) {
          skinsMod = m;
          foundSkins = true;
        } else if (m.type == BetModuleType.nassau ||
                   m.type == BetModuleType.matchAutoPress) {
          matchStatus = GameEngine.matchPlayStatus(round, p1.id, p2.id, true);
        }
      }
    }

    if (foundSkins && skinsMod != null) {
      final results = BetEngine.skinsScorecard(round, p1.id, p2.id, skinsMod);
      final played = results.where((r) => !r.isPending).toList();
      if (played.isEmpty) return _DuelFilter.todos;

      final last = played.last;
      final skins1 = last.cumP1;
      final skins2 = last.cumP2;
      final currentPot = results.last.pot;
      final skinsInPot = (currentPot / skinsMod.skins.valuePerSkin).round();
      final hasCarry = skinsInPot > 1 && skinsMod.skins.carryOver;

      if (hasCarry) return _DuelFilter.acumulados;

      // Perspectiva del usuario
      final isP1 = myPlayer.id == p1.id;
      final myLead = isP1 ? (skins1 - skins2) : (skins2 - skins1);
      if (myLead > 0) return _DuelFilter.ganados;
      if (myLead < 0) return _DuelFilter.perdidos;
      return _DuelFilter.todos; // empate
    }

    // Match/Nassau
    final playedCount = List.generate(round.totalHoles, (i) => i + 1)
        .where((h) => round.getScore(p1.id, h).hasScore && round.getScore(p2.id, h).hasScore)
        .length;
    if (playedCount == 0) return _DuelFilter.todos;

    final isP1 = myPlayer.id == p1.id;
    final myStatus = isP1 ? matchStatus : -matchStatus;
    if (myStatus > 0) return _DuelFilter.ganados;
    if (myStatus < 0) return _DuelFilter.perdidos;
    return _DuelFilter.todos; // all square
  }

  @override
  Widget build(BuildContext context) {
    final t     = widget.t;
    final round = widget.round;

    if (round.players.length < 2) {
      return Center(child: Text('Necesitas al menos 2 jugadores', style: TextStyle(color: t.sub)));
    }

    final allPairs = _buildPairs(round);
    // Solo mostrar barra de filtros si hay más de 1 duelo
    final canFilter = allPairs.length > 1;

    // Resolver jugador "yo"
    final myPlayer = _resolveMyPlayer(round);

    // ── Aplicar filtro "mis duelos" ──────────────────────────────────────
    final mineFiltered = (_onlyMine && canFilter && myPlayer != null)
        ? allPairs
            .where((p) => p.$1.id == myPlayer.id || p.$2.id == myPlayer.id)
            .toList()
        : allPairs;

    // ── Aplicar filtro de estado ─────────────────────────────────────────
    // IMPORTANTE: si el filtro es "todos", mostrar todos sin condición.
    // Si hay filtro activo y no hay resultados, mostrar vacío (NO hacer fallback).
    final finalPairs = (_duelFilter == _DuelFilter.todos)
        ? mineFiltered
        : mineFiltered.where((p) {
            final state = _duelStateFor(round, p.$1, p.$2, myPlayer);
            return state == _duelFilter;
          }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(children: [
        // ── Barra de filtros ─────────────────────────────────────────────
        if (canFilter) ...[
          _FiltersBar(
            onlyMine: _onlyMine,
            duelFilter: _duelFilter,
            myPlayer: myPlayer,
            allPlayers: round.players,
            t: t,
            onToggleMine: () => setState(() => _onlyMine = !_onlyMine),
            onPickPlayer: (pid) => setState(() {
              _myPlayerId = pid;
              _onlyMine   = true;
            }),
            onFilterChange: (f) => setState(() => _duelFilter = f),
          ),
          const SizedBox(height: 12),
        ],

        // ── Tarjetas de duelo ─────────────────────────────────────────────
        if (finalPairs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              Icon(Icons.filter_list_off, color: t.sub, size: 40),
              const SizedBox(height: 10),
              Text('Sin duelos en esta categoría',
                  style: TextStyle(color: t.sub, fontSize: 14)),
            ]),
          )
        else
          ...finalPairs.asMap().entries.map((entry) {
            final i    = entry.key;
            final pair = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: i < finalPairs.length - 1 ? 12 : 0),
              child: _MatchDuelCard(
                round: round, p1: pair.$1, p2: pair.$2, t: t,
                expanded: finalPairs.length == 1,
                myPlayerId: myPlayer?.id,
                onApplyCarry: (ctx, factor, nassauMods, matchMods) =>
                    _applyCarry(ctx, pair.$1.id, pair.$2.id, factor, nassauMods, matchMods),
              ),
            );
          }),
      ]),
    );
  }

  /// Construye pares únicos (p1, p2) para la vista 1v1.
  ///
  /// Estrategia en orden de prioridad:
  ///  1. BetGroups con exactamente 2 jugadores → duelo directo.
  ///  2. Módulos 1v1 (nassau / matchAutoPress / skins) con participantIds de 2
  ///     dentro de grupos multi-jugador → cada par de participantIds = un duelo.
  ///  3. Si sigue vacío, generar todos los pares posibles entre los jugadores
  ///     de la ronda (round-robin) como fallback visual.
  List<(Player, Player)> _buildPairs(Round round) {
    final seen  = <String>{};
    final pairs = <(Player, Player)>[];

    void addPair(String id1, String id2) {
      final key = ([id1, id2]..sort()).join('|');
      if (seen.contains(key)) return;
      try {
        final p1 = round.players.firstWhere((p) => p.id == id1);
        final p2 = round.players.firstWhere((p) => p.id == id2);
        seen.add(key);
        pairs.add((p1, p2));
      } catch (_) {}
    }

    // ── Prioridad 1: grupos con exactamente 2 jugadores ──────────────────
    for (final g in round.betGroups) {
      if (g.playerIds.length == 2) {
        addPair(g.playerIds[0], g.playerIds[1]);
      }
    }

    // ── Prioridad 2: módulos 1v1 dentro de grupos multi-jugador ──────────
    for (final g in round.betGroups) {
      for (final m in g.modules) {
        // Tipos que implican duelo 1v1
        if (m.type == BetModuleType.nassau ||
            m.type == BetModuleType.matchAutoPress ||
            m.type == BetModuleType.skins) {
          // Fuente de participantes: sides > participantIds > playerIds del grupo
          List<String> pids;
          if (m.hasTeamSides) {
            // Cada "side" puede ser un equipo, pero tratamos el duelo como 1v1
            // tomando el primer jugador de cada lado
            pids = [m.sideA.playerIds.first, m.sideB.playerIds.first];
          } else {
            pids = m.participantIds.isNotEmpty ? m.participantIds : g.playerIds;
          }
          if (pids.length == 2) {
            addPair(pids[0], pids[1]);
          }
        }
      }
    }

    // ── Prioridad 3: fallback round-robin si no se encontró ningún par ────
    if (pairs.isEmpty && round.players.length >= 2) {
      final players = round.players;
      for (int i = 0; i < players.length; i++) {
        for (int j = i + 1; j < players.length; j++) {
          addPair(players[i].id, players[j].id);
        }
      }
    }

    return pairs;
  }

  void _applyCarry(BuildContext context, String p1Id, String p2Id, double factor,
      List<BetModuleInstance> nassauMods, List<BetModuleInstance> matchMods) {
    final prov  = context.read<RoundProvider>();
    final round = prov.round!;

    final newGroups = round.betGroups.map((g) {
      final newModules = g.modules.map((m) {
        if (nassauMods.any((nm) => nm.id == m.id)) {
          return m.copyWith(nassauConfig: m.nassau.copyWith(carryApplied: true, carryFactor: factor));
        }
        if (matchMods.any((mm) => mm.id == m.id)) {
          final existingByPair = Map<String, double>.from(m.matchAutoPress.carryByPair);
          existingByPair[MatchAutoPressConfig.pairKey(p1Id, p2Id)] = factor;
          return m.copyWith(
            matchAutoPressConfig: m.matchAutoPress.copyWith(
              carryByPair: existingByPair,
              carryApplied: true,
              carryFactor: factor,
            ),
          );
        }
        // Nassau con carry (pressEnabled o no): aplica si tiene carryEnabled
        if (m.type == BetModuleType.nassau && m.nassau.carryEnabled) {
          final pids = m.participantIds.isNotEmpty ? m.participantIds : g.playerIds;
          if (pids.contains(p1Id) && pids.contains(p2Id)) {
            return m.copyWith(nassauConfig: m.nassau.copyWith(
              carryApplied: true, carryFactor: factor));
          }
        }
        return m;
      }).toList();
      return BetGroup(id: g.id, name: g.name, format: g.format, playerIds: g.playerIds, modules: newModules);
    }).toList();
    prov.updateBetGroups(newGroups);
  }

  List<BetModuleInstance> _findModules(Round round, String p1Id, String p2Id, BetModuleType type) {
    final mods = <BetModuleInstance>[];
    for (final g in round.betGroups) {
      final ids = g.playerIds;
      if (ids.length == 2 && ids.contains(p1Id) && ids.contains(p2Id)) {
        mods.addAll(g.modules.where((m) => m.type == type));
      }
    }
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

// ── Barra de filtros combinada ────────────────────────────────────────────────
// Fila 1: Toggle "Mis duelos" + botón de elegir jugador
// Fila 2: Chips de estado (Todos / Ganados / Acumulados / Perdidos)
class _FiltersBar extends StatelessWidget {
  final bool onlyMine;
  final _DuelFilter duelFilter;
  final Player? myPlayer;
  final List<Player> allPlayers;
  final GolfTheme t;
  final VoidCallback onToggleMine;
  final void Function(String pid) onPickPlayer;
  final void Function(_DuelFilter) onFilterChange;

  const _FiltersBar({
    required this.onlyMine,
    required this.duelFilter,
    required this.myPlayer,
    required this.allPlayers,
    required this.t,
    required this.onToggleMine,
    required this.onPickPlayer,
    required this.onFilterChange,
  });

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¿Cuál jugador eres tú?',
              style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text('Filtrará solo los duelos donde participas.',
              style: TextStyle(color: t.sub, fontSize: 12)),
          const SizedBox(height: 14),
          ...allPlayers.map((p) => ListTile(
            leading: GAvatar(name: p.name, colorIndex: p.colorIndex, size: 36),
            title: Text(p.name,
                style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
            subtitle: Text('HCP ${p.handicapBase.toStringAsFixed(0)}',
                style: TextStyle(color: t.sub)),
            trailing: myPlayer?.id == p.id
                ? Icon(Icons.check_circle, color: t.primary, size: 20)
                : null,
            onTap: () {
              onPickPlayer(p.id);
              Navigator.pop(context);
            },
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myName   = myPlayer?.name.split(' ').first;
    final hasPlayer = myPlayer != null;

    // Chips: (filtro, icono, color, tooltip)
    final chips = [
      (_DuelFilter.todos,      Icons.apps_rounded,            Colors.white70,             'Todos'),
      (_DuelFilter.ganados,    Icons.trending_up_rounded,     const Color(0xFF35C759),    'Ganados'),
      (_DuelFilter.acumulados, Icons.local_fire_department,   const Color(0xFFFFCC00),    'Acumulados'),
      (_DuelFilter.perdidos,   Icons.trending_down_rounded,   const Color(0xFFFF453A),    'Perdidos'),
    ];

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      // ── Toggle "Mis duelos" — ocupa el espacio disponible ─────────────
      Expanded(
        child: GestureDetector(
          onTap: hasPlayer ? onToggleMine : () => _showPicker(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              gradient: (onlyMine && hasPlayer)
                  ? const LinearGradient(
                      colors: [Color(0xFF1F8F3A), Color(0xFF0D5020)])
                  : null,
              color: (onlyMine && hasPlayer) ? null : const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (onlyMine && hasPlayer)
                    ? const Color(0xFF35C759).withValues(alpha: 0.50)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1.2,
              ),
            ),
            child: Row(children: [
              Icon(
                (onlyMine && hasPlayer) ? Icons.person : Icons.people_outline,
                color: (onlyMine && hasPlayer) ? Colors.white : t.sub,
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  (onlyMine && hasPlayer)
                      ? 'Mis duelos ($myName)'
                      : 'Todos',
                  style: TextStyle(
                    color: (onlyMine && hasPlayer) ? Colors.white : t.sub,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _MiniSwitch(active: onlyMine && hasPlayer),
            ]),
          ),
        ),
      ),

      const SizedBox(width: 6),

      // ── Botón elegir jugador ──────────────────────────────────────────
      GestureDetector(
        onTap: () => _showPicker(context),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: hasPlayer
                ? t.primary.withValues(alpha: 0.15)
                : const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: hasPlayer
                    ? t.primary.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(
            hasPlayer ? Icons.edit_outlined : Icons.person_search_outlined,
            color: hasPlayer ? t.primary : t.sub,
            size: 16,
          ),
        ),
      ),

      const SizedBox(width: 6),

      // ── Separador vertical ────────────────────────────────────────────
      Container(
        width: 1, height: 28,
        color: Colors.white.withValues(alpha: 0.10),
      ),

      const SizedBox(width: 6),

      // ── Chips de estado: solo iconos, sin scroll, misma altura ────────
      ...chips.map((chip) {
        final (filter, icon, chipColor, tooltip) = chip;
        final isSelected = duelFilter == filter;
        return Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Tooltip(
            message: tooltip,
            child: GestureDetector(
              onTap: () => onFilterChange(filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isSelected
                      ? chipColor.withValues(alpha: 0.18)
                      : const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? chipColor.withValues(alpha: 0.70)
                        : Colors.white.withValues(alpha: 0.08),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Icon(icon,
                    color: isSelected ? chipColor : t.sub,
                    size: 17),
              ),
            ),
          ),
        );
      }),
    ]);
  }
}

// Mini switch visual reutilizable
class _MiniSwitch extends StatelessWidget {
  final bool active;
  const _MiniSwitch({required this.active});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 36, height: 20,
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Colors.white.withValues(alpha: active ? 0.40 : 0.12)),
      ),
      child: Stack(children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          left: active ? 17 : 2,
          top: 2,
          child: Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Toggle "Solo mis duelos" (DEPRECATED — mantenido para compatibilidad) ─────
class _MyMatchesToggle extends StatelessWidget {
  final bool active;
  final Player? myPlayer;           // null = aún no determinado
  final List<Player> allPlayers;
  final GolfTheme t;
  final VoidCallback onToggle;
  final void Function(String pid) onPickPlayer;

  const _MyMatchesToggle({
    required this.active,
    required this.myPlayer,
    required this.allPlayers,
    required this.t,
    required this.onToggle,
    required this.onPickPlayer,
  });

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¿Cuál jugador eres tú?',
              style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text('Filtrará solo los duelos donde participas.',
              style: TextStyle(color: t.sub, fontSize: 12)),
          const SizedBox(height: 14),
          ...allPlayers.map((p) => ListTile(
            leading: GAvatar(name: p.name, colorIndex: p.colorIndex, size: 36),
            title: Text(p.name,
                style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
            subtitle: Text('HCP ${p.handicapBase.toStringAsFixed(0)}',
                style: TextStyle(color: t.sub)),
            trailing: myPlayer?.id == p.id
                ? Icon(Icons.check_circle, color: t.primary, size: 20)
                : null,
            onTap: () {
              onPickPlayer(p.id);
              Navigator.pop(context);
            },
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const activeGrad = [Color(0xFF1F8F3A), Color(0xFF0D5020)];
    final myName = myPlayer?.name.split(' ').first;
    final hasPlayer = myPlayer != null;

    return Row(children: [
      // ── Botón principal toggle ──────────────────────────────────────
      Expanded(
        child: GestureDetector(
          onTap: hasPlayer ? onToggle : () => _showPicker(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: (active && hasPlayer)
                  ? const LinearGradient(colors: activeGrad)
                  : null,
              color: (active && hasPlayer) ? null : const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: (active && hasPlayer)
                    ? const Color(0xFF35C759).withValues(alpha: 0.50)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1.2,
              ),
            ),
            child: Row(children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  (active && hasPlayer) ? Icons.person : Icons.people_outline,
                  key: ValueKey(active && hasPlayer),
                  color: (active && hasPlayer) ? Colors.white : t.sub,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    (active && hasPlayer)
                        ? 'Mis duelos ($myName)'
                        : 'Todos los duelos',
                    key: ValueKey(active && hasPlayer),
                    style: TextStyle(
                      color: (active && hasPlayer) ? Colors.white : t.sub,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // Switch visual
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 38, height: 22,
                decoration: BoxDecoration(
                  color: (active && hasPlayer)
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                      color: Colors.white.withValues(
                          alpha: (active && hasPlayer) ? 0.40 : 0.12)),
                ),
                child: Stack(children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    left: (active && hasPlayer) ? 18 : 2,
                    top: 2,
                    child: Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        color: (active && hasPlayer) ? Colors.white : t.sub,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),

      // ── Botón "elegir jugador" (siempre visible, pequeño) ─────────
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => _showPicker(context),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: hasPlayer
                ? t.primary.withValues(alpha: 0.15)
                : const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hasPlayer
                    ? t.primary.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(
            hasPlayer ? Icons.edit_outlined : Icons.person_search_outlined,
            color: hasPlayer ? t.primary : t.sub,
            size: 18,
          ),
        ),
      ),
    ]);
  }
}

// ── Tarjeta de duelo expandible ───────────────────────────────────────────────
// Muestra el badge de resultado. Al tocar, despliega hoyo-a-hoyo y paneles.
class _MatchDuelCard extends StatefulWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  final bool expanded;
  final String? myPlayerId;   // ID del jugador del usuario autenticado (para resaltar)
  final void Function(BuildContext ctx, double factor,
      List<BetModuleInstance> nassauMods,
      List<BetModuleInstance> matchMods) onApplyCarry;

  const _MatchDuelCard({
    required this.round, required this.p1, required this.p2,
    required this.t, required this.expanded,
    required this.onApplyCarry,
    this.myPlayerId,
  });

  @override
  State<_MatchDuelCard> createState() => _MatchDuelCardState();
}

class _MatchDuelCardState extends State<_MatchDuelCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _expanded = widget.expanded;
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    if (_expanded) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  List<BetModuleInstance> _findModules(BetModuleType type) {
    final round = widget.round;
    final p1Id  = widget.p1.id;
    final p2Id  = widget.p2.id;
    final mods  = <BetModuleInstance>[];
    for (final g in round.betGroups) {
      final ids = g.playerIds;
      if (ids.length == 2 && ids.contains(p1Id) && ids.contains(p2Id)) {
        mods.addAll(g.modules.where((m) => m.type == type));
      }
    }
    if (mods.isEmpty) {
      for (final g in round.betGroups) {
        if (g.playerIds.contains(p1Id) && g.playerIds.contains(p2Id)) {
          mods.addAll(g.modules.where((m) => m.type == type));
        }
      }
    }
    return mods;
  }

  @override
  Widget build(BuildContext context) {
    final round            = widget.round;
    final p1               = widget.p1;
    final p2               = widget.p2;
    final t                = widget.t;
    final skinsModules     = _findModules(BetModuleType.skins);
    final nassauModules    = _findModules(BetModuleType.nassau);
    final matchMods        = _findModules(BetModuleType.matchAutoPress);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── Badge resultado (siempre visible, tap para expandir) ──────
      GestureDetector(
        onTap: _toggle,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            _MatchStatusCard(
              round: round, p1: p1, p2: p2, t: t,
              skinsModules:      skinsModules,
              nassauModules:     nassauModules,
              matchPressModules: matchMods,
            ),
            // Indicador de expansión (chevron) en la esquina inferior derecha
            Positioned(
              right: 14, bottom: 12,
              child: AnimatedRotation(
                turns: _expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 280),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.keyboard_arrow_down,
                      color: Colors.white.withValues(alpha: 0.60), size: 16),
                ),
              ),
            ),
          ],
        ),
      ),

      // ── Detalle expandible ────────────────────────────────────────
      SizeTransition(
        sizeFactor: _fadeAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(children: [
            const SizedBox(height: 10),

            // Paneles Nassau
            ...nassauModules.map((mod) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NassauLivePanel(round: round, p1: p1, p2: p2, mod: mod, t: t),
            )),

            // Paneles Match+Press
            ...matchMods.map((mod) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MatchPressLivePanel(round: round, p1: p1, p2: p2, mod: mod, t: t),
            )),

            // Hoyo a hoyo
            _HoleByHoleMatch(
              round: round, p1: p1, p2: p2, t: t,
              skinsMod: skinsModules.isNotEmpty ? skinsModules.first : null,
            ),
            const SizedBox(height: 10),

            // Carry
            _CarryPanel(
              round: round, p1: p1, p2: p2, t: t,
              nassauModules:     nassauModules,
              matchPressModules: matchMods,
              onApplyCarry: (factor) =>
                  widget.onApplyCarry(context, factor, nassauModules, matchMods),
            ),

            // Desglose financiero por duelo
            _FinancialBreakdown(round: round, p1: p1, p2: p2, t: t),
          ]),
        ),
      ),
    ]);
  }
}

// ── Selector de jugadores (mantenido por compatibilidad, ya no usado en UI) ───
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
// Premium hero card: gradiente según estado, score grande centrado,
// avatares con nombres, pills secundarias (thru, carry, dinero).
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
    if (skinsModules.isNotEmpty) {
      return _SkinsGlanceCard(
          round: round, p1: p1, p2: p2, mod: skinsModules.first, t: t);
    }
    if (nassauModules.isNotEmpty) {
      return _buildNassauCard(context);
    }
    return _buildMatchCard(context);
  }

  // ── Badge principal para Nassau (F9 / B9 / Total) ─────────────────────────
  Widget _buildNassauCard(BuildContext context) {
    final mod  = nassauModules.first;
    final st   = BetEngine.nassauLiveStatus(round, p1.id, p2.id, mod);
    final n1   = p1.name.split(' ').first;
    final n2   = p2.name.split(' ').first;
    final lastH       = GameEngine.lastCompletedHole(round, [p1.id, p2.id]);
    final playedCount = st.frontPlayed + st.backPlayed;

    // ── Resultado global: segmentos COMPLETADOS ganados por cada jugador ───────
    // Solo se cuenta un segmento cuando se jugaron sus 9 hoyos completos.
    // Un segmento en curso (< 9 hoyos) no se asigna como ganado — influye
    // solo como desempate visual cuando segsP1 == segsP2.
    int segsP1 = 0, segsP2 = 0;
    if (st.frontPlayed >= 9) {          // F9 completado
      if (st.front > 0) segsP1++;
      else if (st.front < 0) segsP2++;
    }
    if (st.backPlayed >= 9) {           // B9 completado
      if (st.back > 0) segsP1++;
      else if (st.back < 0) segsP2++;
    }
    if (playedCount >= 18) {            // Total completado
      if (st.total > 0) segsP1++;
      else if (st.total < 0) segsP2++;
    }

    // ── Balance en vivo (suma de segmentos + presiones) ───────────────────────
    double npBal = 0.0;
    if (st.frontPlayed > 0) {
      if (st.front > 0) npBal += st.frontVal;
      if (st.front < 0) npBal -= st.frontVal;
    }
    if (st.backPlayed > 0) {
      if (st.back > 0) npBal += st.backVal;
      if (st.back < 0) npBal -= st.backVal;
    }
    // Total 18: se acumula en vivo desde el primer hoyo jugado (es una apuesta
    // independiente al ganador global, no solo al terminar los 18 hoyos).
    if (playedCount > 0) {
      if (st.total > 0) npBal += st.totalVal;
      if (st.total < 0) npBal -= st.totalVal;
    }
    // Presiones: usar valor correcto por segmento
    final isBack   = round.startingNine == StartingNine.back;
    final seg1From = isBack ? 10 : 1;
    final seg1To   = isBack ? 18 : 9;
    for (final p in st.presses) {
      final inSeg1   = p.startHole >= seg1From && p.startHole <= seg1To;
      final pressVal = inSeg1 ? mod.nassau.frontPressValue : mod.nassau.backPressValue;
      if (p.score > 0) npBal += pressVal;
      if (p.score < 0) npBal -= pressVal;
    }

    // ── Etiquetas de estado ───────────────────────────────────────────────────
    final Color accentColor;
    final List<Color> gradColors;
    final String stateWord;
    final String diffLabel;

    // diffLabel: resumen F9 / B9
    final fLabel = st.frontPlayed == 0
        ? 'F9: –'
        : st.front == 0
            ? 'F9: AS'
            : 'F9: ${st.front > 0 ? n1 : n2} ${st.front.abs()}UP';
    final bLabel = st.backPlayed == 0
        ? 'B9: –'
        : st.back == 0
            ? 'B9: AS'
            : 'B9: ${st.back > 0 ? n1 : n2} ${st.back.abs()}UP';
    diffLabel = '$fLabel  ·  $bLabel';

    // ── Color basado en segmentos ganados (F9/B9/Total), no en balance monetario
    // Esto es más intuitivo: verde = ganando más segmentos, rojo = perdiendo más
    // El balance monetario (npBal) se usa solo para el chip de dinero
    if (playedCount == 0) {
      accentColor = const Color(0xFF607D8B);
      gradColors  = const [Color(0xFF37474F), Color(0xFF1C1C1E)];
      stateWord   = 'NASSAU';
    } else if (segsP1 > segsP2) {
      accentColor = const Color(0xFF35C759);
      gradColors  = const [Color(0xFF1F8F3A), Color(0xFF0E3D1B)];
      stateWord   = 'GANANDO';
    } else if (segsP2 > segsP1) {
      accentColor = const Color(0xFFFF453A);
      gradColors  = const [Color(0xFF7A1E1E), Color(0xFF2A0E0E)];
      stateWord   = 'PERDIENDO';
    } else {
      // segsP1 == segsP2: ninguno lleva ventaja en segmentos cerrados
      accentColor = const Color(0xFF1565C0);
      gradColors  = const [Color(0xFF1A3A6B), Color(0xFF0D1F3C)];
      stateWord   = 'EMPATADO';
    }

    // subLabel: presiones activas
    String? subLabel;
    final parts = <String>[];
    if (st.frontPlayed > 0) parts.add(fLabel);
    if (st.backPlayed > 0)  parts.add(bLabel);
    final totalPresses = st.presses.length;
    if (totalPresses > 0) {
      parts.add('$totalPresses press${totalPresses > 1 ? 'iones' : 'ión'}');
    }
    if (parts.length > 2) subLabel = parts.skip(2).join('  •  ');

    return _PremiumResultBadge(
      p1: p1, p2: p2, t: t,
      stateWord: stateWord,
      score1: segsP1, score2: segsP2,
      scoreLabel: 'segs',
      diffLabel: diffLabel,
      accentColor: accentColor,
      gradColors: gradColors,
      playedCount: playedCount,
      lastHole: lastH,
      tieCount: null,
      skinsInPot: null,
      round: round,
      subLabel: subLabel,
      liveBalance: npBal,
    );
  }

  Widget _buildMatchCard(BuildContext context) {
    final status      = GameEngine.matchPlayStatus(round, p1.id, p2.id, true);
    final lastH       = GameEngine.lastCompletedHole(round, [p1.id, p2.id]);
    final playedCount = List.generate(round.totalHoles, (i) => i + 1)
        .where((h) => round.getScore(p1.id, h).hasScore &&
                      round.getScore(p2.id, h).hasScore)
        .length;

    // ── Tema según estado ──────────────────────────────────────────────────
    final Color accentColor;
    final List<Color> gradColors;
    final String stateWord;
    final String scoreLabel;
    final String diffLabel;

    final n1 = p1.name.split(' ').first;
    final n2 = p2.name.split(' ').first;
    if (status == 0) {
      accentColor = const Color(0xFF1565C0);
      gradColors  = const [Color(0xFF1A3A6B), Color(0xFF0D1F3C)];
      stateWord   = 'EMPATADO';
      scoreLabel  = 'hoyos';
      diffLabel   = 'All Square';
    } else if (status > 0) {
      accentColor = const Color(0xFF35C759);
      gradColors  = const [Color(0xFF1F8F3A), Color(0xFF0E3D1B)];
      stateWord   = 'GANANDO';
      scoreLabel  = 'hoyos';
      diffLabel   = '$n1 +$status UP';
    } else {
      accentColor = const Color(0xFFFF453A);
      gradColors  = const [Color(0xFF7A1E1E), Color(0xFF2A0E0E)];
      stateWord   = 'PERDIENDO';
      scoreLabel  = 'hoyos';
      diffLabel   = '$n2 +${status.abs()} UP';
    }

    // Scores grandes: hoyos ganados por cada jugador
    final s1 = status > 0 ? status : 0;
    final s2 = status < 0 ? status.abs() : 0;

    // ── Métricas y balance en vivo ────────────────────────────────────────────
    String? subLabel;
    double? liveBalance;

    if (matchPressModules.isNotEmpty) {
      final mod     = matchPressModules.first;
      final presses = BetEngine.matchAutoPressLive(round, p1.id, p2.id, mod);
      double mpBal = 0.0;
      for (final pr in presses) {
        if (pr.played == 0) continue;
        if (pr.leadingPlayerId == p1.id) mpBal += pr.value;
        if (pr.leadingPlayerId == p2.id) mpBal -= pr.value;
      }
      liveBalance = mpBal;
      final pressSegments = presses.skip(1).where((pr) => pr.played > 0).toList();
      if (pressSegments.isNotEmpty) {
        final pw1          = pressSegments.where((pr) => pr.leadingPlayerId == p1.id).length;
        final pw2          = pressSegments.where((pr) => pr.leadingPlayerId == p2.id).length;
        final ties         = pressSegments.where((pr) => pr.score == 0).length;
        final totalPresses = pressSegments.length;
        final tieStr       = ties > 0 ? '  ($ties AS)' : '';
        subLabel = 'Presiones: $n1 $pw1 – $pw2 $n2$tieStr  •  $totalPresses jugadas';
      }
    } else if (nassauModules.isNotEmpty && nassauModules.first.pressEnabled) {
      // Nassau con presiones: mostrar balance en vivo usando nassauLiveStatus
      final mod = nassauModules.first;
      final st  = BetEngine.nassauLiveStatus(round, p1.id, p2.id, mod);
      double npBal = 0.0;
      if (st.frontPlayed > 0) {
        if (st.front > 0) npBal += st.frontVal;
        if (st.front < 0) npBal -= st.frontVal;
      }
      if (st.backPlayed > 0) {
        if (st.back > 0) npBal += st.backVal;
        if (st.back < 0) npBal -= st.backVal;
      }
      if (st.frontPlayed + st.backPlayed > 0 && round.totalHoles >= 18) {
        if (st.total > 0) npBal += st.totalVal;
        if (st.total < 0) npBal -= st.totalVal;
      }
      for (final p in st.presses) {
        // Determinar si la presión es del segmento 1 o 2 según startingNine
        final isBack   = round.startingNine == StartingNine.back;
        final seg1From = isBack ? 10 : 1;
        final seg1To   = isBack ? 18 : 9;
        final inSeg1   = p.startHole >= seg1From && p.startHole <= seg1To;
        final pressVal = inSeg1 ? mod.nassau.frontPressValue : mod.nassau.backPressValue;
        if (p.score > 0) npBal += pressVal;
        if (p.score < 0) npBal -= pressVal;
      }
      liveBalance = npBal;
      final parts = <String>[];
      if (st.frontPlayed > 0) {
        final fs = st.front == 0 ? 'F9: AS' : 'F9: ${st.front > 0 ? n1 : n2} ${st.front.abs()}UP';
        parts.add(fs);
      }
      if (st.backPlayed > 0) {
        final bs = st.back == 0 ? 'B9: AS' : 'B9: ${st.back > 0 ? n1 : n2} ${st.back.abs()}UP';
        parts.add(bs);
      }
      final totalPresses = st.presses.length;
      if (totalPresses > 0) parts.add('$totalPresses press${totalPresses > 1 ? 'iones' : 'ión'}');
      if (parts.isNotEmpty) subLabel = parts.join('  •  ');
    }

    return _PremiumResultBadge(
      p1: p1, p2: p2, t: t,
      stateWord: stateWord,
      score1: s1, score2: s2,
      scoreLabel: scoreLabel,
      diffLabel: diffLabel,
      accentColor: accentColor,
      gradColors: gradColors,
      playedCount: playedCount,
      lastHole: lastH,
      tieCount: null,
      skinsInPot: null,
      round: round,
      subLabel: subLabel,
      liveBalance: liveBalance,
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
    final results  = BetEngine.skinsScorecard(round, p1.id, p2.id, mod);
    final played   = results.where((r) => !r.isPending).toList();
    final last     = played.isNotEmpty ? played.last : null;
    final skins1   = last?.cumP1 ?? 0;
    final skins2   = last?.cumP2 ?? 0;
    final tieCount = results.where((r) => r.isTie).length;
    final currentPot  = results.isNotEmpty ? results.last.pot : mod.skins.valuePerSkin;
    final skinsInPot  = (currentPot / mod.skins.valuePerSkin).round();
    final playedCount = List.generate(round.totalHoles, (i) => i + 1)
        .where((h) => round.getScore(p1.id, h).hasScore &&
                      round.getScore(p2.id, h).hasScore)
        .length;
    final lastH = GameEngine.lastCompletedHole(round, [p1.id, p2.id]);
    final lead  = skins1 - skins2;

    final Color accentColor;
    final List<Color> gradColors;
    final String stateWord;
    final String diffLabel;

    final sn1 = p1.name.split(' ').first;
    final sn2 = p2.name.split(' ').first;
    // ¿Hay skins acumulados en el bote? → sobreescribir gradiente con amarillo-alerta
    final bool hasCarry = skinsInPot > 1;

    if (playedCount == 0) {
      accentColor = const Color(0xFF607D8B);
      gradColors  = const [Color(0xFF37474F), Color(0xFF1C1C1E)];
      stateWord   = 'EN JUEGO';
      diffLabel   = 'Esperando scores';
    } else if (lead == 0) {
      if (hasCarry) {
        // Empate con carry: amarillo-ámbar de alerta
        accentColor = const Color(0xFFFFCC00);
        gradColors  = const [Color(0xFF5C4500), Color(0xFF2A1E00)];
        stateWord   = 'EMPATADO';
        diffLabel   = '🔥 ×$skinsInPot en juego';
      } else {
        accentColor = const Color(0xFF1565C0);
        gradColors  = const [Color(0xFF1A3A6B), Color(0xFF0D1F3C)];
        stateWord   = 'EMPATADO';
        diffLabel   = 'All Square';
      }
    } else if (lead > 0) {
      if (hasCarry) {
        accentColor = const Color(0xFFFFCC00);
        gradColors  = const [Color(0xFF4A3800), Color(0xFF1F1600)];
        stateWord   = 'GANANDO';
        diffLabel   = '$sn1 +$lead UP  🔥×$skinsInPot';
      } else {
        accentColor = const Color(0xFF35C759);
        gradColors  = const [Color(0xFF1F8F3A), Color(0xFF0E3D1B)];
        stateWord   = 'GANANDO';
        diffLabel   = '$sn1 +$lead UP';
      }
    } else {
      if (hasCarry) {
        accentColor = const Color(0xFFFFCC00);
        gradColors  = const [Color(0xFF4A3800), Color(0xFF1F1600)];
        stateWord   = 'PERDIENDO';
        diffLabel   = '$sn2 +${lead.abs()} UP  🔥×$skinsInPot';
      } else {
        accentColor = const Color(0xFFFF453A);
        gradColors  = const [Color(0xFF7A1E1E), Color(0xFF2A0E0E)];
        stateWord   = 'PERDIENDO';
        diffLabel   = '$sn2 +${lead.abs()} UP';
      }
    }

    return _PremiumResultBadge(
      p1: p1, p2: p2, t: t,
      stateWord: stateWord,
      score1: skins1, score2: skins2,
      scoreLabel: 'skins',
      diffLabel: diffLabel,
      accentColor: accentColor,
      gradColors: gradColors,
      playedCount: playedCount,
      lastHole: lastH,
      tieCount: tieCount,
      skinsInPot: skinsInPot,
      round: round,
    );
  }
}

// ── PREMIUM RESULT BADGE ──────────────────────────────────────────────────────
// Badge elegante con gradiente, score grande centrado, avatares y pills.
// Usado tanto para Skins como para Match/Nassau.
class _PremiumResultBadge extends StatelessWidget {
  final Player p1, p2;
  final GolfTheme t;
  final String stateWord;
  final int score1, score2;
  final String scoreLabel;   // "skins", "hoyos"
  final String diffLabel;    // texto de diferencia principal
  final String? subLabel;    // línea secundaria opcional (ej: métricas de presiones)
  final Color accentColor;
  final List<Color> gradColors;
  final int playedCount;
  final int lastHole;
  final int? tieCount;
  final int? skinsInPot;
  final Round round;
  final double? liveBalance;  // override del balance en vivo (para matchAutoPress)

  const _PremiumResultBadge({
    required this.p1, required this.p2, required this.t,
    required this.stateWord, required this.score1, required this.score2,
    required this.scoreLabel, required this.diffLabel,
    required this.accentColor, required this.gradColors,
    required this.playedCount, required this.lastHole,
    required this.round,
    this.tieCount, this.skinsInPot,
    this.subLabel, this.liveBalance,
  });

  @override
  Widget build(BuildContext context) {
    final n1 = p1.name.split(' ').first;
    final n2 = p2.name.split(' ').first;
    final isWinning = score1 > score2;
    final isLosing  = score1 < score2;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradColors,
        ),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: gradColors[0].withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(children: [
          // ── Parte superior: estado ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(
              stateWord,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
              ),
            ),
          ),

          // ── Score grande centrado: Avatar · Número · vs · Número · Avatar ─
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Jugador 1
                _playerBlock(n1, p1, isWinning, true),

                // Score izquierdo
                const SizedBox(width: 12),
                _scoreBlock(score1, isWinning),

                // Separador "–"
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '–',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 14), // espacio para el label
                    ],
                  ),
                ),

                // Score derecho
                _scoreBlock(score2, isLosing),
                const SizedBox(width: 12),

                // Jugador 2
                _playerBlock(n2, p2, isLosing, false),
              ],
            ),
          ),

          // ── Label de tipo debajo de los scores ────────────────────────
          Padding(
            padding: EdgeInsets.only(bottom: subLabel != null ? 2 : 6),
            child: Text(
              diffLabel,
              style: TextStyle(
                color: accentColor.withValues(alpha: 0.90),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),

          // ── SubLabel opcional (ej: métricas de presiones) ─────────────
          if (subLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                subLabel!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),

          // ── Separador fino ─────────────────────────────────────────────
          Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.08),
            indent: 20,
            endIndent: 20,
          ),

          // ── Pills: Thru · carry · dinero ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Thru X hoyos
                if (playedCount > 0) ...[
                  _pill(
                    label: 'Thru $lastHole',
                    icon: null,
                    textColor: Colors.white.withValues(alpha: 0.55),
                    bgColor: Colors.white.withValues(alpha: 0.06),
                    borderColor: Colors.white.withValues(alpha: 0.10),
                  ),
                  const SizedBox(width: 8),
                ],
                // Carry/empates skins
                if ((tieCount ?? 0) > 0 && (skinsInPot ?? 0) > 1) ...[
                  _pill(
                    label: '🔥×${skinsInPot!}',
                    icon: null,
                    textColor: const Color(0xFFFF9500),
                    bgColor: const Color(0xFFFF9500).withValues(alpha: 0.12),
                    borderColor: const Color(0xFFFF9500).withValues(alpha: 0.30),
                  ),
                  const SizedBox(width: 8),
                ] else if ((tieCount ?? 0) > 0) ...[
                  _pill(
                    label: '${tieCount!} carries',
                    icon: null,
                    textColor: const Color(0xFFFF9500),
                    bgColor: const Color(0xFFFF9500).withValues(alpha: 0.12),
                    borderColor: const Color(0xFFFF9500).withValues(alpha: 0.30),
                  ),
                  const SizedBox(width: 8),
                ],
                // Balance neto
                _NetBalanceChip(
                    round: round, p1: p1, p2: p2, t: t,
                    stateColor: accentColor,
                    liveBalance: liveBalance),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _playerBlock(String name, Player p, bool highlight, bool alignLeft) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: highlight
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                        color: accentColor.withValues(alpha: 0.35),
                        blurRadius: 8,
                        spreadRadius: 1),
                  ],
                )
              : null,
          child: GAvatar(
            name: p.name,
            colorIndex: p.colorIndex,
            size: 38,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: 56,
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: highlight
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.60),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _scoreBlock(int score, bool highlight) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Text(
            '$score',
            key: ValueKey(score),
            style: TextStyle(
              color: highlight
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.45),
              fontSize: 52,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ),
        SizedBox(
          height: 16,
          child: Text(
            scoreLabel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.30),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill({
    required String label,
    required Color textColor,
    required Color bgColor,
    required Color borderColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, color: textColor, size: 10),
          const SizedBox(width: 3),
        ],
        Text(label, style: TextStyle(
            color: textColor, fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

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
  /// Si se pasa, usa este valor en lugar del ledger (para balance en vivo de Match+Press)
  final double? liveBalance;
  const _NetBalanceChip({required this.round, required this.p1,
      required this.p2, required this.t, required this.stateColor,
      this.liveBalance});

  @override
  Widget build(BuildContext context) {
    context.watch<RoundProvider>(); // reconstruir al cambiar scores

    // Si hay un balance en vivo (matchAutoPress activo), usarlo directamente
    // Si no, calcular desde el ledger (balance de apuestas cerradas)
    final double bal1;
    if (liveBalance != null) {
      bal1 = liveBalance!;
    } else {
      // Balance neto total entre p1 y p2 (suma todos los módulos activos)
      final bd = LedgerEngine.breakdownBetween(round, p1.id, p2.id);
      bal1 = bd.values.fold(0.0, (sum, v) => sum + v);
    }

    // balance neto desde perspectiva de p1
    final label = bal1.abs() < 0.005
        ? '\$0'
        : bal1 > 0
            ? '+\$${bal1.abs().toStringAsFixed(0)}'
            : '-\$${bal1.abs().toStringAsFixed(0)}';
    final color = bal1.abs() < 0.005 ? t.sub : bal1 > 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
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
    final n1 = p1.name.split(' ').first;
    final n2 = p2.name.split(' ').first;

    // Si tiene presiones activas, usar nassauPressLiveStatus para obtener
    // frontPresses/backPresses separados y valores por segmento.
    final NassauPressLiveStatus? pressStatus = mod.pressEnabled
        ? BetEngine.nassauPressLiveStatus(round, p1.id, p2.id, mod)
        : null;
    final baseStatus = pressStatus == null
        ? BetEngine.nassauLiveStatus(round, p1.id, p2.id, mod)
        : null;

    final int frontScore  = pressStatus?.front      ?? baseStatus!.front;
    final int backScore   = pressStatus?.back       ?? baseStatus!.back;
    final int totalScore  = pressStatus?.total      ?? baseStatus!.total;
    final int frontPlayed = pressStatus?.frontPlayed ?? baseStatus!.frontPlayed;
    final int backPlayed  = pressStatus?.backPlayed  ?? baseStatus!.backPlayed;
    final double frontVal = pressStatus?.frontVal   ?? baseStatus!.frontVal;
    final double backVal  = pressStatus?.backVal    ?? baseStatus!.backVal;
    final double totalVal = pressStatus?.totalVal   ?? baseStatus!.totalVal;
    final int totalPlayed = frontPlayed + backPlayed;

    final List<NassauPress> frontPresses = pressStatus?.frontPresses ?? [];
    final List<NassauPress> backPresses  = pressStatus?.backPresses  ?? [];
    final double frontPressVal = pressStatus?.frontPressVal ?? mod.nassau.frontPressValue;
    final double backPressVal  = pressStatus?.backPressVal  ?? mod.nassau.backPressValue;
    final bool carryActive     = pressStatus?.carryActive   ?? false;

    final openCount      = frontPresses.where((p) => p.isOpen).length
                         + backPresses.where((p) => p.isOpen).length;
    final totalPressCount = frontPresses.length + backPresses.length;

    // ── helper: chip visual de cada presión ──────────────────────────────────
    Widget pressChip(NassauPress press, double pressVal) {
      final rawScore = press.loser == p1.id ? press.score : -press.score;
      final color = rawScore == 0
          ? t.sub
          : rawScore > 0 ? t.profit : t.loss;
      final scoreStr = rawScore == 0
          ? 'AS'
          : rawScore > 0
              ? '$n1 +${rawScore.abs()}'
              : '$n2 +${rawScore.abs()}';
      return Container(
        margin: const EdgeInsets.only(top: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: press.isOpen
                ? t.accent.withValues(alpha: 0.55)
                : color.withValues(alpha: 0.35),
          ),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('⚡ H${press.startHole}',
                style: TextStyle(
                    color: t.accent, fontSize: 9, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 6),
          Text('(${press.loser == p1.id ? n1 : n2})',
              style: TextStyle(
                  color: t.sub.withValues(alpha: 0.7), fontSize: 9)),
          const Spacer(),
          Text(scoreStr,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(width: 5),
          Text('\$${pressVal.toStringAsFixed(0)}',
              style: TextStyle(color: t.sub, fontSize: 9)),
          if (press.isOpen) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text('EN JUEGO',
                  style: TextStyle(
                      color: t.accent, fontSize: 8, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.divider, width: 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              Text('NASSAU',
                  style: TextStyle(color: t.sub, fontSize: 10,
                      fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              if (carryActive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.profit.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'CARRY ×${mod.nassau.carryFactor.toStringAsFixed(0)}',
                    style: TextStyle(color: t.profit, fontSize: 8,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ],
              const Spacer(),
              if (totalPlayed > 0)
                Text('$totalPlayed/18 hoyos',
                    style: TextStyle(color: t.sub, fontSize: 10)),
              if (mod.pressEnabled) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: openCount > 0
                        ? t.accent.withValues(alpha: 0.12)
                        : t.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    openCount > 0 ? '$openCount press\u2009🔥' : 'Press ON',
                    style: TextStyle(
                        color: openCount > 0 ? t.accent : t.primary,
                        fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 10),

          // ── Tres bloques F9 / B9 / Total ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(children: [
              Expanded(child: _NassauSegment(
                label: 'F9', played: frontPlayed, total: 9,
                score: frontScore, value: frontVal,
                p1Name: n1, p2Name: n2, t: t,
              )),
              const SizedBox(width: 6),
              Expanded(child: _NassauSegment(
                label: 'B9', played: backPlayed, total: 9,
                score: backScore, value: backVal,
                p1Name: n1, p2Name: n2, t: t,
              )),
              const SizedBox(width: 6),
              Expanded(child: _NassauSegment(
                label: '18', played: totalPlayed, total: 18,
                score: totalScore, value: totalVal,
                p1Name: n1, p2Name: n2, t: t,
              )),
            ]),
          ),

          // ── Presiones: bloques visuales por segmento ──────────────────────
          if (totalPressCount > 0) ...[
            Divider(color: t.divider.withValues(alpha: 0.5), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (frontPresses.isNotEmpty) ...[
                    Text('PRESIONES  F9',
                        style: TextStyle(color: t.sub, fontSize: 9,
                            fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                    ...frontPresses.map((p) => pressChip(p, frontPressVal)),
                  ],
                  if (backPresses.isNotEmpty) ...[
                    if (frontPresses.isNotEmpty) const SizedBox(height: 10),
                    Text('PRESIONES  B9',
                        style: TextStyle(color: t.sub, fontSize: 9,
                            fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                    ...backPresses.map((p) => pressChip(p, backPressVal)),
                  ],
                ],
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
    // ── Paleta según estado ───────────────────────────────────────────────
    final Color baseColor;
    final List<Color> grad;
    final String bigNumber;   // número grande central
    final String playerName;  // nombre del ganador (o vacío)

    if (played == 0) {
      baseColor  = const Color(0xFF546E7A);
      grad       = const [Color(0xFF37474F), Color(0xFF263238)];
      bigNumber  = '\u2013';
      playerName = '';
    } else if (score == 0) {
      baseColor  = const Color(0xFF1976D2);
      grad       = const [Color(0xFF1565C0), Color(0xFF0D47A1)];
      bigNumber  = 'AS';
      playerName = '';
    } else if (score > 0) {
      baseColor  = const Color(0xFF2E7D32);
      grad       = const [Color(0xFF388E3C), Color(0xFF1B5E20)];
      bigNumber  = '+${score.abs()}';
      playerName = p1Name;
    } else {
      baseColor  = const Color(0xFFC62828);
      grad       = const [Color(0xFFD32F2F), Color(0xFF7F0000)];
      bigNumber  = '+${score.abs()}';
      playerName = p2Name;
    }

    final isDone = played >= total;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: grad,
        ),
        border: Border.all(color: baseColor.withValues(alpha: 0.45), width: 1),
        boxShadow: [
          BoxShadow(
            color: grad[0].withValues(alpha: 0.30),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Etiqueta del segmento (F9 / B9 / 18) ──────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 5),

            // ── Número grande: ventaja o AS o – ───────────────────────────
            Text(
              bigNumber,
              style: TextStyle(
                color: Colors.white,
                fontSize: bigNumber.length > 2 ? 18 : 22,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
              textAlign: TextAlign.center,
            ),

            // ── Nombre del jugador líder ────────────────────────────────
            if (playerName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                playerName,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ] else
              const SizedBox(height: 4),

            // ── Separador sutil ────────────────────────────────────────────
            const SizedBox(height: 5),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 5),

            // ── Pie: progreso + valor ─────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isDone) ...[
                  Text(
                    '$played/$total',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '  ·  ',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.20),
                      fontSize: 8,
                    ),
                  ),
                ],
                Text(
                  '\$${value.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: isDone
                        ? Colors.white.withValues(alpha: 0.95)
                        : Colors.white.withValues(alpha: 0.65),
                    fontSize: isDone ? 11 : 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
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

    // Match+Press: calcular balance desde live status (orden de pids no importa)
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

    // Nassau (con o sin presiones): sobreescribir con balance en vivo.
    // computeAll solo liquida segmentos CERRADOS; durante la ronda en curso
    // el breakdown quedaría en $0 aunque alguien lleve ventaja.
    // nassauLiveStatus / nassauPressLiveStatus calculan el estado real en cada hoyo.
    final nassauMods = _modsOf(BetModuleType.nassau);
    if (nassauMods.isNotEmpty) {
      double npBal = 0.0;
      for (final mod in nassauMods) {
        if (mod.pressEnabled) {
          // Con presiones: usar nassauPressLiveStatus para frontPresses/backPresses
          final st = BetEngine.nassauPressLiveStatus(round, p1.id, p2.id, mod);
          final isBack   = round.startingNine == StartingNine.back;
          final seg1From = isBack ? 10 : 1;
          final seg1To   = isBack ? 18 : 9;
          if (st.frontPlayed > 0) {
            if (st.front > 0) npBal += st.frontVal;
            if (st.front < 0) npBal -= st.frontVal;
          }
          if (st.backPlayed > 0) {
            if (st.back > 0) npBal += st.backVal;
            if (st.back < 0) npBal -= st.backVal;
          }
          if (st.frontPlayed + st.backPlayed > 0) {
            if (st.total > 0) npBal += st.totalVal;
            if (st.total < 0) npBal -= st.totalVal;
          }
          for (final p in [...st.frontPresses, ...st.backPresses]) {
            final inSeg1   = p.startHole >= seg1From && p.startHole <= seg1To;
            final pressVal = inSeg1 ? mod.nassau.frontPressValue : mod.nassau.backPressValue;
            if (p.score > 0) npBal += pressVal;
            if (p.score < 0) npBal -= pressVal;
          }
        } else {
          // Sin presiones: usar nassauLiveStatus estándar
          final st = BetEngine.nassauLiveStatus(round, p1.id, p2.id, mod);
          if (st.frontPlayed > 0) {
            if (st.front > 0) npBal += st.frontVal;
            if (st.front < 0) npBal -= st.frontVal;
          }
          if (st.backPlayed > 0) {
            if (st.back > 0) npBal += st.backVal;
            if (st.back < 0) npBal -= st.backVal;
          }
          if (st.frontPlayed + st.backPlayed > 0) {
            if (st.total > 0) npBal += st.totalVal;
            if (st.total < 0) npBal -= st.totalVal;
          }
        }
      }
      breakdown[BetModuleType.nassau] = npBal;
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

