import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';

// Firebase CLI requires rules to be inside its project directory. The checked
// in root file remains the only source; this ignored copy is refreshed per run.
const directory = new URL('./.cache/', import.meta.url);
mkdirSync(directory, {recursive: true});
writeFileSync(new URL('firestore.rules', directory),
  readFileSync(new URL('../../firestore.rules', import.meta.url)));
