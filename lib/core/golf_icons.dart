// ─────────────────────────────────────────────────────────────────────────────
// ICONOGRAFÍA — por qué NO hay SVG propio aquí
//
// La decisión de partida era dibujar los iconos de golf a mano, dando por hecho
// que Material no los tiene. Se comprobó antes de dibujar, y los tiene:
//
//     Icons.golf_course   bandera en el hoyo   ⛳
//     Icons.sports_golf   bola y palo          🏌️
//
// Con esos dos, los VEINTICUATRO que hacen falta existen ya. Y dibujarlos igual
// habría sido exactamente lo que el propio encargo prohíbe —"no dibujes lo que
// ya está"— a cambio de mantener un juego de trazados a mano que hay que
// afinar en cada tamaño.
//
// Si algún día se quiere una marca de golf PROPIA por identidad, eso es otra
// decisión y se toma por eso, no porque falte el icono.
//
// ── QUÉ PROBLEMA RESUELVE ESTO, que no es "iconos inconsistentes" ───────────
//
// Un emoji no es un icono: es un CARÁCTER DEL SISTEMA. Y de ahí salen tres
// cosas que rompen todo lo que el sistema visual construyó:
//
//   · No hereda el color. El 🏆 se ve igual en claro y en oscuro, con sus
//     colores, mientras el resto sigue la escalera de tres niveles.
//   · Cambia según el aparato. El 🏌️ de Apple, el de Android y el de Windows
//     no se parecen: la app no se ve igual en dos teléfonos.
//   · Y es el PICO VISUAL de la pantalla. Un emoji a color junto a texto gris
//     llama más la atención que cualquier otra cosa, sin merecerlo.
//
// ── EL TRAZO SALE DEL SISTEMA ───────────────────────────────────────────────
//
// Dos reglas, y las dos se comprueban:
//
//   1 · SIEMPRE la variante OUTLINED. Es lo que da el grosor consistente que
//       pide el manual; mezclar rellenos y contornos es la inconsistencia con
//       otro nombre.
//   2 · El TAMAÑO sale de la escala tipográfica, no de un número suelto. Un
//       icono junto a una etiqueta mide como la etiqueta; junto a un valor,
//       como el valor. Así el peso visual del icono acompaña al del texto en
//       vez de competir con él.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

class GolfIcons {
  const GolfIcons._();

  // ── Golf ──────────────────────────────────────────────────────────────────
  /// La bandera en el hoyo. Sustituye a ⛳.
  static const bandera = Icons.golf_course;

  /// Bola y palo. Sustituye a 🏌️.
  static const golpe = Icons.sports_golf;

  // ── Resultado ─────────────────────────────────────────────────────────────
  static const trofeo = Icons.emoji_events_outlined;      // 🏆
  static const medalla = Icons.military_tech_outlined;    // 🥇
  static const diana = Icons.my_location;                 // 🎯
  static const destello = Icons.auto_awesome_outlined;    // 🌟 💫
  static const racha = Icons.local_fire_department_outlined; // 🔥
  static const duelo = Icons.sports_kabaddi_outlined;     // ⚔️
  static const equilibrio = Icons.balance_outlined;       // ⚖️
  static const acuerdo = Icons.handshake_outlined;        // 🤝

  // ── Dinero y datos ────────────────────────────────────────────────────────
  static const dinero = Icons.payments_outlined;          // 💰
  static const grafico = Icons.bar_chart;                 // 📊
  static const azar = Icons.casino_outlined;              // 🎲
  static const cartas = Icons.style_outlined;             // 🃏

  // ── Estado ────────────────────────────────────────────────────────────────
  static const cerrado = Icons.lock_outline;              // 🔒
  static const arrastra = Icons.refresh;                  // 🔄
  static const pantalla = Icons.tv_outlined;              // 🖥
  static const copia = Icons.visibility_outlined;         // 👁️‍🗨️
  static const rapido = Icons.bolt_outlined;              // ⚡
  static const aviso = Icons.warning_amber_rounded;       // ⚠️
  static const bien = Icons.check_circle_outline;         // ✅
  static const mal = Icons.cancel_outlined;               // ❌
  static const caminar = Icons.directions_walk;           // 👟

  // ── Tamaños, atados a la escala tipográfica ───────────────────────────────
  //
  // No son valores sueltos: cada uno acompaña a un escalón de GolfType. Un
  // icono más grande que su texto se lee como el elemento principal, y casi
  // nunca lo es.

  /// Junto a una ETIQUETA (11 px). El más pequeño que sigue siendo legible.
  static const double juntoAEtiqueta = 13;

  /// Junto a CUERPO o VALOR (15 px). El tamaño normal de la app.
  static const double juntoAValor = 17;

  /// Junto a un TÍTULO (21 px).
  static const double juntoATitulo = 22;

  /// Junto al HÉROE. Uno por pantalla, si acaso.
  static const double juntoAlHeroe = 34;
}
