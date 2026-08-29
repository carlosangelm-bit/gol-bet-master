// ─────────────────────────────────────────────────────────────────────────────
// RESULTS SCREEN — Liquidación financiera centrada en jugadores (no en apuestas)
// Nivel 1: balance por jugador  (podio PGA premium — respeta modo claro/oscuro/clásico)
// Nivel 2: cara a cara          (pagos cinematográficos)
// Nivel 3: detalle expandible   (breakdown por tipo de apuesta)
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../engines/ledger_engine.dart';
import '../../engines/bet_engine.dart';
import '../../models/models.dart';
import '../torneos/republicar_al_cerrar.dart';
import '../../providers/round_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/sliding_adjustment_dialog.dart';
import '../../services/user_profile_service.dart';
import '../../engines/settlement_notes.dart';
import '../../widgets/notas_liquidacion_card.dart';
import '../../providers/torneo_provider.dart';
import '../../providers/user_profile_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: paleta de colores sólidos por estado — sin gradientes que desaparezcan
// ─────────────────────────────────────────────────────────────────────────────
class _ThemeGrad {
  final GolfTheme t;
  const _ThemeGrad(this.t);

  bool get isLight => t.brightness == Brightness.light;

  // ── Colores de superficie ──────────────────────────────────────────────────
  Color get scaffoldBg  => t.bg;
  Color get cardSurface => isLight ? Colors.white : const Color(0xFF1C1C1E);
  Color get cardBorder  => isLight ? const Color(0xFFE8E8EC) : const Color(0xFF2C2C30);

  // ── Header ────────────────────────────────────────────────────────────────
  // Gradiente sólido de arriba a abajo, siempre visible
  List<Color> get header => isLight
      ? [t.primary, t.primary.withValues(alpha: 0.82)]
      : [const Color(0xFF1A1A2E), const Color(0xFF16213E)];

  Color get headerText  => Colors.white;
  Color get headerSub   => Colors.white.withValues(alpha: 0.70);

  // ── Ganador hero ──────────────────────────────────────────────────────────
  List<Color> heroGrad(bool isPos) => isPos
      ? (isLight
          ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
          : [const Color(0xFF1B5E20), const Color(0xFF2E7D32)])
      : (isLight
          ? [const Color(0xFF7F0000), const Color(0xFFC62828)]
          : [const Color(0xFF7F0000), const Color(0xFFC62828)]);

  Color get heroText   => Colors.white;
  Color get heroSub    => Colors.white.withValues(alpha: 0.72);

  // ── Fila ranking compacta ─────────────────────────────────────────────────
  Color get rankBg     => cardSurface;
  Color get rankBorder => cardBorder;

  // ── Medallas ──────────────────────────────────────────────────────────────
  List<Color> get medal1 => [const Color(0xFFFFC107), const Color(0xFFFF8F00)];
  List<Color> get medal2 => [const Color(0xFFB0BEC5), const Color(0xFF78909C)];
  List<Color> get medal3 => [const Color(0xFFBF9660), const Color(0xFF8D6E3A)];
  List<Color> get medalN => [const Color(0xFF757575), const Color(0xFF616161)];
  List<Color> medalGrad(int rank) => rank == 1 ? medal1 : rank == 2 ? medal2 : rank == 3 ? medal3 : medalN;

  Color get medal1Shadow => const Color(0xFFFFC107).withValues(alpha: 0.45);

  // ── Monto ─────────────────────────────────────────────────────────────────
  Color amountHero(bool isPos) => Colors.white;
  Color amountRow(bool isPos)  => isPos ? t.profit : t.loss;

  // ── Chip balance duelo ────────────────────────────────────────────────────
  // El chip del balance es dinero puro, así que sus tres estados salen del
  // canal del dinero. Antes el "en ceros" usaba scoreUnder —el azul de bajo
  // par— metiendo el canal del score dentro del del dinero.
  Color chipBg(double bal) {
    if (bal == 0) return t.even.withValues(alpha: 0.15);
    return (bal > 0 ? t.profit : t.loss).withValues(alpha: 0.15);
  }
  Color chipBorder(double bal) {
    if (bal == 0) return t.even.withValues(alpha: 0.45);
    return (bal > 0 ? t.profit : t.loss).withValues(alpha: 0.45);
  }
  Color chipText(double bal) {
    if (bal == 0) return t.even;
    return bal > 0 ? t.profit : t.loss;
  }

  // ── Sección label ─────────────────────────────────────────────────────────
  Color get sectionColor => isLight ? t.primary : t.accent;

  // ── Transferencias ────────────────────────────────────────────────────────
  // Fondo con contraste sólido, no transparente
  List<Color> transferBg(bool isDark) => isDark
      ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
      : [const Color(0xFFF8F9FF), const Color(0xFFEEF0F8)];

  Color get transferBorder => isLight
      ? const Color(0xFFD0D5E8)
      : const Color(0xFF2A2A3E);

  /// El importe se pinta del color de QUIEN COBRA.
  ///
  /// Antes era indigo —#3D5AFE— en oscuro y clásico, y el primary en claro. Ese
  /// azul no pertenecía a ningún canal del sistema: ni dinero, ni identidad, ni
  /// estado. En clásico cantaba especialmente, con el resto de la pantalla en
  /// dorado y verde.
  ///
  /// Ahora el mismo elemento dice cuánto Y hacia dónde. Antes la dirección solo
  /// la daban la posición y las etiquetas PAGA/COBRA.
  List<Color> get amountPillBg =>
      [t.profit, t.profit.withValues(alpha: 0.80)];

  /// Blanco o casi negro según lo claro que sea el fondo del chip.
  ///
  /// Es una decisión de CONTRASTE, no de paleta: en clásico el profit es dorado
  /// y el texto blanco encima no se leería.
  Color get amountPillText => t.profit.computeLuminance() > 0.5
      ? const Color(0xFF1A1A1A)
      : Colors.white;

  // ── Duelo card ────────────────────────────────────────────────────────────
  Color get duelBg     => isLight ? const Color(0xFFF4F5F9) : const Color(0xFF1E1E24);
  Color get duelBorder => cardBorder;

  // ── Unidades ─────────────────────────────────────────────────────────────
  Color get unitChipBg     => t.accent.withValues(alpha: 0.12);
  Color get unitChipBorder => t.accent.withValues(alpha: 0.30);
  Color get unitAccent     => t.accent;

  // ── Botón cerrar ronda ───────────────────────────────────────────────────
  List<Color> get closeRoundGrad => isLight
      ? [Colors.white, Colors.white.withValues(alpha: 0.90)]
      : [const Color(0xFF2E7D32), const Color(0xFF1B5E20)];
  Color get closeRoundText => isLight ? t.primary : Colors.white;

  // ── Trofeo ───────────────────────────────────────────────────────────────
  Color get trophyColor => isLight ? Colors.white : t.accent;
}

// ─────────────────────────────────────────────────────────────────────────────
/// Expuesto para el barrido de color: el fondo del chip de importe en
/// Transferencias.
///
/// Se testea porque llevaba un indigo —#3D5AFE— que no pertenecía a ningún canal
/// del sistema, y un color fuera de paleta no lo detecta ningún grep: hay que
/// compararlo contra los canales.
List<Color> transferAmountBgForTest(GolfTheme t) => _ThemeGrad(t).amountPillBg;

Color transferAmountTextForTest(GolfTheme t) => _ThemeGrad(t).amountPillText;

class ResultsScreen extends StatefulWidget {
  /// Sin Scaffold ni SafeArea, para vivir dentro de una pestaña.
  ///
  /// La fase 5 fusiona Tarjeta y Resultados —las dos responden "cómo va la
  /// cosa"— en un solo destino con pestañas. Anidar dos Scaffold daría dos
  /// cabeceras, así que la pantalla necesita saber que está embebida.
  final bool embedded;

  const ResultsScreen({super.key, this.embedded = false});
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

    final sortedPlayers = getDisplayPlayers(round)
      ..sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));

    final g = _ThemeGrad(t);

    // ── Determinar si este usuario tiene cuenta registrada (linked) ──────────
    final myUid = AuthService.uid;
    final myLinkedPlayer = myUid != null
        ? round.players.where((p) =>
              p.linkedUserId == myUid && !p.isVirtual).firstOrNull
        : null;
    final iAmRegistered = myLinkedPlayer != null;

    // ── De quién es la cifra héroe ─────────────────────────────────────────
    //
    // 1º el vinculado, 2º el que se eligió y se recordó. Si no hay ninguno, el
    // héroe PREGUNTA en vez de adivinar: la app no sabe quién eres, así que lo
    // pide una vez.
    //
    // Se descartó caer al "jugador que está anotando": _activePlayerId es estado
    // local de la pantalla de captura, se pierde al salir y no está disponible
    // aquí. Subirlo al provider sería más trabajo del que el caso justifica.
    // 0º: el jugador que el PERFIL dice que eres. Es la respuesta durable —se
    // crea al registrarse y se corrige en Ajustes— y no depende de que esta
    // ronda tenga el vínculo escrito. Faltaba, así que en una ronda sin vínculo
    // la cifra héroe preguntaba teniendo la respuesta a mano.
    final delPerfil = UserProfileService.miJugadorId;
    final heroe = (delPerfil != null
            ? round.realPlayers.where((p) => p.id == delPerfil).firstOrNull
            : null) ??
        myLinkedPlayer ??
        (prov.heroPlayerId != null
            ? round.realPlayers
                .where((p) => p.id == prov.heroPlayerId)
                .firstOrNull
            : null);
    final adminFinished = prov.roundFinishedByAdmin;

    final cuerpo = Column(children: [
          // Banner: ronda finalizada por el admin (solo para invitados)
          if (adminFinished && !prov.isLiveOwner)
            _AdminFinishedBanner(
              t: t,
              iAmRegistered: iAmRegistered,
              onClose: () => _handleGuestClose(context, round, prov, iAmRegistered),
            ),
          _PGAHeader(round: round, t: t, g: g, prov: prov, onFinish: _confirmFinish),
          // La cifra héroe: UNA pregunta respondida arriba y en grande.
          //
          // El podio mostraba los cuatro jugadores por igual, así que la
          // pantalla apilaba varias respuestas sin declarar cuál es la
          // principal. Aquí la pregunta es "¿cuánto gano o pierdo YO?".
          _HeroNeto(
            round: round,
            jugador: heroe,
            balance: heroe == null ? null : (balances[heroe.id] ?? 0),
            t: t,
            onElegir: (pid) => prov.setHeroPlayer(pid),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Apuestas que el motor no pudo liquidar. Antes de todo:
                  // el podio de abajo NO las incluye, y sin este aviso un
                  // balance incompleto es indistinguible de uno correcto.
                  if (LedgerEngine.integrityErrors(round).isNotEmpty) ...[
                    _ResultsIntegrityBanner(
                        errors: LedgerEngine.integrityErrors(round), t: t),
                    const SizedBox(height: 20),
                  ],
                  // Y aparte, lo que SÍ se liquidó con otra regla de la pactada.
                  if (LedgerEngine.avisos(round).isNotEmpty) ...[
                    _AvisoVentajaNoAplicada(
                        avisos: LedgerEngine.avisos(round), t: t),
                    const SizedBox(height: 20),
                  ],

                  // Lo que las apuestas DICEN sin que sea un error: la
                  // serpiente que nadie agarró, el conejo suelto, el hoyo sin
                  // compañero. Tarjeta aparte del banner de integridad a
                  // propósito —ver notas_liquidacion_card.dart—.
                  if (notasDeLiquidacion(round).isNotEmpty) ...[
                    NotasLiquidacionCard(
                        notas: notasDeLiquidacion(round), t: t),
                    const SizedBox(height: 20),
                  ],

                  // Qué apuestas tiene la ronda y con qué cobertura de scores.
                  // Estaba solo en el detalle del Historial, así que desde la
                  // ronda en vivo no había forma de ver qué se está liquidando.
                  _RoundBetsSummary(round: round, t: t, g: g),
                  const SizedBox(height: 20),

                  // Resultado por equipos de los formatos que lo tienen. Va
                  // antes del ranking individual porque es lo que explica el
                  // dinero: el ranking dice cuánto, esto dice por qué.
                  ..._lowHighModules(round).map((m) =>
                      _LowHighTeamResult(round: round, mod: m, t: t, g: g)),

                  // NIVEL 1: Podio PGA
                  _PGAPodium(players: sortedPlayers, round: round, balances: balances, t: t, g: g),
                  const SizedBox(height: 28),

                  // NIVEL 2: Pagos directos
                  if (netDebts.isNotEmpty) ...[
                    _PGASectionLabel(label: 'TRANSFERENCIAS', icon: Icons.currency_exchange_rounded, g: g),
                    const SizedBox(height: 12),
                    ...netDebts.map((d) => _PGAPaymentCard(debt: d, round: round, t: t, g: g)),
                    const SizedBox(height: 28),
                  ],

                  // NIVEL 3: Detalle cara a cara
                  _PGASectionLabel(label: 'DETALLE POR JUGADOR', icon: Icons.analytics_outlined, g: g),
                  const SizedBox(height: 10),
                  ...sortedPlayers.map((p) => _PlayerDetailSection(
                    player: p, round: round, t: t, g: g,
                    isExpanded: _expandedPlayerId == p.id,
                    onToggle: () => setState(() =>
                      _expandedPlayerId = _expandedPlayerId == p.id ? null : p.id),
                  )),

                  // Sliding
                  if (round.sliding.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _PGASectionLabel(label: 'SLIDING', icon: Icons.swap_horiz_rounded, g: g),
                    const SizedBox(height: 10),
                    SlidingSummaryCard(round: round, t: t),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ]);

    // Embebida en una pestaña: sin Scaffold ni SafeArea, que los pone el
    // anfitrión. Anidarlos daría dos cabeceras y un doble recorte de notch.
    if (widget.embedded) return cuerpo;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(child: cuerpo),
    );
  }

  void _confirmFinish(BuildContext context, Round round, RoundProvider prov, GolfTheme t) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Finalizar ronda', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
      content: Text(
        'Los resultados se guardarán en el historial y la ronda quedará cerrada.',
        style: TextStyle(color: t.sub),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('Cancelar', style: TextStyle(color: t.sub))),
        TextButton(onPressed: () async {
          Navigator.pop(ctx);
          final roundSnapshot = prov.round;
                    // Los proveedores se leen AQUÍ, antes del await: después de cerrar,
          // esta pantalla puede estar destruida y `context` ya no vale. Es
          // exactamente lo que impedía que el resultado llegara al torneo.
          final _tp = context.read<TorneoProvider>();
          final _misTorneos = _tp.torneos;
          final _seguidos = _tp.seguidos;
          final _miFicha = context.read<UserProfileProvider>().profile?.myPlayerId;
          final ok = await prov.finishRound(
              misTorneos: _misTorneos, seguidos: _seguidos, miFicha: _miFicha);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('⚠️ Sin conexión. La ronda se guardó localmente y se sincronizará pronto.'),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 5),
            ));
          }
          // Sliding solo para usuarios con cuenta registrada (premium)
          final myUid = AuthService.uid;
          final myLinkedPlayer = myUid != null
              ? roundSnapshot?.players.where((p) =>
                    p.linkedUserId == myUid && !p.isVirtual).firstOrNull
              : null;
          if (roundSnapshot != null && myLinkedPlayer != null && context.mounted) {
            await showSlidingAdjustmentDialog(context, roundSnapshot);
          }
          // El enlace del torneo se refresca solo. Publicar por primera vez
          // sigue siendo una decisión; dejar la tabla vieja no debería serlo.
          if (roundSnapshot != null && context.mounted) {
            final refrescados =
                await republicarTorneosDe(context, roundSnapshot);
            if (refrescados.isNotEmpty && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(refrescados.length == 1
                    ? 'Tabla de ${refrescados.first} actualizada para quien tenga el enlace.'
                    : 'Tablas actualizadas: ${refrescados.join(', ')}.'),
                duration: const Duration(seconds: 4),
              ));
            }
          }
        }, child: Text('Finalizar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  /// Lógica para que el invitado cierre la ronda desde el banner de "admin finalizó"
  Future<void> _handleGuestClose(
    BuildContext context,
    Round round,
    RoundProvider prov,
    bool iAmRegistered,
  ) async {
    final t = prov.theme;
    // Mostrar diálogo de confirmación
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cerrar ronda', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        content: Text(
          iAmRegistered
              ? 'La ronda se guardará en tu historial y podrás actualizar tus ajustes de sliding.'
              : 'La ronda se cerrará. Puedes revisar los resultados finales antes de salir.',
          style: TextStyle(color: t.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: TextStyle(color: t.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cerrar', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final roundSnapshot = round;
    await prov.acknowledgeAdminFinish();

    // Sliding: solo para usuarios con cuenta registrada (funcionalidad premium)
    if (iAmRegistered && context.mounted) {
      await showSlidingAdjustmentDialog(context, roundSnapshot);
    }
  }
}

// ── Banner: el admin finalizó la ronda — aviso para invitados ─────────────────
class _AdminFinishedBanner extends StatelessWidget {
  final GolfTheme t;
  final bool iAmRegistered;
  final VoidCallback onClose;
  const _AdminFinishedBanner({
    required this.t,
    required this.iAmRegistered,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF8C00).withValues(alpha: 0.92),
            const Color(0xFFFF5722).withValues(alpha: 0.92),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        const Text('🏁', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El administrador finalizó la ronda',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Text(
                iAmRegistered
                    ? 'Presiona "Cerrar" para guardar los resultados y actualizar tu sliding.'
                    : 'Revisa los resultados finales y presiona "Cerrar" cuando quieras.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onClose,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child: Text(
              'Cerrar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Header con gradiente sólido siempre visible ───────────────────────────────
class _PGAHeader extends StatelessWidget {
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  final RoundProvider prov;
  final void Function(BuildContext, Round, RoundProvider, GolfTheme) onFinish;
  const _PGAHeader({required this.round, required this.t, required this.g,
      required this.prov, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: g.header,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(children: [
        // Ícono trofeo
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.emoji_events_rounded, color: g.trophyColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('RESULTADOS FINALES',
            style: TextStyle(
              color: g.headerText, fontWeight: FontWeight.w900,
              fontSize: 13, letterSpacing: 1.4,
            )),
          Text(round.name,
            style: TextStyle(color: g.headerSub, fontSize: 11),
            overflow: TextOverflow.ellipsis),
        ])),
        // Botón cerrar ronda — solo visible para el owner/admin de la ronda
        if (prov.isLiveOwner || !round.isLive)
          GestureDetector(
            onTap: () => onFinish(context, round, prov, t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: g.closeRoundGrad),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 8, offset: const Offset(0, 2),
                )],
              ),
              child: Text('Cerrar ronda',
                style: TextStyle(color: g.closeRoundText, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
      ]),
    );
  }
}

// ── Label de sección ──────────────────────────────────────────────────────────
class _PGASectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final _ThemeGrad g;
  const _PGASectionLabel({required this.label, required this.icon, required this.g});

  @override
  Widget build(BuildContext context) {
    final color = g.sectionColor;
    return Row(children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(
        color: color, fontSize: 10,
        fontWeight: FontWeight.w900, letterSpacing: 2.0,
      )),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.25))),
    ]);
  }
}

// ── Podio PGA ─────────────────────────────────────────────────────────────────
class _PGAPodium extends StatelessWidget {
  final List<Player> players;
  final Round round;
  final Map<String, double> balances;
  final GolfTheme t;
  final _ThemeGrad g;
  const _PGAPodium({required this.players, required this.round, required this.balances, required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (players.isNotEmpty)
        _WinnerHeroCard(player: players[0], round: round, balance: balances[players[0].id] ?? 0, rank: 1, t: t, g: g),
      if (players.length > 1) const SizedBox(height: 8),
      ...players.skip(1).toList().asMap().entries.map((e) {
        final rank = e.key + 2;
        final p    = e.value;
        final bal  = balances[p.id] ?? 0.0;
        return _RankingRow(rank: rank, player: p, round: round, balance: bal, t: t, g: g);
      }),
    ]);
  }
}

// ── Tarjeta hero: fondo de color sólido intenso, texto blanco ────────────────
class _WinnerHeroCard extends StatelessWidget {
  final Player player;
  final Round round;
  final double balance;
  final int rank;
  final GolfTheme t;
  final _ThemeGrad g;
  const _WinnerHeroCard({required this.player, required this.round, required this.balance, required this.rank,
      required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final isPos = balance >= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: g.heroGrad(isPos),
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
          color: (isPos ? const Color(0xFF1B5E20) : const Color(0xFF7F0000))
              .withValues(alpha: 0.40),
          blurRadius: 18, offset: const Offset(0, 6),
        )],
      ),
      child: Row(children: [
        // Medalla #1
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: g.medal1,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: g.medal1Shadow, blurRadius: 10)],
          ),
          child: const Center(
            child: Text('1', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20,
            )),
          ),
        ),
        const SizedBox(width: 14),
        GAvatar(name: player.name, colorIndex: player.colorIndex, size: 52),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          playerOrTeamName(
            player,
            round,
            style: TextStyle(color: g.heroText, fontWeight: FontWeight.w800, fontSize: 16),
            showTeamIcon: true,
          ),
          const SizedBox(height: 2),
          if (teamMembersFootnote(player, round, style: TextStyle(color: g.heroSub, fontSize: 10)) != null)
            teamMembersFootnote(player, round, style: TextStyle(color: g.heroSub, fontSize: 10))!
          else
            Text('HCP ${player.handicapBase.toStringAsFixed(0)}',
              style: TextStyle(color: g.heroSub, fontSize: 11)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
            ),
            child: Text(
              // Un saldo de exactamente cero no es cobrar ni pagar. Decir
              // "COBRA" sobre un \$0 hacía leer como resultado lo que en
              // realidad era una ronda sin liquidar.
              balance == 0 ? 'SIN SALDO' : (isPos ? 'LÍDER  ·  COBRA' : 'PAGA'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2,
              ),
            ),
          ),
        ])),
        // Balance grande en blanco sobre fondo oscuro
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '\$${balance.abs().toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 30,
            ),
          ),
          Text('MXN', style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 10, letterSpacing: 0.5,
          )),
        ]),
      ]),
    );
  }
}

// ── Fila ranking compacta ─────────────────────────────────────────────────────
class _RankingRow extends StatelessWidget {
  final int rank;
  final Player player;
  final Round round;
  final double balance;
  final GolfTheme t;
  final _ThemeGrad g;
  const _RankingRow({required this.rank, required this.player, required this.round, required this.balance,
      required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final isPos = balance >= 0;
    final medGrad = g.medalGrad(rank);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: g.rankBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: g.rankBorder, width: 1),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: g.isLight ? 0.04 : 0.18),
            blurRadius: 8, offset: const Offset(0, 2),
          )],
        ),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: medGrad,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text('$rank',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
          ),
          const SizedBox(width: 10),
          GAvatar(name: player.name, colorIndex: player.colorIndex, size: 38),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            playerOrTeamName(
              player,
              round,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
              showTeamIcon: false,
            ),
            if (teamMembersFootnote(player, round, style: TextStyle(color: t.sub, fontSize: 9)) != null)
              teamMembersFootnote(player, round, style: TextStyle(color: t.sub, fontSize: 9))!
            else
              Text('HCP ${player.handicapBase.toStringAsFixed(0)}',
                style: TextStyle(color: t.sub, fontSize: 10)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '\$${balance.abs().toStringAsFixed(0)}',
              style: TextStyle(
                color: g.amountRow(isPos),
                fontWeight: FontWeight.w800, fontSize: 19,
              ),
            ),
            Text(
              balance == 0 ? 'SIN SALDO' : (isPos ? 'COBRA' : 'PAGA'),
              style: TextStyle(
                color: g.amountRow(isPos).withValues(alpha: 0.70),
                fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Tarjeta de transferencia — diseño impactante ───────────────────────────────
class _PGAPaymentCard extends StatelessWidget {
  final NetDebt debt;
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  const _PGAPaymentCard({required this.debt, required this.round, required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final payer    = round.players.firstWhere((p) => p.id == debt.fromPlayerId);
    final receiver = round.players.firstWhere((p) => p.id == debt.toPlayerId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: g.transferBg(g.isLight ? false : true),
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: g.transferBorder, width: 1),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: g.isLight ? 0.06 : 0.28),
            blurRadius: 12, offset: const Offset(0, 4),
          )],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              // ── Pagador ──────────────────────────────────────────────────
              _TransferPlayer(
                player: payer,
                round: round,
                label: 'PAGA',
                labelColor: t.loss,
                t: t,
                g: g,
              ),

              // ── Centro: flecha + monto ────────────────────────────────────
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Monto en pill con gradiente sólido
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: g.amountPillBg,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(
                          color: g.amountPillBg.first.withValues(alpha: 0.40),
                          blurRadius: 10, offset: const Offset(0, 3),
                        )],
                      ),
                      child: Text(
                        '\$${debt.amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: g.amountPillText,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Flecha animada
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _ArrowDot(color: t.loss.withValues(alpha: 0.50)),
                      const SizedBox(width: 2),
                      _ArrowDot(color: t.loss.withValues(alpha: 0.75)),
                      const SizedBox(width: 2),
                      _ArrowDot(color: t.loss),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_forward_rounded, color: t.loss, size: 16),
                    ]),
                  ],
                ),
              ),

              // ── Cobrador ─────────────────────────────────────────────────
              _TransferPlayer(
                player: receiver,
                round: round,
                label: 'COBRA',
                labelColor: t.profit,
                t: t,
                g: g,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferPlayer extends StatelessWidget {
  final Player player;
  final Round round;
  final String label;
  final Color labelColor;
  final GolfTheme t;
  final _ThemeGrad g;
  const _TransferPlayer({
    required this.player, required this.round, required this.label, required this.labelColor,
    required this.t, required this.g,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: labelColor.withValues(alpha: 0.50), width: 2),
        ),
        child: GAvatar(name: player.name, colorIndex: player.colorIndex, size: 42),
      ),
      const SizedBox(height: 6),
      playerOrTeamName(
        player,
        round,
        style: TextStyle(
          color: t.text, fontSize: 12, fontWeight: FontWeight.w700,
        ),
        showTeamIcon: false,
      ),
      const SizedBox(height: 2),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: labelColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8,
          ),
        ),
      ),
    ]);
  }
}

class _ArrowDot extends StatelessWidget {
  final Color color;
  const _ArrowDot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 4, height: 4,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

// ── Nivel 3: Detalle por jugador expandible ───────────────────────────────────
class _PlayerDetailSection extends StatelessWidget {
  final Player player;
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  final bool isExpanded;
  final VoidCallback onToggle;
  const _PlayerDetailSection({
    required this.player, required this.round, required this.t, required this.g,
    required this.isExpanded, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: g.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded
                ? t.accent.withValues(alpha: 0.45)
                : g.cardBorder,
            width: isExpanded ? 1.5 : 1,
          ),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: g.isLight ? 0.04 : 0.20),
            blurRadius: 8, offset: const Offset(0, 2),
          )],
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(children: [
                  GAvatar(name: player.name, colorIndex: player.colorIndex, size: 36),
                  const SizedBox(width: 12),
                  Expanded(child: playerOrTeamName(
                    player,
                    round,
                    style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
                    showTeamIcon: false,
                  )),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.keyboard_arrow_down, color: t.sub, size: 22),
                  ),
                ]),
              ),
            ),
            if (isExpanded) ...[
              Divider(height: 1, color: g.cardBorder),
              _PlayerFaceToFace(player: player, round: round, t: t, g: g),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Cara a cara ───────────────────────────────────────────────────────────────
class _PlayerFaceToFace extends StatelessWidget {
  final Player player;
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  const _PlayerFaceToFace({required this.player, required this.round, required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final Set<String> bettingOpponentIds = {};
    bool playerHasUnitsModule = false;
    for (final group in round.betGroups) {
      for (final mod in group.modules) {
        final pids = mod.effectivePids(group.playerIds);
        if (!pids.contains(player.id)) continue;
        for (final pid in pids) {
          if (pid != player.id) bettingOpponentIds.add(pid);
        }
        if (mod.type == BetModuleType.units) playerHasUnitsModule = true;
      }
    }
    final opponents = round.players.where((p) => bettingOpponentIds.contains(p.id)).toList();

    final Map<UnitEventType, List<int>> unitsByType = {};
    if (playerHasUnitsModule) {
      // Iterar sobre los hoyos reales del curso (no 1..18 hardcoded),
      // para que startingNine=back encuentre los eventos en H10-H18.
      final holeNums = round.course.holes.map((ch) => ch.hole);
      for (final h in holeNums) {
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
          ...opponents.map((opp) {
            final breakdown = LedgerEngine.breakdownBetween(round, player.id, opp.id);

            for (final gr in round.betGroups) {
              if (!gr.playerIds.contains(player.id) || !gr.playerIds.contains(opp.id)) continue;
              for (final mod in gr.modules) {
                // Resolver participantIds efectivos del módulo (igual que BetEngine)
                final modPids = mod.effectivePids(gr.playerIds);
                // Solo procesar el módulo si aplica a AMBOS jugadores del par
                if (!modPids.contains(player.id) || !modPids.contains(opp.id)) continue;
                // ── Match + Press live balance ─────────────────────────────
                if (mod.type == BetModuleType.matchAutoPress) {
                  double mpLiveBal = 0.0;
                  final presses = BetEngine.matchAutoPressLive(round, player.id, opp.id, mod);
                  for (final pr in presses) {
                    if (pr.played == 0) continue;
                    if (pr.leadingPlayerId == player.id) mpLiveBal += pr.value;
                    if (pr.leadingPlayerId == opp.id) mpLiveBal -= pr.value;
                  }
                  breakdown[BetModuleType.matchAutoPress] = mpLiveBal;
                }
                // Nassau: sobreescribir con balance en vivo
                if (mod.type == BetModuleType.nassau) {
                  double npLiveBal = 0.0;
                  if (mod.pressEnabled) {
                    final st = BetEngine.nassauPressLiveStatus(round, player.id, opp.id, mod);
                    final isBack   = round.startingNine == StartingNine.back;
                    final seg1From = isBack ? 10 : 1;
                    final seg1To   = isBack ? 18 : 9;
                    if (st.frontPlayed > 0) {
                      if (st.front > 0) npLiveBal += st.frontVal;
                      if (st.front < 0) npLiveBal -= st.frontVal;
                    }
                    if (st.backPlayed > 0) {
                      if (st.back > 0) npLiveBal += st.backVal;
                      if (st.back < 0) npLiveBal -= st.backVal;
                    }
                    if (st.frontPlayed + st.backPlayed > 0) {
                      if (st.total > 0) npLiveBal += st.totalVal;
                      if (st.total < 0) npLiveBal -= st.totalVal;
                    }
                    for (final p in [...st.frontPresses, ...st.backPresses]) {
                      // Solo liquidar presses CERRADAS; las abiertas son apuestas pendientes
                      if (p.isOpen) continue;
                      final inSeg1   = p.startHole >= seg1From && p.startHole <= seg1To;
                      final pressVal = inSeg1 ? mod.nassau.frontPressValue : mod.nassau.backPressValue;
                      if (p.score > 0) npLiveBal += pressVal;
                      if (p.score < 0) npLiveBal -= pressVal;
                    }
                  } else {
                    final st = BetEngine.nassauLiveStatus(round, player.id, opp.id, mod);
                    if (st.frontPlayed > 0) {
                      if (st.front > 0) npLiveBal += st.frontVal;
                      if (st.front < 0) npLiveBal -= st.frontVal;
                    }
                    if (st.backPlayed > 0) {
                      if (st.back > 0) npLiveBal += st.backVal;
                      if (st.back < 0) npLiveBal -= st.backVal;
                    }
                    if (st.frontPlayed + st.backPlayed > 0) {
                      if (st.total > 0) npLiveBal += st.totalVal;
                      if (st.total < 0) npLiveBal -= st.totalVal;
                    }
                  }
                  breakdown[BetModuleType.nassau] = npLiveBal;
                }
              }
            }

            final balance = breakdown.values.fold<double>(0.0, (s, v) => s + v);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DuelCard(
                opponent: opp, balance: balance, breakdown: breakdown,
                player: player, round: round, t: t, g: g,
              ),
            );
          }),

          if (hasUnits) _UnitsDetailSection(
            player: player, round: round, unitsByType: unitsByType, t: t, g: g,
          ),
        ],
      ),
    );
  }
}

// ── Tarjeta de duelo cara a cara ──────────────────────────────────────────────
class _DuelCard extends StatelessWidget {
  final Player opponent;
  final double balance;
  final Map<BetModuleType, double> breakdown;
  final Player player;
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  const _DuelCard({
    required this.opponent, required this.balance, required this.breakdown,
    required this.player, required this.round, required this.t, required this.g,
  });

  @override
  Widget build(BuildContext context) {
    final order = [
      BetModuleType.skins,
      BetModuleType.nassau,
      BetModuleType.matchAutoPress,
      BetModuleType.medal,
      BetModuleType.putts,
      BetModuleType.oyeses,
      BetModuleType.units,
    ];
    final allTypes = order.where((type) {
      for (final gr in round.betGroups) {
        if (!gr.playerIds.contains(player.id) || !gr.playerIds.contains(opponent.id)) continue;
        // Verificar que exista un módulo de este tipo cuyos participantIds
        // efectivos incluyan a AMBOS jugadores del par (no solo al grupo).
        for (final m in gr.modules) {
          if (m.type != type) continue;
          if (m.containsPair(player.id, opponent.id)) return true;
        }
      }
      return false;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: g.duelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: g.duelBorder),
      ),
      child: Column(
        children: [
          // Cabecera del duelo
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(children: [
              GAvatar(name: opponent.name, colorIndex: opponent.colorIndex, size: 30),
              const SizedBox(width: 8),
              Expanded(child: Text(opponent.name,
                style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13))),
              // Balance chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: g.chipBg(balance),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: g.chipBorder(balance), width: 1),
                ),
                child: Text(
                  balance.abs() < 0.005
                      ? 'AS'
                      : '${balance > 0 ? '+' : ''}\$${balance.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: g.chipText(balance),
                    fontWeight: FontWeight.w900, fontSize: 14,
                  ),
                ),
              ),
            ]),
          ),

          // Desglose por módulo (filas compactas)
          if (allTypes.isNotEmpty) ...[
            Divider(height: 1, color: g.cardBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: allTypes.map((betType) {
                  final amount   = breakdown[betType] ?? 0.0;
                  final amtColor = amount > 0 ? t.profit : amount < 0 ? t.loss : t.sub;
                  final amtText  = amount.abs() < 0.005
                      ? 'AS'
                      : '${amount >= 0 ? '+' : ''}\$${amount.toStringAsFixed(0)}';

                  // Sub-detalle para Oyeses: marcador + zapato
                  String? oyesesDetail;
                  if (betType == BetModuleType.oyeses) {
                    // Buscar módulo de oyeses que incluya a ambos jugadores
                    BetModuleInstance? oyesMod;
                    for (final gr in round.betGroups) {
                      if (!gr.playerIds.contains(player.id) || !gr.playerIds.contains(opponent.id)) continue;
                      final found = gr.modules.where((m) => m.type == BetModuleType.oyeses).toList();
                      if (found.isNotEmpty) { oyesMod = found.first; break; }
                    }
                    if (oyesMod != null) {
                      final o = oyesMod.oyeses;
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
                        final ordered = ranking.ranking.where((pid) => [player.id, opponent.id].contains(pid)).toList();
                        if (ordered.length < 2) continue;
                        holesPlayed++;
                        if (ordered[0] == player.id) { oyes1++; winsP1vsP2++; }
                        else { oyes2++; winsP2vsP1++; }
                      }
                      final pName = player.shortName;
                      final oName = opponent.shortName;
                      String scoreLine = '$pName $oyes1 · $oyes2 $oName';
                      if (o.zapatoEnabled && holesPlayed == totalEligible && totalEligible > 0) {
                        final enoughHoles = o.zapatoRequires18 ? (totalEligible >= 3) : true;
                        if (enoughHoles) {
                          final zapatoAmt = o.zapatoValue > 0 ? o.zapatoValue : (totalEligible * o.value);
                          if (winsP1vsP2 == holesPlayed) {
                            scoreLine += '  ·  👟 +\$${zapatoAmt.toStringAsFixed(0)}';
                          } else if (winsP2vsP1 == holesPlayed) {
                            scoreLine += '  ·  👟 -\$${zapatoAmt.toStringAsFixed(0)}';
                          }
                        }
                      }
                      oyesesDetail = scoreLine;
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        // Icono y nombre del tipo de apuesta
                        Text(betType.icon, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(betType.label,
                          style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w500))),
                        // Barra de monto
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: amtColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(amtText,
                            style: TextStyle(
                              color: amtColor,
                              fontWeight: FontWeight.w800, fontSize: 12,
                            )),
                        ),
                      ]),
                      if (oyesesDetail != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 18, top: 2),
                          child: Text(oyesesDetail,
                            style: TextStyle(color: t.sub, fontSize: 10)),
                        ),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Unidades ganadas ───────────────────────────────────────────────────────────
class _UnitsDetailSection extends StatelessWidget {
  final Player player;
  final Round round;
  final Map<UnitEventType, List<int>> unitsByType;
  final GolfTheme t;
  final _ThemeGrad g;
  const _UnitsDetailSection({
    required this.player, required this.round,
    required this.unitsByType, required this.t, required this.g,
  });

  String _icon(UnitEventType type) => const {
    UnitEventType.birdie:       '🐦',
    UnitEventType.eagle:        '🦅',
    UnitEventType.sandyPar:     '🏖️',
    UnitEventType.parUnico:     '⭐',
    UnitEventType.birdieUnico:  '💫',
    UnitEventType.holeOut:      '🕳️',
  }[type]!;

  double _earnedFor(UnitEventType type) {
    double total = 0;
    for (final group in round.betGroups) {
      for (final mod in group.modules) {
        if (mod.type != BetModuleType.units) continue;
        final pids = mod.effectivePids(group.playerIds);
        if (!pids.contains(player.id)) continue;
        final holes = unitsByType[type] ?? [];
        final value = mod.units.valueFor(type);
        for (final _ in holes) {
          total += value * (pids.length - 1);
        }
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final totalUnits  = unitsByType.values.fold<int>(0, (sum, holes) => sum + holes.length);
    final totalEarned = unitsByType.keys.fold<double>(0, (sum, type) => sum + _earnedFor(type));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: g.unitChipBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: g.unitChipBorder),
        ),
        child: Row(children: [
          const Text('💫', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text('UNIDADES GANADAS',
            style: TextStyle(color: g.unitAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: g.unitAccent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$totalUnits unit${totalUnits != 1 ? 's' : ''}  ·  \$${totalEarned.toStringAsFixed(0)}',
              style: TextStyle(color: g.unitAccent, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),

      ...unitsByType.entries.map((entry) {
        final type   = entry.key;
        final holes  = List<int>.from(entry.value)..sort();
        final count  = holes.length;
        final earned = _earnedFor(type);

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: g.cardBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_icon(type), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(type.label,
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('×$count',
                    style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 11)),
                ),
                const SizedBox(width: 8),
                Text(
                  earned > 0 ? '+\$${earned.toStringAsFixed(0)}' : '\$0',
                  style: TextStyle(
                    color: earned > 0 ? t.profit : t.sub,
                    fontWeight: FontWeight.w800, fontSize: 13,
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 5, runSpacing: 4, children: holes.map((h) {
                final par = round.course.holes
                    .firstWhere((ch) => ch.hole == h, orElse: () => round.course.holes.first).par;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: g.unitChipBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: g.unitChipBorder),
                  ),
                  child: Text('H$h · P$par',
                    style: TextStyle(color: g.unitAccent, fontSize: 10, fontWeight: FontWeight.w700)),
                );
              }).toList()),
            ]),
          ),
        );
      }),
    ]);
  }
}

// ── ResultsBody reutilizable (historial) ─────────────────────────────────────
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
    final g = _ThemeGrad(t);
    final round = widget.round;
    final balances = LedgerEngine.playerBalances(round);
    final netDebts = LedgerEngine.compute(round);
    final sortedPlayers = getDisplayPlayers(round)
      ..sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));

    // Apuestas que no se pudieron liquidar. Va ARRIBA del balance a propósito:
    // sin esto, una apuesta rota se ve como un balance de $0 perfectamente
    // normal, y el usuario no tiene forma de saber que falta dinero. El aviso
    // existía solo en la pestaña de Apuestas, que no es donde se leen los
    // números finales.
    final integrityErrors = LedgerEngine.integrityErrors(round);
    final avisos = LedgerEngine.avisos(round);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (avisos.isNotEmpty) ...[
          _AvisoVentajaNoAplicada(avisos: avisos, t: t),
          const SizedBox(height: 12),
        ],
        if (integrityErrors.isNotEmpty) ...[
          _ResultsIntegrityBanner(errors: integrityErrors, t: t),
          const SizedBox(height: 16),
        ],
        // Qué apuestas tiene la ronda. Va antes del balance porque un balance
        // en ceros no dice si nadie ganó nada o si la apuesta que se creía
        // configurada no llegó a la ronda — y no había ninguna pantalla donde
        // consultarlo en una ronda ya terminada.
        _RoundBetsSummary(round: round, t: t, g: g),
        const SizedBox(height: 20),

        ..._lowHighModules(round).map((m) =>
            _LowHighTeamResult(round: round, mod: m, t: t, g: g)),

        _PGASectionLabel(label: 'BALANCE FINAL', icon: Icons.emoji_events_rounded, g: g),
        const SizedBox(height: 10),
        _PGAPodium(players: sortedPlayers, round: round, balances: balances, t: t, g: g),
        const SizedBox(height: 20),
        if (netDebts.isNotEmpty) ...[
          _PGASectionLabel(label: 'TRANSFERENCIAS', icon: Icons.currency_exchange_rounded, g: g),
          const SizedBox(height: 12),
          ...netDebts.map((d) => _PGAPaymentCard(debt: d, round: round, t: t, g: g)),
          const SizedBox(height: 20),
        ],
        _PGASectionLabel(label: 'DETALLE POR JUGADOR', icon: Icons.analytics_outlined, g: g),
        const SizedBox(height: 10),
        ...sortedPlayers.map((p) => _PlayerDetailSection(
          player: p, round: round, t: t, g: g,
          isExpanded: _expandedPlayerId == p.id,
          onToggle: () => setState(() =>
            _expandedPlayerId = _expandedPlayerId == p.id ? null : p.id),
        )),

        if (round.sliding.isNotEmpty) ...[
          const SizedBox(height: 20),
          _PGASectionLabel(label: 'SLIDING', icon: Icons.swap_horiz_rounded, g: g),
          const SizedBox(height: 10),
          SlidingSummaryCard(round: round, t: t),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }
}

// ── Aviso de apuestas sin liquidar ───────────────────────────────────────────
//
// El motor descarta un módulo que no puede calcular y deja constancia en
// LedgerEngine.integrityErrors. Sin mostrarlo aquí, el usuario ve un balance de
// $0 indistinguible de "nadie debe nada" — que en una app de apuestas es la
// peor forma de fallar.
class _ResultsIntegrityBanner extends StatelessWidget {
  final List<String> errors;
  final GolfTheme t;
  const _ResultsIntegrityBanner({required this.errors, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.danger.withValues(alpha: 0.40)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: t.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errors.length == 1
                  ? '1 apuesta no se pudo liquidar'
                  : '${errors.length} apuestas no se pudieron liquidar',
              style: TextStyle(
                  color: t.danger, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'El balance de abajo NO las incluye.',
          style: TextStyle(color: t.loss, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 10),
        ...errors.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('· ', style: TextStyle(color: t.loss, fontSize: 12)),
                Expanded(
                  child: Text(e,
                      style: TextStyle(
                          color: t.danger, fontSize: 12, height: 1.35)),
                ),
              ]),
            )),
      ]),
    );
  }
}

// ── Qué apuestas tiene la ronda ──────────────────────────────────────────────
//
// Una ronda terminada no tenía ninguna pantalla que dijera qué se jugó. Si el
// balance sale en ceros no hay forma de distinguir "nadie ganó nada" de "la
// apuesta que configuré no llegó a la ronda" — que es un fallo real y frecuente,
// porque al iniciar sin partidas configuradas la app crea una Nassau por defecto.
class _RoundBetsSummary extends StatefulWidget {
  final Round round;
  final GolfTheme t;
  final _ThemeGrad g;
  const _RoundBetsSummary({required this.round, required this.t, required this.g});

  @override
  State<_RoundBetsSummary> createState() => _RoundBetsSummaryState();
}

/// Arranca colapsada: es contexto, no la respuesta de la pantalla.
///
/// Con una excepción que no se puede plegar: si alguna apuesta no tiene score
/// de todos sus jugadores, el balance de abajo está incompleto. Ese aviso sube
/// a la cabecera, porque esconder un problema detrás de un "ver más" es
/// exactamente cómo se pierde media sesión buscando por qué el balance da cero.
class _RoundBetsSummaryState extends State<_RoundBetsSummary> {
  bool _abierto = false;

  Round get round => widget.round;
  GolfTheme get t => widget.t;
  _ThemeGrad get g => widget.g;

  String _nombre(String id) => round.players
      .firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id))
      .name
      .split(' ')
      .first;

  /// Nombre legible de un jugador, incluidos los virtuales de equipo. Cae al
  /// id si no se encuentra: un id feo en pantalla dice más que un hueco.
  String _nombreCorto(String pid) {
    for (final p in round.players) {
      if (p.id == pid) return p.name;
    }
    return pid;
  }

  /// Jugadores cuyos scores necesita esta apuesta para liquidar.
  ///
  /// Delega en Round.scoreCarriersOfModule en vez de re-derivarlo: preguntar
  /// por sideX.playerIds daba los reales, que en scramble no anotan, y el
  /// aviso de apuesta incompleta quedaba encendido para siempre.
  List<String> _jugadoresDe(BetGroup grp, BetModuleInstance m) =>
      round.scoreCarriersOfModule(m, grp.playerIds);

  @override
  Widget build(BuildContext context) {
    final mods = [
      for (final grp in round.betGroups)
        for (final m in grp.modules) (grp, m),
    ];

    // Apuestas a las que les falta algún hoyo completo. Se calcula aquí y no
    // dentro del desplegable porque el aviso tiene que verse esté abierto o no.
    //
    // El aviso NOMBRA a quién le falta. "No tiene score de todos sus
    // jugadores" describe el síntoma y esconde el dato: en una ronda por
    // equipos la diferencia entre que falte una persona real y que falte el
    // jugador virtual del equipo es la diferencia entre "sigue capturando" y
    // "la apuesta está mal armada". Sin el nombre hay que salir a buscarlo por
    // fuera de la app.
    // Se agrupan por TIPO, no una línea por módulo.
    //
    // Una apuesta expandida en módulos 1v1 —porque un cruce quedó fuera o pactó
    // otro importe— daba seis líneas casi idénticas: "Nassau · falta CAM, CAV",
    // "Nassau · falta CAM, AAM"… Seis avisos del mismo problema no informan seis
    // veces mejor; entierran el resto de la pantalla.
    //
    // Es el mismo colapso que la ficha de la regla, en otra superficie: los N
    // módulos son UNA apuesta.
    final porTipo = <BetModuleType, ({int duelos, Set<String> faltan})>{};
    for (final e in mods) {
      final (grp, m) = e;
      final pids = _jugadoresDe(grp, m);
      final faltan = <String>{};
      var completos = 0;
      for (final ch in round.course.holes) {
        var lleno = true;
        for (final pid in pids) {
          if (!round.getScore(pid, ch.hole).hasScore) {
            lleno = false;
            faltan.add(_nombreCorto(pid));
          }
        }
        if (lleno) completos++;
      }
      if (completos >= round.course.holes.length) continue;
      final previo = porTipo[m.type];
      porTipo[m.type] = (
        duelos: (previo?.duelos ?? 0) + 1,
        faltan: {...?previo?.faltan, ...faltan},
      );
    }

    final incompletas = [
      for (final e in porTipo.entries)
        e.value.duelos > 1
            // Con varios módulos del mismo tipo, quién falta se repite en todos:
            // lo que informa es CUÁNTOS duelos están sin cerrar.
            ? '${e.key.label} · sin score en ${e.value.duelos} duelos'
            : '${e.key.label} · falta ${e.value.faltan.join(', ')}',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: g.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: g.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Cabecera tocable ────────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _abierto = !_abierto),
          borderRadius: BorderRadius.circular(8),
          child: Row(children: [
            Icon(Icons.receipt_long_outlined, color: g.sectionColor, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text('APUESTAS DE ESTA RONDA',
                  style: TextStyle(
                      color: g.sectionColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6)),
            ),
            Text(
                mods.isEmpty
                    ? 'ninguna'
                    : '${mods.length} apuesta${mods.length == 1 ? "" : "s"}',
                style: TextStyle(
                    color: t.sub, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(_abierto ? Icons.expand_less : Icons.expand_more,
                color: g.sectionColor, size: 18),
          ]),
        ),

        // ── Aviso de cobertura: NO se pliega ────────────────────────────
        // Si falta score de algún jugador, el balance de abajo está incompleto.
        // Esconderlo detrás del desplegable es cómo se pierde media sesión
        // buscando por qué el balance da cero.
        if (incompletas.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.error_outline, color: t.danger, size: 13),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                incompletas.length == 1
                    ? 'Sin score completo en ${incompletas.first}'
                    : 'Sin score completo:\n${incompletas.join('\n')}',
                style: TextStyle(color: t.danger, fontSize: 11, height: 1.3),
              ),
            ),
          ]),
        ],

        if (!_abierto) const SizedBox.shrink() else ...[
        const SizedBox(height: 10),

        if (mods.isEmpty)
          Text('Esta ronda se jugó sin apuestas configuradas.',
              style: TextStyle(color: t.sub, fontSize: 12))
        else ...[
          ...mods.map((e) {
            final (grp, m) = e;
            final pids = _jugadoresDe(grp, m);
            final quien = m.hasTeamSides
                ? '${m.sideA.playerIds.map(_nombre).join(" + ")}'
                    '  vs  ${m.sideB.playerIds.map(_nombre).join(" + ")}'
                : pids.length == 2
                    ? '${_nombre(pids[0])} vs ${_nombre(pids[1])}'
                    : '${pids.length} jugadores';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.type.icon, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.type.label,
                            style: TextStyle(
                                color: t.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 1),
                        Text(quien,
                            style: TextStyle(color: t.sub, fontSize: 11)),
                      ]),
                ),
                if (m.hasTeamSides)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: g.sectionColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('EQUIPOS',
                        style: TextStyle(
                            color: g.sectionColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800)),
                  ),
              ]),
            );
          }),

          // ── Cobertura de scores ──────────────────────────────────────────
          //
          // Una apuesta solo liquida los hoyos donde TODOS sus jugadores
          // anotaron. Sin este dato, una que no paga por falta de scores es
          // indistinguible de una que no paga porque todo quedó empatado.
          Divider(height: 18, color: g.cardBorder),
          ...mods.map((e) {
            final (grp, m) = e;
            final pids = _jugadoresDe(grp, m);
            final holes = round.course.holes;
            final completos = holes
                .where((ch) =>
                    pids.every((pid) => round.getScore(pid, ch.hole).hasScore))
                .length;
            final total = holes.length;
            final falta = completos < total;

            // Cuántos hoyos anotó CADA jugador. Con solo el total no se sabe
            // si falta un jugador entero o un hoyo suelto de varios, que son
            // problemas distintos y se arreglan distinto.
            final porJugador = {
              for (final pid in pids)
                pid: holes
                    .where((ch) => round.getScore(pid, ch.hole).hasScore)
                    .length,
            };
            // Hoyos donde falta alguien, para poder ir directo a corregirlos.
            final huecos = holes
                .where((ch) => !pids
                    .every((pid) => round.getScore(pid, ch.hole).hasScore))
                .map((ch) => ch.hole)
                .toList();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                          falta
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: falta ? t.danger : t.profit,
                          size: 13),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${m.type.label}: $completos de $total hoyos con '
                          'score de sus ${pids.length} jugadores',
                          style: TextStyle(
                              color: falta ? t.danger : t.sub, fontSize: 11),
                        ),
                      ),
                    ]),
                    if (falta) ...[
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.only(left: 19),
                        child: Text(
                          porJugador.entries
                              .map((e) => '${_nombre(e.key)} ${e.value}')
                              .join('  ·  '),
                          style: TextStyle(color: t.sub, fontSize: 10),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 19, top: 2),
                        child: Text(
                          'Hoyos incompletos: '
                          '${huecos.take(12).join(", ")}'
                          '${huecos.length > 12 ? "…" : ""}',
                          style: TextStyle(color: t.sub, fontSize: 10),
                        ),
                      ),
                    ],
                  ]),
            );
          }),
        ],
        ],
      ]),
    );
  }
}


/// Módulos de Bola Baja / Bola Alta con equipos válidos.
///
/// Se comparte entre las DOS vistas de resultados —la de la ronda en vivo y la
/// del detalle en Historial— porque ya me pasó dos veces poner la información
/// en una sola y dar por hecho que era la que se usaba.
List<BetModuleInstance> _lowHighModules(Round round) => [
      for (final g in round.betGroups)
        for (final m in g.modules)
          if (m.type == BetModuleType.nassauLowHigh && m.hasTeamSides) m,
    ];

// ── Resultado por equipos: Bola Baja / Bola Alta ─────────────────────────────
//
// El ranking individual de abajo sigue siendo el que manda para pagar —el
// dinero se mueve persona a persona— pero no explica NADA del formato: no
// muestra los puntos de bola baja y alta, ni el desglose por segmento, que es
// la esencia del juego.
//
// Los números salen de BetEngine.lowHighBreakdown, que consume el mismo
// recorrido que la liquidación. No hay un segundo cálculo de puntos.
class _LowHighTeamResult extends StatefulWidget {
  final Round round;
  final BetModuleInstance mod;
  final GolfTheme t;
  final _ThemeGrad g;
  const _LowHighTeamResult({
    required this.round, required this.mod, required this.t, required this.g,
  });

  @override
  State<_LowHighTeamResult> createState() => _LowHighTeamResultState();
}

/// Arranca COLAPSADO a propósito.
///
/// Resultados apilaba cuatro representaciones del mismo hecho —ranking,
/// transferencias, detalle por jugador y tabla por segmento— sin que ninguna
/// se declarara principal. La pantalla responde una pregunta: cuánto gano o
/// pierdo. El desglose de cómo se llegó ahí es una segunda pregunta, y va bajo
/// demanda.
class _LowHighTeamResultState extends State<_LowHighTeamResult> {
  bool _abierto = false;

  Round get round => widget.round;
  BetModuleInstance get mod => widget.mod;
  GolfTheme get t => widget.t;
  _ThemeGrad get g => widget.g;

  String _nombre(String id) => round.players
      .firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id))
      .name
      .split(' ')
      .first;

  @override
  Widget build(BuildContext context) {
    final List<LowHighSegmentBreakdown> segs;
    try {
      segs = BetEngine.lowHighBreakdown(round, mod);
    } catch (_) {
      // Configuración inválida: el banner de integridad ya lo explica arriba.
      return const SizedBox.shrink();
    }
    if (segs.isEmpty) return const SizedBox.shrink();

    final cfg = mod.lowHigh;
    final sideA = mod.sideA;
    final sideB = mod.sideB;
    final muestraPuntos = cfg.pointBetEnabled;

    // Neto de toda la apuesta desde la perspectiva del lado A.
    var netoA = 0.0;
    for (final s in segs) {
      if (!s.isTie) netoA += s.diff > 0 ? s.total : -s.total;
    }

    Widget celda(String txt, {bool fuerte = false, Color? color, int flex = 1}) =>
        Expanded(
          flex: flex,
          child: Text(txt,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color ?? (fuerte ? t.text : t.sub),
                fontSize: 11,
                fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: g.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: g.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Encabezado: los dos lados ────────────────────────────────────
        Row(children: [
          Text(mod.type.icon, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(mod.type.label,
                style: TextStyle(
                    color: t.text, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: g.sectionColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
                cfg.mode == GrossNetMode.net ? 'NETO' : 'BRUTO',
                style: TextStyle(
                    color: g.sectionColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          '${sideA.name} · ${sideA.playerIds.map(_nombre).join(" + ")}'
          '   vs   ${sideB.name} · ${sideB.playerIds.map(_nombre).join(" + ")}',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),

        // ── Resultado, siempre visible ──────────────────────────────────
        // Cerrada, la tarjeta ya responde: quién paga a quién y cuánto. Abrir
        // es para ver CÓMO se llegó ahí, que es otra pregunta.
        const SizedBox(height: 10),
        InkWell(
          onTap: () => setState(() => _abierto = !_abierto),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Text(
                  netoA == 0
                      ? 'Sin saldo entre equipos'
                      : '${netoA > 0 ? sideB.name : sideA.name} paga '
                          '\$${netoA.abs().toStringAsFixed(0)} a '
                          '${netoA > 0 ? sideA.name : sideB.name}',
                  style: TextStyle(
                      color: netoA == 0 ? t.even : t.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              Text(_abierto ? 'Ocultar' : 'Ver desglose',
                  style: TextStyle(
                      color: g.sectionColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 2),
              Icon(_abierto ? Icons.expand_less : Icons.expand_more,
                  color: g.sectionColor, size: 18),
            ]),
          ),
        ),

        if (!_abierto) const SizedBox.shrink() else ...[
        const SizedBox(height: 12),

        // ── Cabecera de la tabla ─────────────────────────────────────────
        Row(children: [
          Expanded(flex: 3, child: Text('SEGMENTO',
              style: TextStyle(
                  color: t.sub, fontSize: 9, fontWeight: FontWeight.w800))),
          celda('BAJA A'), celda('ALTA A'), celda('A', fuerte: true),
          celda('BAJA B'), celda('ALTA B'), celda('B', fuerte: true),
          if (muestraPuntos) celda('PTOS', flex: 2),
          celda('NETO', flex: 3),
        ]),
        Divider(height: 12, color: g.cardBorder),

        // ── Una fila por segmento ────────────────────────────────────────
        ...segs.map((s) {
          final ganaA = !s.isTie && s.diff > 0;
          final colorNeto = s.isTie ? t.sub : (ganaA ? t.profit : t.loss);
          final p = BetEngine.formatPoints;
          return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Text(
                  s.label.replaceFirst('Bola Baja/Alta ', ''),
                  style: TextStyle(
                      color: t.text, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              celda(p(s.aLow)), celda(p(s.aHigh)),
              celda(p(s.aTotal), fuerte: true, color: ganaA ? t.profit : null),
              celda(p(s.bLow)), celda(p(s.bHigh)),
              celda(p(s.bTotal),
                  fuerte: true, color: (!s.isTie && !ganaA) ? t.profit : null),
              if (muestraPuntos)
                celda(s.pointAmount > 0
                        ? '\$${s.pointAmount.toStringAsFixed(0)}'
                        : '—',
                    flex: 2),
              Expanded(
                flex: 3,
                child: Text(
                  // Un segmento empatado se muestra explícitamente, no se omite.
                  s.isTie
                      ? 'Empate'
                      : '${ganaA ? sideA.name : sideB.name} '
                          '\$${s.total.toStringAsFixed(0)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: colorNeto,
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ]),
          );
        }),

        const SizedBox(height: 6),
        Text(
          'El pago se reparte entre los cruces de ambos lados; el desglose por '
          'jugador está más abajo.',
          style: TextStyle(color: t.sub, fontSize: 10, height: 1.3),
        ),
        ],
      ]),
    );
  }
}


// ── Cifra héroe de Resultados ───────────────────────────────────────────────
//
// Responde "¿cuánto gano o pierdo yo?" en una cifra grande, y subordina el resto
// de la pantalla en vez de apilarlo todo al mismo tamaño.
//
// Es TOCABLE para cambiar de jugador, que resuelve el caso real de pasarse el
// teléfono entre el grupo para que cada uno vea lo suyo.
class _HeroNeto extends StatelessWidget {
  final Round round;

  /// De quién es la cifra. null = todavía no se sabe, y entonces se pregunta.
  final Player? jugador;

  final double? balance;
  final GolfTheme t;
  final void Function(String pid) onElegir;

  const _HeroNeto({
    required this.round,
    required this.jugador,
    required this.balance,
    required this.t,
    required this.onElegir,
  });

  @override
  Widget build(BuildContext context) {
    // Sin jugador resuelto se PREGUNTA, no se adivina ni se deja vacío. Una
    // pantalla sin héroe vuelve al problema que esto viene a arreglar.
    if (jugador == null) return _preguntar();

    final b = balance ?? 0;
    // El canal del dinero: cobrar y pagar nunca son el mismo color, y "en ceros"
    // tiene su propio token porque es un resultado, no un dato ausente.
    final color = b > 0 ? t.profit : (b < 0 ? t.loss : t.even);
    final signo = b > 0 ? '+' : (b < 0 ? '−' : '');

    return GestureDetector(
      // Toda el área, no solo el número.
      behavior: HitTestBehavior.opaque,
      onTap: () => _elegir(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(children: [
          Text('$signo\$${b.abs().toStringAsFixed(0)}',
              style: GolfType.hero(color)),
          const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
                b > 0
                    ? 'COBRAS · ${jugador!.name.split(' ').first}'
                    : b < 0
                        ? 'PAGAS · ${jugador!.name.split(' ').first}'
                        : 'EN CEROS · ${jugador!.name.split(' ').first}',
                style: GolfType.label(t.sub)),
            const SizedBox(width: 5),
            // Que se puede cambiar tiene que VERSE, o nadie lo intenta.
            Icon(Icons.unfold_more_rounded, size: 13, color: t.sub),
          ]),
        ]),
      ),
    );
  }

  Widget _preguntar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¿Cuál eres?', style: GolfType.title(t.text)),
          const SizedBox(height: 2),
          Text('Para mostrar tu neto arriba. Se recuerda durante la ronda.',
              style: GolfType.label(t.sub)),
          const SizedBox(height: 9),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in round.realPlayers)
              GestureDetector(
                onTap: () => onElegir(p.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: t.divider),
                  ),
                  child: Text(p.name.split(' ').first,
                      style: GolfType.body(t.text)),
                ),
              ),
          ]),
        ]),
      );

  void _elegir(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 14),
          Text('¿De quién es el neto?', style: GolfType.body(t.text)),
          const SizedBox(height: 4),
          Text('Para que cada uno vea lo suyo al pasarse el teléfono.',
              style: GolfType.label(t.sub)),
          const SizedBox(height: 10),
          for (final p in round.realPlayers)
            ListTile(
              title: Text(p.name, style: GolfType.body(t.text)),
              trailing: p.id == jugador?.id
                  ? Icon(Icons.check, color: t.primary, size: 18)
                  : null,
              onTap: () {
                onElegir(p.id);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }
}


// ── Aviso INFORMATIVO: la ventaja que el formato no aplica ───────────────────
//
// Distinto del banner de integridad, y la diferencia es toda la cuestión:
// aquel dice "falta dinero en el balance de abajo", este dice "el balance está
// completo, pero una regla que pactaron no se usó".
//
// Nacieron juntos y el resultado fue un banner rojo anunciando "3 apuestas no se
// pudieron liquidar" cuando era UNA y sí se liquidó. Un aviso informativo en el
// canal de las alarmas gasta la alarma: la próxima vez que de verdad falte
// dinero, ya nadie la mira.
class _AvisoVentajaNoAplicada extends StatelessWidget {
  final List<String> avisos;
  final GolfTheme t;
  const _AvisoVentajaNoAplicada({required this.avisos, required this.t});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.primary.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline, color: t.primary, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  avisos.length == 1
                      ? 'Una ventaja pactada no aplica en este formato'
                      : '\${avisos.length} ventajas pactadas no aplican en este formato',
                  style: TextStyle(
                      color: t.text, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('El dinero de abajo está completo: la apuesta SÍ se liquidó.',
              style: TextStyle(color: t.sub, fontSize: 11.5)),
          const SizedBox(height: 9),
          for (final a in avisos)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('· \$a',
                  style: TextStyle(color: t.text, fontSize: 12, height: 1.35)),
            ),
        ]),
      );
}
