// ─────────────────────────────────────────────────────────────────────────────
// PRUEBAS DE LAS REGLAS DE STORAGE
//
//   firebase emulators:exec --only storage "node test_rules/storage.mjs"
//
// Existen por lo mismo que las de Firestore: una regla mal puesta no da un
// error, da archivos de otras personas a quien no debía verlos.
//
// Y hay una razón añadida para mirar esto con lupa. En este proyecto, `allow
// read` ha concedido un `list` que nadie usaba TRES veces —sharedTorneos, con
// dinero; players; y userLookup, con el correo de todos los registrados—.
// Storage tiene la misma trampa con otra forma: `read` son `get` y `list`, y un
// `listAll` sobre el prefijo devolvería los archivos de todos los torneos de
// todos los organizadores, y de paso todos los ownerUid.
//
// Por eso la primera prueba de este archivo es la del listado.
// ─────────────────────────────────────────────────────────────────────────────
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  ref, uploadBytes, getBytes, deleteObject, listAll,
} from 'firebase/storage';

const ORG = 'uid_organizador';
const OTRO = 'uid_otro';
const TORNEO = 'tor_abc123';

let fallos = 0;
let pasados = 0;

async function prueba(nombre, fn) {
  try {
    await fn();
    pasados++;
    console.log(`  ok   ${nombre}`);
  } catch (e) {
    fallos++;
    console.log(`  FALLA ${nombre}`);
    console.log(`        ${String(e).split('\n')[0]}`);
  }
}

const env = await initializeTestEnvironment({
  projectId: 'golf-bet-master',
  storage: {
    rules: readFileSync('storage.rules', 'utf8'),
    host: '127.0.0.1',
    port: 9199,
  },
});

/// Un PNG mínimo de verdad. El emulador mira el contentType declarado, pero un
/// archivo real deja la prueba más cerca de lo que pasa al subir.
const PNG = new Uint8Array([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
]);
const imagen = { contentType: 'image/png' };

const ruta = (uid = ORG, torneo = TORNEO, archivo = 'cabecera.png') =>
  `patrocinio/${uid}/${torneo}/${archivo}`;

// Se siembra sin reglas, igual que en Firestore: si el montaje pasara por las
// reglas, un fallo de montaje se leería como un fallo de regla.
await env.withSecurityRulesDisabled(async (ctx) => {
  const s = ctx.storage();
  await uploadBytes(ref(s, ruta()), PNG, imagen);
  await uploadBytes(ref(s, ruta(ORG, TORNEO, 'pie1.png')), PNG, imagen);
  await uploadBytes(ref(s, ruta(OTRO, 'tor_vecino', 'suyo.png')), PNG, imagen);
});

const organizador = env.authenticatedContext(ORG).storage();
const otro = env.authenticatedContext(OTRO).storage();
const anonimo = env.unauthenticatedContext().storage();

console.log('\n1 · GET NO ES LIST — la prueba que este proyecto ya necesitó tres veces');
await prueba('CLAVE: nadie recorre el prefijo de un torneo, ni su dueño', () =>
    assertFails(listAll(ref(organizador, `patrocinio/${ORG}/${TORNEO}`))));
await prueba('ni el de un organizador entero', () =>
    assertFails(listAll(ref(organizador, `patrocinio/${ORG}`))));
await prueba('ni la raíz, que además daría todos los ownerUid', () =>
    assertFails(listAll(ref(anonimo, 'patrocinio'))));
await prueba('y un tercero con cuenta tampoco', () =>
    assertFails(listAll(ref(otro, `patrocinio/${ORG}/${TORNEO}`))));

console.log('\n2 · La imagen se lee SIN SESIÓN — la tele no tiene cuenta');
await prueba('CRITERIO 2: el anónimo trae el archivo por su ruta', () =>
    assertSucceeds(getBytes(ref(anonimo, ruta()))));
await prueba('y un tercero con cuenta también: la URL es la que manda', () =>
    assertSucceeds(getBytes(ref(otro, ruta()))));

console.log('\n3 · Escribir es solo del dueño');
await prueba('CRITERIO 1: el organizador sube en su espacio', () =>
    assertSucceeds(
        uploadBytes(ref(organizador, ruta(ORG, TORNEO, 'nueva.png')), PNG, imagen)));
await prueba('CRITERIO 3: un tercero NO escribe en el espacio del organizador', () =>
    assertFails(
        uploadBytes(ref(otro, ruta(ORG, TORNEO, 'colada.png')), PNG, imagen)));
await prueba('ni sobrescribe un archivo que ya está', () =>
    assertFails(uploadBytes(ref(otro, ruta()), PNG, imagen)));
await prueba('ni el anónimo, que sí puede leer', () =>
    assertFails(
        uploadBytes(ref(anonimo, ruta(ORG, TORNEO, 'anon.png')), PNG, imagen)));
await prueba('y el organizador tampoco escribe en el espacio de otro', () =>
    assertFails(
        uploadBytes(ref(organizador, ruta(OTRO, 'tor_vecino', 'x.png')), PNG, imagen)));

console.log('\n4 · Solo imágenes, y de tamaño razonable');
await prueba('un ejecutable disfrazado de logo no entra', () =>
    assertFails(uploadBytes(ref(organizador, ruta(ORG, TORNEO, 'malo.png')), PNG,
        { contentType: 'application/x-msdownload' })));
await prueba('ni un PDF, aunque sea inofensivo', () =>
    assertFails(uploadBytes(ref(organizador, ruta(ORG, TORNEO, 'folleto.pdf')),
        PNG, { contentType: 'application/pdf' })));
await prueba('CONTRAPESO: un SVG y un JPEG sí, que son formatos del manual', async () => {
  await assertSucceeds(uploadBytes(ref(organizador, ruta(ORG, TORNEO, 'l.svg')),
      PNG, { contentType: 'image/svg+xml' }));
  await assertSucceeds(uploadBytes(ref(organizador, ruta(ORG, TORNEO, 'l.jpg')),
      PNG, { contentType: 'image/jpeg' }));
});
await prueba('un archivo de más de 5 MB no entra', () =>
    assertFails(uploadBytes(ref(organizador, ruta(ORG, TORNEO, 'enorme.png')),
        new Uint8Array(6 * 1024 * 1024), imagen)));

console.log('\n5 · Borrar es del dueño, y es explícito');
await prueba('CRITERIO 4: el organizador borra lo suyo', () =>
    assertSucceeds(deleteObject(ref(organizador, ruta(ORG, TORNEO, 'nueva.png')))));
await prueba('un tercero no borra el logo de otro', () =>
    assertFails(deleteObject(ref(otro, ruta()))));
await prueba('ni el anónimo', () =>
    assertFails(deleteObject(ref(anonimo, ruta()))));

console.log('\n6 · Fuera del espacio de patrocinio, nada');
await prueba('no se puede subir a la raíz del bucket', () =>
    assertFails(uploadBytes(ref(organizador, 'suelto.png'), PNG, imagen)));
await prueba('ni a una carpeta inventada', () =>
    assertFails(uploadBytes(ref(organizador, 'otracosa/x.png'), PNG, imagen)));
await prueba('ni un nivel de más dentro de patrocinio', () =>
    // La regla acota la profundidad a propósito: {archivo}, no {todo=**}. Una
    // subcarpeta sin revisar es por donde entra lo que nadie miró.
    assertFails(uploadBytes(
        ref(organizador, `patrocinio/${ORG}/${TORNEO}/sub/x.png`), PNG, imagen)));

await env.cleanup();
console.log(`\n${pasados} pruebas ok, ${fallos} fallos`);
process.exit(fallos === 0 ? 0 : 1);
