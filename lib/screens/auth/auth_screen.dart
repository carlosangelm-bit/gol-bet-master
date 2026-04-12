// ─────────────────────────────────────────────────────────────────────────────
// AUTH SCREEN — Diseño premium con logo, fondo verde y formulario flotante
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;
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
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF1A3A1C),
      body: Stack(
        children: [
          // ── Fondo decorativo ──────────────────────────────────────────────
          Positioned.fill(child: _GolfBackground()),

          // ── Contenido principal ───────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // ── Sección hero con logo ─────────────────────────────────
                SizedBox(
                  height: size.height * 0.34,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo con sombra y brillo
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 30,
                                spreadRadius: 2,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: const Color(0xFFD4A520).withValues(alpha: 0.25),
                                blurRadius: 40,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              'assets/icon/logo_main.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Título
                        const Text(
                          'Golf Bet Master',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            shadows: [
                              Shadow(
                                color: Colors.black38,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Tagline con chips decorativos
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _HeroBadge(icon: '⛳', label: 'Golf'),
                            const SizedBox(width: 6),
                            _HeroBadge(icon: '💰', label: 'Apuestas'),
                            const SizedBox(width: 6),
                            _HeroBadge(icon: '🏆', label: 'Resultados'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Tarjeta de formulario ─────────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: t.bg,
                      borderRadius: const BorderRadius.only(
                        topLeft:  Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 30,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: _showReset
                          ? _ResetPasswordCard(
                              ctrl: _resetEmailCtrl, t: t,
                              onBack: () => setState(() {
                                _showReset = false;
                                _resetEmailCtrl.clear();
                              }),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Cabecera de la tarjeta
                                Text(
                                  'Bienvenido',
                                  style: TextStyle(
                                    color: t.text,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Inicia sesión o crea tu cuenta para continuar',
                                  style: TextStyle(color: t.sub, fontSize: 13),
                                ),
                                const SizedBox(height: 20),

                                // ── Botón Google ──────────────────────────
                                _GoogleButton(t: t),
                                const SizedBox(height: 16),

                                // ── Divisor ───────────────────────────────
                                _Divider(t: t),
                                const SizedBox(height: 16),

                                // ── Tabs email / registro ─────────────────
                                Container(
                                  decoration: BoxDecoration(
                                    color: t.surface,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: TabBar(
                                    controller: _tabs,
                                    labelColor: t.primary,
                                    unselectedLabelColor: t.sub,
                                    labelStyle: const TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 14),
                                    indicatorColor: t.primary,
                                    indicatorSize: TabBarIndicatorSize.tab,
                                    dividerColor: Colors.transparent,
                                    tabs: const [
                                      Tab(text: 'Iniciar sesión'),
                                      Tab(text: 'Registrarse'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),

                                SizedBox(
                                  height: 340,
                                  child: TabBarView(
                                    controller: _tabs,
                                    children: [
                                      _LoginTab(
                                        emailCtrl: _loginEmailCtrl,
                                        passCtrl: _loginPassCtrl,
                                        passVisible: _loginPassVisible,
                                        onTogglePass: () => setState(
                                            () => _loginPassVisible = !_loginPassVisible),
                                        onForgot: () => setState(() {
                                          _showReset = true;
                                          _resetEmailCtrl.text =
                                              _loginEmailCtrl.text;
                                        }),
                                        t: t,
                                      ),
                                      _RegisterTab(
                                        nameCtrl: _regNameCtrl,
                                        emailCtrl: _regEmailCtrl,
                                        passCtrl: _regPassCtrl,
                                        pass2Ctrl: _regPass2Ctrl,
                                        passVisible: _regPassVisible,
                                        onTogglePass: () => setState(
                                            () => _regPassVisible = !_regPassVisible),
                                        t: t,
                                      ),
                                    ],
                                  ),
                                ),

                                // Error global
                                Consumer<AuthProvider>(
                                    builder: (_, auth, __) {
                                  if (auth.error == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Container(
                                    margin: const EdgeInsets.only(top: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: t.loss.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: t.loss.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(children: [
                                      Icon(Icons.error_outline,
                                          color: t.loss, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                          child: Text(auth.error!,
                                              style: TextStyle(
                                                  color: t.loss, fontSize: 13))),
                                      GestureDetector(
                                        onTap: () => context
                                            .read<AuthProvider>()
                                            .clearError(),
                                        child: Icon(Icons.close,
                                            color: t.loss, size: 16),
                                      ),
                                    ]),
                                  );
                                }),

                              ],
                            ),
                    ),
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

// ── Fondo decorativo con patrón de golf ───────────────────────────────────────
class _GolfBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GolfBgPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _GolfBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Gradiente de fondo: verde muy oscuro arriba → verde medio abajo
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Color(0xFF0D2B0F),
          Color(0xFF1A3A1C),
          Color(0xFF1E4620),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Círculo decorativo grande (luz de fondo)
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFD4A520).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.18),
          radius: size.width * 0.7));
    canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.18),
        size.width * 0.7,
        glowPaint);

    // Líneas decorativas: contorno de ondas de campo de golf
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < 5; i++) {
      final path = Path();
      final y = size.height * 0.05 + i * size.height * 0.06;
      path.moveTo(0, y);
      for (double x = 0; x <= size.width; x += 30) {
        path.quadraticBezierTo(
          x + 15, y - 8,
          x + 30, y,
        );
      }
      canvas.drawPath(path, linePaint);
    }

    // Pequeñas estrellas / puntos decorativos (representan hoyos)
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    final rng = math.Random(42);
    for (int i = 0; i < 18; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * 0.38;
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }

    // Líneas de fairway (verticales difusas)
    final fairwayPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.03),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.4))
      ..strokeWidth = 28
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 4; i++) {
      final x = size.width * (0.1 + i * 0.27);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height * 0.4), fairwayPaint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Badge hero pequeño ────────────────────────────────────────────────────────
class _HeroBadge extends StatelessWidget {
  final String icon;
  final String label;
  const _HeroBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
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
        onPressed: auth.loading
            ? null
            : () async {
                final ok =
                    await context.read<AuthProvider>().loginWithGoogle();
                if (ok && context.mounted) {
                  context.read<AuthProvider>().clearError();
                }
              },
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: t.divider, width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: t.card,
        ),
        child: auth.loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: t.primary))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleLogo(),
                  const SizedBox(width: 10),
                  Text(
                    'Continuar con Google',
                    style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 15),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.18;
    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFFEA4335),
      const Color(0xFFFBBC05),
      const Color(0xFF34A853),
    ];
    for (int i = 0; i < 4; i++) {
      paint.color = colors[i];
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.85),
        (i * 90 - 90) * (math.pi / 180),
        90 * (math.pi / 180),
        false,
        paint,
      );
    }
    final fillPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = size.width * 0.18
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx, cy), Offset(cx + r * 0.85, cy), fillPaint);
  }

  @override
  bool shouldRepaint(_) => false;
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
        child: Text('o continúa con email',
            style: TextStyle(color: t.sub, fontSize: 12)),
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
  const _LoginTab({
    required this.emailCtrl,
    required this.passCtrl,
    required this.passVisible,
    required this.onTogglePass,
    required this.onForgot,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Field(
          ctrl: emailCtrl,
          label: 'Correo electrónico',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          t: t),
      const SizedBox(height: 12),
      _Field(
          ctrl: passCtrl,
          label: 'Contraseña',
          icon: Icons.lock_outline,
          obscure: !passVisible,
          t: t,
          suffix: IconButton(
            icon: Icon(
                passVisible ? Icons.visibility_off : Icons.visibility,
                color: t.sub,
                size: 18),
            onPressed: onTogglePass,
          )),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: onForgot,
          style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 0, vertical: 4)),
          child: Text('¿Olvidaste tu contraseña?',
              style: TextStyle(color: t.primary, fontSize: 12)),
        ),
      ),
      const SizedBox(height: 4),
      _SubmitButton(
        label: 'Iniciar sesión',
        loading: auth.loading,
        t: t,
        onTap: () async {
          if (emailCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Completa todos los campos')));
            return;
          }
          final ok = await context
              .read<AuthProvider>()
              .login(email: emailCtrl.text.trim(), password: passCtrl.text);
          if (ok && context.mounted) {
            context.read<AuthProvider>().clearError();
          }
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
  const _RegisterTab({
    required this.nameCtrl,
    required this.emailCtrl,
    required this.passCtrl,
    required this.pass2Ctrl,
    required this.passVisible,
    required this.onTogglePass,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Field(
          ctrl: nameCtrl,
          label: 'Nombre completo',
          icon: Icons.person_outline,
          t: t),
      const SizedBox(height: 10),
      _Field(
          ctrl: emailCtrl,
          label: 'Correo electrónico',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          t: t),
      const SizedBox(height: 10),
      _Field(
          ctrl: passCtrl,
          label: 'Contraseña (mín. 6 caracteres)',
          icon: Icons.lock_outline,
          obscure: !passVisible,
          t: t,
          suffix: IconButton(
            icon: Icon(
                passVisible ? Icons.visibility_off : Icons.visibility,
                color: t.sub,
                size: 18),
            onPressed: onTogglePass,
          )),
      const SizedBox(height: 10),
      _Field(
          ctrl: pass2Ctrl,
          label: 'Confirmar contraseña',
          icon: Icons.lock_outline,
          obscure: !passVisible,
          t: t),
      const SizedBox(height: 14),
      _SubmitButton(
        label: 'Crear cuenta',
        loading: auth.loading,
        t: t,
        onTap: () async {
          if (nameCtrl.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ingresa tu nombre')));
            return;
          }
          if (passCtrl.text != pass2Ctrl.text) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Las contraseñas no coinciden'),
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
  const _ResetPasswordCard(
      {required this.ctrl, required this.t, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(
            icon: Icon(Icons.arrow_back, color: t.text), onPressed: onBack),
        Text('Recuperar contraseña',
            style: TextStyle(
                color: t.text, fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
      const SizedBox(height: 12),
      Text('Te enviaremos un correo para restablecer tu contraseña.',
          style: TextStyle(color: t.sub, fontSize: 13)),
      const SizedBox(height: 16),
      _Field(
          ctrl: ctrl,
          label: 'Correo electrónico',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          t: t),
      const SizedBox(height: 16),
      _SubmitButton(
        label: 'Enviar correo',
        loading: auth.loading,
        t: t,
        onTap: () async {
          final ok = await context
              .read<AuthProvider>()
              .resetPassword(ctrl.text.trim());
          if (ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('✅ Correo enviado. Revisa tu bandeja.')));
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
  const _Field({
    required this.ctrl,
    required this.label,
    required this.icon,
    required this.t,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });

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
        filled: true,
        fillColor: t.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
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
  const _SubmitButton(
      {required this.label,
      required this.loading,
      required this.onTap,
      required this.t});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          shadowColor: t.primary.withValues(alpha: 0.4),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }
}


