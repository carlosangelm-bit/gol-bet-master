// ─────────────────────────────────────────────────────────────────────────────
// LA TENDENCIA DEL HANDICAP
//
// Dos cosas se prueban aquí, y la segunda es la que el encargo señaló como la
// que más importa:
//
//   · Que la serie SE DERIVE bien del histórico —el índice de ayer no lo guarda
//     nadie, se recalcula—, incluido el signo: en golf BAJAR es mejorar, y un
//     gráfico con el signo invertido dice lo contrario de lo que pasa.
//
//   · Que con pocas rondas NO dibuje. El estado normal de una cuenta nueva es
//     no tener datos, y una línea de dos puntos presentada como tendencia dice
//     algo falso. Es la misma familia que el "AS" que significaba tres cosas.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_bet_master/core/app_theme.dart';
import 'package:golf_bet_master/models/tendencia.dart';
import 'package:golf_bet_master/services/handicap_service.dart';
import 'package:golf_bet_master/widgets/grafico_tendencia.dart';

/// Un diferencial de [d] jugado el día [dia] de enero.
ScoreDifferential _d(int dia, double d) => ScoreDifferential(
      roundId: 'r$dia',
      roundName: 'Ronda $dia',
      playedAt: DateTime(2026, 1, dia),
      differential: d,
      grossScore: 90,
      adjustedGrossScore: 90,
      courseRating: 72,
      slopeRating: 113,
      parTotal: 72,
      holesPlayed: 18,
      courseName: 'Los Encinos',
    );

/// [n] rondas con diferencial que empieza en [desde] y cambia [paso] cada una.
List<ScoreDifferential> _serie(int n, {double desde = 20, double paso = 0}) =>
    [for (var i = 0; i < n; i++) _d(i + 1, desde + paso * i)];

final _ene1 = DateTime(2026, 1, 1);
final _ene2 = DateTime(2026, 1, 2);
final _ene3 = DateTime(2026, 1, 3);
final _ene4 = DateTime(2026, 1, 4);
final _ene5 = DateTime(2026, 1, 5);

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('1 · con pocas rondas NO se dibuja nada', () {
    test('cero rondas: ni serie ni línea', () {
      final s = tendenciaDeHandicap([]);
      expect(s.puntos, isEmpty);
      expect(s.suficiente, isFalse);
      expect(s.faltan, SerieDeTendencia.minimoRondas);
    });

    test('CLAVE: dos puntos NUNCA son una tendencia', () {
      // Una línea de dos puntos siempre "sube" o "baja": no describe nada,
      // decora una coincidencia.
      final s = tendenciaDeHandicap(_serie(4, paso: -1));
      expect(s.puntos.length, lessThanOrEqualTo(2));
      expect(s.suficiente, isFalse);
    });

    test('CLAVE: con TRES puntos tampoco, aunque ya haya línea que dibujar', () {
      // El tramo que faltaba cubrir. Con nueve rondas hay tres puntos: se
      // podría dibujar, y no se dibuja. Sin esta prueba, un
      // `suficiente => puntos.isNotEmpty` pasaba todo lo demás, porque los
      // otros casos dan CERO puntos.
      final s = tendenciaDeHandicap(_serie(9, paso: -1));
      expect(s.puntos.length, 3);
      expect(s.suficiente, isFalse);
      expect(s.faltan, 2);
    });

    test('CONTRAPESO: y con once SÍ, o esto no serviría nunca', () {
      // Sin este contrapeso, un `suficiente => false` fijo pasaría todo lo de
      // arriba y la función no se dibujaría jamás.
      final s = tendenciaDeHandicap(_serie(11, paso: -1));
      expect(s.puntos.length, greaterThanOrEqualTo(SerieDeTendencia.minimoPuntos));
      expect(s.suficiente, isTrue);
      expect(s.faltan, 0);
    });

    // ── EL HALLAZGO QUE CAMBIÓ EL DISEÑO ────────────────────────────────────
    //
    // La serie iba a empezar en la tercera ronda, que es donde WHS da índice.
    // Una prueba con doce rondas de diferencial IDÉNTICO lo desmintió: el
    // índice subía 2,0 puntos sin que el jugador cambiara nada.
    //
    // Es la tabla WHS, que con pocas rondas aplica una reducción y después la
    // retira: −2,0 a las tres, −1,0 a las cuatro, −1,0 a las seis, cero desde
    // la séptima. Los primeros puntos se movían por el andamiaje.
    test('CLAVE: el primer punto nace donde el ajuste WHS ya es CERO', () {
      final s = tendenciaDeHandicap(_serie(15, paso: -0.5));
      expect(s.puntos.first.rondas, SerieDeTendencia.primeraRondaComparable);
      expect(SerieDeTendencia.primeraRondaComparable, 7);
    });

    test('CLAVE: un jugador que no cambia nada sale PLANO', () {
      // Es la prueba que destapó el ajuste. Antes daba "has subido 2,0" y se lo
      // atribuía al jugador; ahora la serie empieza donde eso ya no pasa.
      final s = tendenciaDeHandicap(_serie(15, desde: 15));
      expect(s.suficiente, isTrue);
      expect(s.delta.abs(), lessThan(0.2),
          reason: 'el andamiaje de la tabla ya no está en la serie');
      expect(s.rumbo, RumboDeTendencia.plana);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('2 · el signo: en golf, bajar es mejorar', () {
    test('CLAVE: el índice bajando es MEJORA', () {
      final s = tendenciaDeHandicap(_serie(16, desde: 25, paso: -1));
      expect(s.ultimo, lessThan(s.primero));
      expect(s.delta, lessThan(0));
      expect(s.rumbo, RumboDeTendencia.mejora);
      expect(s.frase, contains('bajado'));
    });

    test('y subiendo es empeorar', () {
      final s = tendenciaDeHandicap(_serie(16, desde: 10, paso: 1));
      expect(s.rumbo, RumboDeTendencia.empeora);
      expect(s.frase, contains('subido'));
    });

    test('CLAVE: una diferencia mínima NO es noticia', () {
      // Sin zona muerta, 0,05 se anunciaría como "mejorando" y sería ruido
      // presentado como tendencia. El índice se muestra con un decimal, así
      // que por debajo de dos décimas no hay nada que contar.
      //
      // Se construye a mano: por el camino de WHS es difícil fabricar un delta
      // de exactamente 0,1, y lo que se prueba aquí es la zona muerta, no el
      // cálculo del índice.
      final casi = SerieDeTendencia(rondas: 20, puntos: [
        PuntoDeTendencia(cuando: _ene1, indice: 15.0, rondas: 7),
        PuntoDeTendencia(cuando: _ene2, indice: 15.05, rondas: 8),
        PuntoDeTendencia(cuando: _ene3, indice: 14.95, rondas: 9),
        PuntoDeTendencia(cuando: _ene4, indice: 15.1, rondas: 10),
        PuntoDeTendencia(cuando: _ene5, indice: 15.1, rondas: 11),
      ]);
      expect(casi.delta.abs(), lessThan(0.2));
      expect(casi.rumbo, RumboDeTendencia.plana);
      expect(casi.frase, contains('Estable'));
    });

    test('CONTRAPESO: y justo por encima del umbral SÍ lo es', () {
      // Sin esto, un `rumbo => plana` fijo pasaría la prueba de arriba.
      final baja = SerieDeTendencia(rondas: 20, puntos: [
        PuntoDeTendencia(cuando: _ene1, indice: 15.0, rondas: 7),
        PuntoDeTendencia(cuando: _ene2, indice: 14.9, rondas: 8),
        PuntoDeTendencia(cuando: _ene3, indice: 14.8, rondas: 9),
        PuntoDeTendencia(cuando: _ene4, indice: 14.7, rondas: 10),
        PuntoDeTendencia(cuando: _ene5, indice: 14.7, rondas: 11),
      ]);
      expect(baja.rumbo, RumboDeTendencia.mejora);
    });

    test('la frase lleva la CIFRA, no solo la dirección', () {
      // "Ha bajado" sin cuánto deja al jugador mirando el gráfico para
      // adivinarlo.
      final s = tendenciaDeHandicap(_serie(16, desde: 25, paso: -1));
      expect(s.frase, matches(RegExp(r'\d+[.,]\d')));
      expect(s.frase, contains('${s.puntos.length} rondas'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('3 · la serie se deriva del histórico', () {
    test('el orden de entrada da igual', () {
      // Confiar en el orden de quien llama es pedir un fallo silencioso.
      final normal = _serie(16, desde: 25, paso: -1);
      final revuelto = [...normal.reversed];
      final a = tendenciaDeHandicap(normal);
      final b = tendenciaDeHandicap(revuelto);
      expect(b.puntos.map((p) => p.indice), a.puntos.map((p) => p.indice));
    });

    test('cada punto es el índice que HABÍA entonces', () {
      // O sea: con las rondas hasta esa, y ninguna posterior. Es lo que
      // distingue una tendencia de una línea recalculada al revés.
      final diffs = _serie(16, desde: 25, paso: -1);
      final s = tendenciaDeHandicap(diffs);
      for (final p in s.puntos) {
        final hasta = diffs.take(p.rondas).toList();
        expect(p.indice, HandicapService.calculateIndex(hasta).index,
            reason: 'punto de la ronda ${p.rondas}');
      }
    });

    test('y el último punto coincide con el índice de hoy', () {
      // El contrapeso que ata la serie a lo que la pantalla ya enseña: si se
      // separan, el gráfico contradice al número que tiene encima.
      final diffs = _serie(16, desde: 25, paso: -1);
      final s = tendenciaDeHandicap(diffs);
      expect(s.ultimo, HandicapService.calculateIndex(diffs).index);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('4 · el color sale del sistema', () {
    test('CLAVE: la tendencia NUNCA usa el canal del dinero', () {
      // El verde y el rojo saturados son "cobras" y "pagas". Un handicap
      // bajando no es dinero cobrado, y reutilizar esos tonos rompería "un
      // canal, un significado" — que ya tiene test propio desde antes.
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        for (final r in RumboDeTendencia.values) {
          final c = GraficoTendencia.colorDe(r, t);
          expect(c, isNot(t.profit), reason: '$r');
          expect(c, isNot(t.loss), reason: '$r');
        }
      }
    });

    test('usa el canal del SCORE, que es el idioma de jugar mejor o peor', () {
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        expect(GraficoTendencia.colorDe(RumboDeTendencia.mejora, t), t.scoreUnder);
        expect(GraficoTendencia.colorDe(RumboDeTendencia.empeora, t), t.scoreOver);
      }
    });

    test('CONTRAPESO: mejora y empeora no son el mismo color', () {
      // Sin esto, devolver siempre t.sub pasaría las dos pruebas de arriba.
      for (final t in [GolfTheme.light, GolfTheme.dark, GolfTheme.classic]) {
        expect(GraficoTendencia.colorDe(RumboDeTendencia.mejora, t),
            isNot(GraficoTendencia.colorDe(RumboDeTendencia.empeora, t)));
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('5 · la geometría, que es donde vive el error que no se ve', () {
    const lienzo = Size(300, 64);

    test('CLAVE: el índice más BAJO va arriba', () {
      // En golf menos es mejor. Sin invertir el eje, la línea diría lo
      // contrario de lo que pasa — y se vería perfectamente bien.
      final s = tendenciaDeHandicap(_serie(16, desde: 25, paso: -1));
      final pts = posicionesDeTendencia(s, lienzo);
      final iMin = s.puntos.indexWhere((p) => p.indice == s.minimo);
      final iMax = s.puntos.indexWhere((p) => p.indice == s.maximo);
      expect(pts[iMin].dy, lessThan(pts[iMax].dy),
          reason: 'menos y es más arriba en el lienzo');
    });

    test('una serie PLANA no divide por cero', () {
      // Pasa de verdad: cinco rondas clavadas en el mismo índice. Sin
      // protección, la línea sale fuera del lienzo o no sale.
      final s = tendenciaDeHandicap(_serie(16, desde: 15));
      final pts = posicionesDeTendencia(s, lienzo);
      expect(pts, hasLength(s.puntos.length));
      for (final p in pts) {
        expect(p.dy.isFinite, isTrue);
        expect(p.dy, inInclusiveRange(0, lienzo.height));
      }
    });

    test('todos los puntos caen dentro del lienzo', () {
      final s = tendenciaDeHandicap(_serie(20, desde: 30, paso: -1.2));
      for (final p in posicionesDeTendencia(s, lienzo)) {
        expect(p.dx, inInclusiveRange(0, lienzo.width));
        expect(p.dy, inInclusiveRange(0, lienzo.height));
      }
    });

    test('y el primero y el último tocan los bordes laterales', () {
      // Un gráfico que deja aire a los lados desperdicia ancho justo donde la
      // pendiente se lee.
      final s = tendenciaDeHandicap(_serie(16, desde: 25, paso: -1));
      final pts = posicionesDeTendencia(s, lienzo);
      expect(pts.first.dx, 0);
      expect(pts.last.dx, lienzo.width);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('6 · en pantalla', () {
    Future<void> montar(WidgetTester tester, SerieDeTendencia s) async {
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      GolfThemeExt.setCurrent(GolfTheme.dark);
      await tester.pumpWidget(MaterialApp(
        theme: GolfTheme.dark.toMaterial(),
        home: Scaffold(
          body: GraficoTendencia(serie: s, t: GolfTheme.dark),
        ),
      ));
      await tester.pump();
    }

    testWidgets('CRITERIO 3: sin datos dice cuántas rondas faltan',
        (tester) async {
      await montar(tester, tendenciaDeHandicap(_serie(4, paso: -1)));
      expect(find.textContaining('Te faltan 7 rondas'), findsOneWidget);
      // Nada de rumbo: ni flecha, ni frase, ni escala. Material pinta sus
      // propios CustomPaint por dentro, así que contarlos no dice nada.
      expect(find.byIcon(Icons.trending_down), findsNothing);
      expect(find.byIcon(Icons.trending_up), findsNothing);
      expect(find.textContaining('puntos'), findsNothing);
    });

    testWidgets('y explica POR QUÉ hacen falta, no solo que faltan',
        (tester) async {
      await montar(tester, tendenciaDeHandicap(_serie(4, paso: -1)));
      expect(find.textContaining('una sola ronda mala manda'), findsOneWidget);
    });

    testWidgets('CRITERIO 1: con histórico, dibuja y dice el rumbo',
        (tester) async {
      await montar(tester, tendenciaDeHandicap(_serie(16, desde: 25, paso: -1)));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.textContaining('Has bajado'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down), findsOneWidget);
      expect(find.textContaining('faltan'), findsNothing);
    });

    testWidgets('y rotula los extremos: un gráfico sin escala es una forma',
        (tester) async {
      final s = tendenciaDeHandicap(_serie(16, desde: 25, paso: -1));
      await montar(tester, s);
      expect(find.text(s.primero.toStringAsFixed(1)), findsOneWidget);
      expect(find.text(s.ultimo.toStringAsFixed(1)), findsOneWidget);
      expect(find.text('${s.puntos.length} puntos'), findsOneWidget);
    });

    testWidgets('con el índice subiendo, la flecha va al revés', (tester) async {
      await montar(tester, tendenciaDeHandicap(_serie(16, desde: 8, paso: 1)));
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
      expect(find.textContaining('Has subido'), findsOneWidget);
    });
  });
}
