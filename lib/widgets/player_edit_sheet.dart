// ─────────────────────────────────────────────────────────────────────────────
// PLAYER EDIT SHEET — el ÚNICO formulario de jugador
//
// Estaba dentro de SetupScreen como _editPlayer, atado a _players, _playerTees,
// _teeOf y _selectedApiCourse. Cuando hizo falta crear un jugador desde el atajo
// de arranque rápido, la salida fácil era copiarlo.
//
// No se copió. Dos formularios de crear jugador divergen en cuanto alguien
// añada un campo a uno de los dos —el tee habitual, una foto, lo que sea— y
// entonces el mismo jugador se guarda distinto según por dónde entres.
//
// El acoplamiento se rompió pasando por parámetro lo que antes leía del State:
// el tee inicial en vez de _teeOf, y el ApiCourse en vez de leerlo del campo
// seleccionado. Con apiCourse null no se pinta la sección de tees, que es lo que
// necesita el atajo cuando todavía no hay campo elegido.
//
// Devuelve el resultado en vez de escribirlo: quien llama decide qué hacer con
// él —el wizard lo mete en _players, el atajo en la nómina de hoy— y así el
// formulario no sabe nada de ninguno de los dos.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/models.dart';
import '../services/golf_course_service.dart';
import 'common_widgets.dart';

/// Lo que el formulario devuelve. null si se cerró sin guardar.
class PlayerEditResult {
  final String name;
  final double handicap;
  final TeeInfo tee;
  const PlayerEditResult({
    required this.name,
    required this.handicap,
    required this.tee,
  });
}

/// Abre el formulario de jugador.
///
/// [apiCourse] null → sin selector de salida. Es el caso del arranque rápido
/// cuando el campo todavía no está elegido: pedir un tee de un campo que no se
/// ha decidido no significa nada.
///
/// [nombreFallback] es el nombre que se usa si se deja en blanco.
Future<PlayerEditResult?> showPlayerEditSheet(
  BuildContext context, {
  required GolfTheme t,
  required String nombreInicial,
  required double handicapInicial,
  required TeeInfo teeInicial,
  required String nombreFallback,
  ApiCourse? apiCourse,
}) {
  
    final nc = TextEditingController(text: nombreInicial);
    final hc = TextEditingController(text: handicapInicial.toStringAsFixed(1));
    // Tee actual del jugador
    TeeInfo selectedTee = teeInicial;
    final availableTees = apiCourse?.allTees ?? [];

    return showModalBottomSheet<PlayerEditResult>(context: context, backgroundColor: t.card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom + 24, left: 20, right: 20, top: 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Jugador', style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          // Nombre
          TextField(controller: nc, style: TextStyle(color: t.text),
            decoration: InputDecoration(labelText: 'Nombre', fillColor: t.surface, filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 2)),
              labelStyle: TextStyle(color: t.sub))),
          const SizedBox(height: 12),
          // HCP Index
          TextField(controller: hc, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: TextStyle(color: t.text),
            decoration: InputDecoration(labelText: 'HCP Index', fillColor: t.surface, filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 2)),
              labelStyle: TextStyle(color: t.sub),
              helperText: availableTees.isNotEmpty
                  ? 'HCP de juego se calculará según tu salida'
                  : 'Handicap base del jugador',
              helperStyle: TextStyle(color: t.sub, fontSize: 10))),

          // ── Selector de salida (solo si hay campo con tees) ──────────
          if (availableTees.isNotEmpty) ...[
            const SizedBox(height: 16),

            // Sección masculinos
            if ((apiCourse?.maleTees ?? []).isNotEmpty) ...[
              Text('TEEs MASCULINOS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: (apiCourse!.maleTees).map((tee) {
                final cleanName = tee.teeName;
                // Comparar por key (nombre + género) para evitar falsos positivos
                final thisTeeKey = TeeInfo(name: cleanName, courseRating: tee.courseRating, slopeRating: tee.slopeRating, parTotal: tee.parTotal, gender: 'M').key;
                final isSelected = selectedTee.key == thisTeeKey;
                return GestureDetector(
                  onTap: () => setSt(() => selectedTee = TeeInfo(
                    name: cleanName,
                    courseRating: tee.courseRating,
                    slopeRating: tee.slopeRating,
                    parTotal: tee.parTotal,
                    gender: 'M',
                  )),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? t.primary.withValues(alpha: 0.12) : t.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? t.primary : t.divider, width: isSelected ? 1.5 : 1),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(cleanName, style: TextStyle(color: isSelected ? t.primary : t.text, fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('CR ${tee.courseRating.toStringAsFixed(1)} / Slope ${tee.slopeRating}',
                          style: TextStyle(color: isSelected ? t.primary.withValues(alpha: 0.7) : t.sub, fontSize: 10)),
                    ]),
                  ),
                );
              }).toList()),
            ],

            // Sección femeninos
            if ((apiCourse?.femaleTees ?? []).isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('TEEs FEMENINOS', style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: (apiCourse!.femaleTees).map((tee) {
                final cleanName = tee.teeName;
                final thisTeeKey = TeeInfo(name: cleanName, courseRating: tee.courseRating, slopeRating: tee.slopeRating, parTotal: tee.parTotal, gender: 'F').key;
                final isSelected = selectedTee.key == thisTeeKey;
                return GestureDetector(
                  onTap: () => setSt(() => selectedTee = TeeInfo(
                    name: cleanName,
                    courseRating: tee.courseRating,
                    slopeRating: tee.slopeRating,
                    parTotal: tee.parTotal,
                    gender: 'F',
                  )),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? t.accent.withValues(alpha: 0.12) : t.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? t.accent : t.divider, width: isSelected ? 1.5 : 1),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(cleanName, style: TextStyle(color: isSelected ? t.accent : t.text, fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('CR ${tee.courseRating.toStringAsFixed(1)} / Slope ${tee.slopeRating}',
                          style: TextStyle(color: isSelected ? t.accent.withValues(alpha: 0.7) : t.sub, fontSize: 10)),
                    ]),
                  ),
                );
              }).toList()),
            ],
            // Mostrar HCP de juego calculado
            const SizedBox(height: 10),
            Builder(builder: (_) {
              final hcpIdx = double.tryParse(hc.text) ?? handicapInicial;
              final phcp = selectedTee.playingHandicap(hcpIdx);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.calculate_outlined, color: t.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'HCP de juego: ',
                    style: TextStyle(color: t.sub, fontSize: 12),
                  ),
                  Text(
                    '${phcp.toStringAsFixed(0)} strokes',
                    style: TextStyle(color: t.primary, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(${hcpIdx.toStringAsFixed(1)} × ${selectedTee.slopeRating}/113 + ${(selectedTee.courseRating - selectedTee.parTotal).toStringAsFixed(1)})',
                    style: TextStyle(color: t.sub, fontSize: 9),
                  ),
                ]),
              );
            }),
          ],

          const SizedBox(height: 20),
          GPrimaryButton(label: 'Guardar', onTap: () {
            Navigator.pop(
                ctx,
                PlayerEditResult(
                  name: nc.text.trim().isEmpty ? nombreFallback : nc.text.trim(),
                  handicap: double.tryParse(hc.text) ?? handicapInicial,
                  tee: selectedTee,
                ));
          }),
        ])),
      )));
  }
