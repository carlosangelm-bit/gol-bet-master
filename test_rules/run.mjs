// ─────────────────────────────────────────────────────────────────────────────
// PRUEBAS DE LAS REGLAS DE FIRESTORE
//
// Se ejecutan contra el emulador, no contra producción:
//
//   firebase emulators:exec --only firestore "node test_rules/run.mjs"
//
// Existen porque probar reglas de seguridad es el caso donde "compila" no vale
// nada: una regla mal puesta no da un error, da datos de otras personas a quien
// no debía verlos. Es el único sitio de este proyecto donde un fallo sale de la
// app.
// ─────────────────────────────────────────────────────────────────────────────
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  doc, getDoc, setDoc, deleteDoc, collection, getDocs,
} from 'firebase/firestore';

const ORG = 'uid_organizador';
const INV = 'uid_invitado';
const OTRO = 'uid_otro';
const TOKEN = 'tok_abc123';

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
  projectId: 'golf-bet-master-rules-test',
  firestore: {
    rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    host: '127.0.0.1',
    port: 8080,
  },
});

// ── Datos de partida, escritos sin reglas ───────────────────────────────────
//
// withSecurityRulesDisabled es la forma de sembrar: si el montaje pasara por las
// reglas, un fallo de montaje se leería como un fallo de regla.
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'sharedTorneos', TOKEN), {
    ownerUid: ORG,
    nombre: 'Copa CGM 2026',
    publicadoEn: new Date().toISOString(),
    // La instantánea: solo lo del torneo.
    tabla: [{ nombre: 'RAFA', total: 42, puesto: 1 }],
  });
  // Y datos privados del organizador, para comprobar que NO se alcanzan.
  await setDoc(doc(db, 'users', ORG), { displayName: 'Carlos' });
  await setDoc(doc(db, 'users', ORG, 'roundResults', 'r1'),
      { balances: { rafa: 500 } });
  await setDoc(doc(db, 'users', ORG, 'torneos', 't1'), { nombre: 'Privado' });
  await setDoc(doc(db, 'users', ORG, 'rounds', 'ronda1'), { name: 'Sábado' });
  // El directorio público de email → uid, que es para lo que el permiso del
  // documento raíz decía existir.
  await setDoc(doc(db, 'userLookup', 'carlos@ejemplo.com'),
      { uid: ORG, email: 'carlos@ejemplo.com' });
});

const invitado = env.authenticatedContext(INV).firestore();
const organizador = env.authenticatedContext(ORG).firestore();
const anonimo = env.unauthenticatedContext().firestore();

console.log('\n1 · El invitado autenticado LEE el torneo compartido');
await prueba('lee sharedTorneos/{token}', () =>
    assertSucceeds(getDoc(doc(invitado, 'sharedTorneos', TOKEN))));
await prueba('y el contenido llega', async () => {
  const d = await getDoc(doc(invitado, 'sharedTorneos', TOKEN));
  if (d.data().nombre !== 'Copa CGM 2026') throw new Error('sin contenido');
});

console.log('\n2 · El invitado NO alcanza nada de users/{otroUid}');
await prueba('no lee el documento raíz del organizador', () =>
    assertFails(getDoc(doc(invitado, 'users', ORG))));
await prueba('no lee sus roundResults', () =>
    assertFails(getDoc(doc(invitado, 'users', ORG, 'roundResults', 'r1'))));
await prueba('no lista sus roundResults', () =>
    assertFails(getDocs(collection(invitado, 'users', ORG, 'roundResults'))));
await prueba('no lee sus torneos privados', () =>
    assertFails(getDoc(doc(invitado, 'users', ORG, 'torneos', 't1'))));
await prueba('no lee sus rondas', () =>
    assertFails(getDoc(doc(invitado, 'users', ORG, 'rounds', 'ronda1'))));
await prueba('no escribe en sus datos', () =>
    assertFails(setDoc(doc(invitado, 'users', ORG, 'torneos', 't1'),
        { nombre: 'hackeado' })));

console.log('\n3 · El invitado NO escribe en el torneo compartido');
await prueba('no actualiza la instantánea', () =>
    assertFails(setDoc(doc(invitado, 'sharedTorneos', TOKEN),
        { nombre: 'otro' }, { merge: true })));
await prueba('no la borra', () =>
    assertFails(deleteDoc(doc(invitado, 'sharedTorneos', TOKEN))));
await prueba('no publica a nombre del organizador', () =>
    assertFails(setDoc(doc(invitado, 'sharedTorneos', 'tok_falso'),
        { ownerUid: ORG, nombre: 'suplantado' })));
await prueba('ni se apropia de un token existente', () =>
    assertFails(setDoc(doc(invitado, 'sharedTorneos', TOKEN),
        { ownerUid: INV, nombre: 'mío ahora' })));

console.log('\n4 · Sin autenticar no se lee nada');
await prueba('no lee el torneo compartido', () =>
    assertFails(getDoc(doc(anonimo, 'sharedTorneos', TOKEN))));
await prueba('no lee users/**', () =>
    assertFails(getDoc(doc(anonimo, 'users', ORG))));

console.log('\n5 · El organizador sí manda sobre lo suyo');
await prueba('actualiza su instantánea', () =>
    assertSucceeds(setDoc(doc(organizador, 'sharedTorneos', TOKEN),
        { ownerUid: ORG, nombre: 'Copa CGM 2026', tabla: [] })));
await prueba('publica una nueva', () =>
    assertSucceeds(setDoc(doc(organizador, 'sharedTorneos', 'tok_nuevo'),
        { ownerUid: ORG, nombre: 'Otra' })));
await prueba('y no puede publicar a nombre de otro', () =>
    assertFails(setDoc(doc(organizador, 'sharedTorneos', 'tok_ajeno'),
        { ownerUid: OTRO, nombre: 'de otro' })));

console.log('\n6 · Borrar el documento deja el enlace inservible');
await prueba('el organizador borra', () =>
    assertSucceeds(deleteDoc(doc(organizador, 'sharedTorneos', TOKEN))));
await prueba('y el invitado ya no ve nada', async () => {
  const d = await getDoc(doc(invitado, 'sharedTorneos', TOKEN));
  if (d.exists()) throw new Error('el documento sigue ahí');
});

console.log('\n7 · El dueño sí lee lo suyo, y los flujos que existen siguen');
await prueba('el organizador lee su propio documento raíz', () =>
    assertSucceeds(getDoc(doc(organizador, 'users', ORG))));
await prueba('y sus propios roundResults', () =>
    assertSucceeds(getDoc(doc(organizador, 'users', ORG, 'roundResults', 'r1'))));
await prueba('el correo de otro NO se alcanza por el doc raíz', async () => {
  // La comprobación concreta de lo que estaba expuesto: apodo, correo, moneda.
  await assertFails(getDoc(doc(invitado, 'users', ORG)));
});
await prueba('pero userLookup sigue resolviendo email → uid', () =>
    assertSucceeds(getDoc(doc(invitado, 'userLookup', 'carlos@ejemplo.com'))));

console.log('\n8 · El acceso cruzado que la app SÍ necesita sigue vivo');
// Es el único: al publicar una ronda en vivo, el organizador escribe una
// referencia en users/{invitado}/liveRoundRefs. Tiene su propia regla y cerrar
// el documento raíz no debía tocarla — esto lo comprueba en vez de suponerlo.
await env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), 'liveRounds', 'ronda_viva'),
      { ownerUid: ORG, participantUids: [ORG, INV] });
});
await prueba('el organizador escribe la referencia al invitado', () =>
    assertSucceeds(setDoc(
        doc(organizador, 'users', INV, 'liveRoundRefs', 'ronda_viva'),
        { roundId: 'ronda_viva', status: 'pending' })));
await prueba('y un tercero NO puede', () =>
    assertFails(setDoc(
        doc(env.authenticatedContext(OTRO).firestore(),
            'users', INV, 'liveRoundRefs', 'ronda_viva'),
        { roundId: 'ronda_viva', status: 'pending' })));

console.log('\n9 · Nada de subcolecciones no revisadas');
await prueba('el invitado no escribe en una subcolección del compartido', () =>
    assertFails(setDoc(
        doc(invitado, 'sharedTorneos', 'tok_nuevo', 'lo_que_sea', 'x'),
        { a: 1 })));

await env.cleanup();

console.log(`\n${pasados} pruebas ok, ${fallos} fallos`);
process.exit(fallos === 0 ? 0 : 1);
