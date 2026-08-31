# Qué mirar en cada tema

El criterio 4 de las dos entregas de iconografía —*verificado en pantalla, en
claro y en oscuro*— quedó a medias: la 1 se verificó solo en oscuro. Esto es la
lista para cerrarlo de una pasada.

La app arranca con el tema del sistema. Para cambiarlo: **Ajustes → Apariencia**.

---

## Por qué las dos, y no una

Un emoji se ve **idéntico** en los dos temas: tiene sus propios colores y no
hereda nada. Por eso *cantaba* en oscuro y pasaba desapercibido en claro — y
por eso verificar solo en oscuro no cierra nada. Un icono hace lo contrario:
toma su color del tema, y ahí es donde puede fallar de dos maneras opuestas.

| | Lo que falla en **claro** | Lo que falla en **oscuro** |
|---|---|---|
| **Contraste** | El icono en `t.sub` (gris medio) sobre `surface` casi blanco: se pierde | El icono en `t.primary` sobre `#121212`: puede vibrar |
| **Peso** | Un icono se ve *más ligero* de lo que es | Un icono se ve *más pesado*: el trazo claro sobre fondo negro engorda |
| **Selección** | El estado elegido (`primary` al 12 %) se distingue mal del no elegido | El mismo relleno puede quedar demasiado visible |

Lo que se busca es lo mismo en las dos: que el icono **acompañe** a su texto y
no compita con él.

---

## Las siete pantallas, en orden

### 1 · Entrada y Portada de Inicio
Tres insignias en fila: **bandera / dinero / trofeo**, con su etiqueta al lado.

- **En claro**: van sobre el degradado del héroe, en blanco. Mirar que se lean
  sobre la parte más clara del degradado.
- **En oscuro**: mirar que no queden más brillantes que el título.

### 2 · Nueva ronda — *Setup* (la que más cambió: 25 emoji)
Cuatro sitios en la misma pantalla:

- **El selector de marca** (la cuadrícula de doce). En claro, comprobar que la
  marca elegida —borde y relleno `primary`— se distingue de las otras once. Es
  el punto donde el modo claro suele quedarse corto.
- **Las cuatro estructuras de apuesta** (Grupo único / Head to head / Jugador
  vs varios / Una apuesta por pareja). Cada una con su icono a la izquierda; el
  elegido en `primary`, los demás en `sub`.
- **La vista previa del match**: cuatro filas con icono de 13 px junto a texto
  de 12. Aquí es donde un icono mal escalado se nota primero.
- **Los modos de formato** (un pozo / todos contra todos): trofeo y duelo.

### 3 · Tarjeta — *Scorecard* (17 emoji, ahora ninguno)
- El **duelo** (⚔️) y el **rayo** (⚡) que antes eran caracteres sueltos.
- Las frases donde el emoji iba **dentro** del texto —*Zapato:*, *×N en pot*—
  ya no lo llevan. Mirar que la frase se lea bien sin él: es donde se decidió
  que la palabra ya cargaba el significado.

### 4 · Resultados — el detalle de unidades
Los **seis eventos** en columna: birdie, eagle, par de arena, par único, birdie
único, hoyo directo. Es la única pantalla donde se ven los seis juntos, así que
es donde se comprueba que **se distinguen entre sí de un vistazo**. Van en
`t.sub` a 13 px.

### 5 · Grupos de apuestas y Plantillas
La **marca guardada**, en dos sitios: el botón grande del editor (34 px) y la
tarjeta de la lista (22 px).

> **Lo importante aquí**: un grupo creado **antes** de hoy tiene guardado un
> emoji, no una clave. Debe enseñar **la bandera** —la marca por defecto— y no
> un hueco ni un cuadrado. Es la promesa del *sin migración*: si aparece un
> hueco, eso sí es un fallo que hay que contar.

### 6 · Ajustes
La insignia del índice de handicap: **bandera** si hay índice, **gráfico** si
todavía no. En claro, comprobar que la versión gris (sin índice) se distingue
del fondo.

### 7 · La tele — *Leaderboard TV*
Cerró en la entrega 1 y no cambió aquí, pero es la superficie que se proyecta.
Vale una mirada en los dos temas: el trofeo del campeón y nada más.

---

## Lo que ya está comprobado por prueba, y no hace falta mirar

- Que no queda **ningún** emoji en el código de interfaz — hay un contador en
  `test/iconografia_test.dart` que falla con el primero que se escriba.
- Que ninguno es la **variante rellena**.
- Que los **tamaños** van por encima de su escalón de texto y por debajo del
  doble.
- Que el **mismo icono da dos colores** en los dos temas.
- Que una **marca vieja** (`'⛳'`, `'🏆'`, vacío, nulo) cae en la bandera sin
  lanzar.
- Que las **doce claves** de la paleta dan doce iconos distintos.

Lo que ninguna prueba puede decir es si el resultado se **ve bien**. Eso es lo
que queda arriba.
