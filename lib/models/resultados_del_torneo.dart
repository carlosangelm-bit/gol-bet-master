// ─────────────────────────────────────────────────────────────────────────────
// LOS RESULTADOS COMPLETOS DE UN TORNEO — la receta, en un solo sitio
//
// ── El fallo que obliga a que esto exista ───────────────────────────────────
//
// Al republicar la pantalla desde el portal, la pared se llenó de guiones:
// ciento cincuenta y tres filas con `—`, `0/2` y `0`. Los nombres eran el
// síntoma visible; lo que en realidad pasó es que la tabla se reconstruyó
// desde una fuente INCOMPLETA y salió vacía de arriba abajo.
//
// La tabla de un torneo no sale de una sola fuente. Son cuatro pasos, y hay
// que darlos todos:
//
//   1 · los resultados PROPIOS, del perfil de quien mira
//   2 · MÁS los que publicaron otros jugadores del torneo
//   3 · filtrados por INSCRITOS, que es lo que la regla no puede comprobar
//   4 · y con el DIRECTORIO de nombres, porque un inscrito que todavía no ha
//       jugado no tiene nombre en ningún resultado y se queda en `—`
//
// La receta vivía suelta dentro de la pantalla del torneo. Al escribir la
// republicación copié dos de los cuatro pasos y salió lo que salió.
//
// ── Por qué una función y no "acordarse" ────────────────────────────────────
//
// Es la cuarta vez en el proyecto que un dato se cae al reconstruir algo campo
// a campo o paso a paso: el par dos veces, el nombre ahora. La respuesta no es
// mirar mejor: es que solo haya UN sitio donde se componga, y que quien
// publique lo RECIBA en vez de calcularlo.
//
// Por eso `republicarPantalla` ya no calcula ninguna tabla. La pide.
// ─────────────────────────────────────────────────────────────────────────────
import 'round_result.dart';
import 'torneo.dart';

/// Los cuatro pasos, juntos.
///
/// [propios] son los del perfil; [publicados] los que llegaron de otros. El
/// filtro por inscritos y la unión van aquí para que nadie tenga que recordar
/// el orden: unir primero y filtrar después daría el mismo resultado, pero
/// filtrar lo ajeno y luego unir es lo que ya hacía la pantalla y lo que las
/// pruebas del filtro describen.
List<RoundResult> resultadosDelTorneo({
  required Torneo torneo,
  required List<RoundResult> propios,
  required Iterable<ResultadoPublicado> publicados,
  required Map<String, String> nombres,
}) =>
    resultadosUnidos(
      propios,
      resultadosQueCuentan(torneo, publicados, nombres: nombres),
    );

/// La tabla completa de [torneo]. Es lo que se publica y lo que se enseña.
///
/// Recibe [nombres] porque sin ellos un inscrito que aún no ha jugado sale como
/// `—`: su nombre no está en ningún RoundResult, solo en el directorio. Es
/// exactamente el guion que apareció en la pared.
TablaDelTorneo tablaCompletaDe({
  required Torneo torneo,
  required List<RoundResult> propios,
  required Iterable<ResultadoPublicado> publicados,
  required Map<String, String> nombres,
}) =>
    tablaDe(
      torneo,
      resultadosDelTorneo(
        torneo: torneo,
        propios: propios,
        publicados: publicados,
        nombres: nombres,
      ),
      nombres: nombres,
    );
