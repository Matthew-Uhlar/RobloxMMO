// Run from the project root: node tools/organic-baseline.cjs (only when an owning team re-authors shapes and lowers their metrics).
// Writes art/organic-baseline.json: the §54 QC A2/A3 organic metrics of every
// organic shape outside the terrain catalog, as measured when the stricter
// metrics landed (a ratchet: verify-mesh fails if a shape gets worse).
const fs = require('fs'); const real = fs.writeFileSync; fs.writeFileSync = () => {};
let S, K; global.__aetherShapes = s => { S = s }; global.__aetherKit = k => { K = k }; global.__aetherShapesOnly = true;
const log = console.log; console.log = () => {}; require('../art/generate-props.cjs'); console.log = log; fs.writeFileSync = real;
const ORGANIC_WORLD = new Set(['tree', 'rock', 'ore', 'crop', 'plant', 'node']);
const out = {};
for (const [cat, store, meta] of [['world', S.worldShapes, S.worldMeta], ['creature', S.creatureShapes, S.creatureMeta], ['outfit', S.outfitShapes, S.outfitMeta]]) {
  for (const [name, data] of Object.entries(store)) {
    const m = meta[name];
    if (cat === 'world' && (!ORGANIC_WORLD.has(m.kind) || m.hull)) continue;
    const r = K.organicMetrics(data, m.smooth || 0);
    // §55: a shape that meets the strict bar (and its subdivision) leaves the baseline for good.
    if (r.dev98 <= 15 && r.sharp <= .02 && !K.subdivisionErrors(name, data, m).length) continue;
    out[name] = { catalog: cat, kind: m.kind, dev98: Math.round(r.dev98 * 10) / 10, sharp: Math.round(r.sharp * 1000) / 1000 };
  }
}
real('art/organic-baseline.json', JSON.stringify(out, null, 1) + '\n');
log(`${Object.keys(out).length} organic shapes outside the terrain catalog are still held to the baseline (the rest meet the strict bar)`);
