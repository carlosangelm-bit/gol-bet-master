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
  doc, getDoc, setDoc, deleteDoc, collection, getDocs, query, where,
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
// Un tercero con cuenta: no es el organizador ni juega en su torneo. Es quien
// tiene que quedarse fuera de todo.
const otro = env.authenticatedContext(OTRO).firestore();

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
// La republicación al cerrar ronda pasa por aquí: es un update, no un create.
// Se prueba con el DOCUMENTO ENTERO, que es lo que escribe publicarTorneo(),
// y aparte el caso del acompañante —autenticado, en la ronda, pero no dueño del
// torneo—, que es quien podría intentarlo sin querer al cerrar.
await prueba('republica al cerrar la ronda (update completo del dueño)', () =>
    assertSucceeds(setDoc(doc(organizador, 'sharedTorneos', TOKEN),
        { ownerUid: ORG, nombre: 'Copa CGM 2026', publicadoEn: '2026-08-22',
          tabla: [{ puesto: 1, nombre: 'ANA', total: 12 }] })));
await prueba('el acompañante no republica el torneo del organizador', () =>
    assertFails(setDoc(doc(invitado, 'sharedTorneos', TOKEN),
        { ownerUid: ORG, nombre: 'Copa CGM 2026', publicadoEn: '2026-08-22' })));
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

// ══════════════════════════════════════════════════════════════════════════════
// 10 · EL INVITADO QUE JUEGA — la parte con consecuencias fuera de la app
// ══════════════════════════════════════════════════════════════════════════════
//
// Hasta ahora el invitado solo LEÍA una instantánea autocontenida, y por eso la
// seguridad se cumplía por construcción. Dejarle jugar su partido parecía romper
// esa propiedad.
//
// NO LA ROMPE, y esa es la conclusión que estas pruebas fijan: el invitado que se
// hace cuenta NO escribe en el torneo ni en los datos del organizador. Escribe en
// la RONDA EN VIVO, que es un camino que ya existía con sus propias reglas —estar
// en participantUids— y que no mira a users/** ni a sharedTorneos.
//
// Así que no hubo que añadir NINGUNA regla condicional sobre users/**. Lo que se
// prueba aquí es que eso es verdad: que puede escribir donde juega, que no puede
// escribir donde no, y que el torneo sigue siendo de solo lectura para él.
console.log('\n10 · El invitado que se hace cuenta y juega su partido');

// Las dos rondas, sembradas sin reglas: un fallo de montaje se leería como un
// fallo de regla.
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  // La ronda del partido, con el invitado dentro.
  await setDoc(doc(db, 'liveRounds', 'ronda_partido'), {
    ownerUid: ORG,
    participantUids: [ORG, INV],
    name: 'Semifinal',
  });
  // Y otra en la que el invitado NO juega.
  await setDoc(doc(db, 'liveRounds', 'ronda_ajena'), {
    ownerUid: ORG,
    participantUids: [ORG, OTRO],
    name: 'La otra semifinal',
  });
});

await prueba('escribe scores en LA RONDA DE SU PARTIDO', () =>
    assertSucceeds(setDoc(doc(invitado, 'liveRounds', 'ronda_partido'),
        { scores: { [INV]: { 1: 4 } } }, { merge: true })));
await prueba('y la lee', () =>
    assertSucceeds(getDoc(doc(invitado, 'liveRounds', 'ronda_partido'))));
await prueba('pero NO escribe en una ronda donde no juega', () =>
    assertFails(setDoc(doc(invitado, 'liveRounds', 'ronda_ajena'),
        { scores: { [INV]: { 1: 2 } } }, { merge: true })));
await prueba('ni la lee', () =>
    assertFails(getDoc(doc(invitado, 'liveRounds', 'ronda_ajena'))));
await prueba('ni se mete en la lista de participantes de la ajena', () =>
    assertFails(setDoc(doc(invitado, 'liveRounds', 'ronda_ajena'),
        { participantUids: [ORG, OTRO, INV] }, { merge: true })));
await prueba('ni borra la ronda de su propio partido: no es el dueño', () =>
    assertFails(deleteDoc(doc(invitado, 'liveRounds', 'ronda_partido'))));

// Y lo que esto tenía que preservar: el torneo sigue siendo de solo lectura.
await prueba('jugar NO le da escritura sobre el torneo compartido', () =>
    assertFails(setDoc(doc(invitado, 'sharedTorneos', TOKEN),
        { nombre: 'mío' }, { merge: true })));
await prueba('ni sobre las rondas del organizador', () =>
    assertFails(setDoc(doc(invitado, 'users', ORG, 'rounds', 'r1'),
        { scores: {} }, { merge: true })));
await prueba('ni sobre su historial de resultados', () =>
    assertFails(setDoc(doc(invitado, 'users', ORG, 'roundResults', 'r1'),
        { balances: {} }, { merge: true })));

console.log('\n11 · Apagar el enlace no lo abre a nadie más');
await prueba('el organizador apaga: deja el documento en la bandera', () =>
    assertSucceeds(setDoc(doc(organizador, 'sharedTorneos', TOKEN),
        { ownerUid: ORG, activo: false })));
await prueba('el invitado lo lee y ve que está apagado', () =>
    assertSucceeds(getDoc(doc(invitado, 'sharedTorneos', TOKEN))));
await prueba('pero no puede encenderlo', () =>
    assertFails(setDoc(doc(invitado, 'sharedTorneos', TOKEN),
        { ownerUid: ORG, activo: true }, { merge: true })));
await prueba('y el organizador lo enciende otra vez en el MISMO token', () =>
    assertSucceeds(setDoc(doc(organizador, 'sharedTorneos', TOKEN),
        { ownerUid: ORG, nombre: 'Copa CGM 2026', tabla: [] })));

// ══════════════════════════════════════════════════════════════════════════════
// 12 · LA AGREGACIÓN DEL TORNEO — dónde entran los resultados, y quién puede
// ══════════════════════════════════════════════════════════════════════════════
//
// La tabla de un torneo sale de users/{organizador}/roundResults. El resultado de
// una ronda se escribe al CERRARLA, en la colección de quien cierra. Así que la
// agregación depende de UNA cosa: que cerrar esté reservado al dueño de la ronda.
//
// Eso es lo que estas pruebas fijan. No hay colección nueva ni regla nueva: se
// probó una —torneoResultados, con verificación de procedencia— y se descartó al
// ver que el camino existente ya da la garantía, sin que nadie escriba bajo
// users/** de otro.
//
// Si alguna de estas cuatro pruebas se pusiera roja, la tabla del torneo podría
// estar contando rondas que el organizador no cerró, o dejando de contar las que
// sí. Es el punto donde un fallo sale de la app.
console.log('\n12 · La agregación: solo el dueño cierra, y por eso la tabla cuadra');

await prueba('el organizador escribe el RESULTADO en su propia colección', () =>
    assertSucceeds(setDoc(doc(organizador, 'users', ORG, 'roundResults', 'ronda_partido'),
        { roundId: 'ronda_partido', balances: { [ORG]: 100 } })));
await prueba('y la ronda cerrada en su historial', () =>
    assertSucceeds(setDoc(doc(organizador, 'users', ORG, 'rounds', 'ronda_partido'),
        { isFinished: true })));

// El que ANOTA es participante de la ronda en vivo: escribe scores —ya probado en
// el bloque 10— pero NO puede publicar el resultado. Si pudiera, la tabla del
// organizador tendría filas que él no cerró.
await prueba('el que anota NO escribe el resultado en la colección del organizador', () =>
    assertFails(setDoc(doc(invitado, 'users', ORG, 'roundResults', 'ronda_partido'),
        { roundId: 'ronda_partido', balances: { [INV]: 999 } })));
await prueba('ni marca la ronda como cerrada en el historial del organizador', () =>
    assertFails(setDoc(doc(invitado, 'users', ORG, 'rounds', 'ronda_partido'),
        { isFinished: true })));

// Y al revés: el resultado que el jugador guarda en SU historial es suyo y no
// contamina el torneo de nadie. Es lo que hace que la agregación sea del
// organizador y no una suma de lo que cada uno diga.
await prueba('el jugador sí escribe en SU propio historial', () =>
    assertSucceeds(setDoc(doc(invitado, 'users', INV, 'roundResults', 'ronda_partido'),
        { roundId: 'ronda_partido', balances: { [INV]: -100 } })));
await prueba('y el organizador NO lo lee: no es suyo', () =>
    assertFails(getDoc(doc(organizador, 'users', INV, 'roundResults', 'ronda_partido'))));

// Las refs por las que el organizador LISTA los grupos de su torneo.
await prueba('el organizador lista sus propias liveRoundRefs', () =>
    assertSucceeds(getDocs(collection(organizador, 'users', ORG, 'liveRoundRefs'))));
await prueba('y nadie más lista las suyas', () =>
    assertFails(getDocs(collection(invitado, 'users', ORG, 'liveRoundRefs'))));

// Cerrar la ronda en vivo: marcar isFinished en liveRounds. Lo puede hacer un
// participante —la regla de update es de participantes— así que la garantía NO
// está ahí: está en que el RESULTADO solo lo escribe el dueño. Se prueba para que
// quede dicho dónde está y dónde no.
await prueba('un participante SÍ puede marcar la ronda en vivo como terminada', () =>
    assertSucceeds(setDoc(doc(invitado, 'liveRounds', 'ronda_partido'),
        { isFinished: true }, { merge: true })));
await prueba('pero eso NO mete nada en la tabla del organizador', () =>
    assertFails(setDoc(doc(invitado, 'users', ORG, 'roundResults', 'otra'),
        { roundId: 'otra' })));

// ══════════════════════════════════════════════════════════════════════════════
// 13 · RESULTADOS PUBLICADOS A UN TORNEO AJENO — la liga de temporada
// ══════════════════════════════════════════════════════════════════════════════
//
// El shotgun no necesita esto: allí el organizador es dueño de las rondas. La liga
// sí, porque cada jugador cierra la suya y su resultado cae en SU colección.
//
// Lo que la regla garantiza, y lo que NO:
//
//   SÍ · que nadie publique firmando por otro
//   SÍ · que el organizador declarado sea el de verdad —se compara contra
//        sharedTorneos/{token}.ownerUid, que solo escribe su dueño—
//   SÍ · que el id sea {torneoId}_{roundId}, así que corregir ACTUALIZA
//   SÍ · que solo el organizador y el autor lo lean
//   NO · que quien publica haya jugado esa ronda. Eso no se puede saber desde
//        aquí, y se cierra en la lectura: la tabla solo cuenta resultados de
//        gente inscrita. Está probado en Dart —resultadosQueCuentan— y dicho en
//        los dos sitios.
// ══════════════════════════════════════════════════════════════════════════════
// 14 · EL LEADERBOARD PROYECTABLE — el único documento sin sesión
// ══════════════════════════════════════════════════════════════════════════════
//
// Se proyecta en la casa club desde un navegador cualquiera, sin cuenta. Así que
// es la superficie MÁS EXPUESTA del sistema, y por eso no lleva un solo importe:
// la garantía es que el dato no esté, no que no se muestre.
//
// Lo que se prueba aquí es el permiso. Que el CONTENIDO no lleve dinero lo fija
// el test de lista cerrada en Dart, y las dos mitades hacen falta: la regla deja
// leer a cualquiera, así que lo único que protege el dinero es que no se escriba.
console.log('\n14 · Leaderboard proyectable');

const LB = 'tor_leaderboard';

await prueba('el organizador publica su leaderboard', () =>
    assertSucceeds(setDoc(doc(organizador, 'leaderboards', LB), {
      ownerUid: ORG,
      nombre: 'Copa de Primavera',
      tabla: [{ puesto: 1, nombre: 'Luis Herrera', jugadas: 3 }],
    })));

await prueba('y la TELE lo lee SIN SESIÓN', () =>
    assertSucceeds(getDoc(doc(anonimo, 'leaderboards', LB))));

await prueba('lectura pública NO es escritura pública', () =>
    assertFails(setDoc(doc(anonimo, 'leaderboards', LB), {
      ownerUid: ORG, nombre: 'Secuestrado',
    })));

await prueba('ni siquiera con cuenta: solo el dueño actualiza', () =>
    assertFails(setDoc(doc(otro, 'leaderboards', LB), {
      ownerUid: OTRO, nombre: 'Mío ahora',
    })));

await prueba('nadie puede apropiarse del token publicando a su nombre', () =>
    assertFails(setDoc(doc(otro, 'leaderboards', 'tor_libre'), {
      ownerUid: ORG, nombre: 'Firmando por otro',
    })));

await prueba('el dueño lo apaga', () =>
    assertSucceeds(setDoc(doc(organizador, 'leaderboards', LB), {
      ownerUid: ORG, activo: false,
    })));

await prueba('y un tercero NO lo borra', () =>
    assertFails(deleteDoc(doc(otro, 'leaderboards', LB))));

// EL CONTRAPESO, y es el que da sentido a todo lo anterior: la instantánea CON
// dinero sigue exigiendo cuenta. Si esta prueba dejara de fallar, el leaderboard
// público habría dejado de ser necesario — y el dinero estaría al alcance de
// cualquiera.
await prueba('la instantánea CON dinero sigue pidiendo sesión', () =>
    assertFails(getDoc(doc(anonimo, 'sharedTorneos', TOKEN))));

await prueba('y sin sesión tampoco se leen las rondas de nadie', () =>
    assertFails(getDoc(doc(anonimo, 'liveRounds', 'ronda_x'))));

console.log('\n13 · Publicar un resultado a un torneo ajeno');

const DOC_OK = `tor_liga_${'ronda_luis'}`;

await prueba('el jugador publica su resultado al torneo del organizador', () =>
    assertSucceeds(setDoc(doc(invitado, 'torneoResultados', DOC_OK), {
      torneoId: 'tor_liga',
      roundId: 'ronda_luis',
      token: TOKEN,
      torneoOwnerUid: ORG,
      escritoPor: INV,
      resultado: { roundId: 'ronda_luis', balances: { [INV]: 100 } },
    })));

// El campo que dice CUÁL de los jugadores de la ronda es el autor. Va en este
// documento —que solo leen el organizador y el autor— y no en la instantánea
// pública, que sigue sin ids de jugador.
//
// Y no hizo falta tocar la regla: el bloque exige unos campos concretos, no una
// lista cerrada. Esto lo comprueba en vez de darlo por bueno.
await prueba('y el jugadorId entra sin regla nueva', () =>
    assertSucceeds(setDoc(doc(invitado, 'torneoResultados', DOC_OK), {
      torneoId: 'tor_liga',
      roundId: 'ronda_luis',
      token: TOKEN,
      torneoOwnerUid: ORG,
      escritoPor: INV,
      jugadorNombre: 'Luis Herrera',
      jugadorId: 'mio_luis',
      resultado: { roundId: 'ronda_luis', balances: { mio_luis: 100 } },
    })));

await prueba('pero el jugadorId no sirve para firmar por otro', () =>
    assertFails(setDoc(doc(otro, 'torneoResultados', `tor_liga_colado`), {
      torneoId: 'tor_liga',
      roundId: 'colado',
      token: TOKEN,
      torneoOwnerUid: ORG,
      escritoPor: INV,
      jugadorId: 'mio_luis',
      resultado: { roundId: 'colado' },
    })));

await prueba('y el organizador lo lee: es de su torneo', () =>
    assertSucceeds(getDoc(doc(organizador, 'torneoResultados', DOC_OK))));
await prueba('y el autor también, para poder corregirlo', () =>
    assertSucceeds(getDoc(doc(invitado, 'torneoResultados', DOC_OK))));
await prueba('pero un tercero NO lo lee', () =>
    assertFails(getDoc(doc(otro, 'torneoResultados', DOC_OK))));

// ── LA CONSULTA, no el documento ────────────────────────────────────────────
//
// Esto faltaba, y es la diferencia que importa: la app no lee el documento por
// su id, hace una CONSULTA con dos filtros. Una regla puede dejar pasar un getDoc
// y tumbar la consulta —basta con que un documento del resultado no cumpla— y el
// síntoma sería una tabla en cero sin ningún error a la vista, porque la lectura
// se traga la excepción.
//
// Es exactamente la forma de fallo que llevamos tres eslabones persiguiendo: el
// dato existe y la capa siguiente no lo lee. Probar el getDoc y no la consulta es
// probar otra cosa.
await prueba('el organizador CONSULTA los resultados de su torneo', () =>
    assertSucceeds(getDocs(query(
        collection(organizador, 'torneoResultados'),
        where('torneoOwnerUid', '==', ORG),
        where('torneoId', '==', 'tor_liga')))));

await prueba('y la consulta devuelve el documento que se publicó', async () => {
  const snap = await getDocs(query(
      collection(organizador, 'torneoResultados'),
      where('torneoOwnerUid', '==', ORG),
      where('torneoId', '==', 'tor_liga')));
  if (snap.empty) throw new Error('la consulta no devolvió nada');
  const hay = snap.docs.some((d) => d.id === DOC_OK);
  if (!hay) throw new Error(`no está ${DOC_OK} entre los devueltos`);
});

await prueba('sin el filtro por dueño la consulta se cae, y eso está bien', () =>
    assertFails(getDocs(query(
        collection(organizador, 'torneoResultados'),
        where('torneoId', '==', 'tor_liga')))));

await prueba('volver a cerrar la ronda ACTUALIZA, no duplica', () =>
    assertSucceeds(setDoc(doc(invitado, 'torneoResultados', DOC_OK), {
      torneoId: 'tor_liga',
      roundId: 'ronda_luis',
      token: TOKEN,
      torneoOwnerUid: ORG,
      escritoPor: INV,
      resultado: { roundId: 'ronda_luis', balances: { [INV]: 250 } },
    })));

await prueba('NO se puede firmar por otro', () =>
    assertFails(setDoc(doc(invitado, 'torneoResultados', 'tor_liga_falso'), {
      torneoId: 'tor_liga',
      roundId: 'falso',
      token: TOKEN,
      torneoOwnerUid: ORG,
      escritoPor: OTRO,
      resultado: {},
    })));

await prueba('NI declarar un organizador que no es el del enlace', () =>
    assertFails(setDoc(doc(invitado, 'torneoResultados', 'tor_liga_inv2'), {
      torneoId: 'tor_liga',
      roundId: 'inv2',
      token: TOKEN,
      torneoOwnerUid: OTRO,
      escritoPor: INV,
      resultado: {},
    })));

await prueba('ni con un token que no existe', () =>
    assertFails(setDoc(doc(invitado, 'torneoResultados', 'tor_liga_inv3'), {
      torneoId: 'tor_liga',
      roundId: 'inv3',
      token: 'tok_inventado',
      torneoOwnerUid: INV,
      escritoPor: INV,
      resultado: {},
    })));

await prueba('ni con el id del documento cambiado', () =>
    assertFails(setDoc(doc(invitado, 'torneoResultados', 'cualquier_cosa'), {
      torneoId: 'tor_liga',
      roundId: 'ronda_luis',
      token: TOKEN,
      torneoOwnerUid: ORG,
      escritoPor: INV,
      resultado: {},
    })));

await prueba('un tercero no borra el resultado de otro', () =>
    assertFails(deleteDoc(doc(otro, 'torneoResultados', DOC_OK))));
await prueba('pero el organizador sí: responde de su tabla', () =>
    assertSucceeds(deleteDoc(doc(organizador, 'torneoResultados', DOC_OK))));

// Y lo que esto NO abre: publicar no da acceso a nada del organizador.
await prueba('publicar no da lectura de users/{organizador}', () =>
    assertFails(getDoc(doc(invitado, 'users', ORG))));
await prueba('ni de sus roundResults', () =>
    assertFails(getDocs(collection(invitado, 'users', ORG, 'roundResults'))));

console.log('\n9 · Nada de subcolecciones no revisadas');
await prueba('el invitado no escribe en una subcolección del compartido', () =>
    assertFails(setDoc(
        doc(invitado, 'sharedTorneos', 'tok_nuevo', 'lo_que_sea', 'x'),
        { a: 1 })));

await env.cleanup();

console.log(`\n${pasados} pruebas ok, ${fallos} fallos`);
process.exit(fallos === 0 ? 0 : 1);
