// Pruebas de las reglas de la Nube AVO (Cloud Storage) con el emulador (npm test).
// Usuarios = tarjetas NFC: correo <codigo>@avo-cards.app. Contrato: docs/NUBE_SESIONES.md
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes, getMetadata, listAll, deleteObject } from 'firebase/storage';

const A = 'AVO-AAAA-AAAA', B = 'AVO-BBBB-BBBB';
const SHA = 'c'.repeat(64);
const BYTES = new Uint8Array([0x50, 0x4b, 3, 4, 1, 2, 3]);
const META = { contentType: 'application/octet-stream', customMetadata: { sha256: SHA, sessionId: 'S0001', horseName: 'LEZAMA DREAMS' } };
let env;

const st = (code) => env.authenticatedContext('uid_' + code, { email: code.toLowerCase() + '@avo-cards.app' }).storage();
const path = (owner, name = 'AVO_S0001.avo') => `trainings/${owner}/${name}`;

before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-avo',
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 9199 } });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearStorage(); });

test('nube: sin sesión no se lee ni se escribe nada', async () => {
  const anon = env.unauthenticatedContext().storage();
  await assertFails(uploadBytes(ref(anon, path(A)), BYTES, META));
  await assertFails(listAll(ref(anon, `trainings/${A}`)));
});

test('nube: el dueño sube, lista, lee metadatos, descarga y borra', async () => {
  const s = st(A);
  await assertSucceeds(uploadBytes(ref(s, path(A)), BYTES, META));
  const l = await assertSucceeds(listAll(ref(s, `trainings/${A}`)));
  if (l.items.length !== 1) throw new Error('debería listar 1 entrenamiento');
  const m = await assertSucceeds(getMetadata(ref(s, path(A))));
  if (m.customMetadata.sha256 !== SHA) throw new Error('sha256 perdido');
  await assertSucceeds(getBytes(ref(s, path(A))));
  await assertSucceeds(uploadBytes(ref(s, path(A)), BYTES, META)); // reemplazar (reasignación)
  await assertSucceeds(deleteObject(ref(s, path(A))));
});

test('nube: otro usuario no puede leer, listar, sobrescribir ni borrar', async () => {
  await assertSucceeds(uploadBytes(ref(st(A), path(A)), BYTES, META));
  const b = st(B);
  await assertFails(getBytes(ref(b, path(A))));
  await assertFails(getMetadata(ref(b, path(A))));
  await assertFails(listAll(ref(b, `trainings/${A}`)));
  await assertFails(uploadBytes(ref(b, path(A)), BYTES, META));
  await assertFails(deleteObject(ref(b, path(A))));
  await assertFails(uploadBytes(ref(b, path(A, 'AVO_X.avo')), BYTES, META));
});

test('nube: solo .avo con sha256 y nombre seguro', async () => {
  const s = st(A);
  await assertFails(uploadBytes(ref(s, path(A, 'AVO_S0001.zip')), BYTES, META));
  await assertFails(uploadBytes(ref(s, path(A, 'sub/AVO_S0001.avo')), BYTES, META));
  await assertFails(uploadBytes(ref(s, path(A, 'AVO S0001.avo')), BYTES, META));
  await assertFails(uploadBytes(ref(s, path(A)), BYTES, { customMetadata: { sessionId: 'S0001' } }));
  await assertFails(uploadBytes(ref(s, path(A)), BYTES, { customMetadata: { sha256: 'xyz' } }));
});

test('nube: nada fuera de trainings/ y códigos de tarjeta válidos', async () => {
  const s = st(A);
  await assertFails(uploadBytes(ref(s, 'otros/AVO_S0001.avo'), BYTES, META));
  await assertFails(uploadBytes(ref(s, 'AVO_S0001.avo'), BYTES, META));
  const bad = env.authenticatedContext('uid_x', { email: 'avo-aaaa@avo-cards.app' }).storage();
  await assertFails(uploadBytes(ref(bad, path('AVO-AAAA')), BYTES, META));
});

test('nube PPK: el dueño sube y lee AVO_<id>.ppk.json; otros no; sin avo_sha256 o como no JSON se rechaza', async () => {
  const s = st(A);
  const J = new TextEncoder().encode('{"formato":"avo-ppk"}');
  const PM = { contentType: 'application/json', customMetadata: { sha256: SHA, avo_sha256: 'd'.repeat(64), sessionId: 'S0001' } };
  const p = path(A, 'AVO_S0001.ppk.json');
  await assertSucceeds(uploadBytes(ref(s, p), J, PM));
  await assertSucceeds(getBytes(ref(s, p)));
  await assertSucceeds(uploadBytes(ref(s, p), J, PM)); // recalculado
  await assertFails(getBytes(ref(st(B), p)));
  await assertFails(uploadBytes(ref(st(B), p), J, PM));
  await assertFails(uploadBytes(ref(s, p), J, { contentType: 'application/json', customMetadata: { sha256: SHA } }));
  await assertFails(uploadBytes(ref(s, p), J, { contentType: 'application/octet-stream', customMetadata: PM.customMetadata }));
  await assertFails(uploadBytes(ref(s, path(A, 'AVO_S0001.json')), J, PM));
});
