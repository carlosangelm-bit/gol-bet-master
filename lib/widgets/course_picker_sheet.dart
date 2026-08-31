// ─────────────────────────────────────────────────────────────────────────────
// COURSE PICKER SHEET
// Bottom sheet completo para buscar y seleccionar un campo de golf via API.
// Flujo:
//   1. Búsqueda por nombre → lista de resultados (solo club/ubicación)
//   2. Tap en un resultado → carga hoyos completos y muestra selector de tee
//   3. Tap en un tee → devuelve CourseInfo listo para usar en la ronda
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/models.dart';
import '../services/golf_course_service.dart';
import '../services/course_corrections_service.dart';
import '../providers/user_profile_provider.dart';
import 'package:provider/provider.dart';
import '../widgets/common_widgets.dart';

class CoursePickerSheet extends StatefulWidget {
  final GolfTheme t;
  /// Callback cuando el usuario elige un tee.
  /// Recibe el CourseInfo (para la ronda) y el ApiCourse completo (para tees).
  final void Function(CourseInfo courseInfo, ApiCourse apiCourse) onSelected;

  const CoursePickerSheet({
    super.key,
    required this.t,
    required this.onSelected,
  });

  @override
  State<CoursePickerSheet> createState() => _CoursePickerSheetState();
}

class _CoursePickerSheetState extends State<CoursePickerSheet> {
  final _searchCtrl = TextEditingController();

  // Estados de búsqueda
  List<ApiCourse> _results = [];
  bool _searching = false;
  String? _searchError;

  // Estado de detalle (tees del campo seleccionado)
  ApiCourse? _selected;
  bool _loadingDetail = false;
  String? _detailError;
  bool _hasCorrectedData = false; // true cuando se usan datos corregidos del campo

  @override
  void initState() {
    super.initState();
    // Pre-cargar los campos favoritos en paralelo para que el tap sea instantáneo
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchFavorites());
  }

  void _prefetchFavorites() {
    if (!mounted) return;
    try {
      final profProv = context.read<UserProfileProvider>();
      // id → clubName: el nombre permite que los favoritos con ID numérico
      // legacy se resuelvan por búsqueda en vez de morir en un 404.
      final favs = {
        for (final f in profProv.favCourses)
          if (f.courseId.isNotEmpty) f.courseId: f.clubName,
      };
      if (favs.isNotEmpty) {
        // Pre-carga silenciosa en background — no bloquea la UI
        GolfCourseService.prefetchByIds(favs).catchError((_) {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Búsqueda ──────────────────────────────────────────────────────────────
  Future<void> _doSearch(String q) async {
    if (q.trim().length < 2) return;
    // Si el campo de búsqueda está vacío, actualizarlo (e.g., tap en favorito)
    if (_searchCtrl.text.trim() != q.trim()) {
      _searchCtrl.text = q;
    }
    setState(() {
      _searching = true;
      _searchError = null;
      _results = [];
      _selected = null;
    });
    try {
      final res = await GolfCourseService.search(q);
      setState(() {
        _results = res;
        _searching = false;
        if (res.isEmpty) _searchError = 'No se encontraron campos para "$q"';
      });
    } catch (e) {
      // Un TypeError crudo en pantalla no le dice nada a nadie y además hace
      // pensar que el error es del teléfono. Se distingue lo que el usuario
      // puede resolver —conexión— de lo que no, y el detalle técnico va al log.
      debugPrint('[CoursePicker] fallo buscando "$q": $e');
      // Por el texto y no por el tipo: SocketException vive en dart:io, que en
      // web no existe. La app es web además de móvil, así que importarlo rompería
      // el build.
      final texto = e.toString();
      final esRed = e is TimeoutException ||
          texto.contains('Failed host lookup') ||
          texto.contains('SocketException') ||
          texto.contains('XMLHttpRequest') ||
          texto.contains('ClientException');
      setState(() {
        _searching = false;
        _searchError = esRed
            ? 'Sin conexión con el buscador de campos. Puedes seguir sin '
                'campo: se usa el Campo Estándar.'
            : 'El buscador devolvió algo que no se pudo leer. Prueba con otro '
                'nombre, o sigue sin campo: se usa el Campo Estándar.';
      });
    }
  }

  // ── Cargar detalle + tees ─────────────────────────────────────────────────
  Future<void> _loadDetail(ApiCourse course) async {
    setState(() {
      _loadingDetail = true;
      _detailError = null;
      _selected = null;
      _hasCorrectedData = false;
    });
    try {
      // Lanzar AMBAS llamadas en paralelo para minimizar la espera:
      // - Firestore: ¿hay corrección oficial para este campo?
      // - API:       datos completos del campo (hoyos + tees)
      // Ambas tienen caché en memoria → segunda visita al mismo campo es instantánea.
      final results = await Future.wait([
        CourseCorrectionsService.getForCourse(course.id),
        GolfCourseService.getById(course.id, fallbackName: course.clubName),
      ]);

      if (!mounted) return;

      final correction = results[0] as CourseCorrection?;
      final full       = results[1] as ApiCourse;

      // La corrección oficial tiene prioridad sobre los datos de la API
      setState(() {
        _selected        = correction?.correctedCourse ?? full;
        _loadingDetail   = false;
        _hasCorrectedData = correction != null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDetail = false;
          _detailError = 'Error al cargar el campo: $e';
          _hasCorrectedData = false;
        });
      }
    }
  }

  /// Carga un campo desde caché (sin llamada a la API).
  /// También aplica corrección oficial si la hay.
  Future<void> _loadFromCache(ApiCourse course) async {
    setState(() {
      _loadingDetail = true;
      _detailError = null;
      _hasCorrectedData = false;
    });
    // PRIMERO: corrección oficial
    final correction = await CourseCorrectionsService.getForCourse(course.id);
    final hasCorrected = correction != null;
    final result = hasCorrected ? correction.correctedCourse : course;
    if (mounted) {
      setState(() {
        _selected = result;
        _loadingDetail = false;
        _detailError = null;
        _hasCorrectedData = hasCorrected;
      });
    }
  }



  // ── Seleccionar tee y devolver CourseInfo ─────────────────────────────────
  void _pickTee(ApiTeeBox tee) {
    final info = tee.toCourseInfo(_selected!.clubName, _selected!.courseName);
    final apiCourse = _selected!;
    Navigator.pop(context);
    widget.onSelected(info, apiCourse);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40, height: 4,
            decoration: BoxDecoration(color: t.divider, borderRadius: BorderRadius.circular(2)),
          ),

          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              // Botón atrás si estamos en detalle de tees
              if (_selected != null)
                GestureDetector(
                  onTap: () => setState(() { _selected = null; _detailError = null; }),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.arrow_back_ios, color: t.primary, size: 18),
                  ),
                ),
              Icon(Icons.sports_golf, color: t.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selected != null ? _selected!.clubName : 'Buscar campo',
                  style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Icon(Icons.close, color: t.sub, size: 20),
              ),
            ]),
          ),

          // ── Barra de búsqueda (solo en vista de lista) ───────────────
          if (_selected == null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(color: t.text),
                textInputAction: TextInputAction.search,
                onSubmitted: _doSearch,
                decoration: InputDecoration(
                  hintText: 'Nombre del club o campo...',
                  hintStyle: TextStyle(color: t.sub),
                  prefixIcon: Icon(Icons.search, color: t.sub, size: 20),
                  suffixIcon: _searching
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: t.primary),
                          ),
                        )
                      : _searchCtrl.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchCtrl.clear();
                                setState(() { _results = []; _searchError = null; });
                              },
                              child: Icon(Icons.clear, color: t.sub, size: 18),
                            )
                          : null,
                  filled: true,
                  fillColor: t.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: t.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: t.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: t.primary, width: 2),
                  ),
                ),
                onChanged: (v) {
                  setState(() {}); // actualiza botón clear
                  // Búsqueda automática al escribir ≥3 chars
                  if (v.trim().length >= 3) {
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (_searchCtrl.text == v) _doSearch(v);
                    });
                  }
                },
              ),
            ),
          ],

          Divider(color: t.divider, height: 1),

          // ── Contenido principal ──────────────────────────────────────
          Expanded(
            child: _loadingDetail
                ? _loadingView(t, 'Cargando tees del campo...')
                : _selected != null
                    ? _teeListView(t, scrollCtrl)
                    : _searching
                        ? _loadingView(t, 'Buscando campos...')
                        : _searchResultsView(t, scrollCtrl),
          ),
        ]),
      ),
    );
  }

  // ── Vista: loading ────────────────────────────────────────────────────────
  Widget _loadingView(GolfTheme t, String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: t.primary),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: t.sub, fontSize: 13)),
        ]),
      );

  // ── Vista: resultados de búsqueda ─────────────────────────────────────────
  Widget _searchResultsView(GolfTheme t, ScrollController scrollCtrl) {
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.search_off, color: t.sub, size: 40),
            const SizedBox(height: 12),
            Text(_searchError!, textAlign: TextAlign.center,
                style: TextStyle(color: t.sub, fontSize: 14)),
            const SizedBox(height: 16),
            GSecButton(label: 'Reintentar', onTap: () => _doSearch(_searchCtrl.text)),
          ]),
        ),
      );
    }

    if (_results.isEmpty) {
      // Mostrar campos favoritos si los hay
      return Consumer<UserProfileProvider>(
        builder: (ctx, profProv, _) {
          final favs = profProv.favCourses;
          if (favs.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.sports_golf, color: t.divider, size: 48),
                const SizedBox(height: 12),
                Text('Busca un campo por nombre', style: TextStyle(color: t.sub, fontSize: 14)),
                const SizedBox(height: 4),
                Text('Ej: "Augusta", "Pebble Beach", "Real Madrid"',
                    style: TextStyle(color: t.sub.withValues(alpha: 0.6), fontSize: 12)),
              ]),
            );
          }
          return ListView.builder(
            controller: scrollCtrl,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: favs.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                    const SizedBox(width: 6),
                    Text('MIS CAMPOS FAVORITOS',
                        style: TextStyle(color: t.sub, fontSize: 10,
                            fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  ]),
                );
              }
              final fav = favs[i - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () {
                    // Solo usar caché si el ID ya es alfanumérico (formato nuevo).
                    // Si es numérico legacy, ir a la API para migrar el favorito.
                    final cacheOk = fav.hasCachedData &&
                        fav.cachedCourse!.id.isNotEmpty &&
                        int.tryParse(fav.cachedCourse!.id) == null;
                    if (cacheOk) {
                      // Directo a selección de tee, aplicando corrección si hay
                      _loadFromCache(fav.cachedCourse!);
                    } else {
                      // Sin caché válido: ir a la API con el ID guardado (+ fallback por nombre)
                      _loadDetail(ApiCourse(
                        id:          fav.courseId,
                        clubName:    fav.clubName,
                        courseName:  fav.courseName,
                        city:        fav.city    ?? '',
                        state:       '',
                        country:     fav.country ?? '',
                        maleTees:    const [],
                        femaleTees:  const [],
                      ));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(fav.fullName,
                            style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                        if (fav.location.isNotEmpty)
                          Text(fav.location, style: TextStyle(color: t.sub, fontSize: 11)),
                        if (fav.hasCachedData)
                          Text(
                            '${fav.cachedCourse!.allTees.length} tees disponibles',
                            style: TextStyle(color: t.primary, fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                      ])),
                      Icon(Icons.chevron_right, color: t.primary, size: 20),
                    ]),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    return ListView.separated(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = _results[i];
        return _CourseResultTile(course: c, t: t, onTap: () => _loadDetail(c));
      },
    );
  }

  // ── Vista: selector de tees ───────────────────────────────────────────────
  Widget _teeListView(GolfTheme t, ScrollController scrollCtrl) {
    final course = _selected!;

    if (_detailError != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, color: t.danger, size: 40),
          const SizedBox(height: 12),
          Text(_detailError!, textAlign: TextAlign.center,
              style: TextStyle(color: t.sub, fontSize: 14)),
        ]),
      );
    }

    final allTees = course.allTees;
    if (allTees.isEmpty) {
      return Center(
        child: Text('Este campo no tiene tees disponibles.',
            style: TextStyle(color: t.sub, fontSize: 14)),
      );
    }

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ── Banner de datos corregidos ────────────────────────────────────────
        if (_hasCorrectedData)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF34C759).withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.verified_rounded, color: Color(0xFF34C759), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Usando datos oficiales corregidos del campo',
                  style: TextStyle(color: const Color(0xFF34C759), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        // Info del campo + botón favorito
        Consumer<UserProfileProvider>(
          builder: (ctx, profProv, _) {
            final courseId = course.id;
            final isFav = profProv.isFavCourse(courseId);
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.divider),
              ),
              child: Row(children: [
                Icon(Icons.place_outlined, color: t.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      course.clubName,
                      style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    if (course.courseName.isNotEmpty && course.courseName != course.clubName)
                      Text(course.courseName, style: TextStyle(color: t.sub, fontSize: 12)),
                    if (course.city.isNotEmpty)
                      Text(
                        [course.city, course.country].where((s) => s.isNotEmpty).join(', '),
                        style: TextStyle(color: t.sub, fontSize: 11),
                      ),
                  ]),
                ),
                // Botón favorito — aquí tenemos el ApiCourse completo con tees
                GestureDetector(
                  onTap: () {
                    profProv.toggleFavCourse(
                      courseId,
                      course.clubName,
                      courseName: course.courseName,
                      city:       course.city.isNotEmpty ? course.city : null,
                      country:    course.country.isNotEmpty ? course.country : null,
                      apiCourse:  course,   // ← guardamos el ApiCourse con todos los tees
                    );
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      backgroundColor: isFav ? t.sub : t.profit,
                      content: Text(isFav
                          ? '${course.clubName} eliminado de favoritos'
                          : '\${course.clubName} guardado como favorito'),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(
                      isFav ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isFav ? Colors.amber : t.sub,
                      size: 26,
                    ),
                  ),
                ),
              ]),
            );
          },
        ),

        const SizedBox(height: 16),

        // Separador con etiqueta
        if (course.maleTees.isNotEmpty)
          _teeSectionLabel('TEEs MASCULINOS', t),
        ...course.maleTees.map((tee) => _TeeTile(
              tee: tee,
              t: t,
              onTap: () => _pickTee(tee),
            )),

        if (course.femaleTees.isNotEmpty) ...[
          const SizedBox(height: 8),
          _teeSectionLabel('TEEs FEMENINOS', t),
          ...course.femaleTees.map((tee) => _TeeTile(
                tee: tee,
                t: t,
                onTap: () => _pickTee(tee),
              )),
        ],
      ],
    );
  }

  Widget _teeSectionLabel(String label, GolfTheme t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: TextStyle(
                color: t.sub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      );
}

// ── Tile de resultado de búsqueda ─────────────────────────────────────────────
class _CourseResultTile extends StatelessWidget {
  final ApiCourse course;
  final GolfTheme t;
  final VoidCallback onTap;

  const _CourseResultTile({required this.course, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProfileProvider>(
      builder: (ctx, profProv, _) {
        final courseId = course.id;
        final isFav = profProv.isFavCourse(courseId);
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isFav ? t.primary.withValues(alpha: 0.05) : t.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isFav ? t.primary.withValues(alpha: 0.3) : t.divider,
              ),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.golf_course,
                    color: isFav ? Colors.amber : t.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.clubName,
                    style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                if (course.courseName.isNotEmpty && course.courseName != course.clubName)
                  Text(course.courseName,
                      style: TextStyle(color: t.sub, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                if (course.city.isNotEmpty)
                  Text(
                    [course.city, course.country].where((s) => s.isNotEmpty).join(', '),
                    style: TextStyle(color: t.sub, fontSize: 11),
                  ),
              ])),
              // Indicador de favorito (solo visual — se gestiona desde la pantalla de tees)
              if (isFav) ...[
                Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
              ],
              Icon(Icons.chevron_right, color: t.sub, size: 20),
            ]),
          ),
        );
      },
    );
  }
}

// ── Tile de tee ───────────────────────────────────────────────────────────────
class _TeeTile extends StatelessWidget {
  final ApiTeeBox tee;
  final GolfTheme t;
  final VoidCallback onTap;

  const _TeeTile({required this.tee, required this.t, required this.onTap});

  // Color visual según nombre del tee
  Color _teeColor(GolfTheme t) {
    final name = tee.teeName.toLowerCase();
    if (name.contains('black') || name.contains('negro')) return Colors.black87;
    if (name.contains('blue')  || name.contains('azul'))  return Colors.blue.shade700;
    if (name.contains('white') || name.contains('blanco')) return Colors.grey.shade400;
    if (name.contains('red')   || name.contains('rojo'))  return Colors.red.shade600;
    if (name.contains('gold')  || name.contains('oro') || name.contains('yellow')) return Colors.amber.shade700;
    if (name.contains('green') || name.contains('verde')) return Colors.green.shade700;
    return t.primary;
  }

  @override
  Widget build(BuildContext context) {
    final color = _teeColor(t);
    final hasHoles = tee.holes.isNotEmpty;
    final par3count = tee.holes.where((h) => h.par == 3).length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Row(children: [
          // Bolita del color del tee
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
            ),
          ),
          const SizedBox(width: 12),
          // Nombre + stats
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tee.teeName,
                style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 3),
            Wrap(spacing: 8, children: [
              _stat('Par ${tee.parTotal}', t),
              _stat('CR ${tee.courseRating.toStringAsFixed(1)}', t),
              _stat('Slope ${tee.slopeRating}', t),
              if (tee.totalYards > 0) _stat('${tee.totalYards} yds', t),
              if (hasHoles && par3count > 0) _stat('$par3count par-3', t),
            ]),
          ])),
          // Flecha acción
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text('Usar',
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String label, GolfTheme t) => Text(
        label,
        style: TextStyle(color: t.sub, fontSize: 11, fontWeight: FontWeight.w500),
      );
}
