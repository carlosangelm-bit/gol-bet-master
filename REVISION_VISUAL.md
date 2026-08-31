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
Cinco sitios en la misma pantalla:

- **Los dos botones de arranque** (*Front 9 primero* / *Back 9 primero*). Eran
  `1️⃣` y `2️⃣` y se habían roto: el dígito quedó suelto y el recuadro que lo
  envuelve, huérfano. Ahora son iconos. Mirar que se vea **1** y **2** dentro
  de su caja, y que el elegido tome el acento.

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

### 5 · Grupos de apuestas y Plantillas — y su estado vacío

**Plantillas, sin ninguna guardada**: la frase del final decía *«Ve a Inicio →
⋮ → Guardar como plantilla»*, y ese `⋮` salía como `▯`. No era un residuo: era
un carácter completo del que la fuente no tiene dibujo. Y además mandaba a un
menú de tres puntos **que no existe** — el botón está a la vista, dentro de la
ronda en curso. Ahora lo dice en palabras. Mirar que la instrucción sea cierta.

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

Ya no depende del tema de la app: tiene **sus propias plantillas**, y se revisan
aparte. Ver la sección de abajo.

---

# La pantalla proyectada, plantilla por plantilla

Se configura en **Portal de organizador → La pantalla**. La previa de esa
sección hace la misma cuenta que la pared, así que sirve para juzgar sin
proyectar — pero el criterio es verlo en la tele.

## Las cuatro, y qué mirar en cada una

| Plantilla | Para qué | Lo que puede fallar |
|---|---|---|
| **Casa club** | El torneo de siempre, verde de campo | Es la de por defecto: ningún torneo ya publicado debe cambiar de cara |
| **Retransmisión** | Neutra, gris | Que el acento sea **lo único** con color en la pared |
| **Corporativa** | Torneo de empresa | Que un logo de marca encaje sin pelearse con el azul |
| **Atardecer** | Pantalla con luz de frente | Que aguante el sol: es la que existe para eso |

**En las cuatro, y en sus tres fondos:** que el nombre y el puesto se lean desde
donde de verdad se va a mirar. El test fija los 40 px en 1080p para las cuatro,
pero 40 px legibles y 40 px cómodos no son lo mismo.

## Las tres cosas nuevas de la tabla

**1 · El score contra el par.** Es lo que hace que se reconozca un leaderboard
de golf. Mirar que el `-7` esté en **rojo**, que el par diga **`E`** y no `0`, y
que el `+4` NO esté en rojo. La columna solo aparece en torneos que se puntúan
por score neto — con dinero, por posición o Stableford no hay bajo par y la
columna no se reserva.

**2 · El progreso.** `2/3` mientras va a medias, **`F`** cuando terminó todas
las rondas del torneo, y el que terminó marcado con el acento. **No dice por qué
hoyo va**: eso sería un dato de hace horas presentado como actual.

**3 · La separación del líder.** Una raya bajo el primero, más el relleno de
podio, más el puesto en el acento. Tres canales a la vez, a propósito: mirar que
se lea **desde lejos** y no solo de cerca — si solo se distingue acercándose,
sobra un canal o falta grosor.

## Y lo que hay que intentar romper

**Elige un color de torneo casi igual al fondo** —un azul muy oscuro sobre la
Corporativa, por ejemplo—. Lo que debe pasar: el color se aclara solo hasta que
se ve, **conservando el tono**. Sigue siendo su azul, más claro.

Si al elegirlo el punto de la paleta ya se ve aclarado, es correcto: la muestra
enseña el color **ya corregido**, no el elegido. Enseñar uno y proyectar otro
sería lo peor de las dos opciones.

## El gobierno, ahora en un solo sitio

**Portal → La pantalla** lo hace todo: encender, el enlace copiable, apagar y el
diseño. Es el **mismo bloque** que la app, no una copia — la app lo conserva
porque el organizador puede necesitar apagar la pared desde el campo.

**Lo que hay que comprobar de una pasada:**

1. Enciende la pantalla **desde el portal** y abre el enlace en otra ventana.
2. Cambia la plantilla o el color **sin tocar nada más**.
3. La pared debe cambiar sola. *Antes había que apagar y encender desde la app.*
4. Lo mismo con un **banner de patrocinador**: cambiarlo en Patrocinio ahora
   llega a la pared. Estaba igual de roto desde antes y nadie lo había visto.

Si algo no llega, sale un aviso diciéndolo. Un cambio guardado que no llega y no
avisa es el fallo que esto viene a cerrar.

**Y la puerta:** en la pantalla del torneo, junto al botón de compartir, hay uno
nuevo al portal. Antes había que escribir `/organizador/{id}` con un id que solo
se sacaba de Firestore.

## Identidad y marca, en la misma cabecera

Con un torneo que tenga **logo propio** y **banner de patrocinador**: van
**apilados**, no lado a lado. Mirar que ninguno encoja al otro y que el orden se
lea — primero de quién es el torneo, después quién lo paga. La pieza de
patrocinio conserva su etiqueta (`PATROCINADOR OFICIAL`); la identidad no lleva
etiqueta, porque quien organiza no se anuncia.

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
- Que no queda ningún **carácter roto o invisible**: selectores de variación
  sueltos, marcas combinantes huérfanas, espacios de ancho cero, mitades de un
  par sustituto.
- Que no hay ningún **símbolo fuera del repertorio**. Hay una lista cerrada
  —`· — → ← × ¿ ¡ … – − • ° « » ½ ± ª º`— y añadir uno exige verlo antes en
  pantalla. Es el trámite que faltaba y por el que se coló el `⋮`.

Lo que ninguna prueba puede decir es si el resultado se **ve bien**. Eso es lo
que queda arriba.
