// Tests of the AVO Realtime Database rules with the Firebase emulator (npm test).
// Users = NFC cards: email <code>@avo-cards.app.
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, set, get, update, remove } from 'firebase/database';

const A = 'AVO-AAAA-AAAA', B = 'AVO-BBBB-BBBB', C = 'AVO-CCCC-CCCC';
const TID = 'a'.repeat(32);
const SHA = 'b'.repeat(64);
let env;

const db = (code) => env.authenticatedContext('uid_' + code, { email: code.toLowerCase() + '@avo-cards.app' }).database();
const meta = (owner = A) => ({ owner, ownerName: 'Propietario', sessionId: 'S0001', horseName: 'LEZAMA DREAMS', riderName: 'Ana',
  size: 1000, sha256: SHA, chunks: 1, chunkSize: 262144, createdMs: Date.now(), expiresMs: Date.now() + 86400000 });
const notice = (from = A) => ({ from, fromName: 'Propietario', sessionId: 'S0001', horseName: 'LEZAMA DREAMS', size: 1000, createdMs: Date.now() });

async function seed(fn) { await env.withSecurityRulesDisabled(async (ctx) => fn(ctx.database())); }
async function users() {
  for (const c of [A, B, C]) await assertSucceeds(set(ref(db(c), 'users/' + c), { name: 'U ' + c, uid: 'uid_' + c }));
}
async function grant(recipient, sender, state) {
  await seed(async (d) => set(ref(d, `grants/${recipient}/${sender}`), { state, senderName: 'x', ms: 1 }));
}
async function uploaded(to = B) {
  await seed(async (d) => set(ref(d, 'blobs/' + TID), { meta: meta(), c: { 0: 'QUJD' }, complete: true, to: { [to]: true } }));
}

before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-avo',
    database: { rules: readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8'), host: '127.0.0.1', port: 9000 } });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearDatabase(); });

test('nothing without authentication', async () => {
  const anon = env.unauthenticatedContext().database();
  await assertFails(get(ref(anon, 'users')));
  await assertFails(set(ref(anon, 'users/' + A), { name: 'x', uid: 'y' }));
  await assertFails(get(ref(db(A), '/')));
});

test('registration: each card only writes its own profile, with its own uid', async () => {
  await assertSucceeds(set(ref(db(A), 'users/' + A), { name: 'Ana', uid: 'uid_' + A }));
  await assertFails(set(ref(db(B), 'users/' + A), { name: 'Hacker', uid: 'uid_' + B }));
  await assertFails(set(ref(db(A), 'users/' + A), { name: 'Ana', uid: 'otro' }));
  await assertFails(set(ref(db(A), 'users/' + A), { name: 'Ana', uid: 'uid_' + A, telefono: '600' }));
  await assertSucceeds(get(ref(db(B), 'users')));
});

test('invitations: sender creates PENDING, only recipient accepts/rejects/blocks', async () => {
  await users();
  await assertFails(set(ref(db(A), `grants/${B}/${A}`), { state: 'ACCEPTED', senderName: 'A', ms: 1 }));
  await assertSucceeds(set(ref(db(A), `grants/${B}/${A}`), { state: 'PENDING', senderName: 'A', ms: 1 }));
  await assertFails(set(ref(db(C), `grants/${B}/${A}`), { state: 'PENDING', senderName: 'A', ms: 1 }));
  await assertFails(update(ref(db(A), `grants/${B}/${A}`), { state: 'ACCEPTED' }));
  await assertFails(get(ref(db(C), `grants/${B}`)));
  await assertSucceeds(get(ref(db(B), `grants/${B}`)));
  await assertSucceeds(get(ref(db(A), `grants/${B}/${A}`)));
  await assertSucceeds(update(ref(db(B), `grants/${B}/${A}`), { state: 'ACCEPTED' }));
  await assertSucceeds(update(ref(db(B), `grants/${B}/${A}`), { state: 'BLOCKED' }));
  // the sender cannot re-invite over a block
  await assertFails(set(ref(db(A), `grants/${B}/${A}`), { state: 'PENDING', senderName: 'A', ms: 2 }));
  await assertFails(remove(ref(db(A), `grants/${B}/${A}`)));   // nor delete the block in order to re-invite
  await assertSucceeds(remove(ref(db(B), `grants/${B}/${A}`))); // the recipient can lift it
  // the sender can remove a recipient from its list
  await grant(C, A, 'ACCEPTED');
  await assertSucceeds(remove(ref(db(A), `grants/${C}/${A}`)));
});

test('content: only the owner uploads, with a valid structure and size', async () => {
  await users();
  await assertSucceeds(set(ref(db(A), `blobs/${TID}/meta`), meta()));
  await assertFails(set(ref(db(B), `blobs/${TID}/c/0`), 'QUJD'));
  await assertSucceeds(set(ref(db(A), `blobs/${TID}/c/0`), 'QUJD'));
  await assertSucceeds(set(ref(db(A), `blobs/${TID}/n`), 1));
  await assertFails(set(ref(db(B), `blobs/${TID}/n`), 0));
  await assertFails(set(ref(db(A), `blobs/${TID}/c/0`), 'x'.repeat(360001)));
  await assertFails(set(ref(db(A), `blobs/${'c'.repeat(32)}/meta`), { ...meta(), size: 31457281 }));
  await assertFails(set(ref(db(A), `blobs/${'c'.repeat(32)}/meta`), meta(B)));         // impersonating another owner
  await assertFails(set(ref(db(B), `blobs/${TID}/meta`), meta(B)));                     // taking over someone else's
  await assertFails(update(ref(db(A), `blobs/${TID}/meta`), { sha256: 'c'.repeat(64) })); // changing content
  await assertSucceeds(set(ref(db(A), `blobs/${TID}/complete`), true));
});

test('complete only if the last chunk exists', async () => {
  await users();
  await assertSucceeds(set(ref(db(A), `blobs/${TID}/meta`), { ...meta(), chunks: 2 }));
  await assertSucceeds(set(ref(db(A), `blobs/${TID}/c/0`), 'QUJD'));
  await assertFails(set(ref(db(A), `blobs/${TID}/complete`), true));
  await assertSucceeds(set(ref(db(A), `blobs/${TID}/c/1`), 'QUJD'));
  await assertSucceeds(set(ref(db(A), `blobs/${TID}/complete`), true));
});

test('read permission: only the owner can add accepted recipients', async () => {
  await users();
  await assertSucceeds(set(ref(db(A), `blobs/${TID}/meta`), meta()));
  await assertFails(set(ref(db(A), `blobs/${TID}/to/${B}`), true)); // B has not accepted
  await grant(B, A, 'ACCEPTED');
  await assertSucceeds(set(ref(db(A), `blobs/${TID}/to/${B}`), true));
});

test('blocks: only an authorized recipient reads; revocation and blocking cut access', async () => {
  await users(); await grant(B, A, 'ACCEPTED'); await grant(C, A, 'ACCEPTED'); await uploaded(B);
  await assertSucceeds(get(ref(db(B), `blobs/${TID}/c/0`)));
  await assertSucceeds(get(ref(db(B), `blobs/${TID}/meta`)));
  await assertFails(get(ref(db(C), `blobs/${TID}/c/0`)));      // accepted but not a recipient of this content
  await assertFails(get(ref(db(B), `blobs/${TID}`)));          // cannot list the whole node
  await assertFails(set(ref(db(B), `blobs/${TID}/to/${C}`), true));
  await assertSucceeds(remove(ref(db(A), `blobs/${TID}/to/${B}`))); // revocation
  await assertFails(get(ref(db(B), `blobs/${TID}/c/0`)));
  await seed(async (d) => set(ref(d, `blobs/${TID}/to/${B}`), true));
  await assertSucceeds(update(ref(db(B), `grants/${B}/${A}`), { state: 'BLOCKED' }));
  await assertFails(get(ref(db(B), `blobs/${TID}/c/0`)));
});

test('notices: only with accepted invitation and complete content of the sender', async () => {
  await users();
  await assertFails(set(ref(db(A), `inbox/${B}/${TID}`), notice()));          // no content
  await grant(B, A, 'ACCEPTED'); await uploaded(B);
  await assertFails(set(ref(db(C), `inbox/${B}/${TID}`), notice(A)));        // forged sender
  await assertFails(set(ref(db(A), `inbox/${B}/${TID}`), { ...notice(), size: 5 })); // lies about the content
  await assertSucceeds(set(ref(db(A), `inbox/${B}/${TID}`), notice()));
  await assertFails(get(ref(db(C), `inbox/${B}`)));
  await assertSucceeds(get(ref(db(B), `inbox/${B}`)));
  await assertSucceeds(remove(ref(db(B), `inbox/${B}/${TID}`)));
});

test('notice rejected if the recipient blocked the sender', async () => {
  await users(); await grant(B, A, 'BLOCKED'); await uploaded(B);
  await assertFails(set(ref(db(A), `inbox/${B}/${TID}`), notice()));
});

test('receipts: only the recipient confirms its own; only the owner reads and deletes', async () => {
  await users(); await grant(B, A, 'ACCEPTED'); await uploaded(B);
  await assertSucceeds(set(ref(db(B), `receipts/${TID}/${B}`), 'imported'));
  await assertFails(set(ref(db(C), `receipts/${TID}/${B}`), 'imported'));
  await assertFails(set(ref(db(C), `receipts/${TID}/${C}`), 'imported'));    // not a recipient
  await assertFails(set(ref(db(B), `receipts/${TID}/${B}`), 'cualquier cosa'));
  await assertSucceeds(get(ref(db(A), `receipts/${TID}`)));
  await assertFails(get(ref(db(B), `receipts/${TID}`)));
  await assertSucceeds(remove(ref(db(A), `receipts/${TID}`)));
});

test('safe deletion: only the owner deletes the content', async () => {
  await users(); await grant(B, A, 'ACCEPTED'); await uploaded(B);
  await assertFails(remove(ref(db(B), `blobs/${TID}`)));
  await assertSucceeds(remove(ref(db(A), `blobs/${TID}`)));
});
