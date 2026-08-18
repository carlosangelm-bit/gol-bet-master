// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS COMUNES — layout idéntico en los 3 temas
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/models.dart';

// ── Tarjeta contenedora ───────────────────────────────────────────────────────
class GCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  const GCard({super.key, required this.child, this.padding, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color ?? t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.divider, width: 1),
        ),
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

// ── Chip de balance (+/-) ─────────────────────────────────────────────────────
class BalChip extends StatelessWidget {
  final double amount;
  const BalChip({super.key, required this.amount});

  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;
    final isPos = amount >= 0;
    final color = isPos ? t.profit : t.loss;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        '${isPos ? '+' : ''}\$${amount.abs().toStringAsFixed(0)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }
}

// ── Encabezado de sección ─────────────────────────────────────────────────────
class GSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const GSectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      child: Row(children: [
        Text(title, style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

// ── Avatar de jugador ─────────────────────────────────────────────────────────
class GAvatar extends StatelessWidget {
  final String name;
  final int colorIndex;
  final double size;
  const GAvatar({super.key, required this.name, this.colorIndex = 0, this.size = 36});

  // Paleta de IDENTIDAD: dice quién, no qué pasa.
  //
  // Deliberadamente sin verde ni rojo. Antes empezaba en 0xFF2E7D32 y llevaba
  // 0xFFC62828, que son exactamente los tokens profit y loss: un equipo podía
  // pintarse del mismo rojo que significa "pagas", y eso ocurría justo en la
  // barra proporcional del marcador. Con la identidad fuera del canal del
  // dinero, un color saturado verde o rojo en pantalla solo puede ser dinero.
  static const _colors = [
    Color(0xFF283593), Color(0xFF1565C0), Color(0xFF6A1B9A),
    Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
    Color(0xFF4A148C), Color(0xFF006064),
  ];

  /// Color asignado a un jugador por su índice.
  ///
  /// Público para que otras superficies —la tarjeta de duelo por equipos, por
  /// ejemplo— usen exactamente el mismo color que su avatar. Si cada pantalla
  /// eligiera el suyo, un equipo sería verde en un sitio y azul en otro.
  static Color colorFor(int colorIndex) => _colors[colorIndex % _colors.length];

  @override
  Widget build(BuildContext context) {
    final c = _colors[colorIndex % _colors.length];
    final initials = name.trim().isEmpty ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials, style: TextStyle(color: Colors.white, fontSize: size * 0.38, fontWeight: FontWeight.w800)),
    );
  }
}

// ── Divisor ───────────────────────────────────────────────────────────────────
class GDivider extends StatelessWidget {
  const GDivider({super.key});
  @override
  Widget build(BuildContext context) => Divider(color: GolfThemeExt.current.divider, height: 1, thickness: 1);
}

// ── Celda de score coloreada por relación al par ─────────────────────────────
class ScoreCell extends StatelessWidget {
  final int? score;
  final int par;
  final bool isSelected;
  final VoidCallback? onTap;
  final double size;
  const ScoreCell({super.key, this.score, required this.par, this.isSelected = false, this.onTap, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;
    Color bg = t.surface;
    Color fg = t.text;
    BoxShape shape = BoxShape.rectangle;

    if (score != null) {
      final rel = score! - par;
      if (rel <= -2) { bg = t.scoreUnder; fg = Colors.white; shape = BoxShape.circle; }          // Eagle+: circulo azul
      else if (rel == -1) { bg = t.scoreUnder.withValues(alpha: 0.15); fg = t.scoreUnder; shape = BoxShape.circle; } // Birdie: circulo
      else if (rel == 1)  { bg = t.scoreOver.withValues(alpha: 0.15);  fg = t.scoreOver; }       // Bogey: cuadrado
      else if (rel >= 2)  { bg = t.scoreOver;  fg = Colors.white; }                              // Doble+: cuadrado rojo
    }
    if (isSelected) { bg = t.primary.withValues(alpha: 0.2); shape = BoxShape.rectangle; }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: bg, shape: shape,
          borderRadius: shape == BoxShape.rectangle ? BorderRadius.circular(6) : null,
          border: isSelected ? Border.all(color: t.primary, width: 2)
              : Border.all(color: score != null ? Colors.transparent : t.divider),
        ),
        alignment: Alignment.center,
        child: Text(
          score?.toString() ?? '·',
          style: TextStyle(color: score != null ? fg : t.sub, fontWeight: FontWeight.w800, fontSize: size * 0.39),
        ),
      ),
    );
  }
}

// ── Botón primario ────────────────────────────────────────────────────────────
class GPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  const GPrimaryButton({super.key, required this.label, this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;
    // Un botón sin acción tiene que VERSE sin acción.
    //
    // Antes pintaba t.primary siempre, así que uno deshabilitado se veía igual
    // que uno activo: al pulsarlo no pasaba nada y parecía que la app no
    // respondía, en vez de que faltaba algo por elegir.
    //
    // Está en el widget compartido y no en la pantalla donde se vio, porque el
    // fallo era del widget: afectaba a todos los botones deshabilitados de la
    // app, no solo al de empezar ronda.
    final activo = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: activo ? 1 : 0.45,
        child: Container(
          height: 52, width: double.infinity,
          decoration: BoxDecoration(
            color: activo ? t.primary : t.sub,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, color: t.onPrimary, size: 18), const SizedBox(width: 8)],
            Text(label, style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
        ),
      ),
    );
  }
}

// ── Botón secundario ──────────────────────────────────────────────────────────
class GSecButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const GSecButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52, width: double.infinity,
        decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.divider)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: t.text, fontWeight: FontWeight.w600, fontSize: 16)),
      ),
    );
  }
}

// ── Contador +/- ─────────────────────────────────────────────────────────────
class GCounter extends StatelessWidget {
  final int value;
  final VoidCallback onDec;
  final VoidCallback onInc;
  /// Cuando true, el número se muestra en color atenuado para indicar
  /// que es un valor de referencia (par) y no un score registrado.
  final bool isPlaceholder;
  const GCounter({
    super.key,
    required this.value,
    required this.onDec,
    required this.onInc,
    this.isPlaceholder = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _btn(Icons.remove, onDec, t),
      SizedBox(
        width: 38,
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isPlaceholder ? t.sub : t.text,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      _btn(Icons.add, onInc, t),
    ]);
  }

  Widget _btn(IconData ic, VoidCallback fn, GolfTheme t) => GestureDetector(
    onTap: fn,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.divider)),
      alignment: Alignment.center,
      child: Icon(ic, size: 16, color: t.text),
    ),
  );
}

// ── Toggle Chip ───────────────────────────────────────────────────────────────
class GToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const GToggleChip({super.key, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? t.accent.withValues(alpha: 0.15) : t.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? t.accent : t.divider),
        ),
        child: Text(label, style: TextStyle(color: active ? t.accent : t.sub, fontWeight: active ? FontWeight.w700 : FontWeight.w400, fontSize: 12)),
      ),
    );
  }
}

// ── Header de app común ───────────────────────────────────────────────────────
PreferredSizeWidget gAppBar(String title, GolfTheme t, {List<Widget>? actions, bool showBack = false, BuildContext? ctx}) {
  return AppBar(
    backgroundColor: t.bg,
    elevation: 0,
    leading: showBack && ctx != null ? IconButton(icon: Icon(Icons.arrow_back, color: t.text), onPressed: () => Navigator.pop(ctx)) : null,
    automaticallyImplyLeading: showBack,
    title: Text(title, style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.5)),
    actions: actions,
    bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: t.divider)),
  );
}

// ── Helper para nombre de jugador/equipo ──────────────────────────────────────
/// Renderiza el nombre del jugador/equipo.
/// Funciona para equipos Scramble (virtuales) y Best Ball (reales)
Widget playerOrTeamName(
  Player player,
  Round round, {
  required TextStyle style,
  bool showTeamIcon = true,
}) {
  // Para cualquier jugador virtual (Scramble o Best Ball)
  if (player.isVirtual) {
    final icon = isBBVirtual(player) ? Icons.group_rounded : Icons.groups_rounded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTeamIcon) ...[
          Icon(icon, size: style.fontSize, color: style.color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(player.name, style: style, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
  // Jugador individual normal
  return Text(player.name, style: style, overflow: TextOverflow.ellipsis);
}

/// Renderiza los miembros del equipo como texto secundario
/// Funciona tanto para equipos Scramble (virtuales) como Best Ball
Widget? teamMembersFootnote(
  Player player,
  Round round, {
  required TextStyle style,
}) {
  // Para cualquier jugador virtual con miembros (Scramble o Best Ball)
  if (player.isVirtual && player.teamMemberIds.isNotEmpty) {
    final memberNames = player.teamMemberIds
        .map((id) => round.players.firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id)))
        .map((p) => p.name.split(' ').first)
        .join(', ');
    final label = isBBVirtual(player) ? 'Best Ball' : 'Miembros';
    return Text(
      '$label: $memberNames',
      style: style,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }
  return null; // No es un equipo
}

// ══════════════════════════════════════════════════════════════════════════════
// TEAM HELPERS — Scramble y Best Ball
// ══════════════════════════════════════════════════════════════════════════════

/// Indica si un jugador virtual es de tipo Best Ball (prefix "bb_team_")
bool isBBVirtual(Player p) => p.isVirtual && p.id.startsWith('bb_team_');

/// Indica si un jugador virtual es de tipo Scramble (prefix "team_")
bool isScrambleVirtual(Player p) => p.isVirtual && p.id.startsWith('team_');

/// Obtiene los jugadores/equipos que deben mostrarse en Tarjeta y Resultados.
/// - Scramble: solo el virtual (team_...)
/// - Best Ball: solo el virtual de equipo (bb_team_...) — los reales se usan solo en Score
/// - Individual: el jugador real si tiene scores
List<Player> getDisplayPlayers(Round round) {
  final displayPlayers = <Player>[];
  final coveredMemberIds = <String>{};

  // 1. Agregar todos los jugadores virtuales que tienen scores
  //    (Scramble con scores, o Best Ball bb_team_ que tienen scores)
  for (final player in round.players.where((p) => p.isVirtual && round.scores.containsKey(p.id))) {
    displayPlayers.add(player);
    coveredMemberIds.addAll(player.teamMemberIds);
  }

  // 2. Agregar jugadores reales que no están cubiertos por ningún equipo virtual
  for (final player in round.players.where((p) => !p.isVirtual && round.scores.containsKey(p.id))) {
    if (!coveredMemberIds.contains(player.id)) {
      displayPlayers.add(player);
    }
  }

  return displayPlayers;
}

/// Obtiene el score bruto de un jugador/equipo para un hoyo.
/// - Virtual Scramble: score directo del virtual
/// - Virtual Best Ball: mejor grossScore entre los miembros del equipo
/// - Individual: score directo del jugador
HoleScore getBestScore(Round round, Player player, int hole) {
  if (isBBVirtual(player)) {
    // Best Ball virtual: mejor score bruto entre miembros
    final teamScores = player.teamMemberIds
        .map((id) => round.getScore(id, hole))
        .where((s) => s.hasScore)
        .toList();
    if (teamScores.isEmpty) return HoleScore(playerId: player.id, hole: hole);
    teamScores.sort((a, b) => a.grossScore!.compareTo(b.grossScore!));
    return teamScores.first;
  }
  // Scramble virtual o individual: score propio
  return round.getScore(player.id, hole);
}

/// Para un equipo Best Ball virtual, obtiene el mejor NET score de sus miembros
/// en un hoyo dado, aplicando la ventaja de cada miembro.
/// La ventaja se calcula relativa al jugador con menos handicap del duelo (baseHandicap).
///
/// [baseHandicap] = handicap del jugador base del duelo (el que tiene 0 golpes extra)
/// Cada miembro recibe golpes en los hoyos según su diferencia con ese base.
int? getBestBallNetScore(Round round, Player bbVirtual, int hole, double baseHandicap) {
  if (!isBBVirtual(bbVirtual)) return null;

  int? bestNet;
  for (final memberId in bbVirtual.teamMemberIds) {
    final sc = round.getScore(memberId, hole);
    if (!sc.hasScore) continue;

    final memberHcp = round.getHandicap(memberId);
    // Strokes que recibe este miembro en este hoyo respecto al base
    final diff = (memberHcp - baseHandicap).round().clamp(0, 18);
    final courseHole = round.course.holes.firstWhere((h) => h.hole == hole, orElse: () => CourseHole(hole: hole, par: 4, strokeIndex: 18));
    final si = courseHole.strokeIndex;
    final strokesHere = diff >= si ? 1 : 0;
    final net = sc.grossScore! - strokesHere;
    if (bestNet == null || net < bestNet) bestNet = net;
  }
  return bestNet;
}

// ── Compatibilidad con código legacy que usa getPlayerBestBallTeam ─────────
/// Clase de compatibilidad para partes del UI que todavía usan la API antigua
class BestBallTeam {
  final String teamId;
  final String teamName;
  final List<String> memberIds;
  final List<Player> members;

  const BestBallTeam({
    required this.teamId,
    required this.teamName,
    required this.memberIds,
    required this.members,
  });
}

/// Obtiene el jugador virtual Best Ball que "representa" a un jugador real,
/// o null si no está en ningún equipo Best Ball.
BestBallTeam? getPlayerBestBallTeam(Round round, String playerId) {
  for (final player in round.players.where(isBBVirtual)) {
    if (player.teamMemberIds.contains(playerId)) {
      final members = player.teamMemberIds
          .map((id) => round.players.firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id)))
          .toList();
      return BestBallTeam(
        teamId: player.id,
        teamName: player.name,
        memberIds: player.teamMemberIds,
        members: members,
      );
    }
  }
  return null;
}

/// Verifica si una ronda tiene equipos Best Ball activos
bool hasBestBallTeams(Round round) {
  return round.players.any(isBBVirtual);
}
