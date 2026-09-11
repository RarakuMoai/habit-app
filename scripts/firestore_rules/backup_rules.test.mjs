import { after, afterEach, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, writeBatch,
  runTransaction, setLogLevel, disableNetwork, enableNetwork, getDocFromServer,
} from 'firebase/firestore';

// This suite must never fall back to a real Firebase project or endpoint.
const emulator = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulator || !/^(127\.0\.0\.1|localhost):\d+$/.test(emulator)) {
  throw new Error('Run through the local Firestore emulator only.');
}
const [host, portText] = emulator.split(':');
const projectId = 'demo-tumi-account-rules';
const rulesPath = process.env.TUMI_RULES_FILE ??
  new URL('../../firestore.rules', import.meta.url);
const prefix = 'tumi_backups_redesign';
const uid = 'fixture-owner';
const ids = [0, 1, 2, 3, 4, 5].map(i => `snapshot${String(i).padStart(12, '0')}`);
const checksum = createHash('sha256').update('a').digest('hex');
let environment;
let db;
const databases = new Set();
function track(database) {
  databases.add(database);
  return database;
}

before(async () => {
  setLogLevel('silent');
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {host, port: Number(portText), rules: readFileSync(rulesPath, 'utf8')},
  });
});
after(async () => { await environment?.cleanup(); });
afterEach(async () => {
  await Promise.all([...databases].map(database => database.terminate()));
  databases.clear();
});
beforeEach(async () => {
  await environment.clearFirestore();
  db = track(environment.authenticatedContext(uid, {
    firebase: {sign_in_provider: 'google.com'},
  }).firestore());
});

const ownerRef = (database = db, owner = uid) => doc(database, prefix, owner);
const snapshotRef = (id = ids[0], database = db, owner = uid) =>
  doc(database, prefix, owner, 'snapshots', id);
const chunkRef = (id = ids[0], index = 0, database = db, owner = uid) =>
  doc(database, prefix, owner, 'snapshots', id, 'chunks', String(index));
const headRef = (database = db, owner = uid) =>
  doc(database, prefix, owner, 'state', 'head');
const manifest = (changes = {}) => ({
  createdAt: serverTimestamp(), chunkCount: 1, byteLength: 1,
  checksum, schemaVersion: 1, ...changes,
});
const head = (id = ids[0], revision = 1, previousSnapshotId = null, changes = {}) => ({
  ...manifest(), snapshotId: id, previousSnapshotId, revision, ...changes,
});
async function stage(id = ids[0]) {
  await setDoc(snapshotRef(id), manifest());
  await setDoc(chunkRef(id), {index: 0, payload: 'YQ=='});
}
async function publish(id = ids[0], revision = 1, prior = null) {
  await stage(id);
  await setDoc(headRef(), head(id, revision, prior));
}

test('owner creates immutable parts and publishes a readable backup', async () => {
  await assertSucceeds(publish());
  assert.equal((await assertSucceeds(getDoc(headRef()))).data().revision, 1);
  assert.equal((await assertSucceeds(getDoc(chunkRef()))).data().payload, 'YQ==');
});

test('signed-out requests cannot read or create a snapshot or head', async () => {
  await publish();
  const guest = track(environment.unauthenticatedContext().firestore());
  await assertFails(getDoc(headRef(guest)));
  await assertFails(getDoc(snapshotRef(ids[0], guest)));
  await assertFails(getDoc(chunkRef(ids[0], 0, guest)));
  await assertFails(setDoc(snapshotRef(ids[1], guest), manifest()));
  await assertFails(setDoc(headRef(guest), head(ids[1], 2, ids[0])));
});

test('another UID cannot read, modify or delete the owner data', async () => {
  await publish();
  const other = track(environment.authenticatedContext('different-owner', {
    firebase: {sign_in_provider: 'apple.com'},
  }).firestore());
  await assertFails(getDoc(headRef(other)));
  await assertFails(getDoc(chunkRef(ids[0], 0, other)));
  await assertFails(setDoc(snapshotRef(ids[1], other), manifest()));
  await assertFails(deleteDoc(headRef(other)));
  await assertFails(setDoc(ownerRef(other), {deleting: true}));
});

test('anonymous identity cannot use cloud storage even with the same UID', async () => {
  const anonymous = track(environment.authenticatedContext(uid, {
    firebase: {sign_in_provider: 'anonymous'},
  }).firestore());
  await assertFails(setDoc(snapshotRef(ids[0], anonymous), manifest()));
  await publish();
  await assertFails(getDoc(headRef(anonymous)));
  await assertFails(setDoc(ownerRef(anonymous), {deleting: true}));
});

test('Apple and Google linked identities resolve to the same owner path', async () => {
  await publish();
  const apple = track(environment.authenticatedContext(uid, {
    firebase: {sign_in_provider: 'apple.com'},
  }).firestore());
  assert.equal((await assertSucceeds(getDoc(headRef(apple)))).data().revision, 1);
});

test('manifest and chunk contents cannot be edited after creation', async () => {
  await stage();
  await assertFails(updateDoc(snapshotRef(), {checksum: 'b'.repeat(64)}));
  await assertFails(setDoc(snapshotRef(), manifest()));
  await assertFails(updateDoc(chunkRef(), {payload: 'Yg=='}));
  await assertFails(setDoc(chunkRef(), {index: 0, payload: 'YQ=='}));
});

test('manifest validation rejects unknown fields, overflows and inconsistent size', async () => {
  const invalid = [
    {extra: true}, {chunkCount: 108}, {byteLength: 20971521},
    {chunkCount: 2, byteLength: 1}, {checksum: 'bad-checksum'}, {schemaVersion: 2},
    {createdAt: new Date('2020-01-01')},
  ];
  for (const data of invalid) {
    await assertFails(setDoc(snapshotRef(), manifest(data)));
  }
});

test('chunk validation rejects missing manifests, wrong indices and oversized payloads', async () => {
  await assertFails(setDoc(chunkRef(), {index: 0, payload: 'YQ=='}));
  await setDoc(snapshotRef(), manifest());
  await assertFails(setDoc(chunkRef(ids[0], 1), {index: 1, payload: 'YQ=='}));
  await assertFails(setDoc(chunkRef(), {index: 1, payload: 'YQ=='}));
  await assertFails(setDoc(chunkRef(), {index: 0, payload: ''}));
  await assertFails(setDoc(chunkRef(), {index: 0, payload: 'a'.repeat(262145)}));
  await assertFails(setDoc(chunkRef(), {index: 0, payload: 'YQ==', extra: true}));
});

test('head rejects missing or mismatched snapshot manifests', async () => {
  await assertFails(setDoc(headRef(), head()));
  await stage();
  await assertFails(setDoc(headRef(), head(ids[0], 1, null, {checksum: 'b'.repeat(64)})));
  await assertFails(setDoc(headRef(), head(ids[0], 1, null, {byteLength: 2})));
  await assertFails(setDoc(headRef(), head(ids[0], 1, null, {extra: true})));
});

test('head creation and replacement enforce revision and previous snapshot', async () => {
  await stage();
  await assertFails(setDoc(headRef(), head(ids[0], 0)));
  await assertFails(setDoc(headRef(), head(ids[0], 2)));
  await setDoc(headRef(), head());
  await stage(ids[1]);
  await assertFails(setDoc(headRef(), head(ids[1], 3, ids[0])));
  await assertFails(setDoc(headRef(), head(ids[1], 2, ids[2])));
  await assertFails(setDoc(headRef(), head(ids[0], 2, ids[0])));
  await assertSucceeds(setDoc(headRef(), head(ids[1], 2, ids[0])));
  await assertFails(setDoc(headRef(), head(ids[1], 2, ids[0])));
});

test('transaction CAS cannot commit a stale device revision', async () => {
  await publish();
  await stage(ids[1]);
  await stage(ids[2]);
  const save = async (expected, id) => runTransaction(db, async transaction => {
    const latest = await transaction.get(headRef());
    if (latest.data().revision !== expected) throw new Error('conflict');
    transaction.set(headRef(), head(id, expected + 1, latest.data().snapshotId));
  });
  await save(1, ids[1]);
  await assert.rejects(save(1, ids[2]), /conflict/);
  assert.equal((await getDoc(headRef())).data().snapshotId, ids[1]);
});

test('cleanup preserves current and prior snapshots while allowing obsolete ones', async () => {
  await publish(ids[0]);
  await publish(ids[1], 2, ids[0]);
  for (const id of [ids[0], ids[1]]) {
    await assertFails(deleteDoc(chunkRef(id)));
    await assertFails(deleteDoc(snapshotRef(id)));
  }
  await assertFails(deleteDoc(headRef()));
  await publish(ids[2], 3, ids[1]);
  await assertSucceeds(deleteDoc(chunkRef(ids[0])));
  await assertSucceeds(deleteDoc(snapshotRef(ids[0])));
});

test('deletion tombstone blocks delayed uploads and permits explicit cleanup', async () => {
  await publish();
  await stage(ids[1]);
  await assertSucceeds(setDoc(ownerRef(), {deleting: true}));
  await assertFails(setDoc(snapshotRef(ids[2]), manifest()));
  await assertFails(setDoc(headRef(), head(ids[1], 2, ids[0])));
  await assertFails(setDoc(ownerRef(), {deleting: false}));
  await assertFails(deleteDoc(ownerRef()));
  await assertSucceeds(deleteDoc(headRef()));
  await assertSucceeds(deleteDoc(chunkRef()));
  await assertSucceeds(deleteDoc(snapshotRef()));
  await assertFails(setDoc(headRef(), head(ids[1])));
});

test('eight production-sized chunk writes fit security-rule access limits', async () => {
  const bytes = 7 * 196608 + 1;
  await setDoc(snapshotRef(), manifest({chunkCount: 8, byteLength: bytes}));
  const batch = writeBatch(db);
  for (let index = 0; index < 8; index++) {
    batch.set(chunkRef(ids[0], index), {
      index, payload: index === 7 ? 'YQ==' : 'YWFh'.repeat(65536),
    });
  }
  await assertSucceeds(batch.commit());
});

test('all other collections and profile fields are denied', async () => {
  await assertFails(setDoc(doc(db, 'tumi_backups_production', uid), {deleting: true}));
  await assertFails(setDoc(doc(db, 'profiles', uid), {name: 'fixture'}));
  await assertFails(setDoc(ownerRef(), {deleting: true, email: 'fixture@example.invalid'}));
});

// The JS SDK defaults to a memory cache. This reproduces the queue semantics
// that persistenceEnabled:false cannot disable in the native adapter either.
// Dart guard tests cover the production phase-control implementation.
for (const phase of ['manifest', 'chunks']) {
  test(`offline ${phase} acknowledgement timeout never publishes after reconnect`,
    {timeout: 10000}, async () => {
      await publish();
      if (phase === 'chunks') await setDoc(snapshotRef(ids[1]), manifest());
      await disableNetwork(db);
      let queued;
      let headWrites = 0;
      let timer;
      try {
        if (phase === 'manifest') {
          queued = setDoc(snapshotRef(ids[1]), manifest());
        } else {
          const batch = writeBatch(db);
          batch.set(chunkRef(ids[1]), {index: 0, payload: 'YQ=='});
          queued = batch.commit();
        }
        const upload = async () => {
          await Promise.race([
            queued,
            new Promise((_, reject) => {
              timer = setTimeout(() => reject(new Error('staging-timeout')), 50);
            }),
          ]);
          headWrites++;
          await setDoc(headRef(), head(ids[1], 2, ids[0]));
        };
        await assert.rejects(upload(), /staging-timeout/);
        await enableNetwork(db);
        await queued; // The SDK really sends the staged write after timeout.
        assert.equal((await getDocFromServer(snapshotRef(ids[1]))).exists(), true);
        assert.equal(headWrites, 0);
        assert.equal((await getDocFromServer(headRef())).data().snapshotId, ids[0]);
        assert.equal((await getDocFromServer(chunkRef(ids[1]))).exists(), phase === 'chunks');
      } finally {
        clearTimeout(timer);
        await enableNetwork(db);
      }
    });
}

test('network stream suspension cannot substitute for transaction cancellation',
  {timeout: 10000}, async () => {
    await publish();
    await stage(ids[1]);
    await disableNetwork(db);
    try {
      // disableNetwork suspends queued writes/listeners; a transaction can
      // still use its direct RPC. The adapter therefore retains its native
      // operation guard rather than using this switch as a cancellation API.
      await runTransaction(db, async transaction => {
        const current = await transaction.get(headRef());
        transaction.set(headRef(), head(ids[1], 2, current.data().snapshotId));
      }, {maxAttempts: 1});
    } finally {
      await enableNetwork(db);
    }
    assert.equal((await getDocFromServer(headRef())).data().snapshotId, ids[1]);
  });
