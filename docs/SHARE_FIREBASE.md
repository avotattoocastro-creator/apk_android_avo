# AVO Performance Horse — Training sharing between users (Firebase)

Branch: `feature/avo-firebase-sync`, based on `feature/avo-nfc-identity`. That branch contains Android 2.1 + engine 1.1.0-dev1 + the NFC identity.

## Decisions taken with the user

- **Account = AVO NFC card. No email.**
  - Registration is tapping the card for the first time.
  - Login on another phone is tapping the same card.
  - The Firebase credential is the email `<code>@avo-cards.app`, which is not a real address, plus the card secret.
  - There is no email verification or password recovery. Recovery is the card itself. A lost card is replaced by a new one made in AVO Tarjetas.
- **No FCM.** On the Spark plan, sending a push requires a server (Cloud Functions on the Blaze plan, or a service account key). That key cannot go inside the app without exposing it. Reception is handled instead by:
  1. a live listener on the inbox while the app or its background service (`AvoLinkService`) is running;
  2. a periodic WorkManager task every 15 minutes, the minimum Android allows;
  3. a check every time the app is opened.

  Android may postpone the periodic task when battery saving is on, so immediate reception is not guaranteed.
- **No Cloud Storage.** The content goes in base64 chunks inside the Realtime Database.

## Three simultaneous modes

| Mode | Where it is configured | When it is sent |
|---|---|---|
| A · Global | Ajustes → Compartir y sincronizar → Sincronización global | Each new training, after its download is verified with the watch |
| B · Per horse | Same screen → Sincronización por caballo (on/off per horse) | Same, added on top of the global recipients |
| C · Manual | «Compartir AVO» button in Historial, «COMPARTIR» in Análisis | Any training, old or new; it can be sent again |

`RecipientResolver` combines the three modes. A user who appears several times receives a single copy. Trainings that were imported (`watchState = IMPORTADO`) are never forwarded automatically, which avoids loops between users.

## Authorization (invitations)

`grants/<recipient>/<sender>` = `PENDING | ACCEPTED | REJECTED | BLOCKED`.

- The sender can only create `PENDING`.
- Only the recipient can accept, reject or block.
- A blocked sender cannot delete the block in order to invite again.
- Nothing is uploaded or notified until the invitation is `ACCEPTED`. Deliveries wait in the `WAITING_ACCEPT` state without using quota.

## Database structure

```
users/<code>                {name, uid}                      directory (name and code only)
grants/<recipient>/<sender> {state, senderName, ms}
blobs/<tid>/meta            {owner, sessionId, size, sha256, chunks, chunkSize, createdMs, expiresMs, …}
blobs/<tid>/c/<i>           base64 (≤ 256 kB raw), n = chunks uploaded (to resume), complete = true
blobs/<tid>/to/<code>       true                             individual read permission
inbox/<recipient>/<tid>     {from, fromName, sessionId, horseName, size, createdMs}   notice only, no data
receipts/<tid>/<recipient>  "imported" | "present" | "error:…"
```

- `tid = sha256(owner, sessionId, content SHA-256)[0..32]` is stable.
- Each training is uploaded once for all its recipients. Each recipient gets an individual read permission.
- A re-share with the same content reuses the same `tid`, so the recipient never ends up with a duplicate.

## Protocol (`core/share/ShareEngine`)

1. **Send.** Steps:
   - build the `.avo` package (AVO-TRAINING-1, the same format as WhatsApp and the importer) and compute its SHA-256;
   - create `meta`;
   - upload the chunks, resuming from `n`;
   - set `complete`;
   - grant each recipient read permission (`to/<code>`);
   - write the notice in each inbox.
2. **Receive.** Steps:
   - read the notice and check that `meta.owner` matches the sender (forged notices are discarded);
   - download the chunks and verify size and SHA-256;
   - import with `TrainingImport`, which runs the same checks as the manual import, including per-segment SHA-256;
   - only then write the receipt and delete the notice.
3. **Duplicates and conflicts.**
   - Identical content: answers `present` and imports nothing.
   - A *different* local version: it is not overwritten. The delivery waits in «Requieren tu decisión» with the options Sustituir or Conservar.
4. **Cleanup.**
   - The sender deletes the content when every recipient has confirmed or rejected it, or after 14 days (marked `EXPIRED` in the history).
   - Local trainings are never deleted.

## Offline-first

- The queue is stored in Room (`share_out`, `share_in` and `share_recipients`; migration 4→5 only adds tables).
- Every step is idempotent, so an interrupted run is simply repeated.
- `ShareWorker` (WorkManager) runs with network constraints and exponential backoff.
- Network preferences, all persistent:
  - allow Wi-Fi;
  - allow mobile data;
  - Wi-Fi only for files larger than N MB;
  - automatic retry;
  - pause and resume;
  - maximum size per training.

## Spark plan limits (real)

- 1 GB stored and 10 GB/month of downloads **for the whole project**, plus 100 simultaneous connections.
- One training: a 700 kB – 5 MB RAW package is about 1–7 MB in base64. Each recipient downloads it once.
  - Example: 3 recipients × 30 trainings/month × 5 MB is about 450 MB/month, well within the limit.
- Hard limits enforced by the rules: 30 MB per training, 120 chunks, chunk ≤ 360 000 characters.
- The app counts what each phone uploads and downloads per month and shows a warning when it passes a configurable threshold.
- The Realtime Database is not meant for files. The design keeps content only temporarily: it is deleted on confirmation or after 14 days.
- **Cleanup without Cloud Functions.** Cleanup runs in the sender's app, so content stays until the sender opens the app or the periodic task runs.
- **Lost card.** Without a server, the old account cannot be disabled. Whoever holds the card can still sign in. Mitigation: each recipient can block that sender.

## Security rules

- File: `firebase/database.rules.json`.
- Tests: `firebase/test/rules.test.js`, run with Firebase Emulator Suite in the `Firebase rules (emulator)` workflow.
- The tests cover:
  - authentication;
  - profiles;
  - invitations and blocking;
  - content owner;
  - structure and sizes;
  - completion only once the last chunk exists;
  - read permission per recipient;
  - revocation;
  - forged notices;
  - receipts;
  - deletion.

**Pending (manual):** publish the rules in the Firebase console. Go to Realtime Database → Reglas, paste the contents of `firebase/database.rules.json` and press Publicar. Do this only after the workflow has passed. Production currently has the locked rules, so the service rejects everything until they are published.

## Tests

- **`core/share/ShareEngineTest` (JVM, fake server with fault injection) covers:**
  - the three modes combined and deduplicated;
  - a single upload for several recipients;
  - re-sharing with no duplicate in the library;
  - no sending without an accepted invitation;
  - blocking;
  - permissions;
  - disconnection during upload, and resuming without re-uploading;
  - disconnection during download, with no confirmation sent;
  - corrupted content;
  - forged notice;
  - conflict with a different local version;
  - expiry;
  - no deletion while a recipient is still pending;
  - working offline;
  - an old training;
  - size limit;
  - stable identifiers;
  - usage counting;
  - large files waiting for Wi-Fi.
- **Not automated (physical validation with two phones still pending):**
  - real Firebase sign-in;
  - Room migration on the device;
  - WorkManager under Doze;
  - notifications.
