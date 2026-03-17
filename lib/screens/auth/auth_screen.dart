// ─────────────────────────────────────────────────────────────────────────────
// AUTH SCREEN — Login y Registro con Email + Google
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/round_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  // Login
  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl  = TextEditingController();
  bool _loginPassVisible = false;
  // Register
  final _regNameCtrl  = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl  = TextEditingController();
  final _regPass2Ctrl = TextEditingController();
  bool _regPassVisible = false;
  // Reset
  bool _showReset = false;
  final _resetEmailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginEmailCtrl.dispose(); _loginPassCtrl.dispose();
    _regNameCtrl.dispose(); _regEmailCtrl.dispose();
    _regPassCtrl.dispose(); _regPass2Ctrl.dispose();
    _resetEmailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<RoundProvider>().theme;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(children: [
            const SizedBox(height: 24),
            // Logo
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('⛳️', style: TextStyle(fontSize: 40))),
            ),
            const SizedBox(height: 14),
            Text('Golf Bet Master',
                style: TextStyle(color: t.text, fontSize: 26, fontWeight: FontWeight.w800)),
            Text('Gestión de apuestas de golf',
                style: TextStyle(color: t.sub, fontSize: 13)),
            const SizedBox(height: 28),

            if (_showReset) ...[
              _ResetPasswordCard(
                ctrl: _resetEmailCtrl, t: t,
                onBack: () => setState(() { _showReset = false; _resetEmailCtrl.clear(); }),
              ),
            ] else ...[
              // ── Botón Google (primero, destacado) ──────────────────────────
              _GoogleButton(t: t),
              const SizedBox(height: 16),
              // ── Divisor "o continúa con email" ────────────────────────────
              _Divider(t: t),
              const SizedBox(height: 16),
              // ── Tabs Email / Registro ──────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabs,
                  labelColor: t.primary,
                  unselectedLabelColor: t.sub,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  indicatorColor: t.primary,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [Tab(text: 'Iniciar sesión'), Tab(text: 'Registrarse')],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 340,
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _LoginTab(
                      emailCtrl: _loginEmailCtrl, passCtrl: _loginPassCtrl,
                      passVisible: _loginPassVisible,
                      onTogglePass: () => setState(() => _loginPassVisible = !_loginPassVisible),
                      onForgot: () => setState(() {
                        _showReset = true;
                        _resetEmailCtrl.text = _loginEmailCtrl.text;
                      }),
                      t: t,
                    ),
                    _RegisterTab(
                      nameCtrl: _regNameCtrl, emailCtrl: _regEmailCtrl,
                      passCtrl: _regPassCtrl, pass2Ctrl: _regPass2Ctrl,
                      passVisible: _regPassVisible,
                      onTogglePass: () => setState(() => _regPassVisible = !_regPassVisible),
                      t: t,
                    ),
                  ],
                ),
              ),
            ],

            // Error global
            Consumer<AuthProvider>(builder: (_, auth, __) {
              if (auth.error == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.loss.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.loss.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline, color: t.loss, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(auth.error!, style: TextStyle(color: t.loss, fontSize: 13))),
                  GestureDetector(
                    onTap: () => context.read<AuthProvider>().clearError(),
                    child: Icon(Icons.close, color: t.loss, size: 16),
                  ),
                ]),
              );
            }),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}

// ── Botón de Google ────────────────────────────────────────────────────────────
class _GoogleButton extends StatelessWidget {
  final GolfTheme t;
  const _GoogleButton({required this.t});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: auth.loading ? null : () async {
          final ok = await context.read<AuthProvider>().loginWithGoogle();
          if (ok && context.mounted) {
            context.read<AuthProvider>().clearError();
          }
        },
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: t.divider, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: t.card,
        ),
        child: auth.loading
            ? SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: t.primary))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                // Ícono SVG de Google hecho con texto (no requiere assets)
                _GoogleLogo(),
                const SizedBox(width: 10),
                Text('Continuar con Google',
                    style: TextStyle(color: t.text, fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22, height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;
    // G de Google con colores oficiales (simplificado como arco de 4 colores)
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = size.width * 0.18;
    final colors = [
      const Color(0xFF4285F4), // azul
      const Color(0xFFEA4335), // rojo
      const Color(0xFFFBBC05), // amarillo
      const Color(0xFF34A853), // verde
    ];
    for (int i = 0; i < 4; i++) {
      paint.color = colors[i];
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.85),
        (i * 90 - 90) * (3.14159 / 180),
        90 * (3.14159 / 180),
        false, paint,
      );
    }
    // Línea recta hacia la derecha para la "G"
    final fillPaint = Paint()..color = const Color(0xFF4285F4)..strokeWidth = size.width * 0.18..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx, cy), Offset(cx + r * 0.85, cy), fillPaint);
  }
  @override bool shouldRepaint(_) => false;
}

// ── Divisor ────────────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  final GolfTheme t;
  const _Divider({required this.t});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Divider(color: t.divider)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('o continúa con email', style: TextStyle(color: t.sub, fontSize: 12)),
      ),
      Expanded(child: Divider(color: t.divider)),
    ]);
  }
}

// ── Tab Login ─────────────────────────────────────────────────────────────────
class _LoginTab extends StatelessWidget {
  final TextEditingController emailCtrl, passCtrl;
  final bool passVisible;
  final VoidCallback onTogglePass, onForgot;
  final GolfTheme t;
  const _LoginTab({required this.emailCtrl, required this.passCtrl,
    required this.passVisible, required this.onTogglePass,
    required this.onForgot, required this.t});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Field(ctrl: emailCtrl, label: 'Correo electrónico', icon: Icons.email_outlined,
        keyboardType: TextInputType.emailAddress, t: t),
      const SizedBox(height: 12),
      _Field(ctrl: passCtrl, label: 'Contraseña', icon: Icons.lock_outline,
        obscure: !passVisible, t: t,
        suffix: IconButton(
          icon: Icon(passVisible ? Icons.visibility_off : Icons.visibility, color: t.sub, size: 18),
          onPressed: onTogglePass,
        )),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: onForgot,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4)),
          child: Text('¿Olvidaste tu contraseña?', style: TextStyle(color: t.primary, fontSize: 12)),
        ),
      ),
      const SizedBox(height: 4),
      _SubmitButton(
        label: 'Iniciar sesión', loading: auth.loading, t: t,
        onTap: () async {
          if (emailCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Completa todos los campos')));
            return;
          }
          final ok = await context.read<AuthProvider>().login(
            email: emailCtrl.text.trim(), password: passCtrl.text,
          );
          if (ok && context.mounted) context.read<AuthProvider>().clearError();
        },
      ),
    ]);
  }
}

// ── Tab Register ──────────────────────────────────────────────────────────────
class _RegisterTab extends StatelessWidget {
  final TextEditingController nameCtrl, emailCtrl, passCtrl, pass2Ctrl;
  final bool passVisible;
  final VoidCallback onTogglePass;
  final GolfTheme t;
  const _RegisterTab({required this.nameCtrl, required this.emailCtrl,
    required this.passCtrl, required this.pass2Ctrl,
    required this.passVisible, required this.onTogglePass, required this.t});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Field(ctrl: nameCtrl, label: 'Nombre completo', icon: Icons.person_outline, t: t),
      const SizedBox(height: 10),
      _Field(ctrl: emailCtrl, label: 'Correo electrónico', icon: Icons.email_outlined,
        keyboardType: TextInputType.emailAddress, t: t),
      const SizedBox(height: 10),
      _Field(ctrl: passCtrl, label: 'Contraseña (mín. 6 caracteres)', icon: Icons.lock_outline,
        obscure: !passVisible, t: t,
        suffix: IconButton(
          icon: Icon(passVisible ? Icons.visibility_off : Icons.visibility, color: t.sub, size: 18),
          onPressed: onTogglePass,
        )),
      const SizedBox(height: 10),
      _Field(ctrl: pass2Ctrl, label: 'Confirmar contraseña', icon: Icons.lock_outline,
        obscure: !passVisible, t: t),
      const SizedBox(height: 14),
      _SubmitButton(
        label: 'Crear cuenta', loading: auth.loading, t: t,
        onTap: () async {
          if (nameCtrl.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ingresa tu nombre')));
            return;
          }
          if (passCtrl.text != pass2Ctrl.text) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Las contraseñas no coinciden'),
                backgroundColor: Colors.red));
            return;
          }
          await context.read<AuthProvider>().register(
            email: emailCtrl.text.trim(),
            password: passCtrl.text,
            name: nameCtrl.text.trim(),
          );
        },
      ),
    ]);
  }
}

// ── Reset Password ────────────────────────────────────────────────────────────
class _ResetPasswordCard extends StatelessWidget {
  final TextEditingController ctrl;
  final GolfTheme t;
  final VoidCallback onBack;
  const _ResetPasswordCard({required this.ctrl, required this.t, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(icon: Icon(Icons.arrow_back, color: t.text), onPressed: onBack),
        Text('Recuperar contraseña',
            style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
      const SizedBox(height: 12),
      Text('Te enviaremos un correo para restablecer tu contraseña.',
          style: TextStyle(color: t.sub, fontSize: 13)),
      const SizedBox(height: 16),
      _Field(ctrl: ctrl, label: 'Correo electrónico', icon: Icons.email_outlined,
        keyboardType: TextInputType.emailAddress, t: t),
      const SizedBox(height: 16),
      _SubmitButton(
        label: 'Enviar correo', loading: auth.loading, t: t,
        onTap: () async {
          final ok = await context.read<AuthProvider>().resetPassword(ctrl.text.trim());
          if (ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Correo enviado. Revisa tu bandeja.')));
            onBack();
          }
        },
      ),
    ]);
  }
}

// ── Widgets reutilizables ─────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final GolfTheme t;
  const _Field({required this.ctrl, required this.label, required this.icon,
    required this.t, this.obscure = false, this.keyboardType, this.suffix});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: t.text, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.sub, fontSize: 13),
        prefixIcon: Icon(icon, color: t.sub, size: 18),
        suffixIcon: suffix,
        filled: true, fillColor: t.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.primary, width: 1.5)),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  final GolfTheme t;
  const _SubmitButton({required this.label, required this.loading,
    required this.onTap, required this.t});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }
}
