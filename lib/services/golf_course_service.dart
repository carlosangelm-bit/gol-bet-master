// ─────────────────────────────────────────────────────────────────────────────
// GOLF COURSE API SERVICE
// Endpoints usados:
//   GET /v1/search?search_query=<term>  → lista de campos (wrapper: "courses")
//   GET /v1/courses/{id}                → detalle completo  (wrapper: "course")
// Auth: Header  Authorization: Key DLZRFGWXFTHO6QNK3ZIOVL5I2Q
//
// NOTA: La API SÍ devuelve el campo "handicap" en los hoyos cuando se obtiene
//       el detalle completo con getById(). Se usa directamente como strokeIndex.
//       Solo en los resultados de búsqueda (sin hoyos) no está disponible.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

// ── Modelos de respuesta de la API ────────────────────────────────────────────

class ApiHole {
  final int holeNumber; // 1-based (posición en la lista)
  final int par;
  final int yardage;
  /// strokeIndex tomado directamente del campo "handicap" de la API.
  /// Si la API no lo provee (resultados de búsqueda), se usa holeNumber como fallback.
  final int strokeIndex;
  /// true si el strokeIndex vino del campo "handicap" real de la API
  final bool hasRealHandicap;

  const ApiHole({
    required this.holeNumber,
    required this.par,
    required this.yardage,
    required this.strokeIndex,
    this.hasRealHandicap = false,
  });

  factory ApiHole.fromJson(Map<String, dynamic> j, int holeNumber) {
    final handicap = (j['handicap'] as num?)?.toInt();
    return ApiHole(
      holeNumber: holeNumber,
      par: (j['par'] as num?)?.toInt() ?? 4,
      yardage: (j['yardage'] as num?)?.toInt() ?? 0,
      // Si la API devuelve "handicap", usarlo directamente como strokeIndex
      strokeIndex: handicap ?? holeNumber,
      hasRealHandicap: handicap != null,
    );
  }

  ApiHole withStrokeIndex(int si) => ApiHole(
        holeNumber: holeNumber,
        par: par,
        yardage: yardage,
        strokeIndex: si,
        hasRealHandicap: hasRealHandicap,
      );

  /// Serializar para cache en Firestore
  Map<String, dynamic> toJson() => {
    'hole':            holeNumber,
    'par':             par,
    'yardage':         yardage,
    'handicap':        strokeIndex,
    'hasRealHandicap': hasRealHandicap,
  };

  /// Deserializar desde cache
  static ApiHole fromCached(Map<String, dynamic> j) {
    final hn = (j['hole'] as num?)?.toInt() ?? 1;
    return ApiHole(
      holeNumber:      hn,
      par:             (j['par']      as num?)?.toInt() ?? 4,
      yardage:         (j['yardage']  as num?)?.toInt() ?? 0,
      strokeIndex:     (j['handicap'] as num?)?.toInt() ?? hn,
      hasRealHandicap: (j['hasRealHandicap'] as bool?) ?? false,
    );
  }
}

class ApiTeeBox {
  final String teeName;
  final double courseRating;
  final int slopeRating;
  final int parTotal;
  final int totalYards;
  final int numberOfHoles;
  final List<ApiHole> holes;

  const ApiTeeBox({
    required this.teeName,
    required this.courseRating,
    required this.slopeRating,
    required this.parTotal,
    required this.totalYards,
    required this.numberOfHoles,
    required this.holes,
  });

  factory ApiTeeBox.fromJson(Map<String, dynamic> j) {
    final rawHoles = (j['holes'] as List?) ?? [];

    // 1. Parsear hoyos — fromJson ya toma el campo "handicap" de la API si existe
    final parsed = rawHoles
        .asMap()
        .entries
        .map((e) => ApiHole.fromJson(e.value as Map<String, dynamic>, e.key + 1))
        .toList();

    // 2. Solo calcular strokeIndex por yardas si NINGÚN hoyo tiene handicap real.
    //    Si al menos uno lo tiene, confiamos en que la API los provee todos.
    final hasRealHandicaps = parsed.any((h) => h.hasRealHandicap);
    final holes = hasRealHandicaps ? parsed : _assignStrokeIndex(parsed);

    return ApiTeeBox(
      teeName: j['tee_name'] as String? ?? 'Tee',
      courseRating: (j['course_rating'] as num?)?.toDouble() ?? 72.0,
      slopeRating: (j['slope_rating'] as num?)?.toInt() ?? 113,
      parTotal: (j['par_total'] as num?)?.toInt() ?? 72,
      totalYards: (j['total_yards'] as num?)?.toInt() ?? 0,
      numberOfHoles: (j['number_of_holes'] as num?)?.toInt() ?? 18,
      holes: holes,
    );
  }

  /// Fallback: asigna strokeIndex 1-18 basado en yardas descendentes.
  /// Solo se usa cuando la API no devuelve el campo "handicap" en los hoyos.
  /// Los impares (1,3,5...) van al front 9; pares (2,4,6...) al back 9.
  static List<ApiHole> _assignStrokeIndex(List<ApiHole> holes) {
    if (holes.isEmpty) return holes;

    // Ordenar por yardage desc para determinar dificultad relativa
    final sorted = [...holes]..sort((a, b) => b.yardage.compareTo(a.yardage));

    // Asignar rangos 1-n según posición en el ranking de yardas
    final rankMap = <int, int>{}; // holeNumber → strokeIndex
    for (int i = 0; i < sorted.length; i++) {
      // Interleave: posición 0→SI 1, 1→SI 2, etc.
      rankMap[sorted[i].holeNumber] = i + 1;
    }

    return holes
        .map((h) => h.withStrokeIndex(rankMap[h.holeNumber] ?? h.holeNumber))
        .toList();
  }

  /// Convierte a CourseInfo compatible con el motor de apuestas
  CourseInfo toCourseInfo(String clubName, String courseName) {
    // Ordenar hoyos por número
    final sorted = [...holes]..sort((a, b) => a.holeNumber.compareTo(b.holeNumber));
    final standardHoles = CourseInfo.standard.holes;

    // Construir 18 hoyos (completar con estándar si faltan)
    final courseHoles = List.generate(18, (i) {
      final num = i + 1;
      try {
        final apiHole = sorted.firstWhere((h) => h.holeNumber == num);
        return CourseHole(
          hole: num,
          par: apiHole.par,
          strokeIndex: apiHole.strokeIndex,
        );
      } catch (_) {
        // Hoyo no disponible en este tee → usar estándar
        return CourseHole(
          hole: num,
          par: standardHoles[i].par,
          strokeIndex: standardHoles[i].strokeIndex,
        );
      }
    });

    // Nombre limpio del campo
    final baseName = (courseName.isNotEmpty && courseName != clubName)
        ? '$clubName — $courseName'
        : clubName;

    // Limpiar nombre del tee (la API a veces incluye prefijos numéricos)
    final cleanTee = _cleanTeeName(teeName);

    return CourseInfo(
      name: '$baseName ($cleanTee)',
      holes: courseHoles,
    );
  }

  /// Elimina prefijos numéricos que la API agrega al nombre del tee
  /// Ej: "50715, USGA, Blue, Men" → "Blue (Men)"
  static String _cleanTeeName(String raw) {
    // Quitar segmentos que sean solo números o "USGA"
    final parts = raw.split(',').map((s) => s.trim()).where((s) {
      if (s.isEmpty) return false;
      if (RegExp(r'^\d+$').hasMatch(s)) return false;
      if (s.toUpperCase() == 'USGA') return false;
      return true;
    }).toList();
    return parts.isEmpty ? raw : parts.join(' ');
  }

  /// Serializar para cache en Firestore (tees ya con strokeIndex calculado)
  Map<String, dynamic> toJson() => {
    'tee_name':        teeName,
    'course_rating':   courseRating,
    'slope_rating':    slopeRating,
    'par_total':       parTotal,
    'total_yards':     totalYards,
    'number_of_holes': numberOfHoles,
    'holes':           holes.map((h) => h.toJson()).toList(),
  };

  /// Deserializar desde cache de Firestore (strokeIndex ya calculado, no recalcular)
  static ApiTeeBox fromCached(Map<String, dynamic> j) {
    final rawHoles = (j['holes'] as List?) ?? [];
    return ApiTeeBox(
      teeName:       j['tee_name']         as String? ?? 'Tee',
      courseRating:  (j['course_rating']   as num?)?.toDouble() ?? 72.0,
      slopeRating:   (j['slope_rating']    as num?)?.toInt() ?? 113,
      parTotal:      (j['par_total']       as num?)?.toInt() ?? 72,
      totalYards:    (j['total_yards']     as num?)?.toInt() ?? 0,
      numberOfHoles: (j['number_of_holes'] as num?)?.toInt() ?? 18,
      holes: rawHoles.map((h) => ApiHole.fromCached(h as Map<String, dynamic>)).toList(),
    );
  }
}

class ApiCourse {
  final int id;
  final String clubName;
  final String courseName;
  final String city;
  final String state;
  final String country;
  final List<ApiTeeBox> maleTees;
  final List<ApiTeeBox> femaleTees;

  const ApiCourse({
    required this.id,
    required this.clubName,
    required this.courseName,
    required this.city,
    required this.state,
    required this.country,
    required this.maleTees,
    required this.femaleTees,
  });

  String get displayName {
    final loc = [city, state, country]
        .where((s) => s.isNotEmpty)
        .toSet() // eliminar duplicados
        .join(', ');
    return loc.isEmpty ? clubName : '$clubName — $loc';
  }

  factory ApiCourse.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>? ?? {};
    final tees = j['tees'] as Map<String, dynamic>? ?? {};
    final maleList   = (tees['male']   as List?) ?? [];
    final femaleList = (tees['female'] as List?) ?? [];

    return ApiCourse(
      id:         (j['id'] as num?)?.toInt() ?? 0,
      clubName:   j['club_name']   as String? ?? 'Campo sin nombre',
      courseName: j['course_name'] as String? ?? '',
      city:       loc['city']    as String? ?? '',
      state:      loc['state']   as String? ?? '',
      country:    loc['country'] as String? ?? '',
      maleTees:   maleList  .map((t) => ApiTeeBox.fromJson(t as Map<String, dynamic>)).toList(),
      femaleTees: femaleList.map((t) => ApiTeeBox.fromJson(t as Map<String, dynamic>)).toList(),
    );
  }

  /// Todos los tees disponibles (male primero, luego female)
  List<ApiTeeBox> get allTees => [...maleTees, ...femaleTees];

  /// Serializar para cache en Firestore (tees ya con strokeIndex calculado)
  Map<String, dynamic> toJson() => {
    'id':          id,
    'club_name':   clubName,
    'course_name': courseName,
    'city':        city,
    'state':       state,
    'country':     country,
    'maleTees':    maleTees.map((t) => t.toJson()).toList(),
    'femaleTees':  femaleTees.map((t) => t.toJson()).toList(),
  };

  /// Deserializar desde cache de Firestore
  factory ApiCourse.fromCached(Map<String, dynamic> j) {
    final maleList   = (j['maleTees']   as List?) ?? [];
    final femaleList = (j['femaleTees'] as List?) ?? [];
    return ApiCourse(
      id:         (j['id'] as num?)?.toInt() ?? 0,
      clubName:   j['club_name']   as String? ?? '',
      courseName: j['course_name'] as String? ?? '',
      city:       j['city']        as String? ?? '',
      state:      j['state']       as String? ?? '',
      country:    j['country']     as String? ?? '',
      maleTees:   maleList  .map((t) => ApiTeeBox.fromCached(t as Map<String, dynamic>)).toList(),
      femaleTees: femaleList.map((t) => ApiTeeBox.fromCached(t as Map<String, dynamic>)).toList(),
    );
  }
}

// ── Servicio ──────────────────────────────────────────────────────────────────

class GolfCourseService {
  static const _baseUrl = 'https://api.golfcourseapi.com';
  static const _apiKey  = 'DLZRFGWXFTHO6QNK3ZIOVL5I2Q';

  static Map<String, String> get _headers => {
    'Authorization': 'Key $_apiKey',
    'Content-Type': 'application/json',
  };

  // ── Buscar campos por nombre ──────────────────────────────────────────────
  // Respuesta: { "courses": [ {...}, ... ] }
  static Future<List<ApiCourse>> search(String query) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/v1/search')
        .replace(queryParameters: {'search_query': query.trim()});

    final resp = await http.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));

    if (resp.statusCode != 200) {
      throw Exception('Error ${resp.statusCode}');
    }

    final body = json.decode(resp.body) as Map<String, dynamic>;
    final courses = (body['courses'] as List?) ?? [];
    return courses
        .map((c) => ApiCourse.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  // ── Obtener campo completo (con hoyos) por ID ─────────────────────────────
  // Respuesta: { "course": { ... } }   ← wrapper singular "course"
  static Future<ApiCourse> getById(int id) async {
    final uri = Uri.parse('$_baseUrl/v1/courses/$id');

    final resp = await http.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));

    if (resp.statusCode != 200) {
      throw Exception('Error ${resp.statusCode}');
    }

    final body = json.decode(resp.body) as Map<String, dynamic>;

    // ⚠️ El wrapper es "course" (singular), NO el objeto directo
    final courseJson = body['course'] as Map<String, dynamic>? ?? body;
    return ApiCourse.fromJson(courseJson);
  }
}
