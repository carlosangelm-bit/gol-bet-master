// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN — Pantalla principal: iniciar ronda, estado de ronda activa
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/live_round_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/bet_module_edit_sheet.dart';
import '../../widgets/sliding_adjustment_dialog.dart';
import '../setup/setup_screen.dart';
import '../templates/templates_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<LiveRoundInvitation> _pendingInvitations = [];
  StreamSubscription<List<LiveRoundInvitation>>? _invSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenInvitations());
  }

  void _listenInvitations() {
    _invSub?.cancel();
    _invSub = LiveRoundService.pendingInvitationsStream().listen((list) {
      if (mounted) setState(() => _pendingInvitations = list);
    });
  }

  @override
  void dispose() {
    _invSub?.cancel();
    super.dispose();
  }

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
            // Banner de invitaciones pendientes.
            // IMPORTANTE: se pasa 'context' de HomeScreen (estable) como
            // stableContext para que el diálogo pueda llamar a joinLiveRound
            // incluso después de que la tarjeta de invitación se desmonte
            // (ocurre cuando el stream emite la lista sin la inv. aceptada).
            if (_pendingInvitations.isNotEmpty)
              _InvitationsBanner(
                invitations: _pendingInvitations,
                t: t,
                stableContext: context,
                onAccepted: () => setState(() {}),
              ),
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
    return _HomeHeader(t: t, prov: prov);
  }
}

// ── Header premium con fondo verde y logo ────────────────────────────────────
class _HomeHeader extends StatelessWidget {
  final GolfTheme t;
  final RoundProvider prov;
  const _HomeHeader({required this.t, required this.prov});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final userName = auth.user?.displayName?.split(' ').first ?? '';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D2B0F),
            Color(0xFF1A3A1C),
            Color(0xFF1E4620),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Fondo decorativo
          Positioned.fill(child: CustomPaint(painter: _HeaderBgPainter())),

          // Contenido
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fila logo + controles
                Row(
                  children: [
                    // Logo
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 12, offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: const Color(0xFFD4A520).withValues(alpha: 0.20),
                            blurRadius: 16, spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset('assets/icon/logo_main.png', fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Nombre app
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Golf Bet Master',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              letterSpacing: -0.3,
                              shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
                            ),
                          ),
                          if (userName.isNotEmpty)
                            Text(
                              'Hola, $userName',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Live indicator
                    if (prov.isLiveRound) ...[_LiveIndicator(t: t), const SizedBox(width: 8)],
                    // Theme selector
                    _ThemeToggle(t: t),
                  ],
                ),

                // Nombre de ronda activa
                if (prov.hasRound) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sports_golf_rounded,
                            color: Colors.white.withValues(alpha: 0.8), size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            prov.round!.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'EN CURSO',
                          style: TextStyle(
                            color: const Color(0xFF69F0AE).withValues(alpha: 0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Pintor del fondo del header
class _HeaderBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Glow dorado detrás del logo (esquina superior izquierda)
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFD4A520).withValues(alpha: 0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.12, size.height * 0.3),
          radius: size.width * 0.5));
    canvas.drawCircle(
        Offset(size.width * 0.12, size.height * 0.3),
        size.width * 0.5,
        glowPaint);

    // Líneas decorativas tipo ondas de fairway
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (int i = 0; i < 4; i++) {
      final path = Path();
      final y = size.height * (0.2 + i * 0.25);
      path.moveTo(0, y);
      for (double x = 0; x <= size.width; x += 24) {
        path.quadraticBezierTo(x + 12, y - 6, x + 24, y);
      }
      canvas.drawPath(path, linePaint);
    }

    // Círculos decorativos (representan hoyos)
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    final rng = math.Random(7);
    for (int i = 0; i < 12; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 2.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Indicador de ronda en vivo ─────────────────────────────────────────────
class _LiveIndicator extends StatefulWidget {
  final GolfTheme t;
  const _LiveIndicator({required this.t});
  @override State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: _anim.value * 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: _anim.value),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text('EN VIVO',
            style: TextStyle(
              color: Colors.red.withValues(alpha: _anim.value),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            )),
        ]),
      ),
    );
  }
}

// ── Banner de invitaciones pendientes ──────────────────────────────────────
class _InvitationsBanner extends StatelessWidget {
  final List<LiveRoundInvitation> invitations;
  final GolfTheme t;
  final VoidCallback onAccepted;
  // Contexto estable de HomeScreen: sobrevive aunque las tarjetas se desmonten.
  final BuildContext stableContext;
  const _InvitationsBanner({
    required this.invitations,
    required this.t,
    required this.stableContext,
    required this.onAccepted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: invitations.map((inv) => _InvitationCard(
          inv: inv, t: t, stableContext: stableContext, onAccepted: onAccepted,
        )).toList(),
      ),
    );
  }
}

class _InvitationCard extends StatefulWidget {
  final LiveRoundInvitation inv;
  final GolfTheme t;
  final VoidCallback onAccepted;
  // Contexto estable de HomeScreen pasado desde _InvitationsBanner.
  // NO usar el contexto propio de la tarjeta como parentContext del diálogo:
  // cuando acceptInvitation() actualiza Firestore, el stream emite la lista
  // sin esta invitación y Flutter desmonta la tarjeta mientras el diálogo
  // sigue abierto. Si el diálogo intenta usar el contexto de la tarjeta,
  // parentContext.mounted es false y joinLiveRound() nunca se llama.
  final BuildContext stableContext;
  const _InvitationCard({
    required this.inv,
    required this.t,
    required this.stableContext,
    required this.onAccepted,
  });
  @override State<_InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends State<_InvitationCard> {
  bool _loading = false;

  // Abre el diálogo usando widget.stableContext (HomeScreen) como parentContext.
  void _showJoinDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _JoinRoundDialog(
        inv: widget.inv,
        t: widget.t,
        parentContext: widget.stableContext,   // ← FIX: contexto de HomeScreen, no de la tarjeta
        onAccepted: widget.onAccepted,
        onDecline: () {
          Navigator.pop(ctx);
          _decline();
        },
      ),
    );
  }

  Future<void> _decline() async {
    await LiveRoundService.declineInvitation(widget.inv);
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final inv = widget.inv;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.primary.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [BoxShadow(color: t.primary.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        // Ícono
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: t.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.wifi_tethering_rounded, color: t.primary, size: 22),
        ),
        const SizedBox(width: 12),
        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
              child: Text('EN VIVO', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            ),
            const SizedBox(width: 6),
            Text(inv.liveCode,
              style: TextStyle(color: t.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 3),
          Text(inv.roundName,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13),
            overflow: TextOverflow.ellipsis),
          Text('${inv.ownerName} · ${inv.courseName}',
            style: TextStyle(color: t.sub, fontSize: 11),
            overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 8),
        // Botones
        if (_loading)
          SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.primary))
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            // Rechazar
            GestureDetector(
              onTap: _decline,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.divider),
                ),
                child: Icon(Icons.close_rounded, color: t.sub, size: 18),
              ),
            ),
            const SizedBox(width: 6),
            // Aceptar → abre diálogo de confirmación
            GestureDetector(
              onTap: _showJoinDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: t.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Unirse',
                  style: TextStyle(color: t.onPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
      ]),
    );
  }
}

// ── Diálogo de confirmación para unirse a ronda en vivo ──────────────────────
class _JoinRoundDialog extends StatefulWidget {
  final LiveRoundInvitation inv;
  final GolfTheme t;
  final BuildContext parentContext;   // contexto de HomeScreen para el provider
  final VoidCallback onAccepted;
  final VoidCallback onDecline;
  const _JoinRoundDialog({
    required this.inv,
    required this.t,
    required this.parentContext,
    required this.onAccepted,
    required this.onDecline,
  });
  @override State<_JoinRoundDialog> createState() => _JoinRoundDialogState();
}

class _JoinRoundDialogState extends State<_JoinRoundDialog> {
  bool _joining = false;
  String? _error;

  Future<void> _doJoin() async {
    // Verificar si ya hay una ronda en vivo activa antes de continuar
    if (widget.parentContext.mounted) {
      final prov = widget.parentContext.read<RoundProvider>();
      if (prov.hasRound && prov.isLiveRound && !(prov.round?.isFinished ?? true)) {
        // Mostrar alerta de confirmación: ya está en otra ronda en vivo
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ya estás en una ronda en vivo'),
            content: Text(
              'Estás participando en "${prov.round?.name ?? 'Ronda activa'}". '
              '¿Deseas salir de esa ronda y unirte a "${widget.inv.roundName}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Sí, cambiar de ronda',
                  style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
        if (confirm != true) return; // El usuario canceló
      }
    }

    setState(() { _joining = true; _error = null; });
    try {
      final round = await LiveRoundService.acceptInvitation(widget.inv);
      if (!mounted) return;
      if (round != null) {
        // 1. Cerrar el diálogo PRIMERO, antes de modificar el provider
        Navigator.of(context).pop();
        // 2. Pequeña pausa para que el diálogo termine de cerrarse
        await Future.delayed(const Duration(milliseconds: 150));
        // 3. Cargar ronda en el provider (el contexto del padre debe seguir válido)
        if (widget.parentContext.mounted) {
          widget.parentContext.read<RoundProvider>().joinLiveRound(round);
          widget.onAccepted();
        }
      } else {
        setState(() {
          _joining = false;
          _error = 'No se pudo cargar la ronda. Intenta de nuevo.';
        });
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[_doJoin] Error: $e\n$st');
      if (mounted) {
        setState(() {
          _joining = false;
          _error = 'Error al unirse: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.inv;
    final t   = widget.t;
    return Dialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Encabezado EN VIVO
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('EN VIVO · ${inv.liveCode}',
                  style: const TextStyle(color: Colors.red, fontSize: 11,
                      fontWeight: FontWeight.w800, letterSpacing: 1)),
              ]),
            ),
            const SizedBox(height: 16),
            // Nombre de la ronda
            Text(inv.roundName,
              style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(inv.courseName,
              style: TextStyle(color: t.sub, fontSize: 13),
              textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Organiza: ${inv.ownerName}',
              style: TextStyle(color: t.sub, fontSize: 12)),
            const SizedBox(height: 12),
            // Jugadores
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Jugadores', style: TextStyle(color: t.sub, fontSize: 11,
                    fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...inv.playerNames.map((name) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(Icons.person_outline, color: t.primary, size: 14),
                    const SizedBox(width: 6),
                    Text(name, style: TextStyle(color: t.text, fontSize: 13)),
                  ]),
                )),
              ]),
            ),
            const SizedBox(height: 20),
            // Error
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
            ],
            // Botones
            if (_joining)
              Column(children: [
                SizedBox(
                  width: 28, height: 28,
                  child: CircularProgressIndicator(color: t.primary, strokeWidth: 2.5),
                ),
                const SizedBox(height: 8),
                Text('Cargando ronda...', style: TextStyle(color: t.sub, fontSize: 12)),
              ])
            else
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onDecline,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.sub,
                      side: BorderSide(color: t.divider),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _doJoin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.primary,
                      foregroundColor: t.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Entrar a la ronda',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
          ],
        ),
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
      child: Column(
        children: [
          // ── Hero section premium ────────────────────────────────────────
          _HeroSection(t: t),

          // ── Card de acciones ────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'Empieza a jugar',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Configura jugadores, apuestas y registra tus scores',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.sub,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // Botón principal – Nueva Ronda
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SetupScreen())),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A520),
                      foregroundColor: const Color(0xFF0D2B0F),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      shadowColor: const Color(0xFFD4A520).withValues(alpha: 0.4),
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                    label: const Text(
                      'Nueva Ronda',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Botón secundario – Usar plantilla
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TemplatesScreen())),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: t.primary.withValues(alpha: 0.5)),
                      foregroundColor: t.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: Icon(Icons.library_books_outlined, size: 18, color: t.primary),
                    label: Text(
                      'Usar plantilla',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: t.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Sección de apuestas disponibles
                _QuickInfoCards(t: t),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sección hero premium con logo y fondo verde ───────────────────────────────
class _HeroSection extends StatelessWidget {
  final GolfTheme t;
  const _HeroSection({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0D2B0F),
            Color(0xFF1A3A1C),
            Color(0xFF1E4620),
            Color(0xFF245527),
          ],
          stops: [0.0, 0.4, 0.75, 1.0],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          // Fondo decorativo completo
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              child: CustomPaint(painter: _HeroBgPainter()),
            ),
          ),

          // Contenido centrado
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 36, 32, 40),
            child: Column(
              children: [
                // ── Logo con glow dorado ──────────────────────────────────
                Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: const Color(0xFFD4A520).withValues(alpha: 0.35),
                        blurRadius: 36,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/icon/logo_main.png', fit: BoxFit.cover),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Título ───────────────────────────────────────────────
                const Text(
                  'Golf Bet Master',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'La forma inteligente de gestionar\ntus apuestas en el campo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Badges ───────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _badge('⛳', 'Golf'),
                    const SizedBox(width: 10),
                    _badge('💰', 'Apuestas'),
                    const SizedBox(width: 10),
                    _badge('🏆', 'Resultados'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(icon, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ]),
  );
}

// ── Pintor del fondo del hero ─────────────────────────────────────────────────
class _HeroBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Glow dorado central detrás del logo
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFD4A520).withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.28),
          radius: size.width * 0.55));
    canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.28),
        size.width * 0.55,
        glowPaint);

    // Glow secundario esquina superior derecha
    final glow2 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF4CAF50).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.9, size.height * 0.1),
          radius: size.width * 0.4));
    canvas.drawCircle(
        Offset(size.width * 0.9, size.height * 0.1),
        size.width * 0.4,
        glow2);

    // Líneas decorativas tipo ondas de fairway
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (int i = 0; i < 5; i++) {
      final path = Path();
      final y = size.height * (0.15 + i * 0.18);
      path.moveTo(0, y);
      for (double x = 0; x <= size.width; x += 30) {
        path.quadraticBezierTo(x + 15, y - 8, x + 30, y);
      }
      canvas.drawPath(path, linePaint);
    }

    // Puntos decorativos (hoyos del campo)
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    final rng = math.Random(42);
    for (int i = 0; i < 18; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 2.2, dotPaint);
    }

    // Arco decorativo inferior (transición suave)
    final arcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    final arcPath = Path()
      ..moveTo(0, size.height * 0.85)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.72, size.width, size.height * 0.85)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(arcPath, arcPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Sección de apuestas disponibles con detalle expandible ───────────────────
class _QuickInfoCards extends StatelessWidget {
  final GolfTheme t;
  const _QuickInfoCards({required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: t.divider, height: 1),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'APUESTAS DISPONIBLES',
                style: TextStyle(
                  color: t.sub,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Text(
              'Toca + para ver detalles',
              style: TextStyle(color: t.sub.withValues(alpha: 0.6), fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._BetInfo.all.map((info) => _BetExpandableCard(t: t, info: info)),
      ],
    );
  }
}

// ── Modelo de datos para cada apuesta ───────────────────────────────────────
class _BetInfo {
  final IconData icon;
  final Color color;
  final String name;
  final String tagline;
  final String howItWorks;
  final List<String> rules;
  final String example;

  const _BetInfo({
    required this.icon,
    required this.color,
    required this.name,
    required this.tagline,
    required this.howItWorks,
    required this.rules,
    required this.example,
  });

  static const List<_BetInfo> all = [
    _BetInfo(
      icon: Icons.attach_money_rounded,
      color: Color(0xFF2E7D32),
      name: 'Nassau',
      tagline: 'La apuesta clásica del golf',
      howItWorks:
          'Tres apuestas independientes en una: ganas el Front 9 (hoyos 1-9), '
          'el Back 9 (hoyos 10-18) y el Total 18. Cada segmento se resuelve '
          'por match play (quién ganó más hoyos).',
      rules: [
        'Se juega por pares (1v1 o equipo A vs equipo B)',
        'Front 9 y Back 9 valen el mismo importe configurado',
        'Total 18 vale el doble (o el importe total configurado)',
        'Con Carry: si el Front 9 termina empatado, su valor se suma al Back 9',
        'Admite handicap neto o score bruto',
        'Opcionalmente con presión automática (Auto-press)',
      ],
      example:
          'Configuración: F9 \$50 · B9 \$50 · Total \$100\n'
          'Rafa gana F9 → cobra \$50\n'
          'Carlos gana B9 → cobra \$50\n'
          'Rafa gana Total → cobra \$100\n'
          'Resultado final: Rafa +\$50',
    ),
    _BetInfo(
      icon: Icons.bolt_rounded,
      color: Color(0xFFF57F17),
      name: 'Nassau + Press',
      tagline: 'Nassau con presiones automáticas integradas',
      howItWorks:
          'Igual que Nassau (F9, B9, Total), pero cada segmento puede generar '
          'presiones automáticas: cuando un jugador va N-down dentro del segmento, '
          'se inicia una mini-apuesta (press) que corre hasta el final de ese segmento.',
      rules: [
        'Presión automática cuando el déficit alcanza el trigger (ej. 2-down)',
        'Cada press corre desde el hoyo siguiente hasta el final del segmento',
        'Las presiones del F9 terminan en el hoyo 9; las del B9 en el 18',
        'Permite múltiples presiones en el mismo segmento (configurable)',
        'Carry en F9 aplica también al valor base del B9',
        'Valor de presión configurable independiente del segmento',
      ],
      example:
          'F9 \$50 · Press trigger: 2-down · Press value: \$50\n'
          'Carlos va 2-down al H3 → Press automático en H4\n'
          'Carlos recupera y gana el press → cobra \$50\n'
          'Rafa gana el F9 → cobra \$50\n'
          'Resultado: neutro en F9 (\$50 - \$50)',
    ),
    _BetInfo(
      icon: Icons.compare_arrows_rounded,
      color: Color(0xFF1565C0),
      name: 'Match + Press',
      tagline: 'Match play de 18 hoyos con presiones en cadena',
      howItWorks:
          'Match play clásico (18 hoyos) donde el jugador que va N-down '
          'puede activar una presión. Las presiones pueden generar a su vez '
          'nuevas presiones, creando una cadena activa durante la ronda.',
      rules: [
        'El match principal corre los 18 hoyos completos',
        'Press automático cuando el déficit alcanza el trigger configurado',
        'Cada press corre desde su hoyo de inicio hasta el hoyo 18',
        'Un press puede generar otro press (cadena anidada)',
        'Se puede limitar el número máximo de presiones activas',
        'Compatible con handicap neto o score bruto',
      ],
      example:
          'Match \$100 · Trigger 2-down · Press \$50\n'
          'H5: Carlos va 2-down → Press 1 (\$50) desde H6\n'
          'H9: Carlos va 2-down en el press → Press 2 (\$50) desde H10\n'
          'Rafa gana el match → cobra \$100\n'
          'Rafa gana Press 1 → cobra \$50\n'
          'Carlos gana Press 2 → cobra \$50',
    ),
    _BetInfo(
      icon: Icons.star_rounded,
      color: Color(0xFFAD1457),
      name: 'Skins',
      tagline: 'Cada hoyo tiene su propio premio',
      howItWorks:
          'Cada hoyo es una apuesta independiente. El jugador con el score '
          'más bajo en ese hoyo gana el "skin". Si hay empate, nadie lo gana '
          'y el valor se acumula (carry-over) para el siguiente hoyo.',
      rules: [
        'Un skin por hoyo; valor igual para todos los hoyos',
        'Empate → nadie gana, el skin pasa al siguiente (carry-over)',
        'El jugador con más skins gana el total acumulado',
        'Se puede configurar con o sin handicap (bruto/neto)',
        'Compatible con partidas de 2 a N jugadores',
        'El pot acumulado puede crecer hasta el último hoyo',
      ],
      example:
          'Skins \$20/hoyo · 3 jugadores\n'
          'H1: Rafa gana → cobra \$20\n'
          'H2: Empate → carry (pot: \$40)\n'
          'H3: Carlos gana → cobra \$40 (acumulado)\n'
          'H4: Empate → carry (pot: \$20)\n'
          '...',
    ),
    _BetInfo(
      icon: Icons.emoji_events_rounded,
      color: Color(0xFF4527A0),
      name: 'Medal',
      tagline: 'Score neto total de la ronda',
      howItWorks:
          'Apuesta al score total neto (o bruto) de la ronda. '
          'El jugador con menos golpes al final de los 9 u 18 hoyos '
          'cobra la apuesta a cada uno de los demás jugadores.',
      rules: [
        'Gana el jugador con el menor score total neto',
        'En caso de empate el premio se divide (o se aplica tie rule)',
        'Configurable para 9 o 18 hoyos',
        'Bruto o neto según handicap de ronda',
        'Se puede usar como apuesta principal o complementaria',
      ],
      example:
          'Medal \$100\n'
          'Rafa: 72 neto · Carlos: 74 neto · Rich: 76 neto\n'
          'Rafa gana → Carlos paga \$100, Rich paga \$100\n'
          'Rafa cobra \$200 total',
    ),
    _BetInfo(
      icon: Icons.sports_golf_rounded,
      color: Color(0xFF00695C),
      name: 'Oyeses',
      tagline: 'Ranking en los par 3',
      howItWorks:
          'Apuesta exclusiva de los hoyos par 3. Se lleva un ranking '
          'de quién hace el mejor tiro (más cerca del pin, birdie, etc.). '
          'Al finalizar la ronda, el que mejor lo hizo en los par 3 cobra.',
      rules: [
        'Solo aplica en hoyos par 3',
        'Se registra el resultado en cada par 3 (birdie/par/bogey)',
        'El ranking se actualiza hoyo a hoyo',
        'El ganador al final de la ronda cobra a todos los demás',
        'Empates se resuelven según la regla de tie configurada',
      ],
      example:
          'Oyeses \$50\n'
          'H4 (par 3): Rafa hace birdie → +1 punto\n'
          'H8 (par 3): Carlos hace birdie → +1 punto\n'
          'H12 (par 3): Rafa hace birdie → Rafa +2\n'
          'Rafa gana → cobra \$50 de Carlos y \$50 de Rich',
    ),
    _BetInfo(
      icon: Icons.touch_app_rounded,
      color: Color(0xFF6A1B9A),
      name: 'Units',
      tagline: 'Puntos por logros especiales',
      howItWorks:
          'Sistema de puntos donde cada logro tiene un valor en unidades. '
          'Los jugadores ganan o pierden unidades según sus logros a lo largo '
          'de la ronda. Al final el balance neto determina quién paga a quién.',
      rules: [
        'Birdie: +1 unidad por jugador que no lo hizo',
        'Eagle: +2 unidades (configurable)',
        'Sandy: par o mejor desde el bunker → +1 unidad',
        'Greenie: más cerca del pin en par 3 → +1 unidad',
        'El valor por unidad es configurable',
        'Se acumulan durante toda la ronda',
      ],
      example:
          'Units: \$10 por unidad\n'
          'H3: Rafa hace birdie → gana 1 unit de Carlos y Rich\n'
          'H7: Carlos hace eagle → gana 2 units de Rafa y Rich\n'
          'H15: Rafa hace sandy → gana 1 unit de Carlos y Rich\n'
          'Balance final: Rafa +\$10, Carlos +\$10, Rich -\$20',
    ),
    _BetInfo(
      icon: Icons.track_changes_rounded,
      color: Color(0xFF00838F),
      name: 'Putts',
      tagline: 'El que menos putts hace, gana',
      howItWorks:
          'Apuesta al número total de putts en la ronda. '
          'El jugador que registre menos putts al finalizar los 9 u 18 hoyos '
          'cobra la apuesta. También disponible en formato por segmento (F9/B9).',
      rules: [
        'Se registran los putts por hoyo durante la captura de scores',
        'Gana el jugador con menos putts totales',
        'Disponible en formato total (18H) o por segmento (F9 + B9)',
        'En caso de empate se divide el premio',
        'No aplica handicap (putts son brutos)',
      ],
      example:
          'Putts \$50 total\n'
          'Rafa: 28 putts · Carlos: 31 putts · Rich: 33 putts\n'
          'Rafa gana → cobra \$50 de Carlos y \$50 de Rich\n'
          'Rafa cobra \$100 total',
    ),
  ];
}

// ── Card expandible individual para cada apuesta ─────────────────────────────
class _BetExpandableCard extends StatefulWidget {
  final GolfTheme t;
  final _BetInfo info;
  const _BetExpandableCard({required this.t, required this.info});
  @override
  State<_BetExpandableCard> createState() => _BetExpandableCardState();
}

class _BetExpandableCardState extends State<_BetExpandableCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _expandAnim;
  late Animation<double> _rotateAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _rotateAnim = Tween<double>(begin: 0, end: 0.25).animate(_expandAnim);
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

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final info = widget.info;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _expanded
              ? info.color.withValues(alpha: 0.4)
              : t.divider,
          width: _expanded ? 1.5 : 1.0,
        ),
        boxShadow: _expanded
            ? [BoxShadow(
                color: info.color.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              )]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fila principal (siempre visible) ─────────────────────────
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Icono con color de la apuesta
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: info.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(info.icon, color: info.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  // Nombre y tagline
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.name,
                          style: TextStyle(
                            color: t.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          info.tagline,
                          style: TextStyle(color: t.sub, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Botón +/chevron animado
                  RotationTransition(
                    turns: _rotateAnim,
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: _expanded
                            ? info.color.withValues(alpha: 0.15)
                            : t.divider.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        color: _expanded ? info.color : t.sub,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Detalle expandible ────────────────────────────────────────
          SizeTransition(
            sizeFactor: _expandAnim,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(
                  color: info.color.withValues(alpha: 0.2),
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Cómo funciona
                      _DetailSection(
                        icon: Icons.info_outline_rounded,
                        color: info.color,
                        label: 'CÓMO FUNCIONA',
                        child: Text(
                          info.howItWorks,
                          style: TextStyle(
                            color: t.sub,
                            fontSize: 12.5,
                            height: 1.55,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Reglas
                      _DetailSection(
                        icon: Icons.rule_rounded,
                        color: info.color,
                        label: 'REGLAS',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: info.rules.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 6, height: 6,
                                  margin: const EdgeInsets.only(top: 5, right: 8),
                                  decoration: BoxDecoration(
                                    color: info.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    r,
                                    style: TextStyle(
                                      color: t.sub,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Ejemplo
                      _DetailSection(
                        icon: Icons.calculate_outlined,
                        color: info.color,
                        label: 'EJEMPLO',
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: info.color.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: info.color.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            info.example,
                            style: TextStyle(
                              color: t.text,
                              fontSize: 12,
                              height: 1.6,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sección de detalle con etiqueta e ícono ───────────────────────────────────
class _DetailSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final Widget child;

  const _DetailSection({
    required this.icon,
    required this.color,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ]),
        const SizedBox(height: 7),
        child,
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
        // ── Ventajas entre jugadores ──────────────────────────────────────
        Row(children: [
          Expanded(child: GSectionHeader(title: 'VENTAJAS')),
          GestureDetector(
            onTap: () => _openHandicapEdit(context, prov, t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.accent.withValues(alpha: 0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_outlined, color: t.accent, size: 12),
                const SizedBox(width: 4),
                Text('Editar', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        ...(() {
          // Generar pares únicos de jugadores
          final pairs = <Widget>[];
          final players = round.players;
          for (int i = 0; i < players.length; i++) {
            for (int j = i + 1; j < players.length; j++) {
              final pA = players[i];
              final pB = players[j];
              final hcpA = round.getHandicap(pA.id);
              final hcpB = round.getHandicap(pB.id);
              final rpA = round.roundPlayers.firstWhere(
                (r) => r.playerId == pA.id,
                orElse: () => RoundPlayer(playerId: pA.id, handicapEnRonda: hcpA, tee: TeeInfo.standard),
              );
              final isManual = rpA.manualHandicaps.containsKey(pB.id);
              // Usar manualHandicap si existe, si no la diferencia de HCPs
              final int diff = isManual
                  ? rpA.manualHandicaps[pB.id]!.round()
                  : (hcpA - hcpB).round();
              final String label = diff > 0
                  ? '${pA.name.split(' ').first} recibe $diff de ${pB.name.split(' ').first}'
                  : diff < 0
                      ? '${pB.name.split(' ').first} recibe ${diff.abs()} de ${pA.name.split(' ').first}'
                      : '${pA.name.split(' ').first} vs ${pB.name.split(' ').first}  (igualdad)';
              pairs.add(Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isManual ? t.accent.withValues(alpha: 0.05) : t.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isManual ? t.accent.withValues(alpha: 0.3) : t.divider),
                  ),
                  child: Row(children: [
                    GAvatar(name: pA.name, colorIndex: pA.colorIndex, size: 18),
                    const SizedBox(width: 4),
                    Text('vs', style: TextStyle(color: t.divider, fontSize: 10)),
                    const SizedBox(width: 4),
                    GAvatar(name: pB.name, colorIndex: pB.colorIndex, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label, style: TextStyle(color: t.sub, fontSize: 11))),
                    if (isManual)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: t.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text('Manual', style: TextStyle(color: t.accent, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
              ));
            }
          }
          return pairs;
        })(),

        const SizedBox(height: 20),
        GSectionHeader(title: 'PARTIDAS'),
        ...round.betGroups.map((g) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.name, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ...g.modules.map((m) => GestureDetector(
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
              )),
              // ── Chip + Añadir apuesta ──────────────────────────────────
              GestureDetector(
                onTap: () => _openAddBet(context, prov, g, t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.accent.withValues(alpha: 0.35), style: BorderStyle.solid),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, color: t.accent, size: 13),
                    const SizedBox(width: 4),
                    Text('Añadir apuesta', style: TextStyle(color: t.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                ),
              ),
            ]),
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

  void _openHandicapEdit(BuildContext context, RoundProvider prov, GolfTheme t) {
    final round   = prov.round!;
    final players = round.players;
    // Copia mutable de los manualHandicaps actuales: playerId → { otroId → strokes }
    final manuals = <String, Map<String, double>>{};
    for (final rp in round.roundPlayers) {
      manuals[rp.playerId] = Map<String, double>.from(rp.manualHandicaps);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) {
          double playingHcp(Player p) {
            // Usar el HCP congelado en la ronda, NO recalcular con el tee
            // (el tee puede haber cambiado; el HCP de la ronda es el correcto)
            final rp = round.roundPlayers.firstWhere(
              (r) => r.playerId == p.id,
              orElse: () => RoundPlayer(playerId: p.id, handicapEnRonda: p.handicapBase, tee: TeeInfo.standard),
            );
            return rp.handicapEnRonda;
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, sc) => SingleChildScrollView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Ventajas', style: TextStyle(color: t.text, fontSize: 20, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  GestureDetector(onTap: () => Navigator.pop(ctx), child: Icon(Icons.close, color: t.sub)),
                ]),
                const SizedBox(height: 4),
                Text('Ajusta cuántos golpes recibe cada jugador', style: TextStyle(color: t.sub, fontSize: 12)),
                const SizedBox(height: 16),

                // Pares únicos
                ...(() {
                  final widgets = <Widget>[];
                  for (int i = 0; i < players.length; i++) {
                    for (int j = i + 1; j < players.length; j++) {
                      final pA = players[i];
                      final pB = players[j];
                      final autoVal = (playingHcp(pA) - playingHcp(pB)).round();
                      final manualVal = manuals[pA.id]?[pB.id];
                      final isManual  = manualVal != null;
                      final current   = isManual ? manualVal!.round() : autoVal;

                      void applyEdit(int newVal) {
                        setSt(() {
                          manuals.putIfAbsent(pA.id, () => {});
                          manuals.putIfAbsent(pB.id, () => {});
                          manuals[pA.id]![pB.id] = newVal.toDouble();
                          manuals[pB.id]![pA.id] = (-newVal).toDouble();
                        });
                      }
                      void resetAuto() {
                        setSt(() {
                          manuals[pA.id]?.remove(pB.id);
                          manuals[pB.id]?.remove(pA.id);
                        });
                      }

                      final String desc = current > 0
                          ? '${pA.name.split(' ').first} recibe $current de ${pB.name.split(' ').first}'
                          : current < 0
                              ? '${pB.name.split(' ').first} recibe ${current.abs()} de ${pA.name.split(' ').first}'
                              : 'Igualdad';
                      final Color rowColor = current > 0 ? t.profit : current < 0 ? t.loss : t.sub;

                      widgets.add(Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isManual ? t.accent.withValues(alpha: 0.06) : t.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isManual ? t.accent.withValues(alpha: 0.4) : t.divider, width: isManual ? 1.5 : 1),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              GAvatar(name: pA.name, colorIndex: pA.colorIndex, size: 22),
                              const SizedBox(width: 4),
                              Text('vs', style: TextStyle(color: t.divider, fontSize: 11)),
                              const SizedBox(width: 4),
                              GAvatar(name: pB.name, colorIndex: pB.colorIndex, size: 22),
                              const SizedBox(width: 8),
                              Expanded(child: Text(desc, style: TextStyle(color: rowColor, fontSize: 12, fontWeight: FontWeight.w600))),
                              if (isManual)
                                GestureDetector(
                                  onTap: resetAuto,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: t.divider)),
                                    child: Text('Auto', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                            ]),
                            const SizedBox(height: 10),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              _handicapBtn('−5', t.loss, () => applyEdit(current - 5)),
                              const SizedBox(width: 6),
                              _handicapBtn('−1', t.loss, () => applyEdit(current - 1)),
                              const SizedBox(width: 10),
                              Container(
                                width: 52, height: 40,
                                decoration: BoxDecoration(
                                  color: t.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: t.primary, width: 1.5),
                                ),
                                child: Center(child: Text(
                                  current > 0 ? '+$current' : '$current',
                                  style: TextStyle(color: t.primary, fontSize: 16, fontWeight: FontWeight.w900),
                                )),
                              ),
                              const SizedBox(width: 10),
                              _handicapBtn('+1', t.profit, () => applyEdit(current + 1)),
                              const SizedBox(width: 6),
                              _handicapBtn('+5', t.profit, () => applyEdit(current + 5)),
                            ]),
                          ]),
                        ),
                      ));
                    }
                  }
                  return widgets;
                })(),

                const SizedBox(height: 8),
                GPrimaryButton(
                  label: 'Guardar ventajas',
                  onTap: () {
                    // Aplicar manuals a roundPlayers
                    final newRPs = round.roundPlayers.map((rp) {
                      final m = Map<String, double>.from(manuals[rp.playerId] ?? {});
                      return RoundPlayer(
                        playerId: rp.playerId,
                        handicapEnRonda: rp.handicapEnRonda,
                        tee: rp.tee,
                        manualHandicaps: m,
                      );
                    }).toList();
                    prov.updateRoundPlayers(newRPs);
                    Navigator.pop(ctx);
                  },
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _handicapBtn(String label, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Center(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13))),
    ),
  );

  void _openBetEdit(BuildContext context, RoundProvider prov, BetGroup group, BetModuleInstance mod, GolfTheme t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BetModuleEditSheet(
        group: group,
        mod: mod,
        t: t,
        courseInfo: prov.round!.course,
        players: prov.round!.players,
        onSave: (updatedMod) {
          final newModules = group.modules.map((m) => m.id == updatedMod.id ? updatedMod : m).toList();
          final newGroup   = BetGroup(id: group.id, name: group.name, format: group.format, playerIds: group.playerIds, modules: newModules);
          final newGroups  = prov.round!.betGroups.map((g) => g.id == group.id ? newGroup : g).toList();
          prov.updateBetGroups(newGroups);
        },
      ),
    );
  }

  // ── Agregar apuesta a un grupo durante la ronda ──────────────────────────
  void _openAddBet(BuildContext context, RoundProvider prov, BetGroup group, GolfTheme t) {
    final selected = <BetModuleType>{};
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24,
          left: 20, right: 20, top: 24,
        ),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Agregar apuesta', style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(ctx2), child: Icon(Icons.close, color: t.sub)),
          ]),
          const SizedBox(height: 4),
          Text('${group.name}  ·  Se activa desde el hoyo actual', style: TextStyle(color: t.sub, fontSize: 12)),
          const SizedBox(height: 16),

          Text('MATCH PLAY', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          ...[BetModuleType.nassau, BetModuleType.matchAutoPress].map((bt) =>
            _betTypeTileHome(bt, selected, setSt, t, group)),
          const SizedBox(height: 16),
          Text('OTRAS APUESTAS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          ...[BetModuleType.skins, BetModuleType.medal, BetModuleType.putts,
              BetModuleType.oyeses, BetModuleType.units].map((bt) =>
            _betTypeTileHome(bt, selected, setSt, t, group)),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: selected.isEmpty ? null : () {
                // Añadir los módulos seleccionados al grupo y guardar
                final newMods = List<BetModuleInstance>.from(group.modules);
                final addedMods = <BetModuleInstance>[];
                for (final bt in selected) {
                  final newMod = BetModuleInstance.defaultFor(bt, group.playerIds);
                  newMods.add(newMod);
                  addedMods.add(newMod);
                }
                final newGroup  = BetGroup(id: group.id, name: group.name, format: group.format, playerIds: group.playerIds, modules: newMods);
                final newGroups = prov.round!.betGroups.map((g) => g.id == group.id ? newGroup : g).toList();
                prov.updateBetGroups(newGroups);
                Navigator.pop(ctx2);
                // Si solo se agregó uno, abrir el editor inmediatamente
                if (addedMods.length == 1) {
                  Future.delayed(const Duration(milliseconds: 250), () {
                    if (context.mounted) {
                      _openBetEdit(context, prov, newGroup, addedMods.first, t);
                    }
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: selected.isEmpty ? t.divider : t.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                selected.isEmpty
                    ? 'Selecciona al menos uno'
                    : 'Agregar ${selected.length} apuesta${selected.length > 1 ? 's' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ])),
      )),
    );
  }

  Widget _betTypeTileHome(BetModuleType bt, Set<BetModuleType> selected, StateSetter setSt, GolfTheme t, BetGroup group) {
    final isSel = selected.contains(bt);
    final isMatchType = bt == BetModuleType.nassau || bt == BetModuleType.matchAutoPress;
    final accentColor = isMatchType ? t.accent : t.primary;
    final alreadyAdded = group.modules.any((m) => m.type == bt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: alreadyAdded ? null : () => setSt(() {
          if (isSel) selected.remove(bt); else selected.add(bt);
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: alreadyAdded
                ? t.divider.withValues(alpha: 0.3)
                : isSel ? accentColor.withValues(alpha: 0.1) : t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSel ? accentColor : t.divider),
          ),
          child: Row(children: [
            Text(bt.icon, style: TextStyle(fontSize: 20, color: alreadyAdded ? t.sub : null)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bt.label, style: TextStyle(color: alreadyAdded ? t.sub : t.text, fontWeight: FontWeight.w700, fontSize: 13)),
              Text(bt.description, style: TextStyle(color: t.sub, fontSize: 10)),
              if (alreadyAdded)
                Text('Ya incluida en esta partida', style: TextStyle(color: t.sub.withValues(alpha: 0.6), fontSize: 9, fontStyle: FontStyle.italic)),
            ])),
            if (isSel && !alreadyAdded)
              Icon(Icons.check_circle, color: accentColor, size: 20),
            if (alreadyAdded)
              Icon(Icons.check, color: t.sub, size: 16),
          ]),
        ),
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
        TextButton(onPressed: () async {
          Navigator.pop(ctx);
          // Capturar la ronda ANTES de que finishRound limpie el estado
          final roundSnapshot = prov.round;
          final ok = await prov.finishRound();
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text(
                '⚠️ Sin conexión a Firestore. La ronda se guardó localmente y se sincronizará automáticamente cuando haya conexión.'),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 5),
            ));
          }
          // Mostrar diálogo de ajuste de sliding
          if (roundSnapshot != null && context.mounted) {
            await showSlidingAdjustmentDialog(context, roundSnapshot);
          }
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
              // Si no hay score, muestra el par como placeholder visual
              value: score.hasScore ? gross : widget.ch.par,
              isPlaceholder: !score.hasScore,
              onDec: () {
                // Base: gross si ya registrado, par si es placeholder
                final base = score.hasScore ? gross : widget.ch.par;
                prov.updateScore(widget.player.id, widget.hole, base > 1 ? base - 1 : null, putts);
              },
              onInc: () {
                final base = score.hasScore ? gross : widget.ch.par;
                prov.updateScore(widget.player.id, widget.hole, base + 1, putts);
              },
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

