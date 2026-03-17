// BET MODULE EDIT SHEET — Widget reutilizable para editar la configuración
// de un BetModuleInstance. Se usa tanto desde home_screen (ronda activa)
// como desde setup_screen (revisión antes de lanzar).
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/models.dart';

class BetModuleEditSheet extends StatefulWidget {
  final BetGroup group;
  final BetModuleInstance mod;
  final GolfTheme t;
  final CourseInfo? courseInfo;
  final void Function(BetModuleInstance) onSave;
  const BetModuleEditSheet({
    super.key,
    required this.group,
    required this.mod,
    required this.t,
    required this.onSave,
    this.courseInfo,
  });
  @override
  State<BetModuleEditSheet> createState() => _BetModuleEditSheetState();
}

class _BetModuleEditSheetState extends State<BetModuleEditSheet> {
  late BetModuleInstance _current;

  late final TextEditingController _skinCtrl;
  late final TextEditingController _nassauF, _nassauB, _nassauT;
  late final TextEditingController _matchM, _matchP;
  late final TextEditingController _medalCtrl;
  late final TextEditingController _puttsCtrl;
  late final TextEditingController _oyesCtrl, _zapatoCtrl;
  late final Map<UnitEventType, TextEditingController> _unitCtrls;

  @override
  void initState() {
    super.initState();
    _current = widget.mod;
    final m = _current;
    _skinCtrl   = TextEditingController(text: m.skins.valuePerSkin.toStringAsFixed(0));
    _nassauF    = TextEditingController(text: m.nassau.frontValue.toStringAsFixed(0));
    _nassauB    = TextEditingController(text: m.nassau.backValue.toStringAsFixed(0));
    _nassauT    = TextEditingController(text: m.nassau.totalValue.toStringAsFixed(0));
    _matchM     = TextEditingController(text: m.matchAutoPress.matchValue.toStringAsFixed(0));
    _matchP     = TextEditingController(text: m.matchAutoPress.pressValue.toStringAsFixed(0));
    _medalCtrl  = TextEditingController(text: m.medal.value.toStringAsFixed(0));
    _puttsCtrl  = TextEditingController(text: m.putts.value.toStringAsFixed(0));
    _oyesCtrl   = TextEditingController(text: m.oyeses.value.toStringAsFixed(0));
    _zapatoCtrl = TextEditingController(
        text: m.oyeses.zapatoValue > 0 ? m.oyeses.zapatoValue.toStringAsFixed(0) : '');
    _unitCtrls  = {
      for (final e in UnitEventType.values)
        e: TextEditingController(text: m.units.valueFor(e).toStringAsFixed(0)),
    };
  }

  @override
  void dispose() {
    _skinCtrl.dispose();
    _nassauF.dispose(); _nassauB.dispose(); _nassauT.dispose();
    _matchM.dispose(); _matchP.dispose();
    _medalCtrl.dispose();
    _puttsCtrl.dispose();
    _oyesCtrl.dispose(); _zapatoCtrl.dispose();
    for (final c in _unitCtrls.values) c.dispose();
    super.dispose();
  }

  void _update(BetModuleInstance updated) => setState(() => _current = updated);

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(color: t.divider, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text(_current.type.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Editar ${_current.type.label}', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 17)),
              Text(widget.group.name, style: TextStyle(color: t.sub, fontSize: 12)),
            ])),
          ]),
        ),
        Divider(height: 20, color: t.divider),
        Expanded(
          child: SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildFields(t),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () { widget.onSave(_current); Navigator.pop(context); },
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: t.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Guardar cambios', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ),
      ]),
    );
  }

  List<Widget> _buildFields(GolfTheme t) {
    switch (_current.type) {
      case BetModuleType.skins:         return _skinsFields(t);
      case BetModuleType.nassau:        return _nassauFields(t);
      case BetModuleType.matchAutoPress: return _matchFields(t);
      case BetModuleType.medal:         return _medalFields(t);
      case BetModuleType.putts:         return _puttsFields(t);
      case BetModuleType.oyeses:        return _oyesesFields(t);
      case BetModuleType.units:         return _unitsFields(t);
    }
  }

  // ── SKINS ───────────────────────────────────────────────────────────────────
  List<Widget> _skinsFields(GolfTheme t) {
    final s = _current.skins;
    return [
      _label('VALOR POR SKIN', t),
      _amountField('Monto', _skinCtrl, t, onChanged: (v) {
        _update(_current.copyWith(skinsConfig: s.copyWith(valuePerSkin: v)));
      }),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], s.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(skinsConfig: s.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
      const SizedBox(height: 16),
      _toggle('Carry-over', s.carryOver ? 'Empates acumulan al siguiente hoyo 🔥' : 'Sin acumulación', s.carryOver, t, (v) {
        _update(_current.copyWith(skinsConfig: s.copyWith(carryOver: v)));
      }),
    ];
  }

  // ── NASSAU ──────────────────────────────────────────────────────────────────
  List<Widget> _nassauFields(GolfTheme t) {
    final n = _current.nassau;
    void saveNassau() {
      final fv = double.tryParse(_nassauF.text) ?? n.frontValue;
      final bv = double.tryParse(_nassauB.text) ?? n.backValue;
      final tv = double.tryParse(_nassauT.text) ?? n.totalValue;
      _update(_current.copyWith(nassauConfig: n.copyWith(frontValue: fv, backValue: bv, totalValue: tv)));
    }
    return [
      _label('VALORES', t),
      _amountField('Front 9', _nassauF, t, onChanged: (_) => saveNassau()),
      const SizedBox(height: 8),
      _amountField('Back 9', _nassauB, t, onChanged: (_) => saveNassau()),
      const SizedBox(height: 8),
      _amountField('Total 18', _nassauT, t, onChanged: (_) => saveNassau()),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], n.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(nassauConfig: n.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
      const SizedBox(height: 16),
      _toggle('Activar Press automático', n.pressEnabled ? 'Trigger: ${n.autoPressTrigger} down' : 'Sin press', n.pressEnabled, t, (v) {
        _update(_current.copyWith(nassauConfig: n.copyWith(pressEnabled: v)));
      }),
      if (n.pressEnabled) ...[
        const SizedBox(height: 12),
        _label('TRIGGER', t),
        _segmented(['1 down', '2 down', '3 down'], n.autoPressTrigger - 1, t, (i) {
          _update(_current.copyWith(nassauConfig: n.copyWith(autoPressTrigger: i + 1)));
        }),
      ],
    ];
  }

  // ── MATCH + PRESS ───────────────────────────────────────────────────────────
  List<Widget> _matchFields(GolfTheme t) {
    final m = _current.matchAutoPress;
    return [
      _label('VALORES', t),
      _amountField('Valor del match', _matchM, t, onChanged: (v) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(matchValue: v)));
      }),
      const SizedBox(height: 8),
      _amountField('Valor por press/dígito', _matchP, t, onChanged: (v) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(pressValue: v)));
      }),
      const SizedBox(height: 16),
      _label('TRIGGER (hoyos de diferencia para nueva presión)', t),
      _segmented(['1 up', '2 up', '3 up'], m.pressTriggerValue - 1, t, (i) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(pressTriggerValue: i + 1)));
      }),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], m.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(matchAutoPressConfig: m.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
    ];
  }

  // ── MEDAL ───────────────────────────────────────────────────────────────────
  List<Widget> _medalFields(GolfTheme t) {
    final m = _current.medal;
    return [
      _label('VALOR', t),
      _amountField('Monto', _medalCtrl, t, onChanged: (v) {
        _update(_current.copyWith(medalConfig: m.copyWith(value: v)));
      }),
      const SizedBox(height: 16),
      _label('HOYOS', t),
      _segmented(['9 hoyos', '18 hoyos'], m.holes == 18 ? 1 : 0, t, (i) {
        _update(_current.copyWith(medalConfig: m.copyWith(holes: i == 1 ? 18 : 9)));
      }),
      const SizedBox(height: 16),
      _label('JUEGO', t),
      _segmented(['Gross', 'Net'], m.mode == GrossNetMode.net ? 1 : 0, t, (i) {
        _update(_current.copyWith(medalConfig: m.copyWith(mode: i == 1 ? GrossNetMode.net : GrossNetMode.gross)));
      }),
    ];
  }

  // ── PUTTS ───────────────────────────────────────────────────────────────────
  List<Widget> _puttsFields(GolfTheme t) {
    final p = _current.putts;
    return [
      _label('VALOR POR SEGMENTO', t),
      _amountField('Monto', _puttsCtrl, t, onChanged: (v) {
        _update(_current.copyWith(puttsConfig: p.copyWith(value: v)));
      }),
      const SizedBox(height: 16),
      _label('MODO', t),
      _segmented(['Total 18H', 'F9 + B9'], p.puttsMode == PuttsMode.total ? 0 : 1, t, (i) {
        _update(_current.copyWith(puttsConfig: p.copyWith(puttsMode: i == 0 ? PuttsMode.total : PuttsMode.perHole)));
      }),
      const SizedBox(height: 8),
      Text(
        p.puttsMode == PuttsMode.total
            ? '1 apuesta: el que menos putts en 18 hoyos gana \$${p.value.toStringAsFixed(0)}'
            : '2 apuestas: F9 (\$${p.value.toStringAsFixed(0)}) + B9 (\$${p.value.toStringAsFixed(0)})',
        style: TextStyle(color: t.sub, fontSize: 11),
      ),
      const SizedBox(height: 16),
      _toggle('Penalti 3-putt', p.threePuttPenalty ? 'Se cobra penalti por cada 3-putt' : 'Sin penalti', p.threePuttPenalty, t, (v) {
        _update(_current.copyWith(puttsConfig: p.copyWith(threePuttPenalty: v)));
      }),
    ];
  }

  // ── OYESES ──────────────────────────────────────────────────────────────────
  List<Widget> _oyesesFields(GolfTheme t) {
    final o = _current.oyeses;
    final realPar3Holes = (widget.courseInfo?.holes ?? CourseInfo.standard.holes)
        .where((h) => h.isPar3)
        .map((h) => h.hole)
        .toList()
      ..sort();
    final par3count = o.eligibleHoles.isEmpty ? realPar3Holes.length : o.eligibleHoles.length;

    return [
      _label('VALOR POR OYÉS', t),
      _amountField('Monto', _oyesCtrl, t, onChanged: (v) {
        _update(_current.copyWith(oyesesConfig: o.copyWith(value: v)));
      }),
      const SizedBox(height: 20),
      _label('👟 ZAPATO', t),
      Text('El jugador que gana TODOS los oyeses cobra el zapato.', style: TextStyle(color: t.sub, fontSize: 11)),
      const SizedBox(height: 10),
      _toggle('Activar zapato', o.zapatoEnabled ? 'Ganador de todos los oyeses cobra extra' : 'Sin regla de zapato', o.zapatoEnabled, t, (v) {
        _update(_current.copyWith(oyesesConfig: o.copyWith(zapatoEnabled: v)));
      }),
      if (o.zapatoEnabled) ...[
        const SizedBox(height: 12),
        _label('VALOR DEL ZAPATO', t),
        Text(
          o.zapatoValue == 0
              ? 'Automático: $par3count oyeses × \$${o.value.toStringAsFixed(0)} = \$${(par3count * o.value).toStringAsFixed(0)}'
              : 'Valor fijo configurado',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _zapatoCtrl,
          onChanged: (txt) {
            final v = double.tryParse(txt) ?? 0;
            _update(_current.copyWith(oyesesConfig: _current.oyeses.copyWith(zapatoValue: v)));
          },
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          textAlign: TextAlign.right,
          style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Monto fijo (vacío = automático)',
            labelStyle: TextStyle(color: t.sub, fontSize: 12),
            prefixText: '\$ ',
            prefixStyle: TextStyle(color: t.sub, fontSize: 13),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            fillColor: t.surface, filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 12),
        _label('APLICA EN', t),
        _segmented(['Solo 18 hoyos', 'También 9 hoyos'], o.zapatoRequires18 ? 0 : 1, t, (i) {
          _update(_current.copyWith(oyesesConfig: _current.oyeses.copyWith(zapatoRequires18: i == 0)));
        }),
        const SizedBox(height: 6),
        Text(
          o.zapatoRequires18
              ? 'Solo aplica si se juegan todos los par-3 del campo.'
              : 'Aplica con 2 o más oyeses registrados (válido en 9H).',
          style: TextStyle(color: t.sub, fontSize: 11),
        ),
      ],
    ];
  }

  // ── UNITS ───────────────────────────────────────────────────────────────────
  List<Widget> _unitsFields(GolfTheme t) {
    final icons = {
      UnitEventType.birdie:      '🐦',
      UnitEventType.eagle:       '🦅',
      UnitEventType.sandyPar:    '🏖️',
      UnitEventType.parUnico:    '⭐',
      UnitEventType.birdieUnico: '💫',
      UnitEventType.holeOut:     '🕳️',
    };

    return [
      _label('VALOR POR EVENTO', t),
      const SizedBox(height: 4),
      Text('Cada jugador que logra el evento cobra este monto de cada rival.', style: TextStyle(color: t.sub, fontSize: 11)),
      const SizedBox(height: 12),
      ...UnitEventType.values.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text(icons[e]!, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.label, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(e.description, style: TextStyle(color: t.sub, fontSize: 10)),
          ])),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _unitCtrls[e],
              onChanged: (_) {
                final newMap = <UnitEventType, double>{};
                for (final ev in UnitEventType.values) {
                  final v = double.tryParse(_unitCtrls[ev]!.text);
                  if (v != null) newMap[ev] = v;
                }
                _update(_current.copyWith(unitsConfig: UnitsConfig(eventValues: newMap)));
              },
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              textAlign: TextAlign.right,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: t.sub, fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                fillColor: t.surface,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.divider)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.primary, width: 1.5)),
              ),
            ),
          ),
        ]),
      )),
    ];
  }

  // ── Helpers UI ──────────────────────────────────────────────────────────────
  Widget _label(String text, GolfTheme t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(color: t.sub, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
  );

  Widget _amountField(String hint, TextEditingController ctrl, GolfTheme t,
      {void Function(double)? onChanged}) =>
    TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      textAlign: TextAlign.right,
      style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 16),
      onChanged: onChanged == null ? null : (txt) {
        final v = double.tryParse(txt);
        if (v != null) onChanged(v);
      },
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(color: t.sub, fontSize: 13),
        prefixText: '\$ ',
        prefixStyle: TextStyle(color: t.sub, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        fillColor: t.surface,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
      ),
    );

  Widget _segmented(List<String> labels, int selected, GolfTheme t, void Function(int) onTap) => Row(
    children: labels.asMap().entries.map((e) {
      final sel = e.key == selected;
      return Expanded(child: GestureDetector(
        onTap: () => setState(() => onTap(e.key)),
        child: Container(
          margin: EdgeInsets.only(right: e.key < labels.length - 1 ? 6 : 0),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? t.primary : t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? t.primary : t.divider),
          ),
          alignment: Alignment.center,
          child: Text(e.value, style: TextStyle(
            color: sel ? t.onPrimary : t.text,
            fontWeight: FontWeight.w700, fontSize: 13,
          )),
        ),
      ));
    }).toList(),
  );

  Widget _toggle(String title, String subtitle, bool value, GolfTheme t, void Function(bool) onChanged) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.divider)),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(color: t.sub, fontSize: 11)),
      ])),
      Switch(
        value: value,
        onChanged: (v) { setState(() => onChanged(v)); },
        activeThumbColor: t.accent,
        activeTrackColor: t.accent.withValues(alpha: 0.4),
        inactiveTrackColor: t.divider,
      ),
    ]),
  );
}
