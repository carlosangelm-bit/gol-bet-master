// ─────────────────────────────────────────────────────────────────────────────
// GUEST JOIN SCREEN
// Pantalla de bienvenida para invitados sin cuenta.
// Se accede mediante un enlace temporal generado por el admin.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/guest_invite_service.dart';
import 'guest_round_view.dart';

class GuestJoinScreen extends StatefulWidget {
  final String token;
  const GuestJoinScreen({super.key, required this.token});

  @override
  State<GuestJoinScreen> createState() => _GuestJoinScreenState();
}

class _GuestJoinScreenState extends State<GuestJoinScreen>
    with SingleTickerProviderStateMixin {
  // ── State ─────────────────────────────────────────────────────────────────
  bool _loadingInvite = true;
  bool _joining = false;
  Map<String, dynamic>? _inviteData;
  String? _loadError;
  String? _joinError;

  final _nameCtrl     = TextEditingController();
  final _initialsCtrl  = TextEditingController();
  final _hcpCtrl       = TextEditingController(text: '0');
  final _formKey       = GlobalKey<FormState>();
  bool _initialsEdited = false;  // true cuando el usuario editó manualmente

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;

  static const _green  = Color(0xFF0D2B0F);
  static const _green2 = Color(0xFF1A3A1C);
  static const _gold   = Color(0xFFD4A520);
  static const _white  = Colors.white;

  // initState movido arriba junto con dispose

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    // Auto-sugerir iniciales cuando cambia el nombre (si el usuario no las editó manualmente)
    _nameCtrl.addListener(_autoSuggestInitials);
    _loadInvite();
  }

  void _autoSuggestInitials() {
    if (_initialsEdited) return;
    final words = _nameCtrl.text.trim().split(' ').where((w) => w.isNotEmpty).toList();
    final auto = words.map((w) => w[0]).take(3).join().toUpperCase();
    if (_initialsCtrl.text != auto) {
      _initialsCtrl.text = auto;
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameCtrl.dispose();
    _initialsCtrl.dispose();
    _hcpCtrl.dispose();
    super.dispose();
  }

  // ── Cargar datos del enlace ───────────────────────────────────────────────
  Future<void> _loadInvite() async {
    setState(() { _loadingInvite = true; _loadError = null; });
    final data = await GuestInviteService.getInviteData(widget.token);
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _loadingInvite = false;
        _loadError = 'Este enlace no es válido o la ronda ya terminó.';
      });
      return;
    }
    setState(() { _loadingInvite = false; _inviteData = data; });
    _animCtrl.forward();
  }

  // ── Unirse como invitado ──────────────────────────────────────────────────
  Future<void> _join() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _joining = true; _joinError = null; });

    final hcp = double.tryParse(_hcpCtrl.text.replaceAll(',', '.')) ?? 0;
    final result = await GuestInviteService.joinAsGuest(
      token:          widget.token,
      guestName:      _nameCtrl.text.trim(),
      guestHcp:       hcp,
      guestInitials:  _initialsCtrl.text.trim().isNotEmpty ? _initialsCtrl.text.trim() : null,
    );

    if (!mounted) return;
    if (result.error != null) {
      setState(() { _joining = false; _joinError = result.error; });
      return;
    }

    // Ir directo a la vista de invitado
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GuestRoundView(
          round:    result.round!,
          playerId: result.playerId!,
          token:    widget.token,
        ),
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
        body: _loadingInvite
            ? _buildLoading()
            : _loadError != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: _gold),
    );
  }

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
    final d = _inviteData!;
    final roundName  = d['roundName']  as String? ?? 'Ronda Golf';
    final courseName = d['courseName'] as String? ?? '';
    final ownerName  = d['ownerName']  as String? ?? 'Admin';
    final roundData  = d['roundData']  as Map<String, dynamic>? ?? {};
    final players    = (roundData['players'] as List? ?? [])
        .where((p) => (p as Map)['isVirtual'] != true)
        .map((p) => (p as Map<String, dynamic>)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final scoringMode = roundData['scoringMode'] as String? ?? 'open';

    return SafeArea(
      child: SingleChildScrollView(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Column(children: [
            // ── Header con gradiente ──────────────────────────────────────
            _buildHeader(roundName, courseName, ownerName, players),

            // ── Formulario ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(children: [
                // Info de modo
                _buildModeInfo(scoringMode),
                const SizedBox(height: 24),

                // Formulario nombre + HCP
                _buildForm(),
                const SizedBox(height: 20),

                // Error de join
                if (_joinError != null)
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
                      Expanded(child: Text(_joinError!,
                        style: const TextStyle(color: Colors.red, fontSize: 13))),
                    ]),
                  ),

                const SizedBox(height: 20),

                // Botón unirse
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _joining ? null : _join,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    child: _joining
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: _green))
                        : const Text('Unirse a la ronda',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ),

                const SizedBox(height: 16),
                Text('Al unirte aceptas que tus datos de juego sean\nvisibles para todos los participantes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white.withValues(alpha: 0.45), fontSize: 11, height: 1.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(String roundName, String courseName, String ownerName, List<String> players) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_green, _green2, Color(0xFF1E3A20)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Logo + app name
        _logo(),
        const SizedBox(height: 28),

        // Chip "Te invitan a una ronda"
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _gold.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.sports_golf_rounded, color: _gold, size: 14),
            const SizedBox(width: 6),
            Text('Invitación a ronda',
              style: TextStyle(color: _gold, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.4)),
          ]),
        ),
        const SizedBox(height: 16),

        // Nombre de la ronda
        Text(roundName,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _white, fontSize: 24, fontWeight: FontWeight.w900, height: 1.2)),
        const SizedBox(height: 8),
        if (courseName.isNotEmpty)
          Text(courseName,
            textAlign: TextAlign.center,
            style: TextStyle(color: _white.withValues(alpha: 0.6), fontSize: 13)),

        const SizedBox(height: 20),

        // Organizador
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.person_rounded, color: _white.withValues(alpha: 0.5), size: 14),
          const SizedBox(width: 6),
          Text('Organiza: $ownerName',
            style: TextStyle(color: _white.withValues(alpha: 0.6), fontSize: 13)),
        ]),

        if (players.isNotEmpty) ...[
          const SizedBox(height: 16),
          // Jugadores actuales
          Wrap(
            spacing: 8, runSpacing: 8,
            alignment: WrapAlignment.center,
            children: players.map((name) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _white.withValues(alpha: 0.15)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.sports_golf_rounded, color: _gold, size: 12),
                const SizedBox(width: 5),
                Text(name, style: TextStyle(color: _white.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            )).toList(),
          ),
        ],
      ]),
    );
  }

  // ── Info de modo ─────────────────────────────────────────────────────────
  Widget _buildModeInfo(String scoringMode) {
    final isAdmin = scoringMode == 'admin';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _white.withValues(alpha: 0.12)),
      ),
      child: Row(children: [
        Icon(
          isAdmin ? Icons.visibility_rounded : Icons.edit_rounded,
          color: _gold, size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            isAdmin ? 'Ronda de solo visualización' : 'Ronda colaborativa',
            style: const TextStyle(color: _white, fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            isAdmin
                ? 'El admin captura los scores. Tú podrás ver todo en tiempo real.'
                : 'Podrás capturar tu propio score y ver el de todos.',
            style: TextStyle(color: _white.withValues(alpha: 0.55), fontSize: 11, height: 1.4),
          ),
        ])),
      ]),
    );
  }

  // ── Formulario ────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TUS DATOS', style: TextStyle(
          color: _white.withValues(alpha: 0.5),
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 10),

        // Nombre completo
        _buildField(
          controller: _nameCtrl,
          label: 'Tu nombre completo',
          hint: 'Ej: Carlos Angel Mendoza',
          icon: Icons.person_rounded,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Ingresa tu nombre';
            if (v.trim().length < 2) return 'Nombre muy corto';
            return null;
          },
        ),
        const SizedBox(height: 12),

        // Iniciales (fila con preview)
        Row(children: [
          Expanded(
            child: _buildField(
              controller: _initialsCtrl,
              label: 'Iniciales (máx 3)',
              hint: 'Ej: CA',
              icon: Icons.badge_rounded,
              maxLength: 3,
              onChanged: (_) => setState(() => _initialsEdited = true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requeridas';
                return null;
              },
            ),
          ),
          const SizedBox(width: 12),
          // Preview del avatar con las iniciales
          StatefulBuilder(builder: (_, __) {
            final ini = _initialsCtrl.text.trim().isNotEmpty
                ? _initialsCtrl.text.trim().toUpperCase()
                : '?';
            return Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5),
                shape: BoxShape.circle,
                border: Border.all(color: _gold.withValues(alpha: 0.5), width: 2),
              ),
              alignment: Alignment.center,
              child: Text(ini,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
            );
          }),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            'Se auto-sugieren desde tu nombre. Se usan en vistas compactas de la tarjeta.',
            style: TextStyle(color: _white.withValues(alpha: 0.4), fontSize: 11, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),

        // HCP
        _buildField(
          controller: _hcpCtrl,
          label: 'Tu Handicap',
          hint: 'Ej: 12',
          icon: Icons.sports_golf_rounded,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Ingresa tu HCP';
            final n = double.tryParse(v.replaceAll(',', '.'));
            if (n == null || n < 0 || n > 54) return 'HCP debe ser entre 0 y 54';
            return null;
          },
        ),
      ]),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      maxLength: maxLength,
      textCapitalization: maxLength != null ? TextCapitalization.characters : TextCapitalization.words,
      style: const TextStyle(color: _white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',   // ocultar contador de chars
        labelStyle: TextStyle(color: _white.withValues(alpha: 0.55), fontSize: 13),
        hintStyle: TextStyle(color: _white.withValues(alpha: 0.25)),
        prefixIcon: Icon(icon, color: _gold, size: 20),
        filled: true,
        fillColor: _white.withValues(alpha: 0.07),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _white.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.7)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // ── Logo ──────────────────────────────────────────────────────────────────
  Widget _logo() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFE8B84B), _gold, Color(0xFFB8860B)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: _gold.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: const Center(
          child: Text('⛳', style: TextStyle(fontSize: 32)),
        ),
      ),
      const SizedBox(height: 10),
      const Text('Golf Bet Master',
        style: TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1)),
    ]);
  }
}
