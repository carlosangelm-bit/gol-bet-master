// ─────────────────────────────────────────────────────────────────────────────
// SCORECARD SCREEN — Tarjeta de la ronda con 3 vistas: Bruto, Neto, 1v1
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../widgets/player_filter_bar.dart';
import '../results/results_screen.dart';
import '../../widgets/score_shape.dart';
import '../../engines/bet_engine.dart';
import '../../engines/game_engine.dart';
import '../../engines/ledger_engine.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/glass_card.dart';

class ScorecardScreen extends StatefulWidget {
  const ScorecardScreen({super.key});
  @override State<ScorecardScreen> createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    // Cuatro: Resumen —lo que era la pantalla Resultados— más las tres vistas
    // de la tarjeta. La fase 5 las fusiona porque las dos responden la MISMA
    // pregunta, "cómo va la cosa", y tenerlas en dos destinos obligaba a
    // elegir entre ellas sin saber cuál tenía el dato.
    _tabCtrl = TabController(length: 4, vsync: this);
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
            // Resumen primero: es la respuesta corta —quién va ganando y
            // cuánto—. Las tres vistas de detalle vienen después.
            const ResultsScreen(embedded: true),
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
        Text('Resultados', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 18)),
        Text(round.name, style: TextStyle(color: t.sub, fontSize: 12)),
      ]),
      bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.divider)),
    );
  }
}

/// Las pestañas de Resultados, para test. Tarjeta se fusionó aquí en la fase 5.
List<String> resultsTabsForTest() => const ['Resumen', 'Bruto', 'Neto', '1v1'];

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
          Tab(text: 'Resumen'),
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

  String _first(Player p) => p.shortName;

  int _strokes(Player p, CourseHole h) =>
      GameEngine.strokesReceived(round.getHandicap(p.id), h);

  @override
  Widget build(BuildContext context) {
    // Obtener jugadores/equipos para visualización (agrupa Best Ball)
    final players = getDisplayPlayers(round);

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
      final sc = getBestScore(round, p, h.hole);
      int? disp;
      int? rel;
      int putts = 0;
      if (sc.hasScore) {
        putts = sc.putts;
        segPutts += putts;
        if (useNet) {
          if (isBBVirtual(p)) {
            // BB virtual: mejor neto entre los miembros del equipo
            int? bestNet;
            for (final memberId in p.teamMemberIds) {
              final msc = round.getScore(memberId, h.hole);
              if (!msc.hasScore) continue;
              final ctx = GameEngine.contextForHole(round, memberId, h.hole, true);
              if (ctx?.netScore != null) {
                if (bestNet == null || (ctx?.netScore ?? 999) < bestNet) bestNet = ctx?.netScore;
              }
            }
            disp = bestNet ?? sc.grossScore;
            rel  = disp != null ? disp - h.par : null;
            segTotal += disp ?? 0;
          } else {
            final ctx = GameEngine.contextForHole(round, p.id, h.hole, true);
            disp = ctx?.netScore;
            rel  = ctx?.relativeToPar;
            segTotal += ctx?.netScore ?? 0;
          }
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
                  Text(_first(p),
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
      // Para BB virtual: sumar el mejor score bruto/neto por hoyo del equipo
      int total = 0;
      if (isBBVirtual(p)) {
        for (final h in round.course.holes.where((h) => h.hole <= round.totalHoles)) {
          final sc = getBestScore(round, p, h.hole);
          if (!sc.hasScore) continue;
          if (useNet) {
            // Neto: usar el mejor jugador del equipo con sus strokes aplicados
            // Buscamos el miembro con mejor neto
            int? bestNet;
            for (final memberId in p.teamMemberIds) {
              final msc = round.getScore(memberId, h.hole);
              if (!msc.hasScore) continue;
              final ctx = GameEngine.contextForHole(round, memberId, h.hole, true);
              if (ctx?.netScore != null) {
                if (bestNet == null || (ctx?.netScore ?? 999) < bestNet) bestNet = ctx?.netScore;
              }
            }
            total += bestNet ?? sc.grossScore!;
          } else {
            total += sc.grossScore!;
          }
        }
      } else {
        total = useNet
            ? GameEngine.netTotal(round, p.id, true)
            : GameEngine.grossTotal(round, p.id);
      }
      final hasAny = round.course.holes
          .any((h) => getBestScore(round, p, h.hole).hasScore);
      final totalPutts = round.course.holes.fold(0, (sum, h) {
        final sc = getBestScore(round, p, h.hole);
        return sum + (sc.hasScore ? sc.putts : 0);
      });
      final playedHoles = round.course.holes
          .where((h) => getBestScore(round, p, h.hole).hasScore)
          .length;
      // Calcular totales F9/B9 (para BB virtual: sumar mejor score por hoyo)
      int calcSegTotal(int from, int to) {
        if (!isBBVirtual(p)) {
          return useNet
              ? GameEngine.netTotal(round, p.id, true, from: from, to: to)
              : GameEngine.grossTotal(round, p.id, from: from, to: to);
        }
        int seg = 0;
        for (final h in round.course.holes.where((h) => h.hole >= from && h.hole <= to)) {
          final sc = getBestScore(round, p, h.hole);
          if (!sc.hasScore) continue;
          if (useNet) {
            int? bestNet;
            for (final memberId in p.teamMemberIds) {
              final msc = round.getScore(memberId, h.hole);
              if (!msc.hasScore) continue;
              final ctx = GameEngine.contextForHole(round, memberId, h.hole, true);
              if (ctx?.netScore != null) {
                if (bestNet == null || (ctx?.netScore ?? 999) < bestNet) bestNet = ctx?.netScore;
              }
            }
            seg += bestNet ?? sc.grossScore!;
          } else {
            seg += sc.grossScore!;
          }
        }
        return seg;
      }
      final f9total = calcSegTotal(1, 9);
      final b9total = calcSegTotal(10, 18);
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
                    // Para equipos virtuales, usar nombre completo
                    final nickname = d.player.isVirtual ? d.player.name : d.player.shortName;
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                playerOrTeamName(
                                  d.player,
                                  round,
                                  style: TextStyle(color: cSub, fontSize: 13, fontWeight: FontWeight.w700),
                                  showTeamIcon: false,
                                ),
                                if (teamMembersFootnote(d.player, round, style: TextStyle(color: cSub.withValues(alpha: 0.6), fontSize: 9)) != null)
                                  teamMembersFootnote(d.player, round, style: TextStyle(color: cSub.withValues(alpha: 0.6), fontSize: 9))!,
                              ],
                            ),
                          ),
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
                  // Virtual (Scramble o BB): nombre completo del equipo
                  // Individual: primer nombre
                  final nickname = d.player.isVirtual
                      ? d.player.name
                      : d.player.shortName;
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
                            // Apodo (primer nombre) del jugador o nombre del equipo
                            Text(nickname,
                                style: TextStyle(
                                    color: cText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis),
                            // Miembros del equipo (BB o Scramble virtual)
                            if (d.player.isVirtual && d.player.teamMemberIds.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                d.player.teamMemberIds
                                    .map((id) => round.players.firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id)))
                                    .map((p) => p.shortName)
                                    .join(', '),
                                style: TextStyle(color: cSub, fontSize: 7),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  playerOrTeamName(
                                    d.player,
                                    round,
                                    style: TextStyle(
                                        color: cText,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                    showTeamIcon: false,
                                  ),
                                  if (teamMembersFootnote(d.player, round, style: TextStyle(color: cSub, fontSize: 8)) != null)
                                    teamMembersFootnote(d.player, round, style: TextStyle(color: cSub, fontSize: 8))!,
                                ],
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

    // ── El score se codifica por FORMA, no por color ────────────────────────
    //
    // La convención de la tarjeta de papel:
    //   ◎ eagle o mejor · ○ birdie · par sin adorno · □ bogey · ▣ doble o peor
    //
    // Antes eagle y doble bogey se pintaban con RELLENO sólido y texto blanco,
    // y birdie y bogey con fondo teñido. Eso obligaba al color a llevar la
    // información: quitarle el rojo al bogey lo dejaba indistinguible de un par.
    //
    // Con la forma cargando el significado el trazo solo TIÑE, y el rojo
    // saturado queda libre para el dinero. Consecuencia comprobable: la tabla
    // se lee en escala de grises.
    final forma = scoreShapeFor(score!, par);
    final tinte = forma.esCirculo
        ? cUnder
        : forma.esCuadro
            ? cOver
            : cSub;
    const sz = 26.0;

    Widget trazo(double lado, double grosor) => Container(
          width: lado,
          height: lado,
          decoration: BoxDecoration(
            border: Border.all(color: tinte, width: grosor),
            borderRadius: BorderRadius.circular(forma.esCirculo ? lado : 4),
          ),
        );

    final cell = SizedBox(
      // El par ocupa lo mismo aunque no lleve adorno: sin eso la columna baila
      // entre hoyos y la tabla deja de leerse en vertical.
      width: sz, height: sz,
      child: Stack(alignment: Alignment.center, children: [
        if (forma != ScoreShape.none) trazo(sz, 1.5),
        // La segunda capa es lo que separa eagle de birdie y doble de bogey sin
        // recurrir a otro color ni a un relleno.
        if (forma.esDoble) trazo(sz - 6, 1.1),
        Text('$score',
            style: TextStyle(
                color: tinte,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
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
  // 1. _myPlayerId elegido MANUALMENTE por el usuario (máxima prioridad — el usuario sabe mejor que nadie)
  // 2. Jugador con linkedUserId == uid autenticado
  // 3. Jugador con linkedUserId == ownerUid de la ronda
  // 4. null → no se puede determinar automáticamente
  Player? _resolveMyPlayer(Round round) {
    // Prioridad 1: jugador elegido manualmente por el usuario con el picker
    // SIEMPRE prevalece sobre la detección automática — es la selección explícita del usuario
    if (_myPlayerId != null) {
      final manual = round.players.where((p) => p.id == _myPlayerId).firstOrNull;
      if (manual != null) return manual;
      // Si el ID ya no existe en la ronda (caso raro), limpiar y continuar
      _myPlayerId = null;
    }

    final uid = AuthService.uid;

    // Prioridad 2: linkedUserId == uid actual
    if (uid != null) {
      final linked = round.players
          .where((p) => p.linkedUserId == uid)
          .firstOrNull;
      if (linked != null) return linked;
    }

    // Prioridad 3: ownerUid de la ronda
    final ownerUid = round.ownerUid;
    if (ownerUid != null) {
      final owner = round.players
          .where((p) => p.linkedUserId == ownerUid)
          .firstOrNull;
      if (owner != null) return owner;
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
            : m.effectivePids(g.playerIds);
        if (!pids.contains(p1.id) || !pids.contains(p2.id)) continue;

        if (m.type == BetModuleType.skins) {
          skinsMod = m;
          foundSkins = true;
        } else if (m.type == BetModuleType.nassau) {
          // Usar hoyos ganados (mismo indicador que el badge visual)
          final nst = BetEngine.nassauLiveStatus(round, p1.id, p2.id, m);
          matchStatus = nst.holesWonP1 - nst.holesWonP2;
        } else if (m.type == BetModuleType.matchAutoPress) {
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
    // La vista 1v1 es de PERSONAS: los duelos salen de _buildPairs, que ya
    // descarta compañeros de lado. Con los virtuales de equipo el umbral de
    // "al menos 2" se cumplía por razones equivocadas.
    if (round.realPlayers.length < 2) {
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

    // Marcador real de los formatos por equipos. Va antes de los cruces y
    // FUERA de los filtros: los filtros operan sobre duelos individuales, y el
    // marcador del equipo no es uno de ellos.
    final lowHighMods = [
      for (final g in round.betGroups)
        for (final m in g.modules)
          if (m.type == BetModuleType.nassauLowHigh && m.hasTeamSides) m,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(children: [
        ...lowHighMods.map((m) => LowHighTeamCard(round: round, mod: m, t: t)),

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
        //
        // Sin cruces porque la ronda no tiene apuestas individuales es un caso
        // distinto de "el filtro no encontró nada", y merece otra explicación:
        // aquí no hay nada que buscar, el resultado real ya está arriba.
        if (allPairs.isEmpty && tieneApuestaPorEquipos(round))
          // solid y no vidrio real: ya hay un BackdropFilter en pantalla (la
          // tarjeta de equipo) y el presupuesto de desenfoques es ajustado.
          GlassCard.solid(
            t: t,
            padding: const EdgeInsets.all(16),
            radius: 18,
            child: Column(children: [
              Icon(Icons.groups_2_outlined, color: t.sub, size: 28),
              const SizedBox(height: 8),
              Text('Esta ronda solo tiene apuestas por equipos',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: t.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(
                'No hay duelos individuales que mostrar. El desglose de quién '
                'le paga a quién está en Resultados.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.sub, fontSize: 11, height: 1.35),
              ),
            ]),
          )
        else if (finalPairs.isEmpty)
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

            // ── Garantizar que myPlayer siempre aparezca como p1 (izquierda) ──
            // Si el jugador propio está en la posición p2, intercambiar el par
            // para que la tarjeta lo muestre siempre a la izquierda como base.
            final bool swapNeeded = myPlayer != null &&
                pair.$2.id == myPlayer.id &&
                pair.$1.id != myPlayer.id;
            final effP1 = swapNeeded ? pair.$2 : pair.$1;
            final effP2 = swapNeeded ? pair.$1 : pair.$2;

            return Padding(
              padding: EdgeInsets.only(bottom: i < finalPairs.length - 1 ? 12 : 0),
              child: _MatchDuelCard(
                round: round, p1: effP1, p2: effP2, t: t,
                expanded: finalPairs.length == 1,
                myPlayerId: myPlayer?.id,
                onApplyCarry: (ctx, factor, nassauMods, matchMods) =>
                    _applyCarry(ctx, effP1.id, effP2.id, factor, nassauMods, matchMods),
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
  ///  2. Módulos 1v1 (nassau / matchAutoPress) con participantIds de 2
  ///     dentro de grupos multi-jugador → cada par de participantIds = un duelo.
  ///  3. BetGroups con más de 2 jugadores → round-robin entre todos ellos.
  ///  4. Fallback: round-robin entre todos los displayPlayers de la ronda.
  List<(Player, Player)> _buildPairs(Round round) {
    final seen  = <String>{};
    final pairs = <(Player, Player)>[];

    // Compañeros de un mismo lado: no son rivales, así que no se dibujan como
    // duelo. Se filtra DENTRO de addPair porque las cuatro estrategias de la
    // cascada pasan por aquí; hacerlo en cada rama dejaría alguna sin cubrir.
    final companeros = companerosDeLado(round);

    // Con un duelo por equipos en juego, un cruce 1v1 sin apuesta individual
    // detrás muestra un marcador de hoyos que nadie pactó. El filtro se activa
    // SOLO cuando hay equipos: sin ellos —incluida una ronda sin apuestas— la
    // pestaña se comporta como siempre.
    final hayEquipos = tieneApuestaPorEquipos(round);

    void addPair(String id1, String id2) {
      // Se usa pairKey para las dos cosas a propósito. La clave local era
      // 'a|b' y la del filtro es 'a__b': con formatos distintos el contains
      // no habría casado nunca y el filtro no haría nada en silencio.
      final key = BetModuleInstance.pairKey(id1, id2);
      if (companeros.contains(key)) return;
      if (hayEquipos && !tieneApuestaIndividual(round, id1, id2)) return;
      if (seen.contains(key)) return;
      try {
        final p1 = round.players.firstWhere((p) => p.id == id1);
        final p2 = round.players.firstWhere((p) => p.id == id2);
        seen.add(key);
        pairs.add((p1, p2));
      } catch (_) {}
    }

    void roundRobinFromIds(List<String> ids) {
      for (int i = 0; i < ids.length; i++) {
        for (int j = i + 1; j < ids.length; j++) {
          addPair(ids[i], ids[j]);
        }
      }
    }

    // ── Prioridad 1: grupos con exactamente 2 jugadores ──────────────────
    for (final g in round.betGroups) {
      if (g.playerIds.length == 2) {
        addPair(g.playerIds[0], g.playerIds[1]);
      }
    }

    // ── Prioridad 2: módulos nassau/match con participantIds de exactamente 2 ─
    for (final g in round.betGroups) {
      for (final m in g.modules) {
        if (m.type == BetModuleType.nassau ||
            m.type == BetModuleType.matchAutoPress) {
          final pids = m.effectivePids(g.playerIds);
          if (pids.length == 2) {
            addPair(pids[0], pids[1]);
          }
        }
      }
    }

    // ── Prioridad 3: grupos con más de 2 jugadores → round-robin ─────────
    for (final g in round.betGroups) {
      if (g.playerIds.length > 2) {
        roundRobinFromIds(g.playerIds);
      }
    }

    // ── Prioridad 4: fallback round-robin con todos los displayPlayers ────
    final displayPlayers = getDisplayPlayers(round);
    if (pairs.isEmpty && displayPlayers.length >= 2) {
      roundRobinFromIds(displayPlayers.map((p) => p.id).toList());
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
          if (m.containsPair(p1Id, p2Id)) {
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
      if (!g.playerIds.contains(p1Id) || !g.playerIds.contains(p2Id)) continue;
      mods.addAll(g.modules.where((m) {
        if (m.type != type) return false;
        return m.containsPair(p1Id, p2Id);
      }));
    }
    return mods;
  }
}

// Helper: devuelve todos los participantes reales de un módulo en la ronda
List<String> _modGroupPids(Round round, BetModuleInstance mod) {
  for (final g in round.betGroups) {
    for (final m in g.modules) {
      if (m.id == mod.id) return m.effectivePids(g.playerIds);
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

  @override
  Widget build(BuildContext context) {
    final chips = [
      (_DuelFilter.todos,      Icons.apps_rounded,            Colors.white70,             'Todos'),
      (_DuelFilter.ganados,    Icons.trending_up_rounded,     const Color(0xFF35C759),    'Ganados'),
      (_DuelFilter.acumulados, Icons.local_fire_department,   const Color(0xFFFFCC00),    'Acumulados'),
      (_DuelFilter.perdidos,   Icons.trending_down_rounded,   const Color(0xFFFF453A),    'Perdidos'),
    ];

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      // EL selector de jugador, compartido con la pestaña Duelos de Apuestas.
      // Antes vivía aquí dentro, mezclado con los chips de estado.
      Expanded(
        child: PlayerFilterBar(
          onlyMine: onlyMine,
          myPlayer: myPlayer,
          allPlayers: allPlayers,
          t: t,
          onToggleMine: onToggleMine,
          onPickPlayer: onPickPlayer,
        ),
      ),

      const SizedBox(width: 6),
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).viewPadding.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad > 0 ? bottomPad : 20),
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
                  Navigator.pop(ctx);
                },
              )),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const activeGrad = [Color(0xFF1F8F3A), Color(0xFF0D5020)];
    final myName = myPlayer?.shortName;
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
      if (!g.playerIds.contains(p1Id) || !g.playerIds.contains(p2Id)) continue;
      mods.addAll(g.modules.where((m) {
        if (m.type != type) return false;
        return m.containsPair(p1Id, p2Id);
      }));
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
    final oyesModules      = _findModules(BetModuleType.oyeses);

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
              oyesModules:       oyesModules,
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
        // opaque: una fila o tarjeta de selección se toca donde caiga, no solo
        // sobre sus letras. Sin esto el GestureDetector responde únicamente donde
        // pintan los hijos, así que el hueco de la fila y el anillo alrededor de
        // un icono quedan muertos. Es el fallo que hacía que el + de la lista de
        // jugadores no respondiera.
        behavior: HitTestBehavior.opaque,
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
  final List<BetModuleInstance> oyesModules;
  const _MatchStatusCard({
    required this.round, required this.p1, required this.p2, required this.t,
    required this.skinsModules, required this.nassauModules,
    this.matchPressModules = const [],
    this.oyesModules       = const [],
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
    if (oyesModules.isNotEmpty) {
      return _buildOyesesCard(context);
    }
    return _buildMatchCard(context);
  }

  // ── Badge principal para Nassau (F9 / B9 / Total) ─────────────────────────
  Widget _buildNassauCard(BuildContext context) {
    final mod  = nassauModules.first;
    final st   = BetEngine.nassauLiveStatus(round, p1.id, p2.id, mod);
    final n1   = p1.shortName;
    final n2   = p2.shortName;
    final lastH       = GameEngine.lastCompletedHole(round, [p1.id, p2.id]);
    final playedCount = st.frontPlayed + st.backPlayed;

    // ── Hoyos ganados por cada jugador (indicador visual principal) ───────────
    // Mismo concepto que skins: cuántos hoyos individuales ha ganado cada uno.
    final holesP1 = st.holesWonP1;
    final holesP2 = st.holesWonP2;
    final lead    = holesP1 - holesP2;  // positivo = p1 va arriba

    // ── Estado de cada segmento (para el diffLabel) ───────────────────────────
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

    // ── Color y etiqueta basados en hoyos ganados (misma lógica que skins) ────
    final Color accentColor;
    final List<Color> gradColors;
    final String stateWord;
    final String diffLabel;

    if (playedCount == 0) {
      accentColor = const Color(0xFF607D8B);
      gradColors  = const [Color(0xFF37474F), Color(0xFF1C1C1E)];
      stateWord   = 'NASSAU';
      diffLabel   = 'Esperando scores';
    } else if (lead == 0) {
      accentColor = const Color(0xFF1565C0);
      gradColors  = const [Color(0xFF1A3A6B), Color(0xFF0D1F3C)];
      stateWord   = 'EMPATADO';
      diffLabel   = '$fLabel  ·  $bLabel';
    } else if (lead > 0) {
      accentColor = const Color(0xFF35C759);
      gradColors  = const [Color(0xFF1F8F3A), Color(0xFF0E3D1B)];
      stateWord   = 'GANANDO';
      diffLabel   = '$n1 +$lead  ·  $fLabel  ·  $bLabel';
    } else {
      accentColor = const Color(0xFFFF453A);
      gradColors  = const [Color(0xFF7A1E1E), Color(0xFF2A0E0E)];
      stateWord   = 'PERDIENDO';
      diffLabel   = '$n2 +${lead.abs()}  ·  $fLabel  ·  $bLabel';
    }

    // subLabel: presiones activas
    String? subLabel;
    final totalPresses = st.presses.length;
    if (totalPresses > 0) {
      subLabel = '$totalPresses press${totalPresses > 1 ? 'iones' : 'ión'} activa${totalPresses > 1 ? 's' : ''}';
    }

    return _PremiumResultBadge(
      p1: p1, p2: p2, t: t,
      stateWord: stateWord,
      score1: holesP1, score2: holesP2,
      scoreLabel: 'hoyos',
      diffLabel: diffLabel,
      accentColor: accentColor,
      gradColors: gradColors,
      playedCount: playedCount,
      lastHole: lastH,
      tieCount: null,
      skinsInPot: null,
      round: round,
      subLabel: subLabel,
    );
  }

  // ── Badge principal para Oyeses ───────────────────────────────────────────
  Widget _buildOyesesCard(BuildContext context) {
    final mod  = oyesModules.first;
    final o    = mod.oyeses;
    final n1   = p1.shortName;
    final n2   = p2.shortName;

    // Calcular oyeses ganados por cada jugador (1° en ranking de cada hoyo)
    final par3Holes = round.course.holes.where((h) => h.isPar3).toList();
    final eligible  = o.eligibleHoles.isNotEmpty
        ? par3Holes.where((h) => o.eligibleHoles.contains(h.hole)).toList()
        : par3Holes;
    final totalEligible = eligible.length;

    int oyes1 = 0, oyes2 = 0, holesPlayed = 0;
    int winsP1vsP2 = 0, winsP2vsP1 = 0;
    bool zapatoFired = false;

    for (final ch in eligible) {
      final ranking = round.getOyese(ch.hole);
      if (ranking == null || ranking.ranking.isEmpty) continue;
      final ordered = ranking.ranking.where((pid) => [p1.id, p2.id].contains(pid)).toList();
      if (ordered.length < 2) continue;
      holesPlayed++;
      if (ordered[0] == p1.id) { oyes1++; winsP1vsP2++; }
      else { oyes2++; winsP2vsP1++; }
    }

    // Verificar si el zapato se disparó
    if (o.zapatoEnabled && holesPlayed == totalEligible && totalEligible > 0) {
      final enoughHoles = o.zapatoRequires18 ? (totalEligible >= 3) : true;
      if (enoughHoles) {
        if (winsP1vsP2 == holesPlayed || winsP2vsP1 == holesPlayed) {
          zapatoFired = true;
        }
      }
    }

    final lead  = oyes1 - oyes2;
    final Color accentColor;
    final List<Color> gradColors;
    final String stateWord;
    final String diffLabel;

    if (holesPlayed == 0) {
      accentColor = const Color(0xFF1565C0);
      gradColors  = const [Color(0xFF1A3A6B), Color(0xFF0D1F3C)];
      stateWord   = 'EN JUEGO';
      diffLabel   = 'Esperando par-3s';
    } else if (lead == 0) {
      accentColor = const Color(0xFF1565C0);
      gradColors  = const [Color(0xFF1A3A6B), Color(0xFF0D1F3C)];
      stateWord   = 'EMPATADO';
      diffLabel   = '$oyes1 oyés c/u';
    } else if (lead > 0) {
      accentColor = const Color(0xFF35C759);
      gradColors  = const [Color(0xFF1F8F3A), Color(0xFF0E3D1B)];
      stateWord   = 'GANANDO';
      diffLabel   = '$n1 +$lead oyés${zapatoFired ? '  👟' : ''}';
    } else {
      accentColor = const Color(0xFFFF453A);
      gradColors  = const [Color(0xFF7A1E1E), Color(0xFF2A0E0E)];
      stateWord   = 'PERDIENDO';
      diffLabel   = '$n2 +${lead.abs()} oyés${zapatoFired ? '  👟' : ''}';
    }

    // Sub-label: progreso + zapato pendiente
    String? subLabel;
    final remaining = totalEligible - holesPlayed;
    if (o.zapatoEnabled && !zapatoFired && holesPlayed > 0) {
      final ahead = lead > 0 ? n1 : (lead < 0 ? n2 : null);
      if (ahead != null && remaining > 0) {
        subLabel = '👟 Zapato: $ahead lidera · $remaining par-3${remaining > 1 ? 's' : ''} restante${remaining > 1 ? 's' : ''}';
      }
    }
    if (zapatoFired) {
      final winner = lead > 0 ? n1 : n2;
      final zapatoAmt = o.zapatoValue > 0 ? o.zapatoValue : (totalEligible * o.value);
      subLabel = '👟 Zapato: $winner ganó todos los oyeses (+\$${zapatoAmt.toStringAsFixed(0)})';
    }

    final lastPar3 = eligible.lastWhere(
      (ch) {
        final r = round.getOyese(ch.hole);
        return r != null && r.ranking.isNotEmpty;
      },
      orElse: () => eligible.isNotEmpty ? eligible.first : round.course.holes.first,
    ).hole;

    return _PremiumResultBadge(
      p1: p1, p2: p2, t: t,
      stateWord: stateWord,
      score1: oyes1, score2: oyes2,
      scoreLabel: 'oyeses',
      diffLabel: diffLabel,
      accentColor: accentColor,
      gradColors: gradColors,
      playedCount: holesPlayed,
      lastHole: holesPlayed > 0 ? lastPar3 : 1,
      tieCount: null,
      skinsInPot: null,
      round: round,
      subLabel: subLabel,
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

    final n1 = p1.shortName;
    final n2 = p2.shortName;
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

    // ── Sub-label: métricas deportivas de presiones (sin dinero — el chip ────────
    // lo toma siempre de LedgerEngine.breakdownBetween para consistencia)
    String? subLabel;

    if (matchPressModules.isNotEmpty) {
      final mod         = matchPressModules.first;
      final presses     = BetEngine.matchAutoPressLive(round, p1.id, p2.id, mod);
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
      // Nassau con presiones: sub-label deportivo (F9/B9 status)
      final mod  = nassauModules.first;
      final st   = BetEngine.nassauLiveStatus(round, p1.id, p2.id, mod);
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

    final sn1 = p1.shortName;
    final sn2 = p2.shortName;
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

  const _PremiumResultBadge({
    required this.p1, required this.p2, required this.t,
    required this.stateWord, required this.score1, required this.score2,
    required this.scoreLabel, required this.diffLabel,
    required this.accentColor, required this.gradColors,
    required this.playedCount, required this.lastHole,
    required this.round,
    this.tieCount, this.skinsInPot,
    this.subLabel,
  });

  @override
  Widget build(BuildContext context) {
    final n1 = p1.shortName;
    final n2 = p2.shortName;
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
                    stateColor: accentColor),
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
  const _NetBalanceChip({required this.round, required this.p1,
      required this.p2, required this.t, required this.stateColor});

  @override
  Widget build(BuildContext context) {
    context.watch<RoundProvider>(); // reconstruir al cambiar scores

    // Fuente única de dinero: LedgerEngine (BetEngine.computeAll)
    // Cubre todos los módulos: match, press, nassau, skins, etc.
    final bd   = LedgerEngine.breakdownBetween(round, p1.id, p2.id);
    final bal1 = bd.values.fold(0.0, (sum, v) => sum + v);

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
    required this.label1, required this.label2,
    required this.highlightP1, required this.highlightP2,
    required this.stateColor, required this.t,
  }) : score1 = null, score2 = null;
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

    final n1 = p1.shortName;
    final n2 = p2.shortName;

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
              color: skins1 > skins2 ? t.primary : t.sub,
              fontSize: 11, fontWeight: FontWeight.w700)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('·', style: TextStyle(color: t.divider, fontSize: 14)),
        ),
        Text('$skins2 $n2',
            style: TextStyle(
              color: skins2 > skins1 ? t.primary : t.sub,
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
    final n1 = p1.shortName;
    final n2 = p2.shortName;

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

    // ── helper: token redondo de presión ────────────────────────────────────
    Widget pressChip(NassauPress press, double pressVal) {
      // press.score está normalizado en perspectiva de p1:
      // positivo = p1 arriba (p1 gana la press), negativo = p2 arriba (p2 gana).
      final rawScore = press.score;

      // Misma paleta de gradientes que _NassauSegment
      final List<Color> grad;
      final Color baseColor;
      final String bigLabel;
      final String subLabel;

      if (rawScore == 0) {
        grad      = const [Color(0xFF1565C0), Color(0xFF0D47A1)];
        baseColor = const Color(0xFF1976D2);
        bigLabel  = 'AS';
        subLabel  = '';
      } else if (rawScore > 0) {
        grad      = const [Color(0xFF388E3C), Color(0xFF1B5E20)];
        baseColor = const Color(0xFF2E7D32);
        bigLabel  = '+${rawScore.abs()}';
        subLabel  = n1;
      } else {
        grad      = const [Color(0xFFD32F2F), Color(0xFF7F0000)];
        baseColor = const Color(0xFFC62828);
        bigLabel  = '+${rawScore.abs()}';
        subLabel  = n2;
      }

      return Container(
        width: 72,
        height: 90,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: grad,
          ),
          border: Border.all(
            color: press.isOpen
                ? Colors.white.withValues(alpha: 0.45)
                : baseColor.withValues(alpha: 0.45),
            width: press.isOpen ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: grad[0].withValues(alpha: 0.30),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ── Etiqueta del hoyo ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: press.isOpen ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'H${press.startHole}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.90),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),

            // ── Número grande + nombre ──────────────────────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bigLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  subLabel.isNotEmpty ? subLabel : ' ',
                  style: TextStyle(
                    color: Colors.white.withValues(
                        alpha: subLabel.isNotEmpty ? 0.70 : 0.0),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),

            // ── Pie: valor + EN JUEGO ───────────────────────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: press.isOpen
                      ? Text(
                          'EN JUEGO',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.90),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        )
                      : Text(
                          '\$${pressVal.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
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
              // ── De cuál de los Nassau estamos hablando ────────────────────
              //
              // Un duelo puede tener varios módulos del mismo tipo, y en la
              // ronda del 28 de agosto tenía TRES: uno pactado entre esos dos y
              // dos con alcance abierto, que liquidan entre los cuatro. Los tres
              // paneles salían idénticos —mismo nombre, mismo importe— y no
              // había forma de saber cuál era cuál.
              //
              // Los paneles no mentían: hay tres módulos y cada uno mueve
              // dinero. Lo que faltaba era decir cuál es cuál.
              () {
                // La insignia sale del catálogo del alcance, no de un literal:
                // la hoja que lo elige y el panel que lo enseña tienen que decir
                // la misma palabra o vuelven a poder separarse.
                final abierto = mod.effectiveScope.isEveryone;
                final color = abierto ? t.scoreOver : t.primary;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: abierto ? 0.18 : 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(mod.effectiveScope.kind.insignia,
                        style: TextStyle(
                            color: color,
                            fontSize: 8,
                            fontWeight: FontWeight.w800)),
                  ),
                );
              }(),
              if (carryActive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.15),
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

          // ── Presiones: tokens visuales por segmento ──────────────────────
          if (totalPressCount > 0) ...[
            Divider(color: t.divider.withValues(alpha: 0.5), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (frontPresses.isNotEmpty) ...[
                    Text('PRESIONES  F9',
                        style: TextStyle(color: t.sub, fontSize: 9,
                            fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: frontPresses
                          .map((p) => pressChip(p, frontPressVal))
                          .toList(),
                    ),
                  ],
                  if (backPresses.isNotEmpty) ...[
                    if (frontPresses.isNotEmpty) const SizedBox(height: 12),
                    Text('PRESIONES  B9',
                        style: TextStyle(color: t.sub, fontSize: 9,
                            fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: backPresses
                          .map((p) => pressChip(p, backPressVal))
                          .toList(),
                    ),
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

    // Altura fija para que las 3 cajas sean siempre iguales
    return SizedBox(
      height: 90,
      child: Container(
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
              color: grad[0].withValues(alpha: 0.28),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ── Etiqueta del segmento (F9 / B9 / 18) ──────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
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
            ),

            // ── Centro: número grande + nombre (altura fija) ───────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(height: 2),
                // Siempre reserva espacio para el nombre (visible o invisible)
                Text(
                  playerName.isNotEmpty ? playerName : ' ',
                  style: TextStyle(
                    color: Colors.white.withValues(
                        alpha: playerName.isNotEmpty ? 0.70 : 0.0),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),

            // ── Pie: progreso + valor (altura fija) ───────────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
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
    final n1  = p1.shortName;
    final n2  = p2.shortName;

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

    final n1 = widget.p1.shortName;
    final n2 = widget.p2.shortName;

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
              color: t.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.accent.withValues(alpha: 0.4)),
            ),
            child: Text('×2', style: TextStyle(color: t.accent, fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CARRY ACTIVO', style: TextStyle(color: t.accent, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.8)),
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
    // Delegamos al helper centralizado del engine (prioridad: manual → HCP fallback).
    // manual[p1][p2] ya ES la diferencia de strokes:
    //   > 0 → p1 recibe esos strokes de p2  → p1 es receptor
    //   < 0 → p1 da esos strokes a p2       → p2 es receptor
    //   = 0 → acuerdo explícito: sin ventaja entre este par (NO se usa HCP)
    final hcp1 = round.getHandicap(p1.id);
    final hcp2 = round.getHandicap(p2.id);

    // Usar el mismo helper centralizado del engine para consistencia total.
    // Prioridad: manual[p1][p2] → manual[p2][p1] invertido → HCP diff
    final recv = BetEngine.strokesP1ReceivesFromP2(round, p1.id, p2.id);
    // ¿Hay un acuerdo explícito (incluyendo acuerdo de 0 = parejo)?
    final hasExplicitHoleByHole = BetEngine.hasExplicitAgreement(round, p1.id, p2.id);

    final Player basePlayer;
    final Player receiverPlayer;
    final double hcpBase;
    final double hcpReceiver;

    // ── El HCPj que se enseña es el DEL JUGADOR ────────────────────────────
    //
    // Aquí decía `hcpReceiver = hcpBase + recv`: el handicap del OTRO más los
    // golpes recibidos, presentado con la etiqueta "HCPj" del receptor. En la
    // ronda del 28 de agosto eso hacía que la tarjeta anunciara HCPj 19 para
    // Dylan, cuyo handicap real es 0, y HCPj 20 para AAM, que tiene 17.
    //
    // Un número derivado del emparejamiento vendido como atributo de la persona
    // es la forma exacta de cifra plausible que no se puede verificar de un
    // vistazo. Los golpes ya se dicen aparte —"recibe 6 · F9 3 · B9 3"— así que
    // no hacía falta esconderlos dentro del handicap.
    if (recv > 0) {
      // p1 recibe de p2 → p2=base, p1=receptor
      basePlayer     = p2;
      receiverPlayer = p1;
      hcpBase        = hcp2;
      hcpReceiver    = hcp1;
    } else if (recv < 0) {
      // p1 da a p2 → p1=base, p2=receptor
      basePlayer     = p1;
      receiverPlayer = p2;
      hcpBase        = hcp1;
      hcpReceiver    = hcp2;
    } else if (hasExplicitHoleByHole) {
      // Acuerdo explícito de parejo (0 strokes) — la leyenda debe mostrar
      // 'Sin ventaja' y NO calcular diff por HCP. Igualamos hcpReceiver = hcpBase.
      basePlayer     = p1;
      receiverPlayer = p2;
      hcpBase        = hcp1;
      hcpReceiver    = hcp2;
    } else {
      // Sin acuerdo — fallback: diferencia de HCP del campo
      basePlayer     = p1;
      receiverPlayer = p2;
      hcpBase        = hcp1;
      hcpReceiver    = hcp2;
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
      // Los GOLPES, no la resta de handicaps. Con una ventaja pactada a mano los
      // dos números no coinciden —Dylan tiene handicap 0 y recibe 6— y el que
      // vale es el que el motor reparte.
      _handicapLegend(basePlayer, receiverPlayer, recv.abs().round(),
          hasExplicitHoleByHole, allHoles, t, round.startingNine, round),
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
            Text(basePlayer.shortName,
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
          Text(receiverPlayer.shortName,
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
        // Usar los hoyos REALES del curso (no un rango fijo 1-18/10-18+1-9).
        // Esto soporta campos de 9 hoyos numerados 1-9 jugados como B9.
        final holeMap = { for (final ch in round.course.holes) ch.hole: ch };
        final List<int> order;
        if (round.startingNine == StartingNine.back) {
          final b9 = round.course.holes.where((c) => c.hole >= 10).map((c) => c.hole).toList()..sort();
          final f9 = round.course.holes.where((c) => c.hole <= 9).map((c) => c.hole).toList()..sort();
          order = [...b9, ...f9];
        } else {
          order = round.course.holes.map((c) => c.hole).toList()..sort();
        }

        // Pre-calcular hoyos del CURSO divididos en F9/B9 (no jugados, sino todos
        // los hoyos del curso) para distribución correcta de SI en rondas parciales.
        // CORRECCIÓN: usar courseHolesInSameNine (no playedHolesInSameNine) para que
        // los strokes se distribuyan sobre los 9 hoyos completos aunque la ronda
        // esté en progreso (evita concentrar todas las ventajas en el hoyo 1).
        final (courseF9ui, courseB9ui) =
            BetEngine.courseHolesF9B9Public(allHoles, round.startingNine);

        // Diferencia oficial de strokes (del pairSliding o diff de HCP)
        final recvOfficial = BetEngine.strokesP1ReceivesFromP2(round, p1.id, p2.id);
        final recvAbsOfficial = recvOfficial.abs().round();
        // ¿Hay acuerdo explícito para este par (incluyendo acuerdo de 0 = parejo)?
        final hasExplicit = BetEngine.hasExplicitAgreement(round, p1.id, p2.id);

        return order.map((hNum) {
          final ch = holeMap[hNum];
          if (ch == null) return const SizedBox.shrink();
          final sBase     = round.getScore(basePlayer.id,     ch.hole);
          final sReceiver = round.getScore(receiverPlayer.id, ch.hole);
          if (!sBase.hasScore && !sReceiver.hasScore) return const SizedBox.shrink();

          // Strokes usando el MISMO método que el engine (skins/nassau/medal):
          // - Con pairSliding > 0: strokesReceivedFromOfficial18Sliding
          //   → distribución proporcional sobre TODOS los hoyos del curso
          // - Acuerdo explícito de 0 (parejo manual): 0 strokes — NO usar HCP fallback.
          //   Sin esta comprobación, un acuerdo "parejo" mostraría la diferencia de HCP.
          // - Sin acuerdo alguno: strokesReceivedVs (diferencia de HCP del campo)
          final courseHolesForUI = courseF9ui.any((h) => h.hole == ch.hole)
              ? courseF9ui : courseB9ui;
          final strokesHere = recvAbsOfficial > 0
              ? GameEngine.strokesReceivedFromOfficial18Sliding(
                  diff18:              recvAbsOfficial,
                  ch:                  ch,
                  courseHolesInSameNine: courseHolesForUI,
                  startingNine:        round.startingNine,
                  isNineHolesStartingNine: courseF9ui.any((h) => h.hole == ch.hole)
                      ? (round.startingNine == StartingNine.front)
                      : (round.startingNine == StartingNine.back),
                )
              : hasExplicit
                  ? 0  // acuerdo explícito de parejo → siempre 0 strokes
                  : GameEngine.strokesReceivedVs(
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
          if (grossBase < netReceiver) {
            baseWins = true;
          } else if (grossBase > netReceiver)  baseWins = false;
          // null = empate
        }

        final skinResult = (hasSkins)
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
    int diff, bool pactado,
    List<CourseHole> allHoles, GolfTheme t,
    StartingNine startingNine, Round round,
  ) {
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
          Text(
              pactado
                  ? 'Sin ventaja — acordado entre ustedes'
                  : 'Sin ventaja — handicaps iguales',
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
              text: receiver.shortName,
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
              text: ' de ${base.shortName}',
              style: TextStyle(color: t.sub, fontSize: 11),
            ),
          ])),
          const SizedBox(height: 2),
          Text(
            'F9: $frontStrokes stroke${frontStrokes != 1 ? 's' : ''} · B9: $backStrokes stroke${backStrokes != 1 ? 's' : ''} · $startLabel',
            style: TextStyle(color: t.sub, fontSize: 10),
          ),
          // Y dónde NO se usa esta ventaja, que es la mitad que faltaba.
          if (_poteConAncla(round) case final pote?) ...[
            const SizedBox(height: 3),
            Text(
                'En ${pote.modulos} se juega en pote: la ventaja se cuenta '
                'contra ${pote.ancla}, no entre ustedes dos.',
                style: TextStyle(
                    color: t.scoreOver, fontSize: 10, height: 1.25)),
          ],
        ])),
        // Chips HCP — el handicap DE CADA UNO, tal como está en la ronda.
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _hcpChip(base.shortName, round.getHandicap(base.id), t),
          const SizedBox(height: 3),
          _hcpChip(receiver.shortName, round.getHandicap(receiver.id), t,
              isHigher: true),
        ]),
      ]),
    );
  }

  /// Si algún módulo de la ronda liquida en POTE con más de dos jugadores.
  ///
  /// ── Por qué esto se tiene que decir ───────────────────────────────────────
  ///
  /// Con más de dos, un pote con ventaja elige un ANCLA y calcula el neto de
  /// todos contra ella. Así que la ventaja pactada entre dos que no son el ancla
  /// no toca el dinero de ese módulo — verificado en la ronda del 28 de agosto:
  /// cambiar el pacto AAM–KAWA de 4 a 9 daba balances idénticos.
  ///
  /// Con handicaps del directorio no se nota, porque salen de diferencias
  /// coherentes en todo el grupo y el ancla las reproduce todas. Con ventajas
  /// puestas a mano sí: la tarjeta anuncia una ventaja que ese módulo no usa.
  ///
  /// Anunciar una cosa y liquidar otra es el fallo; decirlo es lo mínimo
  /// mientras el pote no respete los pactos por par.
  static ({String modulos, String ancla})? _poteConAncla(Round round) {
    final nombres = <String>{};
    String? ancla;
    for (final g in round.betGroups) {
      for (final m in g.modules) {
        if (m.formatMode != BetFormatMode.onePot || !m.useHandicap) continue;
        final pids = round.participantesDe(m, g.playerIds);
        if (pids.length <= 2) continue;
        nombres.add(m.type.label);
        ancla ??= BetEngine.groupAnchor(round, pids);
      }
    }
    if (nombres.isEmpty || ancla == null) return null;
    final quien = round.players.where((p) => p.id == ancla).firstOrNull;
    return (modulos: nombres.join(' y '), ancla: quien?.shortName ?? '—');
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
        ? p1.shortName
        : winnerIsP2
            ? p2.shortName
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
    final bd   = LedgerEngine.breakdownBetween(round, p1.id, p2.id);
    final gain1 = bd[BetModuleType.skins] ?? 0.0;

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
        _skinChip(p1.shortName, total1, t),
        const SizedBox(width: 8),
        Text('–', style: TextStyle(color: t.sub, fontSize: 12)),
        const SizedBox(width: 8),
        _skinChip(p2.shortName, total2, t),
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
/// La tarjeta de desglose 1v1, para tests.
///
/// Mismo patrón que resultsTabsForTest: la tarjeta es privada y lo que hay que
/// poder probar es justo lo que enseña. Aquí vivían dos cifras que no cuadraban
/// con el ledger —el Snake que no se listaba pero sí sumaba, y el Nassau en vivo
/// que seguía mandando con la ronda cerrada—, así que merece puerta.
Widget desgloseParaTest(
        {required Round round,
        required Player p1,
        required Player p2,
        required GolfTheme t}) =>
    _FinancialBreakdown(round: round, p1: p1, p2: p2, t: t);

class _FinancialBreakdown extends StatelessWidget {
  final Round round;
  final Player p1, p2;
  final GolfTheme t;
  const _FinancialBreakdown({required this.round, required this.p1, required this.p2, required this.t});

  // Obtiene los módulos de un tipo dado que incluyen a p1 y p2.
  // IMPORTANTE: si el módulo tiene participantIds propios, ambos jugadores deben aparecer
  // en ellos — así se evita que módulos de otros duelos 1v1 dentro del mismo BetGroup
  // se mezclen con el par (p1, p2) (bug de Nassau quintuplicado).
  List<BetModuleInstance> _modsOf(BetModuleType type) {
    final result = <BetModuleInstance>[];
    for (final g in round.betGroups) {
      if (!g.playerIds.contains(p1.id) || !g.playerIds.contains(p2.id)) continue;
      result.addAll(g.modules.where((m) {
        if (m.type != type) return false;
        return m.containsPair(p1.id, p2.id);
      }));
    }
    return result;
  }

  // Devuelve todos los BetModuleType configurados para el par p1/p2
  List<BetModuleType> _allModuleTypes() {
    final types = <BetModuleType>{};
    for (final g in round.betGroups) {
      if (!g.playerIds.contains(p1.id) || !g.playerIds.contains(p2.id)) continue;
      for (final m in g.modules) {
        // Aplicar mismo filtro de participantIds
        if (!m.containsPair(p1.id, p2.id)) continue;
        types.add(m.type);
      }
    }
    // ── El orden es una PREFERENCIA, no un filtro ──────────────────────────
    //
    // Esta lista era un filtro, y por eso el Snake no salía en el desglose: no
    // estaba aquí. Pero el NETO de la tarjeta suma breakdown.values, que sí lo
    // incluye — así que la tarjeta enseñaba cinco líneas que sumaban −550 y un
    // neto de −450, con $100 sin explicar. Verificado contra la ronda del 28 de
    // agosto en producción.
    //
    // Ahora lo conocido va en su orden y lo demás va detrás. Una apuesta nueva
    // puede quedar mal ordenada; lo que no puede es desaparecer del desglose y
    // seguir estando en el total.
    const orden = [
      BetModuleType.skins,
      BetModuleType.nassau,
      BetModuleType.matchAutoPress,
      BetModuleType.medal,
      BetModuleType.putts,
      BetModuleType.oyeses,
      BetModuleType.units,
    ];
    return [
      ...orden.where(types.contains),
      ...types.where((t) => !orden.contains(t)),
    ];
  }

  /// Los tipos que SÍ mueven dinero entre este par.
  List<BetModuleType> get _entreLosDos => _allModuleTypes()
      .where(LedgerEngine.breakdownBetween(round, p1.id, p2.id).containsKey)
      .toList();

  /// Y los que son de la partida entera, donde este par no se cruza.
  List<BetModuleType> get _deLaPartida => _allModuleTypes()
      .where((x) =>
          !LedgerEngine.breakdownBetween(round, p1.id, p2.id).containsKey(x))
      .toList();

  /// Quién se lleva el pote de [tipo], si ese módulo liquida en pote.
  ///
  /// Se lee de los asientos, no se recalcula: el ledger es el que reparte, así
  /// que preguntarle a él es lo único que no puede discrepar de lo que se cobra.
  String? _ganadorDelPote(BetModuleType tipo) {
    final recibe = <String, int>{};
    for (final e in LedgerEngine.entriesOf(round)) {
      if (e.betType != tipo || e.amount <= 0) continue;
      recibe[e.toPlayerId] = (recibe[e.toPlayerId] ?? 0) + 1;
    }
    // Un pote tiene UN cobrador con varios pagadores. Con dos o más cobradores
    // no es un pote: es que este par simplemente no se cruzó en ese módulo.
    if (recibe.length != 1 || recibe.values.first < 2) return null;
    final id = recibe.keys.first;
    return round.players.where((p) => p.id == id).firstOrNull?.shortName;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<RoundProvider>(); // rebuilda al cambiar la ronda
    final breakdown = LedgerEngine.breakdownBetween(round, p1.id, p2.id);

    // ── El estado EN VIVO solo manda mientras se juega ─────────────────────
    //
    // Lo de abajo sobreescribe el breakdown del ledger con un cálculo propio,
    // y hace falta durante la ronda: computeAll solo liquida segmentos
    // CERRADOS, así que a mitad del F9 el desglose saldría en $0 aunque alguien
    // vaya 3UP.
    //
    // Pero con la ronda TERMINADA el ledger es la verdad: es el que cierra en
    // cero y el que se usa para cobrar. Sin esta condición la tarjeta seguía
    // enseñando su propia cuenta para siempre — $150 de Nassau donde el ledger
    // dice −$100, medido en la ronda del 28 de agosto.
    //
    // Dos cuentas para lo mismo solo pueden convivir si una tiene su momento y
    // la otra el suyo.
    final enVivo = !round.isFinished;

    // Match+Press: calcular balance desde live status (orden de pids no importa)
    final mpMods = enVivo ? _modsOf(BetModuleType.matchAutoPress) : const [];
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
    final nassauMods = enVivo ? _modsOf(BetModuleType.nassau) : const [];
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
            // Solo liquidar presses CERRADAS; las abiertas son apuestas pendientes
            if (p.isOpen) continue;
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
    // Primero lo que se cruza entre estos dos, después lo de la partida.
    final allTypes = [..._entreLosDos, ..._deLaPartida];
    if (allTypes.isEmpty) return const SizedBox.shrink();

    // El total neto es la suma del breakdown corregido (incluye match+press por liveStatus)
    final total = breakdown.values.fold<double>(0, (sum, v) => sum + v);
    final totalColor = total > 0.005 ? t.profit : total < -0.005 ? t.loss : t.sub;

    final n1 = p1.shortName;
    final n2 = p2.shortName;

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

        // ── Dos bloques: lo de ustedes dos y lo de la partida ──────────────
        //
        // Un pote de cuatro no es una apuesta entre dos, y listarlo aquí sin
        // más hacía creer que sí —de ahí el "AS" que se leía como empate—. Pero
        // tampoco se puede esconder: afecta al dinero de los dos, así que
        // pertenece a la tarjeta. Lo que faltaba era la separación.
        if (_deLaPartida.isNotEmpty && _entreLosDos.isNotEmpty) ...[
          Text('ENTRE USTEDES DOS',
              style: TextStyle(
                  color: t.sub,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
        ],

        // Filas por tipo de apuesta — se muestran TODOS los módulos configurados,
        // incluso si el monto es 0 (empate / ronda en progreso)
        ...allTypes.map((betType) {
          // ── "AS" significaba TRES cosas ────────────────────────────────────
          //
          // El badge decía AS con solo mirar que el importe fuera cero, y cero
          // sale de tres sitios distintos: un empate de verdad, un módulo que no
          // liquida entre estos dos, y un pote que ganó un tercero. En un Medal
          // —que es juego por golpes— "AS" es una afirmación sobre el golf que
          // el código nunca comprobó: en la ronda del 28 de agosto decía AS
          // entre CAM y Dylan porque el pote se lo llevó KAWA.
          //
          // La clave presente en el breakdown significa "se calculó y quedó en
          // cero"; ausente significa "entre ustedes no mueve nada". Son cosas
          // distintas y ahora se leen distinto.
          final liquida = breakdown.containsKey(betType);
          final pote = !liquida ? _ganadorDelPote(betType) : null;
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

          // Para Oyeses: mostrar marcador y estado del zapato si aplica
          Widget? oyesesSubtitle;
          if (betType == BetModuleType.oyeses) {
            final oyesMods = _modsOf(BetModuleType.oyeses);
            if (oyesMods.isNotEmpty) {
              final mod  = oyesMods.first;
              final o    = mod.oyeses;
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
                final ordered = ranking.ranking.where((pid) => [p1.id, p2.id].contains(pid)).toList();
                if (ordered.length < 2) continue;
                holesPlayed++;
                if (ordered[0] == p1.id) { oyes1++; winsP1vsP2++; }
                else { oyes2++; winsP2vsP1++; }
              }

              // Verificar zapato
              String? zapatoText;
              if (o.zapatoEnabled && holesPlayed > 0) {
                final enoughHoles = o.zapatoRequires18 ? (totalEligible >= 3) : true;
                if (enoughHoles) {
                  final zapatoAmt = o.zapatoValue > 0
                      ? o.zapatoValue
                      : (totalEligible * o.value);
                  if (holesPlayed == totalEligible) {
                    if (winsP1vsP2 == holesPlayed) {
                      zapatoText = '👟 Zapato: $n1 +\$${zapatoAmt.toStringAsFixed(0)}';
                    } else if (winsP2vsP1 == holesPlayed) {
                      zapatoText = '👟 Zapato: $n2 +\$${zapatoAmt.toStringAsFixed(0)}';
                    } else {
                      zapatoText = '👟 Zapato: no aplica';
                    }
                  } else {
                    final remaining = totalEligible - holesPlayed;
                    if (winsP1vsP2 > 0 && winsP2vsP1 == 0) {
                      zapatoText = '👟 Zapato en juego: $n1 lidera ($remaining par-3 restantes)';
                    } else if (winsP2vsP1 > 0 && winsP1vsP2 == 0) {
                      zapatoText = '👟 Zapato en juego: $n2 lidera ($remaining par-3 restantes)';
                    }
                  }
                }
              }

              oyesesSubtitle = Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '$n1 $oyes1 oyés  ·  $oyes2 oyés $n2',
                    style: TextStyle(color: t.sub, fontSize: 10),
                  ),
                  if (zapatoText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      zapatoText,
                      style: TextStyle(
                        color: zapatoText.contains('no aplica') ? t.sub : t.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ]),
              );
            }
          }

          // Para Match+Press: sin sub-filas, solo encabezado
          // (el detalle lo muestra el panel _MatchPressLivePanel)

          // La cabecera del segundo bloque va con su primera fila, para que la
          // separación exista sin partir el .map en dos listas.
          final abreBloqueDePartida =
              _entreLosDos.isNotEmpty && betType == _deLaPartida.firstOrNull;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (abreBloqueDePartida) ...[
                const SizedBox(height: 6),
                Text('DE LA PARTIDA · no se cruza entre ustedes',
                    style: TextStyle(
                        color: t.sub,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                const SizedBox(height: 6),
              ],
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
                    !liquida
                        ? (pote != null ? 'POTE' : '—')
                        : absAmt < 0.005
                            ? 'AS'
                            : '$sign\$${absAmt.toStringAsFixed(0)}',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              if (!liquida)
                Padding(
                  padding: const EdgeInsets.only(left: 22, top: 2),
                  child: Text(
                      pote != null
                          ? 'Pote de la partida · lo gana $pote. Entre ustedes '
                              'dos no mueve nada.'
                          : 'No se liquida entre ustedes dos.',
                      style: TextStyle(color: t.sub, fontSize: 10, height: 1.2)),
                ),
              if (skinsSubtitle != null)
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: skinsSubtitle,
                ),
              if (oyesesSubtitle != null)
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: oyesesSubtitle,
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


// ── Tarjeta de equipo: Bola Baja / Bola Alta ─────────────────────────────────
//
// Va ARRIBA de los cruces individuales porque es el marcador real del formato.
// Los cruces de abajo muestran "hoyos ganados", que viene de match play
// individual y no tiene relación con cómo se calculó esta apuesta; sin esta
// tarjeta, el jugador no tiene en ninguna parte el marcador que sí cuenta.
//
// Todos los números salen de BetEngine.lowHighBreakdown. Cero cálculo aquí.
class LowHighTeamCard extends StatelessWidget {
  final Round round;
  final BetModuleInstance mod;
  final GolfTheme t;

  /// Segmento a destacar: el que se está jugando. Si es null se resume el
  /// Overall, que es el resultado final de la ronda.
  final String? segmentoEnCurso;

  const LowHighTeamCard({
    super.key,
    required this.round,
    required this.mod,
    required this.t,
    this.segmentoEnCurso,
  });

  String _nombre(String id) => round.players
      .firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id))
      .name
      .split(' ')
      .first;

  /// Color del lado: el de su primer miembro, el mismo de su avatar.
  Color _colorDe(BetSide side) {
    final p = round.players.firstWhere(
      (p) => side.playerIds.contains(p.id),
      orElse: () => Player(id: '', name: ''),
    );
    return GAvatar.colorFor(p.colorIndex);
  }

  @override
  Widget build(BuildContext context) {
    final List<LowHighSegmentBreakdown> segs;
    try {
      segs = BetEngine.lowHighBreakdown(round, mod);
    } catch (_) {
      return const SizedBox.shrink(); // config inválida: ya se avisa en Resultados
    }
    if (segs.isEmpty) return const SizedBox.shrink();

    final sideA = mod.sideA;
    final sideB = mod.sideB;
    final fmt   = BetEngine.formatPoints;

    final destacado = segs.firstWhere(
      (s) => s.segment == (segmentoEnCurso ?? 'overall'),
      orElse: () => segs.last,
    );

    var colorA = _colorDe(sideA);
    var colorB = _colorDe(sideB);
    // Dos lados del mismo color serían ilegibles justo donde el color ES la
    // información. Se desempata girando el tono del lado B.
    if (colorA.toARGB32() == colorB.toARGB32()) {
      colorB = HSLColor.fromColor(colorB)
          .withHue((HSLColor.fromColor(colorB).hue + 150) % 360)
          .toColor();
    }

    // Proporción del duelo. Sin puntos aún, se reparte a la mitad: una barra
    // en blanco diría "va ganando A" cuando no ha pasado nada.
    final suma  = destacado.aTotal + destacado.bTotal;
    final share = suma > 0 ? destacado.aTotal / suma : 0.5;
    final ganaA = !destacado.isTie && destacado.diff > 0;
    final ganaB = !destacado.isTie && destacado.diff < 0;

    var netoA = 0.0;
    for (final s in segs) {
      if (!s.isTie) netoA += s.diff > 0 ? s.total : -s.total;
    }

    // ── Columna de un lado ────────────────────────────────────────────────
    Widget lado(BetSide side, Color color, double low, double high,
            double total, bool gana, bool derecha) =>
        Expanded(
          child: Column(
            crossAxisAlignment:
                derecha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!derecha) ...[
                    _punto(color),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(side.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: t.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2)),
                  ),
                  if (derecha) ...[
                    const SizedBox(width: 6),
                    _punto(color),
                  ],
                ],
              ),
              const SizedBox(height: 1),
              Text(side.playerIds.map(_nombre).join(' + '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: derecha ? TextAlign.right : TextAlign.left,
                  style: GolfType.label(t.sub)),
              const SizedBox(height: 8),
              // Cifra héroe de la pestaña: la que responde "cómo va la
              // apuesta principal". Sale de la escala, no de un tamaño suelto.
              Text(fmt(total),
                  style: GolfType.hero(
                    gana ? color : t.text.withValues(alpha: 0.55),
                    size: 46,
                  )),
              const SizedBox(height: 3),
              Text('baja ${fmt(low)}   alta ${fmt(high)}',
                  style: TextStyle(
                      color: t.sub,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        );

    // Sin desenfoque, y el motivo se verificó en pantalla: esta tarjeta hace
    // SCROLL con el contenido y nunca tiene nada detrás que desenfocar. Sigma
    // 20 y sigma 2 daban el mismo resultado.
    //
    // Además el desenfoque reduce contraste, que es lo contrario de lo que pide
    // el uso a pleno sol.
    //
    // Se conservan las otras tres capas —relleno, borde especular y sombra— y
    // toda la estructura de GlassCard con sus tokens: lo que deja de usarse es
    // la variante con BackdropFilter, no el acabado.
    return GlassCard.solid(
      t: t,
      margin: const EdgeInsets.only(bottom: 14),
      radius: 22,
      // Sin padding: el gradiente proporcional tiene que llegar a los bordes,
      // así que el espaciado va por dentro.
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          // El fondo se inclina hacia quien va ganando: el gradiente cambia de
          // color justo en la proporción del marcador, así que la mitad
          // dominante se lee antes que los números.
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              colorA.withValues(alpha: 0.20),
              colorA.withValues(alpha: 0.06),
              colorB.withValues(alpha: 0.06),
              colorB.withValues(alpha: 0.20),
            ],
            stops: [0, (share * 0.9).clamp(0.05, 0.95),
                    (share * 1.1).clamp(0.05, 0.95), 1],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          child: Column(children: [
          // ── Cabecera ──────────────────────────────────────────────────
          Row(children: [
            Text(mod.type.icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(mod.type.label.toUpperCase(),
                  style: TextStyle(
                      color: t.sub,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: t.text.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                  destacado.label.replaceFirst('Bola Baja/Alta ', ''),
                  style: TextStyle(
                      color: t.text,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 14),

          // ── Marcador ──────────────────────────────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            lado(sideA, colorA, destacado.aLow, destacado.aHigh,
                destacado.aTotal, ganaA, false),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(children: [
                const SizedBox(height: 22),
                // La unidad, explícita: justo debajo hay tarjetas que marcan
                // HOYOS ganados y confundirlas cambia la lectura entera.
                Text('PUNTOS',
                    style: TextStyle(
                        color: t.sub.withValues(alpha: 0.8),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1)),
              ]),
            ),
            lado(sideB, colorB, destacado.bLow, destacado.bHigh,
                destacado.bTotal, ganaB, true),
          ]),
          const SizedBox(height: 12),

          // ── Barra proporcional: el duelo de un vistazo ────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 9,
              child: Stack(children: [
                // Fondo completo del lado B…
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorB.withValues(alpha: 0.75), colorB],
                    ),
                  ),
                ),
                // …y encima el trozo que le corresponde al lado A.
                FractionallySizedBox(
                  widthFactor: share.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorA, colorA.withValues(alpha: 0.75)],
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),

          // ── Otros segmentos ──────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 5,
            alignment: WrapAlignment.center,
            children: segs.map((s) {
              final etq = s.label.replaceFirst('Bola Baja/Alta ', '');
              final act = s.segment == destacado.segment;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: act
                      ? t.text.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: act
                          ? Colors.transparent
                          : t.divider.withValues(alpha: 0.7)),
                ),
                child: Text(
                  s.isTie
                      ? '$etq  empate'
                      : '$etq  ${fmt(s.aTotal)}–${fmt(s.bTotal)}',
                  style: TextStyle(
                      color: act ? t.text : t.sub,
                      fontSize: 10,
                      fontWeight: act ? FontWeight.w800 : FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              );
            }).toList(),
          ),

          if (netoA != 0) ...[
            const SizedBox(height: 11),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
              decoration: BoxDecoration(
                color: (netoA > 0 ? colorA : colorB).withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${netoA > 0 ? sideB.name : sideA.name}  →  '
                '${netoA > 0 ? sideA.name : sideB.name}   '
                '\$${netoA.abs().toStringAsFixed(0)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: netoA > 0 ? colorA : colorB,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ],
          ]),
        ),
      ),
    );
  }

  Widget _punto(Color c) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 5),
          ],
        ),
      );
}
