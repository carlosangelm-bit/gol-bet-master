// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS COMUNES — layout idéntico en los 3 temas
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/app_theme.dart';

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

  static const _colors = [
    Color(0xFF2E7D32), Color(0xFF1565C0), Color(0xFF6A1B9A),
    Color(0xFFC62828), Color(0xFFE65100), Color(0xFF00695C),
    Color(0xFF4A148C), Color(0xFF006064),
  ];

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52, width: double.infinity,
        decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[Icon(icon, color: t.onPrimary, size: 18), const SizedBox(width: 8)],
          Text(label, style: TextStyle(color: t.onPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
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
  const GCounter({super.key, required this.value, required this.onDec, required this.onInc});

  @override
  Widget build(BuildContext context) {
    final t = GolfThemeExt.current;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _btn(Icons.remove, onDec, t),
      SizedBox(width: 38, child: Text('$value', textAlign: TextAlign.center, style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 18))),
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
