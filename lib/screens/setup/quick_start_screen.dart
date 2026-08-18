// ─────────────────────────────────────────────────────────────────────────────
// QUICK START — un punto de partida guardado es un ATAJO, no un formulario
//
// El reporte: "cuando quiero usar el grupo de apuesta me obliga a configurar
// todo nuevamente". Y era cierto aunque la precarga funcionara: el wizard se
// abría en "paso 1 de 8" sin un check, y había que pulsar Siguiente seis veces
// confirmando lo que el grupo ya respondía.
//
// Prellenar ahorra escribir pero se recorre igual. Un atajo lleva al final y
// solo para donde falta algo.
//
// Esta pantalla pregunta SOLO lo que el punto de partida no sabe —hoy campo y
// ventaja— y lanza. Las preguntas se CALCULAN con preguntasPendientes, así que
// el día que un punto de partida guarde el campo, esta pantalla se acorta sola.
//
// No reimplementa nada: el selector de campo es CoursePickerSheet, el mismo del
// wizard, y el lanzamiento pasa por SetupScreen con lanzarAlEntrar, o sea por
// _createAndStartRound. Un segundo camino de lanzamiento habría sido la tercera
// vez en la sesión que dos rutas al mismo sitio se comportan distinto.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/round_provider.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/course_picker_sheet.dart';
import 'setup_flow.dart';
import 'setup_screen.dart';

class QuickStartScreen extends StatefulWidget {
  /// El grupo de apuesta del que se parte.
  final BettingGroup grupo;
  const QuickStartScreen({super.key, required this.grupo});

  @override
  State<QuickStartScreen> createState() => _QuickStartScreenState();
}

class _QuickStartScreenState extends State<QuickStartScreen> {
  CourseInfo? _campo;

  /// 'handicap' · 'sliding' · 'ninguna'. Sin elegir hasta que se toque.
  String? _ventaja;

  /// Lo que este punto de partida NO sabe. Calculado, no fijado.
  List<SetupStep> get _pendientes => preguntasPendientes(
        // Ningún modelo guarda campo todavía; en cuanto uno lo guarde, aquí se
        // lee de él y la pregunta desaparece.
        traeCampo: false,
        traeVentaja: false,
      );

  bool get _listo =>
      (!_pendientes.contains(SetupStep.campo) || _campo != null) &&
      (!_pendientes.contains(SetupStep.ventaja) || _ventaja != null);

  @override
  Widget build(BuildContext context) {
    final t = context.watch<RoundProvider>().theme;
    GolfThemeExt.setCurrent(t);
    final bg = widget.grupo;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: t.text),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bg.name,
              style: TextStyle(
                  color: t.text, fontWeight: FontWeight.w800, fontSize: 18)),
          Text(faltaPorDecidir(_pendientes),
              style: TextStyle(color: t.sub, fontSize: 12)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // ── Lo que el punto de partida YA trae ────────────────────────────
        //
        // Va primero y como resumen, no como pasos: la pregunta que responde es
        // "¿es esto lo que quiero jugar?", no "¿confirmo cada campo?".
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.divider),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YA CONFIGURADO', style: GolfType.label(t.primary)),
            const SizedBox(height: 8),
            _fila(t, Icons.people_outline,
                '${bg.playerIds.length} jugadores habituales'),
            _fila(t, Icons.compare_arrows,
                '${bg.activeRulesCount} duelos con apuesta'),
            _fila(t, Icons.paid_outlined,
                '${bg.totalModules} apuestas con sus montos'),
          ]),
        ),
        const SizedBox(height: 18),

        if (_pendientes.isEmpty)
          Text('No falta nada por decidir.', style: GolfType.body(t.sub))
        else
          Text('FALTA DECIDIR', style: GolfType.label(t.sub)),
        const SizedBox(height: 8),

        if (_pendientes.contains(SetupStep.campo)) _bloqueCampo(t),
        if (_pendientes.contains(SetupStep.ventaja)) _bloqueVentaja(t),

        const SizedBox(height: 22),
        GPrimaryButton(
          label: '⛳ Empezar ronda',
          onTap: _listo ? () => _empezar(directo: true) : null,
        ),
        const SizedBox(height: 8),
        // Salida para quien quiera cambiar algo de lo precargado. El wizard
        // completo sigue siendo el sitio donde se cambia cualquier cosa.
        GSecButton(
          label: 'Revisar todo antes de empezar',
          onTap: () => _empezar(directo: false),
        ),
        const SizedBox(height: 10),
        Text(
            _listo
                ? 'Empezar usa los jugadores y las apuestas del grupo tal cual.'
                : 'Elige ${faltaPorDecidir(_pendientes).toLowerCase()} para empezar.',
            style: GolfType.label(t.sub)),
      ]),
    );
  }

  Widget _fila(GolfTheme t, IconData icono, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icono, size: 15, color: t.sub),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: GolfType.body(t.text))),
        ]),
      );

  Widget _bloqueCampo(GolfTheme t) => GestureDetector(
        onTap: () => showModalBottomSheet(
          context: context,
          backgroundColor: t.card,
          isScrollControlled: true,
          useRootNavigator: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          // El MISMO selector del wizard: reimplementarlo daría dos listas de
          // campos que pueden divergir.
          builder: (_) => CoursePickerSheet(
            t: t,
            onSelected: (info, _) => setState(() => _campo = info),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _campo != null ? t.primary.withValues(alpha: 0.08) : t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _campo != null ? t.primary : t.divider,
                width: _campo != null ? 1.5 : 1),
          ),
          child: Row(children: [
            const Text('📍', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 11),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Campo',
                      style: GolfType.body(t.text)
                          .copyWith(fontWeight: FontWeight.w600)),
                  Text(_campo?.name ?? 'Toca para elegir',
                      style: GolfType.label(t.sub)),
                ])),
            Icon(_campo != null ? Icons.check_circle : Icons.chevron_right,
                color: _campo != null ? t.primary : t.sub, size: 20),
          ]),
        ),
      );

  Widget _bloqueVentaja(GolfTheme t) {
    const opciones = [
      ('handicap', 'Handicap', 'Golpes según el handicap registrado.'),
      ('sliding', 'Sliding', 'Se ajusta según cómo terminó la anterior.'),
      ('ninguna', 'Sin ventaja', 'Todos brutos.'),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ventaja',
            style:
                GolfType.body(t.text).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final (clave, titulo, detalle) in opciones)
          GestureDetector(
            onTap: () => setState(() => _ventaja = clave),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: _ventaja == clave
                    ? t.primary.withValues(alpha: 0.10)
                    : t.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _ventaja == clave ? t.primary : t.divider),
              ),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(titulo, style: GolfType.body(t.text)),
                      Text(detalle, style: GolfType.label(t.sub)),
                    ])),
                if (_ventaja == clave)
                  Icon(Icons.check, color: t.primary, size: 18),
              ]),
            ),
          ),
      ]),
    );
  }

  /// Lanza, o abre el wizard con todo puesto.
  ///
  /// Las dos salidas van por SetupScreen: con [directo] lanza al entrar sin
  /// mostrar los pasos, y sin él se queda en el wizard para cambiar lo que sea.
  /// Un solo camino de lanzamiento.
  void _empezar({required bool directo}) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SetupScreen(
        grupoInicial: widget.grupo,
        campoInicial: _campo,
        ventajaInicial: _ventaja,
        lanzarAlEntrar: directo,
      ),
    ));
  }
}
