# Modelo de negocio: dos productos, dos tarifas

**Esto no está construido.** Falta el sistema de cobro, que es otra conversación.
Lo que hay aquí son las decisiones tomadas y **el estado real del código frente a
ellas**, escrito antes de seguir añadiendo funciones — porque cada función nueva
cae de un lado o del otro, y descubrirlo al cobrar es tarde.

---

## Las decisiones

### Dos productos, no dos niveles

No son dos tiers del mismo producto: son **dos productos con dos clientes
distintos**.

| | El golfista | El organizador |
|---|---|---|
| **Paga por** | jugar mejor | operar un torneo |
| **Incluye** | apuestas, handicap, asistente, sliding | portal, pantalla de casa club, patrocinio, shotgun |
| **Cómo cobra él** | no cobra | a sus patrocinadores |
| **Cadencia** | suscripción | **por evento** |

**El de organizador incluye el de golfista.** Quien organiza también juega, y
regalarle la parte barata quita fricción de venta.

### Por evento, y no por jugador

El organizador **cobra por evento**: el presupuesto de un torneo se arma con sus
patrocinadores y ahí cabe una línea de gasto. Un cargo anual sale de otro
bolsillo y es más difícil de aprobar.

**El precio no varía por número de jugadores.** Los costes que crecen —escrituras
de Firestore, logos en Storage, republicaciones del `Thru`— son **céntimos** entre
20 y 150 personas. No justifica complicar el precio.

**Sí varía por duración.** Y el argumento bueno no es el coste: un torneo de un
día es un **evento**; una liga de temporada es una **herramienta de gestión
durante meses**.

---

## La auditoría: ¿se pueden separar hoy?

**Sí, y en la dirección correcta.** La pregunta útil no era «están separados» sino
**hacia dónde apuntan las dependencias**, porque siendo organizador ⊃ golfista, una
sola dirección es exactamente lo que hace falta.

### Lo que apunta hacia dentro del portal: dos ficheros

```
lib/main.dart                        la ruta /organizador/{id}
lib/screens/torneos/torneos_screen.dart   el botón al portal
```

**Eso es todo.** El código del jugador **no depende** del portal, así que un
build sin portal compilaría quitando dos importaciones y una ruta. Es la
condición que hace posible cobrar por separado, y está cumplida.

### Lo que apunta hacia fuera: 58 importaciones, y ninguna a una pantalla del jugador

Las siete secciones del portal más la tele importan modelos, providers y
servicios —compartidos y correctos— y **solo tres pantallas**:

| Importación | Qué es de verdad |
|---|---|
| `auth/auth_screen.dart` | la sesión. Compartida por definición |
| `torneos/republicar_pantalla.dart` | 95 líneas, y es **del organizador** aunque viva en `torneos/` |
| `torneos/tele_sheet.dart` | 750 líneas, y es **del organizador** |

### El único enredo real, y es barato

**`tele_sheet.dart` es funcionalidad de organizador montada dentro de la hoja de
compartir del jugador.** Encender la pantalla de la casa club —lo que se va a
cobrar— es alcanzable desde la app del jugador.

Y resulta que eso **no es un problema, es la puerta**: es UN widget
(`BloqueTele`) montado en dos sitios, así que la comprobación de pago va dentro
de él y cubre las dos entradas. Ya se unificó una vez por otro motivo —había dos
implementaciones del gobierno de la pantalla— y esa unificación es la que hace
que ahora haya un solo sitio donde poner el candado.

**Lo que conviene hacer cuando toque:** mover `tele_sheet.dart` y
`republicar_pantalla.dart` a `screens/organizador/`. Es un cambio de carpeta, no
de arquitectura.

### Las colecciones ya se parten por la misma línea

| Del golfista | Del organizador |
|---|---|
| `users/{uid}/**` · `liveRounds` · `players` · `userLookup` · `courseCorrections` | `leaderboards/{token}` · Storage de patrocinio |
| `torneoResultados` | |
| `sharedTorneos/{token}` **← el ambiguo** | |

**`sharedTorneos` hay que decidirlo.** Es el enlace de WhatsApp con la tabla del
torneo: lo usa un jugador que comparte su liga de los sábados, y también un
organizador. Si se cobra, se cobra a quien no lo esperaba.

---

## El hallazgo que decide el cobro, y no está en la interfaz

**La regla de `users/{uid}` es:**

```
allow write: if request.auth != null && request.auth.uid == userId;
```

Sin restricción de campos. **Así que una marca de "ha pagado" guardada ahí la
puede escribir el propio usuario** con una llamada a la API de Firestore y su
token — sin tocar la app.

**El derecho de uso no puede vivir donde el usuario escribe.** Tiene que ir en
una colección con `allow write: if false`, escrita solo desde el webhook de
cobro. El precedente exacto ya está en el fichero: `courseCorrections`, que se
lee con `get` y no la escribe nadie desde la app.

Y la comprobación tiene que estar **en las reglas**, no solo en la pantalla:
esconder el botón no impide una escritura a `leaderboards/{token}`, que es
justamente lo que se está vendiendo.

---

## Las tres determinaciones que se pidieron

### 1 · El torneo necesita saber su duración, y hoy no lo sabe

Lo que tiene hoy son **tres cosas que no son duración**:

- `FormatoDeTorneo` — liga o eliminación: **forma de competir**
- `FuenteDeRondas` — marcadas, rango o grupo: **qué rondas cuentan**
- `desde` / `hasta` — un rango de fechas, y solo se usa con `FuenteDeRondas.rango`

`desde`/`hasta` es lo más parecido y **no sirve**: una liga de temporada puede
estar en modo "marcadas" y no tener fechas. La duración es un campo nuevo, y
elegirlo al crear **con el precio delante** hace además que se decida antes de
empezar en vez de descubrirse al pagar.

### 2 · Qué se bloquea sin pagar

**Crear y probar, libre. Se cobra al ENTREGAR el valor**, que son dos momentos
concretos y los dos ya identificables en el código:

- **encender la pantalla** → `Tele.publicar(encender: true)`
- **publicar el inventario** → la primera pieza de patrocinio con logo

Los dos escriben en colecciones del organizador, así que los dos son
comprobables en las reglas y no solo en la interfaz. Formar los grupos del
shotgun y crear las 22 rondas **no** se cobra: son rondas, y las rondas son del
producto del golfista.

### 3 · El asistente, del lado del golfista

Es el caso donde más sentido tiene: quien dice *"Nassau de 500 con presiones y
unidades a 100"* describe en una frase lo que la app pide en nueve pantallas.

**Y con las dos condiciones de siempre**, que en este proyecto ya tienen
historial:

- **Lo que no se diga se pregunta, o se asume DICIÉNDOLO.** Un valor plausible
  que nadie comprueba es el fallo más caro que ha tenido este proyecto: pasó con
  los diferenciales de handicap, con el par inventado, con el monto del paso 7 y
  con el tee horneado en el nombre del campo. Cuatro veces.
- **Confirmar antes de aplicar, con las cifras delante.** Es dinero.

---

## La línea, ya trazada

**Construido.** Lo que queda pendiente es el cobro, no la separación.

### Cómo se entra

**Por el logo de Inicio**, y solo lo ve quien está marcado. Con marca, un punto
dorado en la esquina; sin marca, nada — una insignia que no lleva a ningún sitio
es lo que este proyecto ya quitó una vez.

**Y qué ve quien no la tiene:** una hoja que dice qué es el módulo, que es la
única forma de venderlo desde dentro. Con una línea que decide si suma o resta:
*«Crear tus torneos, su tabla y compartirla ya lo tienes, y seguirá siendo
gratis. Esto es otra cosa.»* Sin ella, la hoja parece decir que lo que ya tienes
está detrás de un pago.

**No hay botón de comprar.** Se contrata hablando, que es lo que encaja con
pagar por evento.

### Dónde vive la marca

`organizadores/{uid}` · `allow get` para uno mismo · `allow write: if false`.

**La EXISTENCIA es la marca**: no hay un campo `activo` que consultar. Un
booleano dentro daría dos estados para lo mismo —documento ausente y documento
en false— y el día que alguien escriba solo uno, la cuenta queda en un limbo.

**Cómo lo administra Carlos: la consola de Firebase.** Crear el documento
`organizadores/{uid}` con lo que quiera dentro. Una pantalla de administración
es trabajo que no hace falta todavía y que además traería su propio problema
—quién es el master— más grande que el que resuelve. El día que haya cobro
automático, lo escribe el webhook.

### Lo que se movió

| Estaba | Está |
|---|---|
| Botón al portal en la pantalla del torneo | fuera — era una puerta lateral |
| `BloqueTele` en la hoja de compartir | fuera — encenderla es lo que se cobra |
| `tele_sheet.dart` en `screens/torneos/` | `screens/organizador/` |
| `republicar_pantalla.dart` en `screens/torneos/` | `screens/organizador/` |

**Apagar la pared se queda en el lado del jugador**: «dejar de compartir» tiene
que apagarla, o la frase del botón sería mentira. **Cortar nunca se cobra.**

### Y el torneo del organizador NO es otra cosa

Se preguntó si debía serlo, sin compatibilidad que respetar. **No**, y el
argumento decisivo no es de diseño sino de seguridad:

**Cualquier marca de «esto es de pago» puesta en el torneo la escribe el propio
usuario** — los torneos viven en `users/{uid}/torneos`, que su dueño escribe
entero. Un tipo de torneo «formal» no puede cobrar nada: se pondría solo.

Lo único que puede cobrar es la marca de la **cuenta**, que vive fuera. Y sin esa
función, un tipo aparte solo duplicaría participantes, rondas, tabla, método y
acumulación.

**Lo que sí se añadió es `DuracionDeTorneo`** —un día / fin de semana /
temporada— porque es un dato real que no existía, y sirve para todos, no solo
para quien paga.

## Lo que esto pide de aquí en adelante

Una regla, corta: **cada función nueva dice de qué lado cae antes de escribirse.**
Y si es del organizador, que no la pueda alcanzar el jugador por un camino que no
sea `BloqueTele` o el portal — porque ese es el sitio donde va el candado.
