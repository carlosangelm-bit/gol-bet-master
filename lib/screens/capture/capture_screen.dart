// ─────────────────────────────────────────────────────────────────────────────
// CAPTURE SCREEN — Layout Opción C
// Estructura:
//   1. Header + selector de hoyos + info del hoyo (fijos arriba)
//   2. Tabla compacta: todos los jugadores — tocar fila = jugador activo
//      Cada fila: Avatar · Apodo · Progreso vs par · −score+ · −putts+
//   3. Zona del jugador activo:
//      - Botones rápidos 2×3 (Eagle/Birdie/Par / Bogey/Doble/+3)
//      - Botón Units (abre sheet igual que antes)
//   4. Oyeses (solo par 3)
//   5. Navegación prev/next hoyo
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../engines/bet_engine.dart';
import '../../models/formaciones.dart';
import '../../models/models.dart';
import '../torneos/republicar_al_cerrar.dart';
import '../../providers/round_provider.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/sliding_adjustment_dialog.dart';
import '../../engines/sixes_engine.dart';
import '../../engines/wolf_engine.dart';
import '../../providers/torneo_provider.dart';
import '../../providers/user_profile_provider.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {

  /// Módulos Wolf de la ronda. Vacío = no se juega y no se pregunta nada.
  static List<(BetGroup, BetModuleInstance)> _wolfMods(Round round) => [
        for (final g in round.betGroups)
          for (final m in g.modules)
            if (m.type == BetModuleType.wolf) (g, m),
      ];

  static bool _tieneWolf(Round round) => _wolfMods(round).isNotEmpty;

  /// Módulos Sixes de la ronda. Vacío = no se juega y no se enseña nada.
  static List<(BetGroup, BetModuleInstance)> _sixesMods(Round round) => [
        for (final g in round.betGroups)
          for (final m in g.modules)
            if (m.type == BetModuleType.sixes) (g, m),
      ];

  static bool _tieneSixes(Round round) => _sixesMods(round).isNotEmpty;

  /// La pareja base de la ronda, si las apuestas dibujan ese patrón.
  ///
  /// Se DERIVA de los módulos —dos o más de 2 contra 2 que comparten un lado— en
  /// vez de leerse de un campo. Así funciona también con las tres apuestas
  /// montadas a mano, que es como este formato ya se podía jugar antes de que el
  /// atajo existiera.
  static ({List<String> base, List<List<String>> rivales})? _parejaBase(
          Round round) =>
      parejaBaseDe([for (final g in round.betGroups) ...g.modules]);

  /// Ancla del bloque de Wolf, para poder traerlo a pantalla.
  ///
  /// Se MIDIÓ que el bloque queda por debajo del borde: los botones van de y=886
  /// a 930 con cuatro jugadores y de 995 a 1039 con cinco, en un viewport de
  /// 844. Subirlo antes de la tabla lo arregla y empeora otra cosa —la zona de
  /// captura de scores pasa de 624 a 906, o sea de dentro a fuera— y esa se usa
  /// cuatro o cinco veces por hoyo contra una de Wolf. Cambiar un elemento fuera
  /// de pantalla por otro peor no es un arreglo.
  ///
  /// Así que el bloque se queda donde está y el aviso LLEVA hasta él. Un aviso
  /// que dice "falta algo" y te deja buscándolo hace la mitad del trabajo.
  final _wolfKey = GlobalKey();

  /// Pasa al hoyo [destino], pero avisa si se deja Wolf sin contestar.
  ///
  /// El riesgo real de Wolf no es que el hoyo no liquide —eso ya se dice en las
  /// notas— es el OLVIDO: reconstruir con quién jugó el Wolf en el hoyo 7 al
  /// final de la ronda es imposible. Nadie se acuerda, y no hay dato del que
  /// deducirlo. El aviso va al salir del hoyo porque es el último momento en que
  /// la respuesta está fresca.
  ///
  /// Solo avisa si el hoyo SE JUGÓ: hay al menos un score capturado y no hay
  /// elección. Navegar entre hoyos para mirar no puede dar la lata, y sin esa
  /// condición el aviso saltaría en los diecisiete que quedan por delante.
  Future<void> _irAlHoyo(int destino, Round round) async {
    final mods = _wolfMods(round);
    if (mods.isEmpty) {
      _jumpToHole(destino);
      return;
    }

    final (grupo, mod) = mods.first;
    final orden = round.participantesDe(mod, grupo.playerIds);
    final jugado = orden.any((pid) => round.getScore(pid, _currentHole).hasScore);
    final faltaElegir = round.getWolfCall(_currentHole) == null;

    if (!jugado ||
        !faltaElegir ||
        BetModuleType.wolf.motivoNoDisponible(orden.length) != null) {
      _jumpToHole(destino);
      return;
    }

    final wolf = WolfEngine.wolfDelHoyo(orden, _currentHole);
    final nombre = round.players
        .firstWhere((p) => p.id == wolf, orElse: () => Player(id: wolf, name: wolf))
        .name
        .split(' ')
        .first;
    final t = context.gt;

    final seguir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Text('Falta el compañero del Wolf',
            style: TextStyle(color: t.text, fontSize: 17,
                fontWeight: FontWeight.w800)),
        content: Text(
          'El hoyo $_currentHole ya tiene score, pero no dice con quién jugó '
          '$nombre. Sin eso el hoyo no liquida, y al terminar la ronda no habrá '
          'forma de reconstruirlo.',
          style: TextStyle(color: t.sub, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Seguir sin elegir',
                style: TextStyle(color: t.sub, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Elegir ahora',
                style:
                    TextStyle(color: t.primary, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (seguir == true) {
      _jumpToHole(destino);
      return;
    }
    // "Elegir ahora": se queda en el hoyo Y se lleva el bloque a pantalla. Sin
    // esto el aviso mandaría a buscar algo que está por debajo del borde.
    final ctx = _wolfKey.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(ctx,
          duration: GolfMotion.pausado, alignment: 0.5);
    }
  }

  int _currentHole = 1; // Se corrige en initState via postFrameCallback
  String? _activePlayerId; // jugador seleccionado en la tabla
  final ScrollController _holeScroll = ScrollController();

  List<int> _firstSegment(StartingNine sn) =>
      sn == StartingNine.back ? List.generate(9, (i) => i + 10) : List.generate(9, (i) => i + 1);
  List<int> _secondSegment(StartingNine sn) =>
      sn == StartingNine.back ? List.generate(9, (i) => i + 1) : List.generate(9, (i) => i + 10);
  int _lastOfFirst(StartingNine sn)   => sn == StartingNine.back ? 18 : 9;
  int _firstOfSecond(StartingNine sn) => sn == StartingNine.back ? 1 : 10;
  bool _isInSecondSegment(Round round) {
    final sn = round.startingNine;
    if (sn == StartingNine.front) return _currentHole >= 10;
    return _currentHole <= 9;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov  = context.read<RoundProvider>();
      if (!prov.hasRound) return;
      final round = prov.round!;
      final sn    = round.startingNine;
      final order = [..._firstSegment(sn), ..._secondSegment(sn)];
      for (final h in order) {
        final activePlayers = round.scoringPlayers;
        if (!activePlayers.every((p) => round.getScore(p.id, h).hasScore)) {
          _jumpToHole(h);
          break;
        }
      }
      // Activar el primer jugador por defecto
      final activePlayers = round.scoringPlayers;
      if (activePlayers.isNotEmpty) {
        setState(() => _activePlayerId = activePlayers.first.id);
      }
    });
  }

  @override
  void dispose() {
    _holeScroll.dispose();
    super.dispose();
  }

  void _jumpToHole(int h) {
    setState(() => _currentHole = h);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_holeScroll.hasClients) return;
      // Calcular posición correcta según el orden real de juego
      final prov  = context.read<RoundProvider>();
      final round = prov.hasRound ? prov.round! : null;
      if (round == null) return;
      final sn    = round.startingNine;
      final order = [..._firstSegment(sn), ..._secondSegment(sn)];
      final idx   = order.indexOf(h);
      if (idx < 0) return;
      _holeScroll.animateTo(
        idx * 46.0,
        duration: GolfMotion.pausado,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final t    = prov.theme;
    GolfThemeExt.setCurrent(t);

    if (!prov.hasRound) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.sports_golf, color: t.sub, size: 48),
            const SizedBox(height: 12),
            Text('No hay ronda activa', style: TextStyle(color: t.sub, fontSize: 16)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: GPrimaryButton(
                label: 'Iniciar Ronda',
                onTap: () => context.read<RoundProvider>().setTab(0),
              ),
            ),
          ]),
        ),
      );
    }

    final round = prov.round!;
    // Validar que _currentHole pertenece al orden de juego real
    final sn0       = round.startingNine;
    final firstSeg0 = sn0 == StartingNine.back
        ? List.generate(9, (i) => i + 10)
        : List.generate(9, (i) => i + 1);
    final secondSeg0 = sn0 == StartingNine.back
        ? List.generate(9, (i) => i + 1)
        : List.generate(9, (i) => i + 10);
    final playOrder0 = round.totalHoles == 9
        ? firstSeg0
        : [...firstSeg0, ...secondSeg0];
    if (!playOrder0.contains(_currentHole)) {
      // Hoyo inválido para esta ronda → corregir de inmediato
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToHole(playOrder0.first));
      _currentHole = playOrder0.first;
    }
    final ch    = round.course.holes.firstWhere((h) => h.hole == _currentHole,
        orElse: () => round.course.holes.first);

    // Asegurar que siempre hay un jugador activo válido
    final activePlayers = round.scoringPlayers;
    final activeId = (_activePlayerId != null &&
            activePlayers.any((p) => p.id == _activePlayerId))
        ? _activePlayerId!
        : activePlayers.first.id;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ─────────────────────────────────────────────────────
          _CaptureHeader(round: round, t: t),

          // ── Selector de hoyos ──────────────────────────────────────────
          _HoleSelector(
            round: round,
            currentHole: _currentHole,
            scrollCtrl: _holeScroll,
            t: t,
            onSelect: _jumpToHole,
            showAll: _isInSecondSegment(round),
          ),

          // ── Info del hoyo ──────────────────────────────────────────────
          _HoleInfoBar(ch: ch, t: t),

          // ── Cuerpo principal scrollable ────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Bola Baja / Bola Alta del hoyo en curso ────────────
                for (final g in round.betGroups)
                  for (final m in g.modules)
                    if (m.type == BetModuleType.nassauLowHigh && m.hasTeamSides)
                      LowHighHoleBlock(
                          round: round, mod: m, hole: _currentHole, t: t),

                // ── Wolf: con quién jugó ───────────────────────────────
                //
                // ARRIBA, antes de la tabla. Estaba al final del cuerpo y
                // MEDIDO quedaba fuera de pantalla: con cuatro jugadores el
                // bloque iba de y=671 a y=943 con un viewport de 844, así que
                // los botones caían por debajo del borde; con cinco, de 730 a
                // 1052. En el campo eso convierte un toque en un gesto y medio.
                //
                // Va antes de la tabla y no después porque es un dato DEL HOYO,
                // como el bloque de Bola Baja que ya estaba aquí, y porque en
                // Wolf la respuesta se sabe antes de anotar: el Wolf elige
                // compañero en el tee, viendo los primeros golpes.
                if (_tieneWolf(round)) ...[
                  _WolfCallSection(
                      key: _wolfKey, hole: _currentHole, t: t),
                  const SizedBox(height: 10),
                ],

                // ── Con quién vas en este bloque ──────────────────────
                //
                // Sixes no pregunta nada: las parejas se derivan del bloque.
                // Pero en el hoyo 7 alguien va a preguntar "¿con quién voy
                // ahora?", y contar bloques mentalmente es justo lo que la app
                // está para evitar. Misma decisión que en Wolf: se deriva, y se
                // ENSEÑA.
                if (_tieneSixes(round)) ...[
                  _SixesBloqueSection(hole: _currentHole, t: t),
                  const SizedBox(height: 10),
                ],

                // ── La pareja base y sus tres rivales ─────────────────
                //
                // Con tres enfrentamientos a la vez, deducir quién juega contra
                // quién mirando la lista de apuestas es trabajo. Aquí la pareja
                // base va destacada —es la constante— y los rivales como chips.
                if (_parejaBase(round) != null) ...[
                  _ParejaBaseSection(round: round, t: t),
                  const SizedBox(height: 10),
                ],

                // ── Tabla de jugadores ─────────────────────────────────
                _PlayerTable(
                  round: round,
                  currentHole: _currentHole,
                  activePlayerId: activeId,
                  t: t,
                  onSelectPlayer: (pid) => setState(() => _activePlayerId = pid),
                ),

                const SizedBox(height: 10),

                // ── Zona del jugador activo ────────────────────────────
                _ActivePlayerZone(
                  round: round,
                  activePlayerId: activeId,
                  hole: _currentHole,
                  ch: ch,
                  t: t,
                ),

                // ── Ranking Oyes (solo par 3) ──────────────────────────
                if (ch.isPar3) ...[
                  const SizedBox(height: 10),
                  _OyesRankingSection(hole: _currentHole, t: t),
                ],

                const SizedBox(height: 10),

                // ── Navegación prev/next ───────────────────────────────
                Builder(builder: (_) {
                  final sn          = round.startingNine;
                  final is9Holes    = round.totalHoles == 9;
                  final firstSeg    = _firstSegment(sn);
                  final secondSeg   = _secondSegment(sn);
                  final firstSecond = _firstOfSecond(sn);
                  // Orden real de juego según startingNine
                  final playOrder   = is9Holes
                      ? firstSeg
                      : [...firstSeg, ...secondSeg];
                  int curIdx = playOrder.indexOf(_currentHole);
                  // Si el hoyo actual no está en el playOrder (ej. _currentHole=1
                  // pero la ronda empieza por Back 9), saltar al primer hoyo válido.
                  if (curIdx == -1) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _jumpToHole(playOrder.first);
                    });
                    curIdx = 0;
                  }
                  final hasPrev     = curIdx > 0;
                  final hasNext     = curIdx >= 0 && curIdx < playOrder.length - 1;
                  final inSecond    = secondSeg.contains(_currentHole);
                  final isLastOfFirst = curIdx == firstSeg.length - 1 && !is9Holes;
                  final isVeryLast    = curIdx == playOrder.length - 1;
                  final isLast9       = is9Holes && curIdx == playOrder.length - 1;

                  return _HoleNavButtons(
                    current:    _currentHole,
                    startingNine: sn,
                    is9HoleRound: is9Holes,
                    inSecondSegment: inSecond,
                    prevHole: hasPrev ? playOrder[curIdx - 1] : null,
                    nextHole: hasNext ? playOrder[curIdx + 1] : null,
                    isLastOfFirstSegment: isLastOfFirst,
                    firstOfSecond: firstSecond,
                    isVeryLast: isVeryLast,
                    isLast9: isLast9,
                    t: t,
                    // Al RETROCEDER no se avisa: se vuelve justamente a
                    // arreglar algo, y un diálogo ahí estorbaría el arreglo.
                    onPrev: hasPrev ? () => _jumpToHole(playOrder[curIdx - 1]) : null,
                    onNext: hasNext
                        ? () => _irAlHoyo(playOrder[curIdx + 1], round)
                        : null,
                    onContinueTo18: isLast9
                        ? () => _jumpToHole(firstSecond)
                        : null,
                  );
                }),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────
class _CaptureHeader extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  const _CaptureHeader({required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    final completed      = _countCompleted(round);
    final effectiveTotal = _effectiveTotal(round);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(color: t.bg, border: Border(bottom: BorderSide(color: t.divider))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Score', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3)),
          Text(round.name, style: TextStyle(color: t.sub, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: t.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.primary.withValues(alpha: 0.25)),
          ),
          child: Text('$completed/$effectiveTotal hoyos',
              style: TextStyle(color: t.primary, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  int _effectiveTotal(Round round) {
    if (round.totalHoles == 18) return 18;
    final secondStart = round.startingNine == StartingNine.back ? 1 : 10;
    final secondEnd   = round.startingNine == StartingNine.back ? 9 : 18;
    final hasSecond   = round.scores.values.any((hmap) =>
        hmap.keys.any((h) => h >= secondStart && h <= secondEnd));
    return hasSecond ? 18 : round.totalHoles;
  }

  int _countCompleted(Round round) {
    final total = _effectiveTotal(round);
    final activePlayers = round.scoringPlayers;
    int c = 0;
    for (int h = 1; h <= total; h++) {
      if (activePlayers.every((p) => round.getScore(p.id, h).hasScore)) c++;
    }
    return c;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELECTOR DE HOYOS
// ─────────────────────────────────────────────────────────────────────────────
class _HoleSelector extends StatelessWidget {
  final Round round;
  final int currentHole;
  final ScrollController scrollCtrl;
  final GolfTheme t;
  final void Function(int) onSelect;
  final bool showAll;
  const _HoleSelector({
    required this.round, required this.currentHole,
    required this.scrollCtrl, required this.t, required this.onSelect,
    this.showAll = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: t.surface,
      child: ListView.builder(
        controller: scrollCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        itemCount: (round.totalHoles == 9 && !showAll) ? 9 : 18,
        itemBuilder: (_, i) {
          // Respetar siempre el orden real de juego (startingNine)
          final List<int> order;
          if (round.totalHoles == 9 && !showAll) {
            order = round.startingNine == StartingNine.back
                ? List.generate(9, (j) => j + 10)
                : List.generate(9, (j) => j + 1);
          } else {
            final first  = round.startingNine == StartingNine.back
                ? List.generate(9, (j) => j + 10)
                : List.generate(9, (j) => j + 1);
            final second = round.startingNine == StartingNine.back
                ? List.generate(9, (j) => j + 1)
                : List.generate(9, (j) => j + 10);
            order = [...first, ...second];
          }
          final h = order[i];
          final isSel   = h == currentHole;
          final activePlayers = round.scoringPlayers;
          final allDone = activePlayers.isNotEmpty &&
              activePlayers.every((p) => round.getScore(p.id, h).hasScore);
          final isPar3  = round.course.holes.firstWhere((c) => c.hole == h).isPar3;

          return GestureDetector(
            onTap: () => onSelect(h),
            child: Container(
              width: 42,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: isSel
                    ? t.primary
                    : allDone
                        ? t.primary.withValues(alpha: 0.18)
                        : t.card,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSel ? t.primary : allDone ? t.primary.withValues(alpha: 0.4) : t.divider,
                ),
              ),
              alignment: Alignment.center,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  '$h',
                  style: TextStyle(
                    color: isSel ? t.onPrimary : allDone ? t.primary : t.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (isPar3)
                  Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      color: isSel ? t.onPrimary.withValues(alpha: 0.7) : t.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INFO DEL HOYO
// ─────────────────────────────────────────────────────────────────────────────
class _HoleInfoBar extends StatelessWidget {
  final CourseHole ch;
  final GolfTheme t;
  const _HoleInfoBar({required this.ch, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: t.bg,
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Text(
            '${ch.hole}',
            style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w900, fontSize: 22),
          ),
        ),
        const SizedBox(width: 12),
        // Los chips ruedan en horizontal en vez de recortarse.
        //
        // Se salían 10 px a 320 px con los cuatro —par, SI, la vuelta y el Oyés
        // de los par 3—. Con Wrap dejaban de recortarse pero costaban una línea
        // de alto, y MEDIDO eso empujaba la quinta fila de la tabla de 844 a 871:
        // fuera de pantalla. Cambiar un recorte por una fila invisible no es un
        // arreglo, y el test de Wolf lo cazó.
        //
        // Rodando no cuestan alto ninguno, y son información —par, índice— no
        // controles: nadie los toca.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip('Par ${ch.par}', t.primary, t),
              const SizedBox(width: 6),
              _chip('SI ${ch.strokeIndex}', t.sub, t),
              const SizedBox(width: 6),
              _chip(ch.hole <= 9 ? 'Front 9' : 'Back 9',
                  ch.hole <= 9 ? t.primary : t.accent, t),
              if (ch.isPar3) ...[
                const SizedBox(width: 6),
                _chip('⛳ Oyes', t.accent, t, accent: true),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _chip(String label, Color color, GolfTheme t, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: accent ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABLA DE JUGADORES — todas las filas compactas
// ─────────────────────────────────────────────────────────────────────────────
class _PlayerTable extends StatelessWidget {
  final Round round;
  final int currentHole;
  final String activePlayerId;
  final GolfTheme t;
  final void Function(String) onSelectPlayer;

  const _PlayerTable({
    required this.round,
    required this.currentHole,
    required this.activePlayerId,
    required this.t,
    required this.onSelectPlayer,
  });

  // Nombre corto: player.name ya contiene el displayName/apodo asignado al crear la ronda
  String _shortName(Player p) => p.isVirtual ? p.name : p.name.split(' ').first;

  // Progreso bruto acumulado vs par (solo hoyos completados hasta el actual)
  String _grossProgress(Round round, String playerId) {
    int totalGross = 0;
    int totalPar   = 0;
    for (final hole in round.course.holes) {
      final s = round.getScore(playerId, hole.hole);
      if (!s.hasScore) continue;
      totalGross += s.grossScore!;
      totalPar   += hole.par;
    }
    if (totalPar == 0) return '';
    final diff = totalGross - totalPar;
    if (diff == 0) return 'E';
    return diff > 0 ? '+$diff' : '$diff';
  }

  Color _progressColor(String progress, GolfTheme t) {
    if (progress.isEmpty || progress == 'E') return t.sub;
    if (progress.startsWith('+')) return t.scoreOver;
    return t.scoreUnder;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.divider),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: round.scoringPlayers.asMap().entries.map((entry) {
          final idx    = entry.key;
          final player = entry.value;
          final isActive = player.id == activePlayerId;
          final score    = prov.round!.getScore(player.id, currentHole);
          final gross    = score.grossScore ?? 0;
          final putts    = score.putts;
          final par      = round.course.holes
              .firstWhere((h) => h.hole == currentHole).par;
          final progress = _grossProgress(round, player.id);
          final progColor = _progressColor(progress, t);
          final shortName = _shortName(player);

          // Color del score del hoyo actual
          Color scoreColor = t.sub;
          if (score.hasScore) {
            final rel = gross - par;
            if (rel < 0) {
              scoreColor = t.scoreUnder;
            } else if (rel > 0) {
              scoreColor = t.scoreOver;
            } else {
              scoreColor = t.sub;
            }
          }

          return GestureDetector(
            onTap: () => onSelectPlayer(player.id),
            child: AnimatedContainer(
              duration: GolfMotion.rapido,
              decoration: BoxDecoration(
                color: isActive
                    ? t.primary.withValues(alpha: 0.06)
                    : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    color: isActive ? t.primary : Colors.transparent,
                    width: 3,
                  ),
                  bottom: idx < round.players.length - 1
                      ? BorderSide(color: t.divider.withValues(alpha: 0.6))
                      : BorderSide.none,
                ),
              ),
              // Cromo más ajustado en pantalla estrecha: el avatar y el
              // relleno ceden 14 px, que es lo que le devuelve sitio al nombre.
              // Se le quita al adorno y no al control ni al nombre, que son lo
              // que se usa.
              padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width < 400 ? 6 : 10,
                  vertical: 8),
              child: Row(children: [
                // Avatar
                GAvatar(
                    name: player.name,
                    colorIndex: player.colorIndex,
                    size: MediaQuery.of(context).size.width < 400 ? 28 : 36),
                SizedBox(
                    width: MediaQuery.of(context).size.width < 400 ? 6 : 8),

                // Nombre + HCP
                //
                // 56 y no 64, y el divisor con la mitad de margen: la fila se
                // salía 15 px a 390 px —MEDIDO— y había que recuperarlos de algún
                // sitio. Se recuperan del CROMO, no de los steppers: esos se
                // tocan cinco veces por hoyo y con guante, y uno recortado
                // convierte un toque en dos.
                //
                // Probado y descartado: Expanded en esta columna. Quita el
                // desborde pero se queda todo el hueco libre, así que los
                // steppers se estrechan, algo se parte dentro y la fila crece 27
                // px —MEDIDO: la quinta pasaba de 844 a 871, o sea fuera de
                // pantalla—. Lo cazó el test de geometría de Wolf.
                //
                // Flexible SÍ: pide 56 y se queda con menos cuando no hay,
                // pero al ser loose no se lleva el hueco libre, así que los
                // steppers conservan su ancho natural. Hacía falta porque el
                // chip de progreso CRECE —"+21" en un jugador 21 sobre par es
                // normal— y con la fila rígida eso la sacaba 22 px a 390 px.
                Flexible(
                  child: SizedBox(
                  width: 56,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      shortName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive ? t.primary : t.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'HCP ${player.handicapBase.toStringAsFixed(0)}',
                      style: TextStyle(color: t.sub, fontSize: 10),
                    ),
                  ]),
                  ),
                ),

                const SizedBox(width: 4),

                // Progreso vs par (bruto acumulado)
                //
                // Se cae en pantallas estrechas, y es una decisión: a 320 px los
                // dos steppers, el divisor y este chip no caben —MEDIDO, 21 px
                // de más— y algo tiene que ceder. Cede el chip porque INFORMA,
                // mientras que los steppers se TOCAN cinco veces por hoyo y con
                // guante. Un stepper recortado convierte un toque en dos.
                if (progress.isNotEmpty && MediaQuery.of(context).size.width >= 360)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: progColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: progColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      progress,
                      style: TextStyle(
                        color: progColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  )
                else if (MediaQuery.of(context).size.width >= 360)
                  const SizedBox(width: 32),

                // Score del hoyo: − valor +
                // Cuando no hay score, el par se muestra como placeholder.
                // − desde par → guarda par-1 (birdie); + desde par → par+1 (bogey)
                _ScoreStepper(
                  score: gross,
                  hasScore: score.hasScore,
                  scoreColor: scoreColor,
                  par: par,
                  t: t,
                  onDec: () {
                    // Base: score actual si ya registrado, o par si es placeholder
                    final base = score.hasScore ? gross : par;
                    final newScore = base > 1 ? base - 1 : 1;
                    prov.updateScore(player.id, currentHole, newScore,
                        putts == 0 ? 2 : putts);
                  },
                  onInc: () {
                    final base = score.hasScore ? gross : par;
                    prov.updateScore(player.id, currentHole, base + 1,
                        putts == 0 ? 2 : putts);
                  },
                  onTapPar: () {
                    // Toque en el círculo sin score → registra exactamente el par
                    prov.updateScore(player.id, currentHole, par,
                        putts == 0 ? 2 : putts);
                  },
                ),

                // Divisor vertical
                Container(
                  width: 1, height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: t.divider,
                ),

                // Putts: − valor +
                _PuttsStepper(
                  putts: putts,
                  t: t,
                  onDec: () => prov.updateScore(
                      player.id, currentHole, score.grossScore,
                      putts > 0 ? putts - 1 : 0),
                  onInc: () => prov.updateScore(
                      player.id, currentHole, score.grossScore, putts + 1),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEPPER DE SCORE (inline en la tabla)
// ─────────────────────────────────────────────────────────────────────────────
class _ScoreStepper extends StatelessWidget {
  final int score;
  final bool hasScore;
  final Color scoreColor;
  final int par;
  final GolfTheme t;
  final VoidCallback onDec;
  final VoidCallback onInc;
  /// Registra exactamente el par (toque al círculo cuando no hay score).
  final VoidCallback onTapPar;

  const _ScoreStepper({
    required this.score, required this.hasScore, required this.scoreColor,
    required this.par, required this.t,
    required this.onDec, required this.onInc, required this.onTapPar,
  });

  @override
  Widget build(BuildContext context) {
    // ── Sin score se enseña un GUION, no el par ────────────────────────────
    //
    // Se enseñaba el par en gris como pista de por dónde empiezan el − y el +.
    // Y se lee como un score: un jugador se quedó sin capturar el hoyo 4, su
    // círculo decía "4" —el par— y al lado el chip del acumulado decía "E",
    // porque iba a la par en los hoyos que SÍ tenía. Las dos cosas juntas se
    // leen como "hoyo 4 hecho en par", y nadie lo cazó hasta que un bloque de la
    // 2ª vuelta no salía y hubo que averiguar por qué.
    //
    // El guion no se puede confundir con nada. La pista se mantiene: tocar el
    // círculo sigue registrando el par, y el − y el + siguen partiendo de él.
    final displayScore = hasScore ? '$score' : '–';
    final displayColor = hasScore ? scoreColor : t.sub;
    final bgColor      = hasScore
        ? scoreColor.withValues(alpha: 0.15)
        : t.surface;
    final borderColor  = hasScore
        ? scoreColor.withValues(alpha: 0.5)
        : t.divider;
    final borderWidth  = hasScore ? 1.5 : 1.0;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      _stepBtn(Icons.remove, t.sub, onDec, t),
      const SizedBox(width: 4),
      GestureDetector(
        // Toque en el círculo cuando no hay score → registra el par
        onTap: hasScore ? null : onTapPar,
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          alignment: Alignment.center,
          child: Text(
            displayScore,
            style: TextStyle(
              color: displayColor,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      _stepBtn(Icons.add, t.primary, onInc, t),
    ]);
  }

  Widget _stepBtn(IconData ic, Color color, VoidCallback fn, GolfTheme t) {
    return GestureDetector(
      onTap: fn,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        alignment: Alignment.center,
        child: Icon(ic, size: 16, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEPPER DE PUTTS (inline en la tabla)
// ─────────────────────────────────────────────────────────────────────────────
class _PuttsStepper extends StatelessWidget {
  final int putts;
  final GolfTheme t;
  final VoidCallback onDec;
  final VoidCallback onInc;

  const _PuttsStepper({
    required this.putts, required this.t,
    required this.onDec, required this.onInc,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('PUTTS', style: TextStyle(color: t.sub, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      const SizedBox(height: 3),
      Row(mainAxisSize: MainAxisSize.min, children: [
        _btn(Icons.remove, onDec, t),
        SizedBox(
          width: 24,
          child: Text(
            '$putts',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        _btn(Icons.add, onInc, t),
      ]),
    ]);
  }

  Widget _btn(IconData ic, VoidCallback fn, GolfTheme t) => GestureDetector(
    onTap: fn,
    child: Container(
      width: 28, height: 28,
      alignment: Alignment.center,
      child: Icon(ic, size: 14, color: t.sub),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ZONA DEL JUGADOR ACTIVO — botones rápidos 2×3 + Units
// ─────────────────────────────────────────────────────────────────────────────
class _ActivePlayerZone extends StatefulWidget {
  final Round round;
  final String activePlayerId;
  final int hole;
  final CourseHole ch;
  final GolfTheme t;

  const _ActivePlayerZone({
    required this.round, required this.activePlayerId,
    required this.hole, required this.ch, required this.t,
  });

  @override
  State<_ActivePlayerZone> createState() => _ActivePlayerZoneState();
}

class _ActivePlayerZoneState extends State<_ActivePlayerZone> {
  static const _quickValues = [10.0, 25.0, 50.0, 100.0];
  final Map<UnitEventType, double> _values = {
    for (final e in UnitEventType.values) e: 25.0,
  };

  @override
  Widget build(BuildContext context) {
    final prov   = context.watch<RoundProvider>();
    final t      = widget.t;
    final par    = widget.ch.par;
    final score  = prov.round!.getScore(widget.activePlayerId, widget.hole);
    final gross  = score.grossScore ?? 0;
    final putts  = score.putts;
    final player = widget.round.players.firstWhere(
        (p) => p.id == widget.activePlayerId);

    // Nombre corto: player.name ya contiene el apodo/displayName asignado al crear la ronda
    // Para equipos virtuales, usar nombre completo
    final shortName = player.isVirtual ? player.name : player.name.split(' ').first;

    // Conteo de units activos
    final activeUnits = UnitEventType.values
        .where((e) => prov.hasEvent(widget.activePlayerId, widget.hole, e))
        .length;

    // Opciones rápidas de score: 3 por fila
    final options = [
      (par - 2, 'Eagle',  t.scoreUnder),
      (par - 1, 'Birdie', t.scoreUnder),
      (par,     'Par',    t.sub),
      (par + 1, 'Bogey',  t.scoreOver),
      (par + 2, 'Doble',  t.scoreOver),
      (par + 3, '+3',     t.scoreOver),
    ].where((o) => o.$1 >= 1).toList();

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Cabecera: jugador activo ────────────────────────────────────
        Row(children: [
          GAvatar(name: player.name, colorIndex: player.colorIndex, size: 22),
          const SizedBox(width: 6),
          // Flexible: con la etiqueta y "Borrar" al lado, un nombre largo se
          // salía 10 px a 320 px. Enésima vez que sale la misma forma.
          Flexible(
            child: Text(
              shortName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text('Score rápido', style: TextStyle(color: t.primary, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          // Borrar score
          if (score.hasScore)
            GestureDetector(
              onTap: () => prov.updateScore(widget.activePlayerId, widget.hole, null, 0),
              child: Text('Borrar', style: TextStyle(color: t.danger.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ]),
        const SizedBox(height: 10),

        // ── Botones rápidos 2×3 ─────────────────────────────────────────
        ...[ [0, 1, 2], [3, 4, 5] ].map((row) {
          final rowOptions = row
              .where((i) => i < options.length)
              .map((i) => options[i])
              .toList();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: rowOptions.map((o) {
              final scoreVal = o.$1;
              final label    = o.$2;
              final color    = o.$3;
              final isSel    = score.hasScore && gross == scoreVal;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => prov.updateScore(
                      widget.activePlayerId, widget.hole, scoreVal,
                      putts == 0 ? 2 : putts,
                    ),
                    child: AnimatedContainer(
                      duration: GolfMotion.instantaneo,
                      height: 58,
                      decoration: BoxDecoration(
                        color: isSel ? color : t.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSel ? color : t.divider,
                          width: isSel ? 2 : 1,
                        ),
                        boxShadow: isSel
                            ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          '$scoreVal',
                          style: TextStyle(
                            color: isSel ? Colors.white : t.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                        ),
                        Text(
                          label,
                          style: TextStyle(
                            color: isSel ? Colors.white.withValues(alpha: 0.85) : color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            }).toList()),
          );
        }),

        const SizedBox(height: 4),

        // ── Fila Units ──────────────────────────────────────────────────
        Row(children: [
          Text('UNITS', style: TextStyle(color: t.sub, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(width: 8),
          Expanded(child: _UnitsButton(
            player: player,
            hole: widget.hole,
            t: t,
            values: _values,
            quickValues: _quickValues,
            activeCount: activeUnits,
          )),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTÓN UNITS (igual que antes: abre sheet)
// ─────────────────────────────────────────────────────────────────────────────
class _UnitsButton extends StatefulWidget {
  final Player player;
  final int hole;
  final GolfTheme t;
  final Map<UnitEventType, double> values;
  final List<double> quickValues;
  final int activeCount;

  const _UnitsButton({
    required this.player, required this.hole, required this.t,
    required this.values, required this.quickValues, required this.activeCount,
  });

  @override
  State<_UnitsButton> createState() => _UnitsButtonState();
}

class _UnitsButtonState extends State<_UnitsButton> {
  late final Map<UnitEventType, double> _values;

  @override
  void initState() {
    super.initState();
    _values = Map<UnitEventType, double>.from(widget.values);
  }

  @override
  Widget build(BuildContext context) {
    final prov   = context.watch<RoundProvider>();
    final t      = widget.t;
    final active = UnitEventType.values
        .where((e) => prov.hasEvent(widget.player.id, widget.hole, e))
        .toList();

    return Row(children: [
      // Chips de units activos
      Expanded(
        child: active.isEmpty
            ? Text('Sin units', style: TextStyle(color: t.sub, fontSize: 12))
            : Wrap(spacing: 4, runSpacing: 4, children: active.map((e) {
                final v = _values[e]!;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.accent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${e.label}  \$${v.toStringAsFixed(0)}',
                    style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                );
              }).toList()),
      ),
      const SizedBox(width: 8),
      // Botón abrir sheet
      GestureDetector(
        onTap: () => _openUnitsSheet(context, prov),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active.isNotEmpty ? t.accent.withValues(alpha: 0.12) : t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active.isNotEmpty ? t.accent.withValues(alpha: 0.5) : t.divider,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_circle_outline,
                size: 15, color: active.isNotEmpty ? t.accent : t.sub),
            const SizedBox(width: 5),
            Text(
              active.isEmpty ? 'Units' : '${active.length} unit${active.length > 1 ? "s" : ""}',
              style: TextStyle(
                color: active.isNotEmpty ? t.accent : t.sub,
                fontSize: 12, fontWeight: FontWeight.w700,
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  void _openUnitsSheet(BuildContext outerCtx, RoundProvider outerProv) {
    final t = widget.t;
    showModalBottomSheet(
      context: outerCtx,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => ChangeNotifierProvider<RoundProvider>.value(
        value: outerProv,
        child: _UnitsSheetContent(
          playerId:    widget.player.id,
          playerName:  widget.player.name,
          hole:        widget.hole,
          t:           t,
          values:      _values,
          quickValues: widget.quickValues,
          onValueChange: (evt, v) => setState(() => _values[evt] = v),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RANKING OYES (par 3)
// ─────────────────────────────────────────────────────────────────────────────
class _OyesRankingSection extends StatelessWidget {
  final int hole;
  final GolfTheme t;
  const _OyesRankingSection({required this.hole, required this.t});

  @override
  Widget build(BuildContext context) {
    final prov     = context.watch<RoundProvider>();
    final round    = prov.round!;
    final ranking  = round.getOyese(hole);
    final ranked   = ranking?.ranking ?? [];
    // Solo personas: un equipo no pega un tiro de aproximación. En scramble
    // los virtuales estaban en la lista y se podía rankear a "Equipo A".
    final unranked = round.realPlayers.map((p) => p.id)
        .where((id) => !ranked.contains(id)).toList();

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.accent.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events, color: t.accent, size: 13),
              const SizedBox(width: 4),
              Text('RANKING OYES — Hoyo $hole',
                  style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
            ]),
          ),
          const Spacer(),
          if (ranked.isNotEmpty)
            GestureDetector(
              onTap: () => prov.setOyeseRanking(hole, []),
              child: Text('Limpiar', style: TextStyle(color: t.sub, fontSize: 10)),
            ),
        ]),
        const SizedBox(height: 10),

        if (ranked.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Toca un jugador para asignar 1°, 2°, 3°...',
              style: TextStyle(color: t.sub, fontSize: 12),
            ),
          ),

        if (ranked.isNotEmpty) ...[
          ...ranked.asMap().entries.map((e) {
            final p = round.players.firstWhere((pl) => pl.id == e.value);
            return _RankedPlayerTile(
              position: e.key + 1,
              player: p,
              t: t,
              onRemove: () {
                final newRanking = List<String>.from(ranked)..removeAt(e.key);
                prov.setOyeseRanking(hole, newRanking);
              },
            );
          }),
          const SizedBox(height: 6),
        ],

        if (unranked.isNotEmpty) ...[
          Text(
            ranked.isEmpty ? 'Selecciona el orden (1° = más cerca del hoyo):' : 'Sin posición:',
            style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: unranked.map((pid) {
            final p = round.players.firstWhere((pl) => pl.id == pid);
            return GestureDetector(
              onTap: () => prov.setOyeseRanking(hole, [...ranked, pid]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: t.primary.withValues(alpha: 0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  GAvatar(name: p.name, colorIndex: p.colorIndex, size: 22),
                  const SizedBox(width: 6),
                  Text(
                    '${p.name.split(' ').first}  +${ranked.length + 1}°',
                    style: TextStyle(color: t.primary, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ]),
              ),
            );
          }).toList()),
        ],
      ]),
    );
  }
}

class _RankedPlayerTile extends StatelessWidget {
  final int position;
  final Player player;
  final GolfTheme t;
  final VoidCallback onRemove;
  const _RankedPlayerTile({required this.position, required this.player, required this.t, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final posColors = [t.primary, t.sub, t.sub.withValues(alpha: 0.6)];
    final posColor  = posColors[position.clamp(1, 3) - 1];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: position == 1 ? t.primary.withValues(alpha: 0.4) : t.divider),
      ),
      child: Row(children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: posColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: posColor.withValues(alpha: 0.5)),
          ),
          alignment: Alignment.center,
          child: Text('$position°',
              style: TextStyle(color: posColor, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        GAvatar(name: player.name, colorIndex: player.colorIndex, size: 26),
        const SizedBox(width: 8),
        Expanded(child: Text(player.name,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13))),
        GestureDetector(
          onTap: onRemove,
          child: Icon(Icons.close, color: t.sub, size: 16),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UNITS SHEET CONTENT (igual que antes)
// ─────────────────────────────────────────────────────────────────────────────
class _UnitsSheetContent extends StatefulWidget {
  final String playerId;
  final String playerName;
  final int hole;
  final GolfTheme t;
  final Map<UnitEventType, double> values;
  final List<double> quickValues;
  final void Function(UnitEventType, double) onValueChange;

  const _UnitsSheetContent({
    required this.playerId, required this.playerName, required this.hole,
    required this.t, required this.values, required this.quickValues,
    required this.onValueChange,
  });

  @override
  State<_UnitsSheetContent> createState() => _UnitsSheetContentState();
}

class _UnitsSheetContentState extends State<_UnitsSheetContent> {
  // Sin copia local de los montos, a propósito.
  //
  // Antes había un _localValues mutable: el monto se podía cambiar durante la
  // ronda desde la tarjeta y esa copia ganaba sobre lo pactado en la apuesta.
  // Dos fuentes de verdad para el mismo número.
  //
  // La tarjeta registra QUÉ unidad ocurrió; cuánto vale se configura en la
  // apuesta. Misma distinción que scoreCarriersOf: una cosa es qué pasó y otra
  // cuánto vale lo que pasó.

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final t    = widget.t;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40, height: 4,
              decoration: BoxDecoration(color: t.divider, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                Icon(Icons.star_rounded, color: t.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Units — ${widget.playerName.split(' ').first}  •  Hoyo ${widget.hole}',
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Icon(Icons.close, color: t.sub, size: 20),
                ),
              ]),
            ),
            Divider(color: t.divider, height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: UnitEventType.values.length,
                itemBuilder: (_, i) {
                  final evt     = UnitEventType.values[i];
                  final isActive = prov.hasEvent(widget.playerId, widget.hole, evt);
                  // El monto viene de la apuesta y se MUESTRA, no se edita.
                  final selVal = widget.values[evt] ?? 25.0;

                  return _UnitRow(
                    evt: evt, isActive: isActive, selVal: selVal, t: t,
                    onToggle: () {
                      context.read<RoundProvider>().toggleEvent(
                          widget.playerId, widget.hole, evt);
                      setState(() {});
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: GPrimaryButton(label: 'Listo', onTap: () => Navigator.pop(ctx)),
            ),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UNIT ROW (igual que antes)
// ─────────────────────────────────────────────────────────────────────────────
class _UnitRow extends StatelessWidget {
  final UnitEventType evt;
  final bool isActive;
  final double selVal;
  final GolfTheme t;
  final VoidCallback onToggle;

  const _UnitRow({
    required this.evt, required this.isActive, required this.selVal,
    required this.t, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: GolfMotion.rapido,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? t.accent.withValues(alpha: 0.07) : t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? t.accent.withValues(alpha: 0.4) : t.divider),
      ),
      child: Column(children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              AnimatedContainer(
                duration: GolfMotion.rapido,
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isActive ? t.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isActive ? t.accent : t.sub.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: isActive ? Icon(Icons.check, color: Colors.white, size: 14) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(evt.label, style: TextStyle(
                  color: isActive ? t.text : t.sub,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  fontSize: 14,
                )),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('\$${selVal.toStringAsFixed(0)}',
                      style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
            ]),
          ),
        ),
        if (isActive) ...[
          Divider(color: t.divider.withValues(alpha: 0.6), height: 1, indent: 12, endIndent: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(children: [
              Text('Valor:', style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              // Se MUESTRA, no se edita: editarlo aquí creaba una segunda fuente
              // de verdad que ganaba sobre lo pactado en la apuesta.
              Text('\$${selVal.toStringAsFixed(0)}',
                  style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('se configura en la apuesta',
                  style: TextStyle(color: t.sub, fontSize: 10)),
            ]),
          ),
        ],
      ]),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// BOTONES DE NAVEGACIÓN PREV/NEXT HOYO
// ─────────────────────────────────────────────────────────────────────────────
class _HoleNavButtons extends StatelessWidget {
  final int current;
  final GolfTheme t;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onContinueTo18;
  final int? prevHole;
  final int? nextHole;
  final bool isLastOfFirstSegment;
  final bool isVeryLast;
  final bool isLast9;
  final bool is9HoleRound;
  final bool inSecondSegment;
  final int firstOfSecond;
  final StartingNine startingNine;

  const _HoleNavButtons({
    required this.current, required this.t, required this.startingNine,
    required this.firstOfSecond,
    this.onPrev, this.onNext, this.onContinueTo18,
    this.prevHole, this.nextHole,
    this.isLastOfFirstSegment = false, this.isVeryLast = false,
    this.isLast9 = false, this.is9HoleRound = false, this.inSecondSegment = false,
  });

  @override
  Widget build(BuildContext context) {
    final prevLabel = prevHole != null ? '← Hoyo $prevHole' : '←';

    if (isLast9) {
      return Column(children: [
        Row(children: [
          Expanded(child: _NavBtn(label: prevLabel, enabled: onPrev != null, t: t, onTap: onPrev)),
          const SizedBox(width: 8),
          Expanded(child: _NavBtn(label: '✓ Terminar', enabled: true, t: t, primary: true,
              onTap: () => _finishRound(context))),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: _NavBtn(
            label: '⛳ Continuar ${startingNine == StartingNine.back ? "Front 9" : "Back 9"} →',
            enabled: true, t: t, primary: false, onTap: onContinueTo18,
          ),
        ),
      ]);
    }

    final String nextLabel;
    if (isVeryLast) {
      nextLabel = '✓ Terminar';
    } else if (isLastOfFirstSegment) {
      nextLabel = '⛳ ${startingNine == StartingNine.back ? "Front 9 →" : "Back 9 →"}';
    } else {
      nextLabel = nextHole != null ? 'Hoyo $nextHole →' : '→';
    }

    return Row(children: [
      Expanded(child: _NavBtn(label: prevLabel, enabled: onPrev != null, t: t, onTap: onPrev)),
      const SizedBox(width: 8),
      Expanded(child: _NavBtn(
        label: nextLabel,
        enabled: onNext != null || isVeryLast,
        t: t, primary: true,
        onTap: onNext ?? (isVeryLast ? () => _finishRound(context) : null),
      )),
    ]);
  }

  Future<void> _finishRound(BuildContext context) async {
    final prov = context.read<RoundProvider>();
    final t    = prov.theme;

    // Solo el owner/admin puede finalizar una ronda en vivo
    if (prov.isLiveRound && !prov.isLiveOwner) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Solo el organizador puede finalizar la ronda.'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Text('Finalizar ronda', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        content: Text('Los resultados se guardarán en el historial y la ronda quedará cerrada.',
            style: TextStyle(color: t.sub)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: TextStyle(color: t.sub))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Finalizar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    // Capturar la ronda ANTES de que finishRound limpie el estado
    final round = prov.round;

    // Y los proveedores también, por lo mismo pero peor: cerrar quita la
    // pestaña Score, así que ESTA pantalla se destruye. Todo lo que se lea de
    // `context` después del await es tarde — es lo que dejaba el resultado sin
    // publicar, con la marca puesta y el seguimiento correcto.
    final tp = context.read<TorneoProvider>();
    final misTorneos = tp.torneos;
    final seguidos = tp.seguidos;
    final miFicha = context.read<UserProfileProvider>().profile?.myPlayerId;

    final ok = await prov.finishRound(
        misTorneos: misTorneos, seguidos: seguidos, miFicha: miFicha);
    if (!context.mounted) return;
    prov.setTab(0);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('⚠️ Sin conexión. La ronda se guardó localmente y se sincronizará cuando haya conexión.'),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 5),
      ));
    }

    // Mostrar diálogo de ajuste de sliding
    if (round != null && context.mounted) {
      await showSlidingAdjustmentDialog(context, round);
    }

    // Lo que pasó al enviar el resultado a los torneos. Se LEE del provider, no
    // se calcula aquí: el envío ya ocurrió dentro de finishRound y esta pantalla
    // puede estar destruida. Si no llega a enseñarse no se pierde nada — que era
    // justo el problema cuando el envío vivía aquí.
    final envios = prov.ultimosEnvios;
    if (envios.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(envios.map((e) => e.frase).join(' ')),
        duration: Duration(seconds: envios.any((e) => !e.enviado) ? 9 : 4),
      ));
      prov.limpiarEnvios();
    }

    // El enlace del torneo se refresca solo. Publicar por primera vez sigue
    // siendo una decisión; dejar la tabla vieja no debería serlo.
    if (round != null && context.mounted) {
      final refrescados = await republicarTorneosDe(context, round);
      if (refrescados.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(refrescados.length == 1
              ? 'Tabla de ${refrescados.first} actualizada para quien tenga el enlace.'
              : 'Tablas actualizadas: ${refrescados.join(', ')}.'),
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }
}

class _NavBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool primary;
  final GolfTheme t;
  final VoidCallback? onTap;
  const _NavBtn({required this.label, required this.enabled, required this.t,
      this.primary = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: !enabled
              ? t.surface.withValues(alpha: 0.5)
              : primary ? t.primary : t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: !enabled ? t.divider.withValues(alpha: 0.4) : primary ? t.primary : t.divider,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: !enabled ? t.sub.withValues(alpha: 0.4) : primary ? t.onPrimary : t.text,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ── Bola Baja / Bola Alta en el hoyo que se está jugando ─────────────────────
//
// Sin esto la regla "Acumular" es completamente invisible mientras se juega,
// que es justo cuando importa: saber que la bola baja vale 2 puntos en este
// hoyo cambia cómo lo juegas. Esa es la razón principal del bloque.
//
// Los datos salen del detalle por hoyo de BetEngine.lowHighBreakdown, el mismo
// recorrido que reparte los puntos. No se recalcula nada aquí.
class LowHighHoleBlock extends StatelessWidget {
  final Round round;
  final BetModuleInstance mod;
  final int hole;
  final GolfTheme t;

  const LowHighHoleBlock({
    super.key,
    required this.round,
    required this.mod,
    required this.hole,
    required this.t,
  });

  String _nombre(String id) => round.players
      .firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id))
      .name
      .split(' ')
      .first;

  /// La apuesta existe pero este hoyo no cae en ningún segmento liquidable.
  ///
  /// Pasa con configuraciones de campo donde la segmentación no cubre el hoyo.
  /// Se dice en vez de no dibujar nada: un bloque ausente parece "aquí no hay
  /// apuesta", y el jugador no tendría forma de saber que sí la hay.
  Widget _sinSegmento(int hole) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.divider),
        ),
        child: Row(children: [
          Icon(Icons.help_outline, color: t.sub, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${mod.type.label}: el hoyo $hole no entra en ningún segmento '
              'de esta apuesta, así que no suma puntos.',
              style: TextStyle(color: t.sub, fontSize: 11, height: 1.3),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final List<LowHighSegmentBreakdown> segs;
    try {
      segs = BetEngine.lowHighBreakdown(round, mod);
    } catch (_) {
      return const SizedBox.shrink();
    }

    // El segmento del hoyo actual, nunca el Overall: el marcador que interesa
    // mientras juegas es el de la vuelta en curso, y el Overall duplicaría los
    // mismos hoyos.
    LowHighSegmentBreakdown? seg;
    for (final s in segs) {
      if (s.segment == 'overall') continue;
      if (s.holes.contains(hole)) { seg = s; break; }
    }
    // Ronda de 9 hoyos: solo hay un segmento y sí es el bueno.
    seg ??= segs.where((s) => s.segment == 'nine' && s.holes.contains(hole)).firstOrNull;

    // Sin segmento resuelto para este hoyo, desaparecer sin más sería
    // indistinguible de "no hay apuesta de este tipo". La ausencia se explica.
    final h = seg?.resultForHole(hole);
    if (seg == null || h == null) return _sinSegmento(hole);

    final sideA = mod.sideA;
    final sideB = mod.sideB;
    final neto  = mod.lowHigh.mode == GrossNetMode.net;
    final p     = BetEngine.formatPoints;

    // Aviso de acumulado: lo primero que hay que ver.
    final avisos = <String>[
      if (h.lowCarry > 1) 'La bola baja vale ${p(h.lowCarry)} puntos en este hoyo',
      if (h.highCarry > 1) 'La bola alta vale ${p(h.highCarry)} puntos en este hoyo',
    ];

    Widget fila(String etiqueta, int? aVal, int? bVal, String? ganador) {
      final ganaA = ganador == 'a';
      final ganaB = ganador == 'b';
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(
            width: 58,
            child: Text(etiqueta,
                style: TextStyle(
                    color: t.sub, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(aVal?.toString() ?? '—',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: ganaA ? t.profit : t.text,
                    fontSize: 14,
                    fontWeight: ganaA ? FontWeight.w900 : FontWeight.w600)),
          ),
          SizedBox(
            width: 46,
            child: Text(
                !h.played ? '—' : (ganador == null ? 'empate' : (ganaA ? '◀' : '▶')),
                textAlign: TextAlign.center,
                style: TextStyle(color: t.sub, fontSize: 10)),
          ),
          Expanded(
            child: Text(bVal?.toString() ?? '—',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: ganaB ? t.profit : t.text,
                    fontSize: 14,
                    fontWeight: ganaB ? FontWeight.w900 : FontWeight.w600)),
          ),
        ]),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(mod.type.icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${mod.type.label} · hoyo $hole',
                style: TextStyle(
                    color: t.text, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          Text(neto ? 'NETO' : 'BRUTO',
              style: TextStyle(
                  color: t.sub, fontSize: 9, fontWeight: FontWeight.w800)),
        ]),

        // ── Acumulado pendiente ────────────────────────────────────────
        if (avisos.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...avisos.map((a) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: t.accent.withValues(alpha: 0.35)),
                ),
                child: Row(children: [
                  Icon(Icons.local_fire_department, color: t.accent, size: 13),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(a,
                        style: TextStyle(
                            color: t.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
              )),
        ],

        const SizedBox(height: 8),
        // Cabecera con los dos lados
        Row(children: [
          const SizedBox(width: 58),
          Expanded(
            child: Text(sideA.playerIds.map(_nombre).join(' + '),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: t.sub, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 46),
          Expanded(
            child: Text(sideB.playerIds.map(_nombre).join(' + '),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: t.sub, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),

        fila('BOLA BAJA', h.aLow, h.bLow, h.lowWinner),
        fila('BOLA ALTA', h.aHigh, h.bHigh, h.highWinner),

        // ── Hoyo incompleto ────────────────────────────────────────────
        if (!h.played) ...[
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.info_outline, color: t.sub, size: 12),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Faltan scores: el hoyo no se disputa hasta que anoten los '
                'cuatro, y el marcador no se mueve.',
                style: TextStyle(color: t.sub, fontSize: 10, height: 1.3),
              ),
            ),
          ]),
        ],

        const SizedBox(height: 8),
        Divider(height: 1, color: t.divider),
        const SizedBox(height: 6),
        // ── Marcador del segmento en curso ─────────────────────────────
        Row(children: [
          Expanded(
            child: Text(seg.label.replaceFirst('Bola Baja/Alta ', ''),
                style: TextStyle(
                    color: t.sub, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          Text('${p(seg.aTotal)} – ${p(seg.bTotal)}',
              style: TextStyle(
                  color: t.text, fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(width: 5),
          Text('puntos', style: TextStyle(color: t.sub, fontSize: 9)),
        ]),
      ]),
    );
  }
}

// ── Wolf: con quién jugó el Wolf en este hoyo ────────────────────────────────
//
// UNA pregunta, un toque, junto al score. Es todo lo que Wolf pide en el campo.
//
// Lo que NO hay, y es la decisión que hace este formato barato: no se pregunta
// quién es el Wolf —se deriva del orden de salida—, no hay máquina de decisión
// secuencial, no hay bloqueo de opciones tras cada tiro, no hay captura en
// tiempo real. Eso es lo que hacía a Wolf parecer caro y no era necesario.
//
// El nombre del Wolf se ENSEÑA porque orienta —"Wolf: RAFA"— pero no se pide. Y
// "Solo" es una opción más de la misma fila: ir en solitario es una de las
// cuatro respuestas posibles, no una pantalla aparte.
/// La pareja base y las parejas contra las que juega.
///
/// Solo informa: no hay nada que tocar. Y no depende del hoyo —la pareja base es
/// fija toda la ronda— así que se pinta una vez y no cambia al navegar.
class _ParejaBaseSection extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  const _ParejaBaseSection({required this.round, required this.t});

  @override
  Widget build(BuildContext context) {
    final p = _CaptureScreenState._parejaBase(round);
    if (p == null) return const SizedBox.shrink();

    String nombre(String pid) => round.players
        .firstWhere((x) => x.id == pid, orElse: () => Player(id: pid, name: pid))
        .name
        .split(' ')
        .first;

    String par(List<String> l) => l.map(nombre).join(' + ').toUpperCase();

    return Container(
      key: const Key('parejaBaseSection'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // La pareja base primero y sola: es lo constante de la ronda, y las
        // tres apuestas se entienden desde ella.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: t.text.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('🎲 PAREJA BASE: ${par(p.base)}',
              style: TextStyle(
                  color: t.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3)),
        ),
        const SizedBox(height: 7),
        // Wrap y no Row: tres parejas de nombres en una fila es la forma que ya
        // desbordó cinco veces en esta app.
        Wrap(
          spacing: 8,
          runSpacing: 5,
          children: [
            for (final r in p.rivales)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.divider),
                ),
                child: Text('vs ${par(r)}',
                    style: TextStyle(
                        color: t.text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
            'Juegan los ${p.rivales.length} a la vez. La pareja base está en '
            'todos, así que gana más y pierde más.',
            style: TextStyle(color: t.sub, fontSize: 10.5, height: 1.3)),
      ]),
    );
  }
}

/// El bloque de Sixes del hoyo actual: quién juega con quién, y desde dónde.
///
/// Solo informa. No hay nada que tocar aquí, y por eso no lleva borde de aviso
/// como el de Wolf: no puede faltar una respuesta que nadie tiene que dar.
class _SixesBloqueSection extends StatelessWidget {
  final int hole;
  final GolfTheme t;
  const _SixesBloqueSection({required this.hole, required this.t});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final round = prov.round!;
    final mods = _CaptureScreenState._sixesMods(round);
    if (mods.isEmpty) return const SizedBox.shrink();

    final (grupo, mod) = mods.first;
    final orden = round.participantesDe(mod, grupo.playerIds);
    // Una ronda guardada a la que se le saca un jugador llega aquí. El texto
    // sale de la misma tabla que atenúa el selector, así que no puede discrepar.
    final motivo = BetModuleType.sixes.motivoNoDisponible(orden.length);
    if (motivo != null) {
      return Container(
        key: const Key('sixesBloqueSection'),
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.scoreOver.withValues(alpha: 0.55)),
        ),
        child: Text(motivo,
            style: TextStyle(color: t.text, fontSize: 11.5, height: 1.35)),
      );
    }

    final n = mod.sixes.hoyosPorBloque;
    final bloque = SixesEngine.bloqueDelHoyo(hole, n);

    String nombre(String pid) => round.players
        .firstWhere((p) => p.id == pid, orElse: () => Player(id: pid, name: pid))
        .name
        .split(' ')
        .first;

    if (bloque == null) {
      // Los hoyos que sobran cuando la ronda no es múltiplo de tres bloques. No
      // se callan: un hoyo que no cuenta para la apuesta hay que saberlo.
      return Container(
        key: const Key('sixesBloqueSection'),
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.divider),
        ),
        child: Text(
            'Este hoyo no cuenta para Sixes: los tres bloques de $n hoyos '
            'acaban en el ${n * 3}.',
            style: TextStyle(color: t.sub, fontSize: 11.5, height: 1.35)),
      );
    }

    final (a, b) = SixesEngine.parejasDelBloque(orden, bloque);
    final desde = (bloque - 1) * n + 1;
    final hasta = bloque * n;

    return Container(
      key: const Key('sixesBloqueSection'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.divider),
      ),
      // Wrap y no Row: dos parejas de nombres con el "vs" en medio es
      // exactamente la forma que ya desbordó cuatro veces en esta app.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: t.text.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('🔄 BLOQUE $bloque · HOYOS $desde-$hasta',
                style: TextStyle(
                    color: t.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3)),
          ),
          Text(
              '${a.map(nombre).join(' + ').toUpperCase()}  vs  '
              '${b.map(nombre).join(' + ').toUpperCase()}',
              style: TextStyle(
                  color: t.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _WolfCallSection extends StatelessWidget {
  final int hole;
  final GolfTheme t;
  const _WolfCallSection({super.key, required this.hole, required this.t});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final round = prov.round!;
    final mods = _CaptureScreenState._wolfMods(round);
    if (mods.isEmpty) return const SizedBox.shrink();

    final (grupo, mod) = mods.first;
    final orden = round.participantesDe(mod, grupo.playerIds);
    final motivoTamano = BetModuleType.wolf.motivoNoDisponible(orden.length);
    if (motivoTamano != null) {
      // No debería pasar —el selector lo atenúa— pero una ronda guardada a la
      // que se le saca un jugador llega aquí, y quedarse mudo sería peor que
      // decirlo. El texto sale de la tabla, así que coincide con el del
      // selector.
      return _aviso(motivoTamano);
    }

    final wolf = WolfEngine.wolfDelHoyo(orden, hole);
    final call = round.getWolfCall(hole);
    final elegido = call?.partnerId;
    final esSolo = call != null && call.solo;

    String nombre(String pid) => round.players
        .firstWhere((p) => p.id == pid, orElse: () => Player(id: pid, name: pid))
        .name
        .split(' ')
        .first;

    final candidatos = orden.where((p) => p != wolf).toList();

    return Container(
      // Llave para los tests: los nombres de los jugadores también aparecen en
      // la tabla de arriba, así que buscarlos por texto apunta a la fila
      // equivocada. Lo descubrió el test.
      key: const Key('wolfCallSection'),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: call == null
                // Sin respuesta el borde avisa: este hoyo no liquida.
                ? t.scoreOver.withValues(alpha: 0.55)
                : t.divider),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: t.text.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('🐺 WOLF: ${nombre(wolf).toUpperCase()}',
                style: TextStyle(
                    color: t.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3)),
          ),
          const SizedBox(width: 8),
          // El estado va EN la cabecera, no en su propia línea.
          //
          // Medido: con cinco jugadores la última fila de la tabla se salía 17
          // px por abajo —841..861 con el viewport en 844— y esta línea con su
          // separación costaba justo eso. Plegarla la devuelve dentro sin tocar
          // el tamaño de los botones, que se usan con guante y no se recortan.
          Expanded(
            child: Text(
              call == null
                  ? '¿con quién jugó?'
                  : (esSolo
                      ? 'solo contra los otros ${orden.length - 1}'
                      : 'con ${nombre(elegido!)}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.sub, fontSize: 11.5),
            ),
          ),
          if (call != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => prov.setWolfCall(hole, limpiar: true),
              child:
                  Text('Limpiar', style: TextStyle(color: t.sub, fontSize: 10)),
            ),
        ]),
        const SizedBox(height: 10),
        // Wrap y no Row: son cuatro opciones con nombres de persona, y a 320 px
        // un Row las recorta. Es la misma lección que la fila de contadores del
        // tablero de Inicio, medida: las etiquetas ocupan más de lo que parece.
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final pid in candidatos)
            _WolfOpcion(
              key: ValueKey('wolfOpt_$pid'),
              texto: nombre(pid),
              activa: elegido == pid,
              t: t,
              onTap: () => prov.setWolfCall(hole, partnerId: pid),
            ),
          _WolfOpcion(
            key: const Key('wolfOpt_solo'),
            texto: 'Solo',
            activa: esSolo,
            t: t,
            destacada: true,
            onTap: () => prov.setWolfCall(hole, solo: true),
          ),
        ]),
      ]),
    );
  }

  Widget _aviso(String texto) => Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.scoreOver.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(12),
        child: Text(texto, style: TextStyle(color: t.sub, fontSize: 12)),
      );
}

class _WolfOpcion extends StatelessWidget {
  final String texto;
  final bool activa;
  final bool destacada;
  final GolfTheme t;
  final VoidCallback onTap;

  const _WolfOpcion({
    super.key,
    required this.texto,
    required this.activa,
    required this.t,
    required this.onTap,
    this.destacada = false,
  });

  @override
  Widget build(BuildContext context) {
    final acento = destacada ? t.accent : t.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        // Área de toque suficiente: se usa con guante, a una mano y entre golpe
        // y golpe.
        constraints: const BoxConstraints(minWidth: 68, minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: activa ? acento.withValues(alpha: 0.16) : t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: activa ? acento : t.divider, width: activa ? 1.6 : 1),
        ),
        child: Center(
          child: Text(
            texto,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: activa ? acento : t.sub,
              fontSize: 12.5,
              fontWeight: activa ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
