// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS SCREEN — Ajustes de la app: Perfil, Tema, Campos favoritos
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../providers/round_provider.dart';
import '../../providers/user_profile_provider.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/common_widgets.dart';
import '../../providers/player_provider.dart';
import '../../services/golf_course_service.dart';
import '../../services/firestore_service.dart';
import '../presets/game_presets_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RoundProvider>();
    final t    = prov.theme;
    GolfThemeExt.setCurrent(t);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
              color: t.bg,
              border: Border(bottom: BorderSide(color: t.divider)),
            ),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: t.primary, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.settings, color: t.onPrimary, size: 20),
              ),
              const SizedBox(width: 10),
              Text('Ajustes', style: TextStyle(
                  color: t.text, fontWeight: FontWeight.w800, fontSize: 20)),
            ]),
          ),

          // ── Contenido scrolleable ────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── MI PERFIL ──────────────────────────────────────────
                  GSectionHeader(title: 'MI PERFIL'),
                  const SizedBox(height: 8),
                  const _ProfileCard(),

                  const SizedBox(height: 28),

                  // ── MIS CAMPOS FAVORITOS ───────────────────────────────
                  GSectionHeader(title: 'MIS CAMPOS FAVORITOS'),
                  const SizedBox(height: 8),
                  _FavCoursesSection(t: t),

                  const SizedBox(height: 28),

                  // ── MIS CONFIGURACIONES DE PARTIDA ─────────────────────
                  GSectionHeader(title: 'MIS CONFIGURACIONES DE PARTIDA'),
                  const SizedBox(height: 8),
                  _GamePresetsCard(t: t),

                  const SizedBox(height: 28),

                  // ── APARIENCIA ──────────────────────────────────────────
                  GSectionHeader(title: 'APARIENCIA'),
                  const SizedBox(height: 8),
                  ...AppThemeMode.values.map((m) =>
                      _ThemeOption(mode: m, prov: prov, t: t)),

                  const SizedBox(height: 28),

                  // ── MÓDULOS DE APUESTA ──────────────────────────────────
                  GSectionHeader(title: 'MÓDULOS DE APUESTA'),
                  const SizedBox(height: 8),
                  _BetModulesInfo(t: t),

                  const SizedBox(height: 28),

                  // ── REGLAS ──────────────────────────────────────────────
                  GSectionHeader(title: 'REGLAS'),
                  const SizedBox(height: 8),
                  _RulesReference(t: t),

                  const SizedBox(height: 28),

                  // ── ACERCA DE ───────────────────────────────────────────
                  GSectionHeader(title: 'ACERCA DE'),
                  const SizedBox(height: 8),
                  GCard(child: Column(children: [
                    Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: t.primary, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.golf_course, color: t.onPrimary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Golf Bet Master',
                            style: TextStyle(color: t.text,
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('Versión 1.0.0',
                            style: TextStyle(color: t.sub, fontSize: 12)),
                      ]),
                    ]),
                    const SizedBox(height: 12),
                    const GDivider(),
                    const SizedBox(height: 12),
                    Text(
                      'App de gestión de apuestas para golf. Soporta Nassau, '
                      'Skins, Medal, Oyeses, Putts y Units con handicap y '
                      'liquidación automática.',
                      style: TextStyle(color: t.sub, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ])),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA DE PERFIL
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final t        = GolfThemeExt.current;
    final profProv = context.watch<UserProfileProvider>();
    final playerProv = context.watch<PlayerProvider>();
    final profile  = profProv.profile;

    if (profProv.loading && profile == null) {
      return GCard(child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: CircularProgressIndicator(color: t.primary),
        ),
      ));
    }

    // Jugador vinculado como "yo"
    final myPlayerId = profile?.myPlayerId;
    final myPlayer = myPlayerId != null
        ? playerProv.directory.where((p) => p.player.id == myPlayerId).firstOrNull
        : null;

    return GCard(
      child: Column(children: [
        // ── Fila principal ─────────────────────────────────────────────────
        InkWell(
          onTap: () => _showProfileSheet(context, t, profile),
          borderRadius: BorderRadius.circular(10),
          child: Row(children: [
            GAvatar(
              name: profile?.shortName ?? '?',
              colorIndex: profile?.colorIndex ?? 0,
              size: 52,
            ),
            const SizedBox(width: 14),

            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.shortName ?? 'Configura tu perfil',
                  style: TextStyle(
                    color: t.text, fontWeight: FontWeight.w800, fontSize: 16),
                ),
                if (profile?.nickname != null &&
                    profile!.nickname!.isNotEmpty &&
                    profile.nickname != profile.displayName)
                  Text(profile.displayName,
                      style: TextStyle(color: t.sub, fontSize: 12)),
                const SizedBox(height: 4),
                Row(children: [
                  _chip('HCP ${profile?.defaultHandicap.toStringAsFixed(1) ?? '–'}', t.primary, t),
                  const SizedBox(width: 6),
                  _chip(profile?.defaultCurrency ?? 'USD', t.accent, t),
                ]),
              ],
            )),

            Icon(Icons.edit_outlined, color: t.sub, size: 18),
          ]),
        ),

        // ── Mi jugador en el directorio ─────────────────────────────────
        const SizedBox(height: 12),
        const GDivider(),
        const SizedBox(height: 12),

        Row(children: [
          Icon(Icons.person_pin_outlined, color: t.sub, size: 18),
          const SizedBox(width: 8),
          Text('Yo en el directorio:',
              style: TextStyle(color: t.sub, fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(
            child: myPlayer != null
                ? Row(children: [
                    GAvatar(
                      name: myPlayer.displayName,
                      colorIndex: myPlayer.player.colorIndex,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      myPlayer.displayName,
                      style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ])
                : Text('No vinculado',
                    style: TextStyle(
                      color: t.accent,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    )),
          ),
          GestureDetector(
            onTap: () => _showLinkPlayerSheet(context, t, profile, playerProv),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                myPlayer != null ? 'Cambiar' : 'Vincular',
                style: TextStyle(
                  color: t.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ]),

        // Aviso si no está configurado
        if (profile == null || myPlayer == null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.accent.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: t.accent, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                profile == null
                    ? 'Configura tu nombre y HCP para aparecer correctamente en tus rondas.'
                    : 'Vincula tu jugador del directorio para que aparezcas automáticamente al crear una ronda.',
                style: TextStyle(color: t.sub, fontSize: 12),
              )),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _chip(String label, Color color, GolfTheme t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label, style: TextStyle(
      color: color, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  void _showProfileSheet(BuildContext ctx, GolfTheme t, UserProfile? profile) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProfileFormSheet(t: t, profile: profile),
    );
  }

  void _showLinkPlayerSheet(
    BuildContext ctx,
    GolfTheme t,
    UserProfile? profile,
    PlayerProvider playerProv,
  ) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LinkPlayerSheet(
        t: t,
        profile: profile,
        playerProv: playerProv,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHEET EDITAR PERFIL
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// SHEET: VINCULAR JUGADOR DEL DIRECTORIO COMO "YO"
// ─────────────────────────────────────────────────────────────────────────────
class _LinkPlayerSheet extends StatelessWidget {
  final GolfTheme t;
  final UserProfile? profile;
  final PlayerProvider playerProv;
  const _LinkPlayerSheet({
    required this.t,
    required this.profile,
    required this.playerProv,
  });

  @override
  Widget build(BuildContext context) {
    final directory = playerProv.directory;
    final currentId = profile?.myPlayerId;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20, right: 20, top: 24,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('¿Cuál jugador eres tú?',
                  style: TextStyle(
                    color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close, color: t.sub),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Selecciona tu jugador del directorio para aparecer automáticamente al crear una ronda.',
              style: TextStyle(color: t.sub, fontSize: 12),
            ),
            const SizedBox(height: 16),

            if (directory.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, color: t.sub, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'No tienes jugadores en tu directorio.\nCrea uno primero desde la pestaña "Compañeros".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.sub, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: directory.length + (currentId != null ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    // Opción "Ninguno" al final si hay vínculo actual
                    if (currentId != null && i == directory.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: () async {
                            await ctx.read<UserProfileProvider>()
                                .updateFields({'myPlayerId': null});
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                backgroundColor: t.sub,
                                content: const Text('Vínculo eliminado'),
                                duration: const Duration(seconds: 2),
                              ));
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: t.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: t.divider),
                            ),
                            child: Row(children: [
                              Icon(Icons.link_off, color: t.sub, size: 18),
                              const SizedBox(width: 12),
                              Text('Ninguno (desvincular)',
                                  style: TextStyle(color: t.sub, fontSize: 13)),
                            ]),
                          ),
                        ),
                      );
                    }

                    final pwl = directory[i];
                    final isSelected = pwl.player.id == currentId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GCard(
                        color: isSelected
                            ? t.primary.withValues(alpha: 0.08)
                            : null,
                        onTap: () async {
                          await ctx.read<UserProfileProvider>()
                              .updateFields({'myPlayerId': pwl.player.id});
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              backgroundColor: t.profit,
                              content: Text(
                                  '¡Listo! Ahora eres "${pwl.displayName}"'),
                              duration: const Duration(seconds: 2),
                            ));
                          }
                        },
                        child: Row(children: [
                          GAvatar(
                            name: pwl.displayName,
                            colorIndex: pwl.player.colorIndex,
                            size: 40,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pwl.displayName,
                                  style: TextStyle(
                                    color: t.text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  )),
                              Text(
                                'HCP ${pwl.player.handicapBase.toStringAsFixed(1)}',
                                style: TextStyle(color: t.sub, fontSize: 11),
                              ),
                            ],
                          )),
                          if (isSelected)
                            Icon(Icons.check_circle,
                                color: t.primary, size: 22)
                          else
                            Icon(Icons.radio_button_unchecked,
                                color: t.divider, size: 22),
                        ]),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _ProfileFormSheet extends StatefulWidget {
  final GolfTheme t;
  final UserProfile? profile;
  const _ProfileFormSheet({required this.t, this.profile});
  @override State<_ProfileFormSheet> createState() => _ProfileFormSheetState();
}

class _ProfileFormSheetState extends State<_ProfileFormSheet> {
  late final _nameCtrl     = TextEditingController(
      text: widget.profile?.displayName ?? '');
  late final _nicknameCtrl = TextEditingController(
      text: widget.profile?.nickname ?? '');
  late final _hcpCtrl      = TextEditingController(
      text: (widget.profile?.defaultHandicap ?? 0).toStringAsFixed(1));
  late final _unitCtrl     = TextEditingController(
      text: (widget.profile?.defaultUnitValue ?? 5).toStringAsFixed(0));

  late int    _colorIdx  = widget.profile?.colorIndex ?? 0;
  late String _currency  = widget.profile?.defaultCurrency ?? 'USD';
  bool _saving = false;

  static const _colors = [
    Colors.green, Colors.blue, Colors.orange, Colors.purple,
    Colors.red, Colors.teal, Colors.amber, Colors.indigo,
  ];
  static const _currencies = ['USD', 'MXN', 'EUR', 'GBP', 'CAD', 'ARS', 'COP'];

  @override
  void dispose() {
    for (final c in [_nameCtrl, _nicknameCtrl, _hcpCtrl, _unitCtrl]) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20, right: 20, top: 24,
      ),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          Row(children: [
            Text('Mi perfil', style: TextStyle(
                color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.close, color: t.sub),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Estos datos aparecerán cuando juegues.',
              style: TextStyle(color: t.sub, fontSize: 12)),
          const SizedBox(height: 20),

          // ── Color de avatar ──────────────────────────────────────────
          Text('COLOR DE AVATAR', style: TextStyle(color: t.sub, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Row(children: List.generate(_colors.length, (i) => GestureDetector(
            onTap: () => setState(() => _colorIdx = i),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: _colors[i],
                shape: BoxShape.circle,
                border: _colorIdx == i
                    ? Border.all(color: t.text, width: 2.5) : null,
              ),
            ),
          ))),
          const SizedBox(height: 16),

          // ── Nombre completo ──────────────────────────────────────────
          _Field(label: 'Nombre completo', ctrl: _nameCtrl, t: t),
          const SizedBox(height: 12),

          // ── Apodo (cómo te verás en rondas) ─────────────────────────
          _Field(
            label: 'Apodo (cómo aparecer en rondas)',
            ctrl: _nicknameCtrl, t: t,
            hint: 'Ej: "Checo", "El Pro"',
          ),
          const SizedBox(height: 12),

          // ── HCP ──────────────────────────────────────────────────────
          _Field(
            label: 'HCP Índice por defecto',
            ctrl: _hcpCtrl, t: t,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            hint: '0.0 – 54.0',
          ),
          const SizedBox(height: 16),

          // ── Moneda ───────────────────────────────────────────────────
          Text('MONEDA', style: TextStyle(color: t.sub, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _currencies.map((c) {
            final sel = c == _currency;
            return GestureDetector(
              onTap: () => setState(() => _currency = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? t.primary.withValues(alpha: 0.12) : t.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: sel ? t.primary : t.divider,
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Text(c, style: TextStyle(
                  color: sel ? t.primary : t.text,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                )),
              ),
            );
          }).toList()),
          const SizedBox(height: 16),

          // ── Valor base de apuesta ────────────────────────────────────
          _Field(
            label: 'Valor base de apuesta (\$$_currency)',
            ctrl: _unitCtrl, t: t,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            hint: 'Ej: 5, 10, 50',
          ),
          const SizedBox(height: 24),

          // ── Guardar ──────────────────────────────────────────────────
          GPrimaryButton(
            label: _saving ? 'Guardando...' : 'Guardar perfil',
            onTap: _saving ? null : () => _save(context),
          ),
        ],
      )),
    );
  }

  Future<void> _save(BuildContext ctx) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        backgroundColor: widget.t.loss,
        content: const Text('El nombre no puede estar vacío'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final hcp  = double.tryParse(_hcpCtrl.text.replaceAll(',', '.')) ?? 0;
      final unit = double.tryParse(_unitCtrl.text) ?? 5;
      final nick = _nicknameCtrl.text.trim().isEmpty
          ? null : _nicknameCtrl.text.trim();

      await ctx.read<UserProfileProvider>().updateFields({
        'displayName':      name,
        'nickname':         nick,
        'defaultHandicap':  hcp,
        'colorIndex':       _colorIdx,
        'defaultCurrency':  _currency,
        'defaultUnitValue': unit,
      });

      if (ctx.mounted) {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          backgroundColor: widget.t.profit,
          content: const Text('Perfil guardado'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('_ProfileFormSheet save error: $e');
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          backgroundColor: widget.t.loss,
          content: Text('Error al guardar: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN CAMPOS FAVORITOS
// ─────────────────────────────────────────────────────────────────────────────
class _FavCoursesSection extends StatelessWidget {
  final GolfTheme t;
  const _FavCoursesSection({required this.t});

  @override
  Widget build(BuildContext context) {
    final profProv = context.watch<UserProfileProvider>();
    final favs     = profProv.favCourses;

    return Column(children: [
      // Lista de favoritos
      if (favs.isEmpty)
        GCard(child: Row(children: [
          Icon(Icons.star_border_rounded, color: t.sub, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sin campos favoritos',
                style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
            Text('Agrega campos que juegas seguido.',
                style: TextStyle(color: t.sub, fontSize: 12)),
          ])),
        ]))
      else
        ...favs.map((fav) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GCard(child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.golf_course, color: t.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fav.displayName,
                  style: TextStyle(color: t.text,
                      fontWeight: FontWeight.w700, fontSize: 14)),
              if (fav.location.isNotEmpty)
                Text(fav.location,
                    style: TextStyle(color: t.sub, fontSize: 11)),
              const SizedBox(height: 4),
              // ── Chip de salida preferida ─────────────────────
              if (fav.hasCachedData && fav.cachedCourse!.allTees.isNotEmpty)
                GestureDetector(
                  onTap: () => _showTeeSheet(context, fav, profProv, t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: t.divider),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.flag_outlined, size: 11, color: t.sub),
                      const SizedBox(width: 4),
                      Text(
                        fav.preferredTeeName != null
                            ? 'Salida: ${fav.preferredTeeName}'
                            : 'Elegir salida favorita',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: fav.preferredTeeName != null ? t.accent : t.sub,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.edit_outlined, size: 10, color: t.sub),
                    ]),
                  ),
                )
              else if (!fav.hasCachedData)
                Text('Selecciona este campo en una ronda para ver salidas',
                    style: TextStyle(color: t.sub, fontSize: 10)),
            ])),
            GestureDetector(
              onTap: () => profProv.removeFavCourse(fav.courseId),
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.star_rounded, color: Colors.amber, size: 22),
              ),
            ),
          ])),
        )),

      // Botón agregar campo
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () => _addCourse(context),
        child: Container(
          height: 48, width: double.infinity,
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.accent.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_location_outlined, color: t.accent, size: 18),
            const SizedBox(width: 8),
            Text('Agregar campo favorito',
                style: TextStyle(color: t.accent, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]);
  }

  /// Muestra selector de salida preferida para un campo favorito.
  void _showTeeSheet(BuildContext ctx, FavoriteCourse fav,
      UserProfileProvider profProv, GolfTheme t) {
    if (!fav.hasCachedData || fav.cachedCourse!.allTees.isEmpty) return;
    final course = fav.cachedCourse!;
    String? picked = fav.preferredTeeName;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: t.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx2, setSt) {
        void saveTee(String name) {
          setSt(() => picked = name);
          profProv.updateFavCourseTee(fav.courseId, name);
          Navigator.pop(ctx2);
        }

        Widget teeChip(ApiTeeBox tee, {bool female = false}) {
          final isSelected = picked == tee.teeName;
          final color = female ? t.accent : t.primary;
          return GestureDetector(
            onTap: () => saveTee(tee.teeName),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.12) : t.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? color : t.divider, width: isSelected ? 2 : 1),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isSelected) ...[
                    Icon(Icons.check_circle_rounded, color: color, size: 14),
                    const SizedBox(width: 4),
                  ],
                  Text(tee.teeName, style: TextStyle(color: isSelected ? color : t.text, fontWeight: FontWeight.w700, fontSize: 14)),
                ]),
                Text('CR ${tee.courseRating.toStringAsFixed(1)} / Slope ${tee.slopeRating}',
                    style: TextStyle(color: isSelected ? color.withValues(alpha: 0.7) : t.sub, fontSize: 10)),
              ]),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24,
              left: 20, right: 20, top: 24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Salida favorita', style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
                Text(fav.displayName, style: TextStyle(color: t.sub, fontSize: 12)),
              ])),
              GestureDetector(onTap: () => Navigator.pop(ctx2), child: Icon(Icons.close, color: t.sub)),
            ]),
            const SizedBox(height: 6),
            Text('Se usará como salida por defecto al elegir este campo en una ronda.',
                style: TextStyle(color: t.sub, fontSize: 12)),
            const SizedBox(height: 16),
            if (course.maleTees.isNotEmpty) ...[
              Align(alignment: Alignment.centerLeft,
                  child: Text('TEEs MASCULINOS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: course.maleTees.map((tee) => teeChip(tee)).toList()),
            ],
            if (course.femaleTees.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft,
                  child: Text('TEEs FEMENINOS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: course.femaleTees.map((tee) => teeChip(tee, female: true)).toList()),
            ],
            const SizedBox(height: 8),
          ])),
        );
      }),
    );
  }

  void _addCourse(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: GolfThemeExt.current.card,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FavCoursePickerSheet(t: t),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHEET PARA AGREGAR CAMPO FAVORITO (reutiliza la API de golf)
// ─────────────────────────────────────────────────────────────────────────────
class _FavCoursePickerSheet extends StatefulWidget {
  final GolfTheme t;
  const _FavCoursePickerSheet({required this.t});
  @override State<_FavCoursePickerSheet> createState() => _FavCoursePickerSheetState();
}

class _FavCoursePickerSheetState extends State<_FavCoursePickerSheet> {
  final _ctrl = TextEditingController();
  List<ApiCourse> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) return;
    setState(() { _searching = true; _error = null; _results = []; });
    try {
      final res = await GolfCourseService.search(q);
      if (mounted) setState(() { _results = res; _searching = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Error: $e'; _searching = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 16, right: 16, top: 20,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          // Título
          Row(children: [
            Text('Agregar campo favorito',
                style: TextStyle(color: t.text, fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.close, color: t.sub),
            ),
          ]),
          const SizedBox(height: 14),

          // Buscador
          TextField(
            controller: _ctrl,
            autofocus: true,
            style: TextStyle(color: t.text, fontSize: 14),
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Buscar campo...',
              hintStyle: TextStyle(color: t.sub),
              prefixIcon: Icon(Icons.search, color: t.sub, size: 20),
              suffixIcon: _searching
                  ? Padding(padding: const EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: t.primary, strokeWidth: 2)))
                  : IconButton(
                      icon: Icon(Icons.search, color: t.primary),
                      onPressed: () => _search(_ctrl.text),
                    ),
              fillColor: t.surface, filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.divider)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.divider)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 10),

          // Resultados
          Expanded(child: _buildResults(context, t)),
        ]),
      ),
    );
  }

  Widget _buildResults(BuildContext ctx, GolfTheme t) {
    if (_searching) return Center(child: CircularProgressIndicator(color: t.primary));
    if (_error != null) return Center(child: Text(_error!, style: TextStyle(color: t.loss)));
    if (_results.isEmpty && _ctrl.text.length >= 2) {
      return Center(child: Text('Sin resultados',
          style: TextStyle(color: t.sub, fontSize: 14)));
    }
    if (_results.isEmpty) {
      return Center(child: Text('Escribe el nombre del campo y presiona buscar',
          textAlign: TextAlign.center,
          style: TextStyle(color: t.sub, fontSize: 13)));
    }

    final profProv = ctx.watch<UserProfileProvider>();

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final course  = _results[i];
        final isFav   = profProv.isFavCourse(course.id.toString());
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GCard(
            onTap: isFav ? null : () async {
              await profProv.toggleFavCourse(
                course.id.toString(),
                course.clubName,
                courseName: course.courseName,
                city: course.city.isNotEmpty ? course.city : null,
                country: course.country.isNotEmpty ? course.country : null,
                // Sin apiCourse aquí porque solo tenemos los datos básicos de búsqueda.
                // El usuario deberá seleccionar el campo en una ronda para cachear los tees.
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
                final name = course.courseName.isNotEmpty && course.courseName != course.clubName
                    ? '${course.clubName} — ${course.courseName}'
                    : course.clubName;
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  backgroundColor: t.profit,
                  content: Text('$name agregado a favoritos'),
                  duration: const Duration(seconds: 2),
                ));
              }
            },
            color: isFav ? t.primary.withValues(alpha: 0.05) : null,
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.golf_course,
                    color: isFav ? Colors.amber : t.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.clubName,
                      style: TextStyle(color: t.text,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  if (course.courseName.isNotEmpty && course.courseName != course.clubName)
                    Text(course.courseName,
                        style: TextStyle(color: t.sub, fontSize: 11)),
                  Text(
                    [course.city, course.country]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: TextStyle(color: t.sub, fontSize: 11),
                  ),
                ],
              )),
              Icon(
                isFav ? Icons.star_rounded : Icons.star_border_rounded,
                color: isFav ? Colors.amber : t.sub,
                size: 22,
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CAMPOS DE TEXTO REUTILIZABLES
// ─────────────────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final GolfTheme t;
  final TextInputType? keyboardType;
  final String? hint;
  const _Field({
    required this.label, required this.ctrl, required this.t,
    this.keyboardType, this.hint,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: keyboardType,
    style: TextStyle(color: t.text, fontSize: 14),
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      hintStyle: TextStyle(color: t.sub.withValues(alpha: 0.6), fontSize: 12),
      labelStyle: TextStyle(color: t.sub),
      fillColor: t.surface, filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.divider)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.primary, width: 2)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// OPCIONES DE TEMA (sin cambios)
// ─────────────────────────────────────────────────────────────────────────────
class _ThemeOption extends StatelessWidget {
  final AppThemeMode mode;
  final RoundProvider prov;
  final GolfTheme t;
  const _ThemeOption({required this.mode, required this.prov, required this.t});

  @override
  Widget build(BuildContext context) {
    final sel = prov.themeMode == mode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => prov.setTheme(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: sel ? t.primary.withValues(alpha: 0.1) : t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? t.primary : t.divider),
          ),
          child: Row(children: [
            _ThemeSwatch(mode: mode, t: t),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_label(mode), style: TextStyle(
                  color: sel ? t.primary : t.text,
                  fontWeight: FontWeight.w700, fontSize: 14)),
              Text(_desc(mode), style: TextStyle(color: t.sub, fontSize: 12)),
            ])),
            if (sel) Icon(Icons.check_circle, color: t.primary, size: 20),
          ]),
        ),
      ),
    );
  }

  String _label(AppThemeMode m) => switch (m) {
    AppThemeMode.light   => 'Modo Claro',
    AppThemeMode.dark    => 'Modo Oscuro',
    AppThemeMode.classic => 'Clásico',
  };

  String _desc(AppThemeMode m) => switch (m) {
    AppThemeMode.light   => '#FFFFFF · Verde forestal #2E7D32',
    AppThemeMode.dark    => '#111111 · Verde brillante #4CAF50',
    AppThemeMode.classic => 'Verde fairway · Crema · Dorado #F9A825',
  };
}

class _ThemeSwatch extends StatelessWidget {
  final AppThemeMode mode;
  final GolfTheme t;
  const _ThemeSwatch({required this.mode, required this.t});

  @override
  Widget build(BuildContext context) {
    final (bg, accent) = switch (mode) {
      AppThemeMode.light   => (const Color(0xFFFFFFFF), const Color(0xFF2E7D32)),
      AppThemeMode.dark    => (const Color(0xFF111111), const Color(0xFF4CAF50)),
      AppThemeMode.classic => (const Color(0xFF1B5E20), const Color(0xFFF9A825)),
    };
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.divider),
      ),
      child: Center(child: Container(
        width: 18, height: 18,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MÓDULOS DE APUESTA (sin cambios)
// ─────────────────────────────────────────────────────────────────────────────
class _BetModulesInfo extends StatelessWidget {
  final GolfTheme t;
  const _BetModulesInfo({required this.t});

  @override
  Widget build(BuildContext context) {
    final modules = [
      ('Nassau',  'Front 9, Back 9 y Total 18. Con press opcional'),
      ('Skins',   'Gana el hoyo. Empate acumula el pozo'),
      ('Medal',   'Menor score neto total gana'),
      ('Oyeses',  'Ranking en hoyos par 3. Jerárquico'),
      ('Putts',   'Menor total de putts gana F9/B9/Total'),
      ('Units',   'Birdie, Eagle, Sandy, Par único, Hole Out'),
    ];
    return Column(children: modules.map((m) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.$1, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(m.$2, style: TextStyle(color: t.sub, fontSize: 12)),
        ])),
      ])),
    )).toList());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REGLAS (sin cambios)
// ─────────────────────────────────────────────────────────────────────────────
class _RulesReference extends StatelessWidget {
  final GolfTheme t;
  const _RulesReference({required this.t});

  @override
  Widget build(BuildContext context) {
    final rules = [
      ('Score Bruto', 'Golpes físicos anotados en el hoyo'),
      ('Score Neto', 'Bruto menos strokes de handicap recibidos'),
      ('Handicap', 'Se aplica por hoyo según Stroke Index'),
      ('Carry Over', 'Empates acumulan el valor al siguiente hoyo'),
      ('Press', 'Nueva apuesta cuando vas X hoyos abajo (Nassau)'),
      ('Sliding', 'Ajuste bilateral de handicap entre dos jugadores'),
    ];
    return Column(children: rules.map((r) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.$1, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(r.$2, style: TextStyle(color: t.sub, fontSize: 12)),
        ])),
      ])),
    )).toList());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA DE CONFIGURACIONES DE PARTIDA
// ─────────────────────────────────────────────────────────────────────────────
class _GamePresetsCard extends StatefulWidget {
  final GolfTheme t;
  const _GamePresetsCard({required this.t});

  @override
  State<_GamePresetsCard> createState() => _GamePresetsCardState();
}

class _GamePresetsCardState extends State<_GamePresetsCard> {
  int _presetCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final presets = await FirestoreService.getGamePresets();
    if (mounted) setState(() { _presetCount = presets.length; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GamePresetsScreen()),
        );
        // Recargar el conteo al volver
        _loadCount();
      },
      child: GCard(
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune, color: t.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Configuraciones de partida',
                style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 15)),
            if (_loading)
              Text('Cargando...', style: TextStyle(color: t.sub, fontSize: 12))
            else
              Text(
                _presetCount == 0
                    ? 'Sin configuraciones — toca para crear'
                    : '$_presetCount configuración${_presetCount != 1 ? 'es' : ''} guardada${_presetCount != 1 ? 's' : ''}',
                style: TextStyle(color: t.sub, fontSize: 12),
              ),
          ])),
          Icon(Icons.arrow_forward_ios, color: t.sub, size: 14),
        ]),
      ),
    );
  }
}
