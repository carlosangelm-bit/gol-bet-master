# Lo que hay que hacer una vez, y no está en el código

Tres cosas que este repositorio no puede desplegar solo. Están aquí porque cada
una costó una ronda de ida y vuelta al descubrirla, y la siguiente persona que
monte el proyecto no tiene por qué repetirla.

---

## 1 · Activar Firebase Storage

Consola de Firebase → **Storage** → **Comenzar**, en modo producción.

Sin esto, `firebase deploy --only storage` falla con:

```
Error: Firebase Storage has not been set up on project 'golf-bet-master'.
```

Y en la app, subir un logotipo devuelve un error que habla de un bucket
inexistente. El servicio lo traduce —`PatrocinioStorage.esFaltaDeBucket`— para
que la pantalla diga qué botón hay que pulsar en vez de enseñar el error crudo.

Bucket actual: `golf-bet-master.firebasestorage.app`, US-EAST1.

---

## 2 · CORS del bucket

**Sin esto los logotipos suben bien y no se pintan.** Es lo que pasó la primera
vez, y el síntoma engaña: el archivo está en Storage, con su tipo correcto y su
tamaño correcto, y en pantalla sale un icono de imagen rota.

### Por qué pasa

Flutter Web con CanvasKit **no dibuja las imágenes con un `<img>` del DOM**: las
lleva a un canvas. Para eso el navegador las pide en modo CORS, y exige la
cabecera `Access-Control-Allow-Origin` **en la respuesta del GET**.

Un bucket recién creado no la manda. Se comprobó así, y conviene saber la sonda
porque el resultado no es obvio:

```
$ curl -s -D- -o /dev/null -X OPTIONS \
    -H "Origin: https://golf-bet-master.web.app" \
    -H "Access-Control-Request-Method: GET" \
    "https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<obj>?alt=media"

  access-control-allow-origin: *      ← el PREFLIGHT sí la manda

$ curl -s -D- -o /dev/null \
    -H "Origin: https://golf-bet-master.web.app" \
    "https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<obj>?alt=media"

  (ninguna cabecera access-control-*)  ← el GET REAL no
```

El preflight pasando y el GET no es exactamente el caso que despista: parece que
CORS está bien configurado y no lo está.

### Cómo se arregla

Con `gcloud` autenticado en el proyecto:

```sh
gcloud storage buckets update gs://golf-bet-master.firebasestorage.app \
  --cors-file=cors.json
```

O con `gsutil`, que es lo que sale en la documentación antigua:

```sh
gsutil cors set cors.json gs://golf-bet-master.firebasestorage.app
```

### Y cómo se comprueba que quedó

El GET real tiene que traer ya la cabecera:

```sh
curl -s -D- -o /dev/null -H "Origin: https://golf-bet-master.web.app" \
  "https://firebasestorage.googleapis.com/v0/b/golf-bet-master.firebasestorage.app/o/<obj>?alt=media" \
  | grep -i access-control-allow-origin
```

### Por qué `origin: ["*"]`

Estos archivos ya son de **lectura pública por regla** —la pantalla de la casa
club no tiene sesión y tiene que poder pintarlos—, así que restringir el origen
no protege nada que la regla no proteja ya.

Lo único que ganaría una lista cerrada es evitar que otro sitio enlace las
imágenes y gaste ancho de banda. A cambio rompe el desarrollo local, porque
`flutter run -d chrome` levanta un puerto distinto cada vez y CORS de GCS compara
el origen entero, puerto incluido.

Si algún día el ancho de banda importa, se cambia a la lista de hosts conocidos
y se añade el puerto local de cada quien. Está escrito para que sea una decisión
y no un descuido.

---

## 3 · Las reglas, que sí están en el código

Estas se despliegan y no hace falta consola:

```sh
firebase deploy --only firestore:rules   # firestore.rules  · 87 pruebas
firebase deploy --only storage           # storage.rules    · 21 pruebas
firebase deploy --only hosting
```

Las pruebas de reglas, contra el emulador:

```sh
firebase emulators:exec --only firestore "node test_rules/run.mjs"
firebase emulators:exec --only storage   "node test_rules/storage.mjs"
```

---

## Lo que sigue sin poder ejecutarse aquí

`integration_test/patrocinio_subida_test.dart` cubre el tramo
`bytes → putData → getDownloadURL` con el plugin de Flutter, contra el emulador.
**Nunca ha llegado a correr**: `flutter test --platform chrome` no carga los
plugins de Firebase, y `flutter drive` con chromedriver se queda sin emitir nada.
El archivo lo avisa en su primera línea.

Lo que sí está verificado en producción es la subida de verdad, hecha a mano
desde el portal: el archivo aparece en `patrocinio/{uid}/{torneoId}/` con
`image/png` y su marca de tiempo.
