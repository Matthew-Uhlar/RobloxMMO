// Run from the project root: node tools/organic-baseline.cjs (only when an owning team re-authors shapes and lowers their metrics).
// Rewrites art/organic-baseline.json: the §54 QC A2/A3 organic metrics of the
// organic shapes not yet re-authored to the strict bar (a ratchet: verify-mesh
// fails if a shape gets worse than its entry).
// §55 QC M1: the ratchet only ever tightens. Only names already in the
// baseline are kept (a new or renamed shape is never added; it must meet the
// strict bar), a shape that now meets the strict bar (and its subdivision)
// leaves for good, and every kept entry takes min(old, new) of each metric.
const fs = require('fs'); const real = fs.writeFileSync; fs.writeFileSync = () => {};
let S, K; global.__aetherShapes = s => { S = s }; global.__aetherKit = k => { K = k }; global.__aetherShapesOnly = true;
const log = console.log; console.log = () => {}; require('../art/generate-props.cjs'); console.log = log; fs.writeFileSync = real;
const old = JSON.parse(fs.readFileSync('art/organic-baseline.json', 'utf8'));
const stores = { world: [S.worldShapes, S.worldMeta], creature: [S.creatureShapes, S.creatureMeta], outfit: [S.outfitShapes, S.outfitMeta] };
const out = {};
let dropped = 0, passed = 0;
for (const [name, b] of Object.entries(old)) {
  const [store, meta] = stores[b.catalog] || [];
  const data = store && store[name], m = meta && meta[name];
  if (!data) { dropped++; continue; }
  const r = K.organicMetrics(data, m.smooth || 0);
  if (r.dev98 <= 15 && r.sharp <= .02 && !K.subdivisionErrors(name, data, m).length) { passed++; continue; }
  out[name] = { catalog: b.catalog, kind: m.kind, dev98: Math.min(b.dev98, Math.round(r.dev98 * 10) / 10), sharp: Math.min(b.sharp, Math.round(r.sharp * 1000) / 1000) };
}
real('art/organic-baseline.json', JSON.stringify(out, null, 1) + '\n');
log(`${Object.keys(out).length} organic shapes outside the terrain catalog are still held to the baseline (${passed} now meet the strict bar, ${dropped} no longer exist)`);
