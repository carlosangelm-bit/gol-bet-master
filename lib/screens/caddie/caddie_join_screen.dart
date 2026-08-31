// ─────────────────────────────────────────────────────────────────────────────
// CADDIE JOIN SCREEN
// Pantalla de entrada para caddies / espectadores.
// Solo visualización — el caddie NO se agrega como jugador.
// El enlace es reutilizable (multi-uso): varios caddies pueden usarlo.
// ─────────────────────────────────────────────────────────────────────────────
import '../../core/golf_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/caddie_service.dart';
import 'caddie_round_view.dart';

class CaddieJoinScreen extends StatefulWidget {
  final String token;
  const CaddieJoinScreen({super.key, required this.token});

  @override
  State<CaddieJoinScreen> createState() => _CaddieJoinScreenState();
}

class _CaddieJoinScreenState extends State<CaddieJoinScreen>
    with SingleTickerProviderStateMixin {
  // ── State ─────────────────────────────────────────────────────────────────
  bool   _loadingInfo = true;
  bool   _entering    = false;
  Map<String, dynamic>? _data;
  String? _loadError;
  String? _enterError;

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeIn;

  static const _green  = Color(0xFF0A2010);
  static const _green2 = Color(0xFF1A3A1C);
  static const _teal   = Color(0xFF00BCD4);   // color caddie — distinto del dorado de jugadores
  static const _white  = Colors.white;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _loadInfo();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Cargar info del token ─────────────────────────────────────────────────
  Future<void> _loadInfo() async {
    setState(() { _loadingInfo = true; _loadError = null; });
    final data = await CaddieService.getCaddieData(widget.token);
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _loadingInfo = false;
        _loadError = 'Este enlace no es válido, ya expiró o la ronda finalizó.';
      });
      return;
    }
    setState(() { _loadingInfo = false; _data = data; });
    _animCtrl.forward();
  }

  // ── Entrar como espectador ────────────────────────────────────────────────
  Future<void> _enter() async {
    setState(() { _entering = true; _enterError = null; });
    final result = await CaddieService.enterAsViewer(widget.token);
    if (!mounted) return;
    if (result.error != null) {
      setState(() { _entering = false; _enterError = result.error; });
      return;
    }
    // Navegar a la vista de caddie
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CaddieRoundView(round: result.round!),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _green,
        body: _loadingInfo
            ? _buildLoading()
            : _loadError != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  Widget _buildLoading() => const Center(
    child: CircularProgressIndicator(color: _teal),
  );

  // ── Error ─────────────────────────────────────────────────────────────────
  Widget _buildError() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _logo(),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
              ),
              child: Column(children: [
                const Icon(Icons.link_off_rounded, color: Colors.red, size: 40),
                const SizedBox(height: 12),
                Text(_loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _white, fontSize: 15, height: 1.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Contenido principal ───────────────────────────────────────────────────
  Widget _buildContent() {
    final d          = _data!;
    final roundName  = d['roundName']  as String? ?? 'Ronda Golf';
    final courseName = d['courseName'] as String? ?? '';
    final ownerName  = d['ownerName']  as String? ?? 'Admin';
    final roundData  = d['roundData']  as Map<String, dynamic>? ?? {};
    final players    = (roundData['players'] as List? ?? [])
        .where((p) => (p as Map)['isVirtual'] != true)
        .map((p) => (p as Map<String, dynamic>)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    return SafeArea(
      child: SingleChildScrollView(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Column(children: [
            // ── Header ────────────────────────────────────────────────────
            _buildHeader(roundName, courseName, ownerName, players),

            // ── Cuerpo ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
              child: Column(children: [
                // Info del modo caddie
                _buildCaddieInfo(),
                const SizedBox(height: 28),

                // Error al entrar
                if (_enterError != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_enterError!,
                          style: const TextStyle(color: Colors.red, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],

                // Botón entrar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _entering ? null : _enter,
                    icon: _entering
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: _green))
                        : const Icon(Icons.visibility_rounded, size: 20),
                    label: Text(
                      _entering ? 'Conectando...' : 'Ver ronda en tiempo real',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Text(
                  'Acceso de solo visualización. No podrás modificar\nscores ni datos de la ronda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _white.withValues(alpha: 0.40),
                      fontSize: 11,
                      height: 1.5),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(
      String roundName, String courseName, String ownerName, List<String> players) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_green, _green2, Color(0xFF1E3A20)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        _logo(),
        const SizedBox(height: 28),

        // Badge "Acceso Caddie"
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _teal.withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.visibility_rounded, color: _teal, size: 14),
            const SizedBox(width: 7),
            Text('Acceso Caddie',
                style: TextStyle(
                    color: _teal,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.5)),
          ]),
        ),
        const SizedBox(height: 18),

        // Nombre de la ronda
        Text(roundName,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                height: 1.2)),
        const SizedBox(height: 8),
        if (courseName.isNotEmpty)
          Text(courseName,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _white.withValues(alpha: 0.6), fontSize: 13)),
        const SizedBox(height: 16),

        // Organizador
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.person_rounded,
              color: _white.withValues(alpha: 0.5), size: 14),
          const SizedBox(width: 6),
          Text('Organiza: $ownerName',
              style: TextStyle(
                  color: _white.withValues(alpha: 0.6), fontSize: 13)),
        ]),

        // Jugadores
        if (players.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 8, runSpacing: 8,
            alignment: WrapAlignment.center,
            children: players.map((name) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _white.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: _white.withValues(alpha: 0.14)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.sports_golf_rounded,
                    color: _teal, size: 12),
                const SizedBox(width: 5),
                Text(name,
                    style: TextStyle(
                        color: _white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            )).toList(),
          ),
        ],
      ]),
    );
  }

  // ── Info modo caddie ──────────────────────────────────────────────────────
  Widget _buildCaddieInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _teal.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.visibility_rounded, color: _teal, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Vista de solo lectura',
                style: TextStyle(
                    color: _white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
          ),
        ]),
        const SizedBox(height: 14),
        _featureRow(Icons.check_circle_outline_rounded,
            'Scores en tiempo real de todos los jugadores'),
        _featureRow(Icons.check_circle_outline_rounded,
            'Tarjeta de hoyos completa con handicap'),
        _featureRow(Icons.check_circle_outline_rounded,
            'Resultados y balance de apuestas'),
        _featureRow(Icons.check_circle_outline_rounded,
            'Vista 1v1 de duelos entre jugadores'),
        const SizedBox(height: 6),
        _featureRow(Icons.block_rounded,
            'Sin posibilidad de ingresar o modificar scores',
            isLocked: true),
        _featureRow(Icons.block_rounded,
            'No ocupa cupo de jugador en la ronda',
            isLocked: true),
      ]),
    );
  }

  Widget _featureRow(IconData icon, String text, {bool isLocked = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon,
            color: isLocked
                ? Colors.red.withValues(alpha: 0.65)
                : _teal.withValues(alpha: 0.80),
            size: 16),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: _white.withValues(alpha: isLocked ? 0.45 : 0.70),
                  fontSize: 12,
                  height: 1.4)),
        ),
      ]),
    );
  }

  // ── Logo ──────────────────────────────────────────────────────────────────
  Widget _logo() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF00BCD4), Color(0xFF0097A7), Color(0xFF006064)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: _teal.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 6))
          ],
        ),
        child: const Center(
          child: Icon(GolfIcons.copia, size: GolfIcons.juntoAlHeroe),
        ),
      ),
      const SizedBox(height: 10),
      const Text('Golf Bet Master',
          style: TextStyle(
              color: _teal,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1)),
    ]);
  }
}
