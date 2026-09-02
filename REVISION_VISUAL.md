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

**Y mira los NOMBRES de la tabla proyectada después de guardar.** La primera
versión de esto republicaba con media receta y la pared se llenó de guiones: 153
filas con `—`, `0/2` y `0`. Los guiones eran el síntoma; lo que pasaba de verdad
es que la clasificación entera se reconstruía desde los resultados de una sola
persona. Si vuelves a ver un `—`, es eso.

**Nada más abrir el portal**, la tabla del torneo tarda un momento en cargar
—hay que traer lo que publicaron los demás—. Guardar antes de que termine NO
publica: sale un aviso pidiendo volver a guardar en unos segundos. Es
deliberado: publicar una tabla a medias sobre una completa es lo que borró la
pared.

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

---

# Scores en vivo · Portal → Scores en vivo

## Lo primero: la frontera es real, no una elección de diseño

**Los grupos que tú montaste** se ven en vivo, hoyo a hoyo, y son los que puedes
corregir. **Las rondas que lleva otra cuenta** se ven cuando las cierran, con su
fecha al lado. La pantalla lo dice en la primera frase.

No es una limitación provisional: las reglas de Firestore dejan leer una ronda
en vivo a quien está en ella o la organizó, y el organizador de un torneo no es
ninguna de las dos cosas en la ronda que montó otro. Ampliarlo daría permiso de
escritura sobre rondas ajenas — la regla concede lectura y escritura juntas.

## Qué mirar

**1 · Las dos listas, separadas.** Que no se confundan. Lo de fuera lleva
candado y fecha; lo tuyo lleva `Van 7/18`.

**2 · La tarjeta.** Toca un grupo tuyo: sale la rejilla de jugadores por hoyos.
Los scores bajo par en verde, sobre par en rojo, el par en el color del texto, y
el hoyo vacío con un punto — **no un cero**: «todavía no» y «cero golpes» no son
lo mismo.

**3 · Corregir.** Toca un score, cambia el número. Después mira abajo: debe
aparecer la línea de **CORRECCIONES** con `Ana Robles · hoyo 7: 5 → 4`, tu
nombre y la hora.

**4 · Los tres casos, que se dicen distinto:**

| Qué haces | Qué debe decir |
|---|---|
| Cambias un 5 por un 4 | `hoyo 7: 5 → 4` |
| Rellenas un hoyo vacío | `hoyo 3: se anotó 6` |
| Borras un score | `hoyo 7: se borró el 5` |

**5 · Y lo que NO debe pasar:** escribir el mismo número que ya había **no** debe
añadir una línea. Un registro con correcciones que no cambiaron nada hace dudar
de las que sí.

**6 · La prueba dura.** Corrige un hoyo, cierra la hoja, vuelve a abrirla. Las
correcciones deben seguir ahí. Es donde este proyecto ha perdido cuatro campos:
el guardado sobrescribe el documento entero y todo lo que no se serialice
desaparece en el siguiente golpe que anote alguien.

## Lo que NO está

**Meter una tarjeta a mano para el grupo que no captura.** El camino existe —
creas la ronda desde el torneo, con esos jugadores, y como es tuya sale en vivo
y corregible — pero no hay un atajo desde esta sección. Va en la siguiente.

---

# Grupos y salidas · Portal → Grupos y salidas

**La última sección.** Con el padrón de Copa de Primavera y un campo con sus
hoyos cargados:

## Empieza por el campo — ahora está aquí

**EL CAMPO** es el primer bloque de la sección, con su botón. Antes el aviso
decía *«elige el campo y vuelve»* y no había dónde: el selector estaba en el
editor del torneo, en la app.

- **Sin campo**: dice *«Sin campo todavía · Tócalo para elegirlo»*, en rojo.
- **Con campo**: el nombre más **los dos números que deciden todo** —
  `18 hoyos · 4 par 3`. Con el nombre solo, un campo mal cargado se ve idéntico
  a uno bueno hasta llegar al reparto.

Tócalo: abre el **mismo selector** del asistente, del arranque rápido y del
editor. Elige uno y **el resto de la sección se rellena en el sitio, sin
recargar** — el nombre del campo, las salidas y el número del botón.

> Si hay que recargar para verlo, es el fallo de antes: la sección leía una copia
> del torneo en vez del vivo. Y en la consola no debe salir ningún
> `permission-denied` de `courseCorrections`: esa colección no tenía regla
> ninguna, así que el deny por defecto la denegaba desde el primer día.

## Si el campo no trae los par 3

Aparece una rejilla de hoyos debajo del interruptor, **solo cuando puede hacer
falta**. Dice cuáles son par 3 según el campo, y se puede **añadir y quitar**:
un campo mal cargado puede traer un par 3 donde hay un par 4, y ahí la app
pondría dos grupos en un tee donde no caben.

El primer toque siembra la lista con los del campo; a partir de ahí manda la
lista. El borde azul marca lo que has dictado tú, distinto de lo que trae el
campo.

## Los cuatro números que hay que ver cuadrar

**1 · Las salidas.** El interruptor de *«Dos salidas en los par 3»* debe decir
**22 salidas** en un campo de 18 con cuatro par 3. Apágalo: debe decir **18**.
Si dice otra cosa, el campo no trae bien los pares.

**2 · Los grupos.** Con 88 inscritos y grupos de 4, **22 grupos** — y ningún
grupo de dos. Mira el número pequeño a la derecha de cada uno: todos 3 o 4.

**3 · Los títulos.** Cada grupo se titula por su **salida**, no «Grupo 14»:
`Hoyo 1`, `Hoyo 3A`, `Hoyo 3B`… Es lo que se canta por megafonía.

**4 · El botón.** Debe decir **Crear 22 rondas**, con el número.

## Lo que hay que intentar romper

**Sube el padrón por encima de lo que cabe** (93 inscritos en grupos de 4 dan 24
grupos). Debe salir el aviso rojo con la cifra — *«24 grupos y 22 salidas: no
caben 2»* — y **el botón se apaga**. Que no reparta como se pueda es el punto.

**Baja el padrón** (78 → 20 grupos). Debe avisar de que **sobran 2** salidas,
pero **sin apagar el botón**: sobrar no es un error.

**Elige un campo sin hoyos cargados.** Debe decirlo con el nombre del campo, no
suponer 18.

## Mover a alguien

Toca un jugador: sale la lista de destinos, cada uno por su salida. Muévelo y
comprueba que **desaparece del grupo de origen** — que aparezca en los dos es el
fallo de mover mal. Cambiar el tamaño de grupo **descarta las mudanzas** a
propósito: un reparto a mano sobre otro tamaño no significa nada.

## Y el cierre del círculo

Dale a **Crear 22 rondas**. Después ve a **Scores en vivo**: las 22 deben estar
en *TUS GRUPOS · EN VIVO*, con su salida como nombre. Ahí ya puedes abrir una
tarjeta y **probar la corrección**, que era lo que faltaba por verificar.

**Vuelve a darle al botón.** No debe duplicar nada: los ids son deterministas, la
segunda pulsación actualiza. Un botón lento produce dobles pulsaciones solo.

---

# Equipos y «Thru» en vivo

## Antes que nada: que lo individual siga igual

**Abre Copa de Primavera, Liga por Score y Match Play Anual.** El interruptor
*«Por equipos»* de Grupos y salidas debe estar **apagado** en los tres, la tabla
igual que siempre, y las rondas del reparto llamadas por su salida a secas
—`Hoyo 3B`, no `Equipo 04 · Hoyo 3B`—.

Si algo de esto cambió, para aquí: es peor que no haberlo hecho.

## Los equipos

En **Grupos y salidas**, enciende *«Por equipos»*. Cada grupo de salida pasa a
titularse **`Equipo 07 · Hoyo 7B`** — las dos cosas, porque el jugador busca su
equipo y el organizador canta la salida.

- **Toca «Poner nombre»** en uno. Debe quedar `Equipo 07 · Sierra`.
- **Cambia el tamaño de grupo.** El equipo 7 tendrá otra gente, **y seguirá
  llamándose Sierra**: el nombre va con el número, que es lo que el equipo
  reconoce.
- El **número va a dos cifras** a propósito: en una lista de 22, `Equipo 7` y
  `Equipo 17` no se alinean.

**Y un detalle que conviene ver una vez:** el equipo 7 sale del **hoyo 6**. Las
salidas van 1, 2, 3A, 3B, 4, 5, 6… así que el número del equipo y el del hoyo
dejan de coincidir en cuanto aparece el primer par 3. Es correcto.

## El «Thru»

Enciende la pantalla, crea las rondas, y **deja el portal abierto**. Cada minuto
publica por dónde va cada equipo, y en la pared la columna del progreso pasa a
decir el **hoyo** en vez de las rondas.

**Lo que hay que comprobar:**

1. Anota un hoyo en una tarjeta desde Scores en vivo. Al minuto, la pared debe
   decir ese hoyo para ese equipo.
2. Un equipo que acabe los 18 debe decir **`F`**.
3. Uno que no haya empezado, **`—`** y no `0`.

> **El Thru es tan vivo como el portal esté abierto.** Lo escribe el portal del
> organizador, no los teléfonos de los equipos — la regla de `leaderboards` solo
> deja escribir al dueño, y el token se proyecta en una pared ocho horas: no es
> sitio para aflojar la escritura. Si cierras el portal, el Thru se queda quieto
> y a la media hora **deja de enseñarse** en vez de mentir.

## La tabla por equipos, y el scramble

**Ya clasifica equipos.** Con *«Por equipos»* encendido, la tabla del torneo
tiene **una fila por equipo** — `Equipo 01 · Sierra` — y las personas no salen:
jugaron una bola, no tienen score propio.

**La pasada que cierra el módulo, y que nunca se ha hecho:**

1. Crea las rondas por lotes desde Grupos y salidas, con equipos.
2. Abre una tarjeta en Scores en vivo. Debe haber **una sola fila de score**,
   titulada `Equipo 01 · Sierra`, con dieciocho puntos — no cuatro filas con
   los nombres de las personas. Los cuatro se siguen viendo **en la lista de
   grupos**, que es donde toca: en la tarjeta no tienen score propio porque
   juegan una bola.

   *Y lo mismo desde la app*: si uno de los cuatro entra a capturar, ve la fila
   del equipo, no la suya.
3. Anota los 18 hoyos y **cierra la ronda**.
4. Vuelve a la tabla del torneo: el equipo debe aparecer **con su score**.

> El paso 4 es el criterio: hasta ahora una ronda de equipo cerrada producía un
> resultado **sin score para nadie**, y nadie lo había visto porque nunca se
> cerró una.

**Y lo que hay que comprobar que NO pasa:** ve a Ajustes → tu historial de
handicap. El score del scramble **no debe aparecer** como ronda tuya. Un
scramble sale seis u ocho golpes por debajo de lo que firmarías solo; meterlo
como score personal produciría diferenciales que no existen.

**Un torneo por equipos se puntúa por score o por Stableford**, no por dinero: el
dinero es de personas, y en estas rondas no hay apuestas.

---

# Quitar inscritos en bloque · Portal → Inscritos

**El caso real: Copa de Primavera con 153 inscritos y 22 salidas.** Hay que bajar
a 88, y eso son 65 fuera.

## Cómo se hace ahora

1. **Toca la casilla** de una fila. Nada se guarda y **nada se mueve**: aparece
   una barra arriba con `1 marcado para quitar`.
2. **Sigue tocando.** Puedes dar veinte toques seguidos en la misma posición y
   contarán veinte — la lista no se recompone hasta confirmar.
3. **`Quitar 20`** en la barra. Una escritura, un aviso.

**Con el buscador:** escribe un apellido y toca **`Marcar los N`**. Marca los que
se ven, no los 153 — filtrar y luego marcar todo sería lo contrario de lo que
pide quien acaba de filtrar.

## Los tres síntomas que esto cierra

| Antes | Ahora |
|---|---|
| Seis clics seguidos contaban uno | Nada se mueve hasta confirmar |
| El aviso tapaba el botón de la fila siguiente | La barra va **arriba**; el aviso, abajo |
| Sin forma de decir «estos veinte» | Una acción para N |

## Y una cosa que hay que intentar romper

**Marca veinte y quita el wifi antes de tocar `Quitar 20`.** Debe decir *«No se
pudo quitar a 20. Siguen marcados: vuelve a intentarlo»* — **y las veinte marcas
deben seguir ahí.** Perder veinte toques porque falló la red, y sin decirlo, es
el trabajo que esto viene a quitar.

## Y con eso, la creación por lotes

Baja Copa de Primavera a 88 y ve a **Grupos y salidas**: 22 grupos, 22 salidas, y
el botón `Crear 22 rondas` encendido. **No hace falta montar otro torneo.**

---

# La pantalla de inicio · en un iPhone

**Es la primera que se ve al abrir la app**, y la que más se mira con una mano.
Lo que quepa arriba del pliegue es lo que existe.

## Lo que se fue

El **hero** entero: ocupaba más de media pantalla para decir el nombre de una app
que acabas de abrir, con tres chips —Golf, Apuestas, Resultados— **que no
navegaban a ningún sitio**.

Había **dos cabeceras**. La de arriba, que siempre está, ya lleva el nombre y el
logotipo. La segunda repetía lo mismo debajo. El nombre sigue apareciendo **una
vez**.

## Lo que hay que ver, sin desplazar

Con el móvil en vertical y **sin tocar la pantalla**:

**Sin ronda en curso:**

1. **Nueva Ronda** — el botón, primero.
2. **Tu nombre y tu ÍNDICE**, con **su línea de tendencia** al lado.
3. **El bloque del dinero**.

**Con ronda en curso:** el nombre de la ronda arriba, y **`Nueva Ronda` no
aparece** — con una ronda abierta, empezar otra no es lo que se busca.

## La línea del índice

Es la novedad: la cifra sola no dice si estás bajando, y **tu índice pasó de 6,0
a 4,7 sin que lo viéramos** porque vivía en una tarjeta pequeña bajo el hero.

- **Con 20 rondas** debe haber una línea corta junto a la cifra.
- **Con pocas rondas no debe haber línea** — con menos de cinco puntos
  comparables describiría el ajuste de la tabla WHS, no tu juego. La hoja
  completa, con sus diferenciales, sigue en **Ajustes**.

## Lo que NO se movió de sitio

**EN JUEGO**, **TU RIVAL HABITUAL** y **ÚLTIMAS RONDAS** siguen ahí, en ese
orden, debajo. No se borró nada: se cambió qué va arriba.

---

# El índice y las rondas de nueve hoyos

## Lo que hay que ver en Ajustes → tu índice

**El índice va a subir.** Tres de tus ocho diferenciales usados eran de nueve
hoyos, y daban alrededor de la mitad de lo que la misma calidad de juego daría
en dieciocho — así que ganaban la selección de los ocho mejores siempre.

**En la lista de diferenciales:**

1. **Las rondas de nueve aparecen combinadas de dos en dos**, con los dos
   nombres: `Ronda A + Ronda B`. Un diferencial de dieciocho por cada par.
2. **Si tienes un número impar de nueves, el último dice que espera pareja** —
   en gris, en la lista, con su motivo: *«WHS junta dos rondas de nueve para
   hacer un diferencial de dieciocho»*. No desaparece.
3. El combinado se fecha con **la más reciente de las dos**.

> **No hay nada que recalcular.** Los diferenciales guardados no estaban mal:
> cada uno era el diferencial correcto de sus nueve hoyos. Lo que estaba mal era
> compararlos con los de dieciocho, y eso se corrige al calcular el índice — así
> que se arregla solo al abrir la app.

## Y el detalle de una ronda, en el iPhone

Toca una ronda de la lista. La fila **SALIDA** ya no se parte letra por letra ni
se sale por la derecha.

**Y hay una fila nueva: `CR · SLOPE`.** Eran el tercer y cuarto dato de la misma
línea. Nada sobraba —esos dos números solo aparecen aquí, y son los que
destaparon el sesgo— así que no se quitó nada: se separó.

En una ronda de nueve verás **`35.9 · 149`**: el CR es la mitad porque es un
total, y el Slope no lo es porque es una pendiente. **Las dos cosas son
correctas**; el fallo era compararlo con un dieciocho.
