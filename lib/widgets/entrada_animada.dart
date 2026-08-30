// ─────────────────────────────────────────────────────────────────────────────
// ENTRADA COREOGRAFIADA — los elementos llegan en orden, no todos a la vez
//
// Del manual: "los elementos deben entrar en secuencia lógica, no todos a la
// vez". La secuencia no es adorno: dice en qué orden mirar. En la pantalla de
// resultados, primero el balance —la respuesta— y después el desglose.
//
// ── Lo que este widget NO hace, y es a propósito ────────────────────────────
//
// No bloquea nada. La entrada es opacidad y un desplazamiento corto; el widget
// ya está ahí, con su tamaño y su posición final, desde el primer frame. Se
// puede tocar mientras entra.
//
// Es la diferencia entre una animación que acompaña y una que hace esperar, y
// es la única forma de que esto no vaya en contra de la app en la pantalla
// donde compite con un lápiz.
//
// Y con "reducir movimiento" no hace nada en absoluto: ni retraso, ni
// desplazamiento, ni opacidad. El widget aparece.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class EntradaAnimada extends StatefulWidget {
  final Widget child;

  /// Su lugar en la secuencia. Cero entra primero.
  final int orden;

  /// Cuánto sube al entrar. Corto a propósito: un desplazamiento largo se lee
  /// como "algo se está cargando" en vez de como "algo acaba de llegar".
  final double desplazamiento;

  final Duration duracion;

  const EntradaAnimada({
    super.key,
    required this.child,
    this.orden = 0,
    this.desplazamiento = 10,
    this.duracion = GolfMotion.normal,
  });

  @override
  State<EntradaAnimada> createState() => _EntradaAnimadaState();
}

class _EntradaAnimadaState extends State<EntradaAnimada> {
  bool _dentro = false;

  @override
  void initState() {
    super.initState();
    // Al siguiente frame, no en initState: el primer build tiene que pintar el
    // estado inicial para que haya algo desde donde animar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final espera = GolfMotion.retraso(context, widget.orden);
      if (espera == Duration.zero) {
        setState(() => _dentro = true);
        return;
      }
      Future.delayed(espera, () {
        if (mounted) setState(() => _dentro = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Con el ajuste puesto, ni siquiera se monta la animación.
    if (GolfMotion.quieto(context)) return widget.child;

    final d = GolfMotion.de(context, widget.duracion);
    return AnimatedSlide(
      offset: _dentro ? Offset.zero : Offset(0, widget.desplazamiento / 100),
      duration: d,
      curve: GolfMotion.entrada,
      child: AnimatedOpacity(
        opacity: _dentro ? 1 : 0,
        duration: d,
        curve: GolfMotion.entrada,
        child: widget.child,
      ),
    );
  }
}

/// Una cifra que cambia, contada en vez de sustituida.
///
/// ── Dónde sí y dónde no ─────────────────────────────────────────────────────
///
/// Sirve para el balance final o para una posición del leaderboard: cosas que
/// cambian una vez y se miran. NO sirve para un score que se anota, porque ahí
/// lo que hace falta es que el número aparezca ya.
///
/// Con "reducir movimiento" enseña el valor final y punto.
class CifraAnimada extends StatelessWidget {
  final double valor;
  final TextStyle estilo;

  /// Cómo se escribe el número. Fuera del widget porque el formato del dinero
  /// ya está decidido en otro sitio y no puede haber dos.
  final String Function(double) formato;

  final Duration duracion;
  final TextAlign? align;

  const CifraAnimada({
    super.key,
    required this.valor,
    required this.estilo,
    required this.formato,
    this.duracion = GolfMotion.escena,
    this.align,
  });

  @override
  Widget build(BuildContext context) {
    if (GolfMotion.quieto(context)) {
      return Text(formato(valor), style: estilo, textAlign: align);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valor),
      duration: GolfMotion.de(context, duracion),
      curve: GolfMotion.cambio,
      builder: (_, v, __) => Text(formato(v), style: estilo, textAlign: align),
    );
  }
}
