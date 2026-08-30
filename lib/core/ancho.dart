// ─────────────────────────────────────────────────────────────────────────────
// EL LAYOUT SE ELIGE POR ANCHO, NO POR PLATAFORMA
//
// Es la misma decisión que ya sostiene la pantalla de la casa club: allí la
// unidad sale del ALTO disponible, aquí el formato sale del ANCHO disponible.
// Y por el mismo motivo: `kIsWeb` o `Platform.isAndroid` responden a una
// pregunta que no es la que importa. Lo que decide si cabe una tabla de seis
// columnas es cuántos píxeles hay, no en qué tienda se descargó la app.
//
// El caso que lo obliga: el organizador abre `/organizador/{id}` en el portátil
// de la casa club por la mañana y en el teléfono desde el estacionamiento a
// mediodía. Es LA MISMA URL. Un portal que solo funcione en escritorio le deja
// sin nada justo el día del torneo, que es cuando está en el campo.
//
// Los cortes salen de lo que cabe, no de nombres de dispositivo:
//
//   · 1100 px  → caben las seis columnas de la tabla con aire
//   ·  720 px  → caben nombre y handicap, sin el resto
//   · por debajo → una columna de fichas
// ─────────────────────────────────────────────────────────────────────────────

/// Cuánto sitio hay. No qué aparato es.
enum Ancho {
  /// Una columna de fichas. El teléfono en el campo.
  estrecho,

  /// Tabla reducida. Tableta, o una ventana a medias.
  medio,

  /// La tabla entera, con panel lateral.
  amplio,
}

/// El corte a partir del cual caben las seis columnas.
const double anchoAmplio = 1100;

/// El corte a partir del cual una tabla se lee mejor que unas fichas.
const double anchoMedio = 720;

/// Qué formato pide [ancho] píxeles.
///
/// Función pura y expuesta a propósito: es lo que hace comprobable que la misma
/// URL sirve en las dos puntas. Un test fija los tres tramos, y entonces nadie
/// puede convertir esto en `if (kIsWeb)` sin que salte.
Ancho anchoDe(double ancho) {
  if (ancho >= anchoAmplio) return Ancho.amplio;
  if (ancho >= anchoMedio) return Ancho.medio;
  return Ancho.estrecho;
}

extension AnchoInfo on Ancho {
  /// Si se dibuja una tabla con cabeceras o una lista de fichas.
  bool get esTabla => this != Ancho.estrecho;

  /// Si hay sitio para las columnas accesorias —inscripción, acciones sueltas—.
  bool get columnasCompletas => this == Ancho.amplio;

  /// El ancho máximo del contenido. Una tabla de 2400 px de ancho no se lee: el
  /// ojo pierde la fila entre el nombre y el handicap.
  double get anchoDeContenido => switch (this) {
        Ancho.amplio => 1240,
        Ancho.medio => 900,
        Ancho.estrecho => 640,
      };
}
